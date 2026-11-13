#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# anonbox installer.
#
#   curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash -s -- --install-deps
#
# Prefer to read it first?  curl -fsSLO <url> && less install.sh && bash install.sh
#
# What it does: downloads a release of anonbox, checks the layout (and the SHA-256 if you give one), installs it
# to ~/.local/share/anonbox, links ~/.local/bin/anonbox, and runs `anonbox doctor`.
# What it never does: use sudo on its own, run as root, touch anything outside the two paths above, or phone home.
# Installing a container engine needs your OS package manager and is opt-in: --install-deps (it asks first).
#
# Options:
#   --ref REF          install this tag/branch/commit (default: the release pinned in this script)
#   --local            install from the checkout this script sits in (no download)
#   --prefix DIR       install location        (env ANONBOX_PREFIX, default ~/.local/share/anonbox)
#   --bin-dir DIR      where the command goes   (env ANONBOX_BIN_DIR, default ~/.local/bin)
#   --install-deps     offer to install Podman with your package manager (asks before running sudo)
#   -y, --yes          do not ask questions
#   --update           same as a normal install (kept for readability)
#   --uninstall        remove anonbox itself (run `anonbox purge` first to remove containers/images)
#   --no-doctor        skip the pre-flight checks at the end
#   -h, --help         this text
#
# Environment: ANONBOX_REF, ANONBOX_PREFIX, ANONBOX_BIN_DIR, ANONBOX_SHA256 (expected SHA-256 of the tarball),
#              ANONBOX_TARBALL_URL (custom download URL), GITHUB_TOKEN (to install from a private repository).

set -euo pipefail

REPO="spignelon/anonbox"
DEFAULT_REF="v0.1.0"   # bumped for every release

REF="${ANONBOX_REF:-$DEFAULT_REF}"
PREFIX="${ANONBOX_PREFIX:-$HOME/.local/share/anonbox}"
BIN_DIR="${ANONBOX_BIN_DIR:-$HOME/.local/bin}"
EXPECTED_SHA256="${ANONBOX_SHA256:-}"
TARBALL_URL="${ANONBOX_TARBALL_URL:-}"

MODE=install
LOCAL=0
YES=0
INSTALL_DEPS=0
RUN_DOCTOR=1
TMP=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; DIM=""; OFF=""
fi

info() { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

usage() {
  if [ -f "$0" ]; then sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  else printf 'anonbox installer. Download it and run with --help, or see https://github.com/%s#install\n' "$REPO"; fi
}

# Asks a yes/no question on the terminal (works even when the script itself is piped into bash).
confirm() {
  [ "$YES" -eq 1 ] && return 0
  local answer=""
  if [ -r /dev/tty ]; then
    printf '%s [y/N] ' "$1" >/dev/tty
    read -r answer </dev/tty || true
  else
    warn "no terminal to ask '$1' (pass --yes to accept)"; return 1
  fi
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------------------------------
# Platform detection
# --------------------------------------------------------------------------------------------------

OS=""; ARCH=""; PKG=""

detect_platform() {
  ARCH="$(uname -m)"
  case "$(uname -s)" in
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi
      if   have apt-get; then PKG=apt
      elif have dnf;     then PKG=dnf
      elif have zypper;  then PKG=zypper
      elif have pacman;  then PKG=pacman
      elif have apk;     then PKG=apk
      elif have yum;     then PKG=yum
      fi ;;
    Darwin) OS="macos"; have brew && PKG=brew ;;
    MINGW*|MSYS*|CYGWIN*) die "native Windows shells are not supported. Run the PowerShell installer (install.ps1) or use WSL2: see GUIDE.md > Windows" ;;
    *) die "unsupported operating system '$(uname -s)'. anonbox supports Linux, macOS, and Windows through WSL2" ;;
  esac
  case "$ARCH" in x86_64|amd64|aarch64|arm64) ;; *) warn "untested CPU architecture '$ARCH' (x86-64 and arm64 are tested/expected)" ;; esac
}

# --------------------------------------------------------------------------------------------------
# Download
# --------------------------------------------------------------------------------------------------

fetch() {   # fetch URL DEST   (HTTPS only; plain HTTP is accepted for a loopback test server and nothing else)
  local url="$1" dest="$2" proto='=https'
  case "$url" in http://127.0.0.1:*|http://localhost:*) proto='=http,https' ;; esac
  if have curl; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL --proto "$proto" --tlsv1.2 -H "Authorization: Bearer $GITHUB_TOKEN" -o "$dest" "$url"
    else
      curl -fsSL --proto "$proto" --tlsv1.2 -o "$dest" "$url"
    fi
  elif have wget; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -q --header="Authorization: Bearer $GITHUB_TOKEN" -O "$dest" "$url"
    else
      wget -q -O "$dest" "$url"
    fi
  else
    die "need curl or wget to download anonbox"
  fi
}

sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum;  then shasum -a 256 "$1" | awk '{print $1}'
  elif have openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else die "no sha256 tool found (sha256sum, shasum or openssl) to verify the download"; fi
}

SRC_DIR=""

acquire_source() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/anonbox-install.XXXXXX")"
  if [ "$LOCAL" -eq 1 ]; then
    local here
    here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -f "$here/bin/anonbox" ] || die "--local must be run from a checkout of the repository (bin/anonbox not found next to install.sh)"
    SRC_DIR="$here"
    ok "installing from the local checkout: $SRC_DIR"
    return
  fi

  local url="$TARBALL_URL"
  if [ -z "$url" ]; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then url="https://api.github.com/repos/$REPO/tarball/$REF"
    else url="https://codeload.github.com/$REPO/tar.gz/$REF"; fi
  fi
  info "Downloading anonbox $REF"
  printf '  %s%s%s\n' "$DIM" "$url" "$OFF"
  fetch "$url" "$TMP/anonbox.tar.gz" || die "download failed. Check the ref '$REF' and your connection. (For a private repository set GITHUB_TOKEN.)"

  local got
  got="$(sha256_of "$TMP/anonbox.tar.gz")"
  if [ -n "$EXPECTED_SHA256" ]; then
    [ "$got" = "$EXPECTED_SHA256" ] || die "SHA-256 mismatch: expected $EXPECTED_SHA256, got $got. Refusing to install."
    ok "SHA-256 verified"
  else
    printf '  %sSHA-256 of the download: %s%s\n' "$DIM" "$got" "$OFF"
    printf '  %s(set ANONBOX_SHA256 to pin it and have the installer verify it)%s\n' "$DIM" "$OFF"
  fi

  mkdir "$TMP/src"
  tar -xzf "$TMP/anonbox.tar.gz" -C "$TMP/src" --strip-components=1 || die "the download is not a valid archive"
  SRC_DIR="$TMP/src"
}

validate_source() {
  local f
  for f in bin/anonbox install.sh images/gateway/Containerfile images/gateway/entrypoint.sh images/workstation/Containerfile LICENSE; do
    [ -f "$SRC_DIR/$f" ] || die "unexpected archive layout: '$f' is missing, refusing to install"
  done
  bash -n "$SRC_DIR/bin/anonbox" || die "bin/anonbox does not parse, refusing to install"
}

# --------------------------------------------------------------------------------------------------
# Install / uninstall
# --------------------------------------------------------------------------------------------------

do_install() {
  info "Installing to $PREFIX"
  local stage="$PREFIX.new.$$" backup="$PREFIX.old.$$"
  mkdir -p "$(dirname "$PREFIX")" "$BIN_DIR"
  rm -rf "$stage"
  mkdir -p "$stage"
  local item
  for item in bin images install.sh LICENSE README.md GUIDE.md SECURITY.md CHANGELOG.md; do
    [ -e "$SRC_DIR/$item" ] && cp -R "$SRC_DIR/$item" "$stage/"
  done
  chmod 755 "$stage/bin/anonbox" "$stage/install.sh" "$stage/images/gateway/entrypoint.sh"

  if [ -e "$PREFIX" ]; then mv "$PREFIX" "$backup"; fi
  mv "$stage" "$PREFIX"
  rm -rf "$backup"
  ok "program files installed"

  local link="$BIN_DIR/anonbox"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "$link exists and is not a symlink; remove or rename it, then run the installer again"
  fi
  ln -sf "$PREFIX/bin/anonbox" "$link"
  ok "command linked: $link"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      warn "$BIN_DIR is not in your PATH. Add it:"
      # shellcheck disable=SC2016  # a literal $PATH is printed on purpose, for the user to copy
      case "$(basename "${SHELL:-bash}")" in
        fish) printf '      fish_add_path %s\n' "$BIN_DIR" ;;
        zsh)  printf '      echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc && exec zsh\n' "$BIN_DIR" ;;
        *)    printf '      echo '\''export PATH="%s:$PATH"'\'' >> ~/.bashrc && exec bash\n' "$BIN_DIR" ;;
      esac ;;
  esac
}

do_uninstall() {
  info "Removing anonbox"
  local link="$BIN_DIR/anonbox"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$PREFIX/bin/anonbox" ]; then
    confirm "Remove $link and $PREFIX?" || die "cancelled"
    rm -f "$link"; ok "removed $link"
  else
    [ -d "$PREFIX" ] || die "nothing to remove: no installation at $PREFIX"
    confirm "Remove $PREFIX?" || die "cancelled"
  fi
  rm -rf "$PREFIX"; ok "removed $PREFIX"
  printf '\nContainers and images are not touched by this. If you have not yet, remove them with the engine:\n'
  printf '  anonbox purge -y    (run it BEFORE uninstalling next time)\n'
  # shellcheck disable=SC2016  # the command is printed for the user to copy, not expanded here
  printf '  or: podman rm -f anonbox-ws anonbox-gw; podman network rm anonbox-net; podman rmi $(podman images -q "localhost/anonbox-*")\n'
}

# --------------------------------------------------------------------------------------------------
# Optional: install a container engine
# --------------------------------------------------------------------------------------------------

install_deps() {
  info "Container engine"
  if have podman || have docker; then ok "a container engine is already installed ($(have podman && echo podman || echo docker))"; return; fi

  local cmds=()
  case "$OS:$PKG" in
    macos:brew)    cmds=("brew install podman" "podman machine init" "podman machine start") ;;
    macos:*)       warn "Homebrew not found. Install it from https://brew.sh, or install Docker Desktop / Colima / OrbStack"; return ;;
    *:apt)         cmds=("sudo apt-get update" "sudo apt-get install -y podman uidmap") ;;
    *:dnf)         cmds=("sudo dnf install -y podman") ;;
    *:yum)         cmds=("sudo yum install -y podman") ;;
    *:zypper)      cmds=("sudo zypper --non-interactive install podman") ;;
    *:pacman)      cmds=("sudo pacman -S --needed --noconfirm podman") ;;
    *:apk)         cmds=("sudo apk add podman fuse-overlayfs shadow-uidmap") ;;
    *)             warn "unknown package manager: install Podman or Docker yourself (see GUIDE.md > Installing a container engine)"; return ;;
  esac

  printf '  Podman (recommended, rootless) will be installed with:\n'
  local c
  for c in "${cmds[@]}"; do printf '      %s\n' "$c"; done
  confirm "Run these commands now?" || { warn "skipped. Install Podman or Docker yourself, then run: anonbox doctor"; return; }
  for c in "${cmds[@]}"; do
    printf '  %s$ %s%s\n' "$DIM" "$c" "$OFF"
    bash -c "$c" || die "'$c' failed; fix it and run the installer again"
  done
  ok "Podman installed"
}

# --------------------------------------------------------------------------------------------------

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)          shift; REF="${1:?--ref needs a value}" ;;
      --local)        LOCAL=1 ;;
      --prefix)       shift; PREFIX="${1:?--prefix needs a value}" ;;
      --bin-dir)      shift; BIN_DIR="${1:?--bin-dir needs a value}" ;;
      --install-deps) INSTALL_DEPS=1 ;;
      -y|--yes)       YES=1 ;;
      --update)       ;;
      --uninstall)    MODE=uninstall ;;
      --no-doctor)    RUN_DOCTOR=0 ;;
      -h|--help)      usage; exit 0 ;;
      *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
  done

  printf '\n%sanonbox installer%s\n\n' "$BOLD" "$OFF"

  if [ "$(id -u)" -eq 0 ] && [ -z "${ANONBOX_ALLOW_ROOT:-}" ]; then
    die "do not run this as root. anonbox is meant to run as your normal user (rootless containers are the point). The installer asks for sudo only where needed."
  fi
  [ "${BASH_VERSINFO[0]}" -ge 3 ] || die "bash 3.2 or newer is required"
  have tar || die "tar is required"
  have mktemp || die "mktemp is required"

  detect_platform
  ok "platform: $OS ($ARCH)${PKG:+, package manager: $PKG}"

  if [ "$MODE" = uninstall ]; then do_uninstall; exit 0; fi

  acquire_source
  validate_source
  [ "$INSTALL_DEPS" -eq 1 ] && install_deps
  do_install

  if [ "$RUN_DOCTOR" -eq 1 ]; then
    printf '\n'
    info "Pre-flight checks"
    "$PREFIX/bin/anonbox" doctor || warn "fix the items above, then run: anonbox doctor"
  fi

  printf '\n%sInstalled.%s Next steps:\n' "$BOLD" "$OFF"
  printf '  anonbox up        # first run builds the images (about a minute) and starts Tor\n'
  printf '  anonbox shell     # a Debian shell whose only network path is Tor\n'
  printf '  anonbox check     # prove it\n'
  printf '  anonbox help      # everything else, or read GUIDE.md\n\n'
}

main "$@"
