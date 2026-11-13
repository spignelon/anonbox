<div align="center">

# anonbox

**A disposable Debian workstation whose only network path is Tor.**

Run scripts, download anything and clone repositories from a command line, with your IP address and DNS kept out of it
and your files out of reach. Rootless containers, fail-closed by design, nothing changed on your host.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Engines](https://img.shields.io/badge/engine-Podman%20%7C%20Docker-informational)
![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20(WSL2)-lightgrey)
![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-green)

</div>

```console
$ curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash
$ anonbox up
$ anonbox shell

user@anonbox:~$ curl https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.45"}
```

---

## Contents

- [Why anonbox](#why-anonbox)
- [Features](#features)
- [How it works](#how-it-works)
- [Install](#install)
- [Supported platforms](#supported-platforms)
- [Before you install: checklist](#before-you-install-checklist)
- [Quick tour](#quick-tour)
- [Moving files in and out](#moving-files-in-and-out)
- [How secure is it?](#how-secure-is-it)
- [Use cases](#use-cases)
- [Drawbacks and limitations](#drawbacks-and-limitations)
- [How it compares](#how-it-compares)
- [Configuration](#configuration)
- [Project layout](#project-layout)
- [Roadmap](#roadmap)
- [Contributing](#contributing) · [License](#license)

Full walkthrough with examples and troubleshooting: **[GUIDE.md](GUIDE.md)**. Threat model: **[SECURITY.md](SECURITY.md)**.

## Why anonbox

You sometimes need to run something you don't fully trust, or fetch something without attaching your name and address to it:
a script someone sent you, a scraper, a downloader, a package from an unfamiliar source, a `git clone` of a repository you'd
rather not be seen reading.

The usual tools fall short:

| Approach | Problem |
|---|---|
| `torsocks`, `proxychains`, `ALL_PROXY` | Only works if the program cooperates. One program that ignores the proxy, or one DNS lookup, leaks your real address. |
| Tor Browser | A browser only. No scripts, no `git`, no `pip`. |
| Tails / Whonix | Excellent, but a whole operating system or VM pair; heavy for "run this one script". |
| A plain container with a proxy variable | Same leak risk as the first row, plus the container can still reach your network. |

anonbox makes the **network layout** the enforcement, not a setting: the workstation is attached to a network that has no
way out, and the only machine it can talk to is a Tor gateway. A program that doesn't speak the proxy simply fails to
connect, instead of leaking.

## Features

- **Fail-closed Tor routing.** No default route, no DNS server and no UDP in the workstation. If Tor is down, nothing connects.
- **Isolated from your machine.** No mounted folders, no host network, no capabilities. It sees only what you copy in.
- **Rootless by default.** With Podman, even "root" inside the container is an unprivileged user on your host.
- **Verified, not assumed.** `anonbox check` runs 12 leak and isolation tests from inside the workstation on demand.
- **Batteries included.** Debian 13 with curl, wget, aria2, git, ssh, Python 3 + pip + venv, **uv**, archive tools, jq, dig.
- **Safe file transfer.** `put`/`get` stream through the engine; `get` lands in a quarantine folder with no execute bits and
  symlinks flattened.
- **Disposable.** `anonbox down` wipes the workstation; `anonbox stop`/`up` pause and resume it with your files intact.
- **New identity on demand.** `anonbox newid` asks Tor for fresh circuits.
- **Works with `.onion` services** out of the box.
- **Podman or Docker**, Linux, macOS and Windows (WSL2). Written for bash 3.2, so it runs on stock macOS.
- **One-line installer** that is safe to pipe, pinnable by SHA-256, and never touches anything outside two directories.
- **`anonbox doctor`** tells you what to fix before the first run.

## How it works

```
 your machine                         private network "anonbox-net"  (no gateway, no route out)
 ┌─────────────┐                     ┌───────────────────────────────┐
 │ your files  │      nothing        │  workstation  (Debian)        │
 │ your LAN    │◄──── shared ───╳────│   no route · no DNS · no caps │
 └─────────────┘                     │   ALL_PROXY=socks5h://GW:9050 │
                                     └───────────────┬───────────────┘
                                                     │ two TCP ports, both end in Tor
                                     ┌───────────────▼───────────────┐
                                     │  gateway: Tor (+ HTTP proxy)  │──► Tor network ──► the internet
                                     └───────────────────────────────┘
```

Two containers, one private network:

1. The **gateway** runs Tor and a tiny pass-through HTTP proxy. It is attached to the private network *and* to the engine's
   normal bridge, so only Tor itself can reach the outside.
2. The **workstation** is attached to the private network *only*. The sole things it can reach are the gateway's SOCKS5 port
   (9050) and HTTP-proxy port (8118). Proxy variables for curl, wget, git, pip, apt, ssh and friends are preconfigured, and
   names are resolved by Tor (`socks5h`), so nothing is resolved locally.

Because the enforcement is the network, **unsetting the proxy variables doesn't leak, it just stops working.**

## Install

> **One line (Linux, macOS, Windows via WSL2):**
> ```bash
> curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash
> ```

The installer downloads a pinned release, checks its layout, installs to `~/.local/share/anonbox`, links
`~/.local/bin/anonbox`, and runs `anonbox doctor`. It **never** uses `sudo` on its own, refuses to run as root, and touches
nothing else. Useful variations:

```bash
# Also install Podman with your package manager (shows the exact commands and asks before running sudo):
curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash -s -- --install-deps

# Read it first, then run it:
curl -fsSLO https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh && less install.sh && bash install.sh

# Pin an exact version and verify its SHA-256 (the installer prints the hash of whatever it downloads):
curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | \
  ANONBOX_REF=v0.1.0 ANONBOX_SHA256=<sha256-of-the-tarball> bash

# From a clone, with no download at all:
git clone https://github.com/spignelon/anonbox.git && cd anonbox && ./install.sh --local
```

**Windows:** anonbox runs inside WSL2. In PowerShell:
`irm https://raw.githubusercontent.com/spignelon/anonbox/main/install.ps1 | iex` (installs inside your WSL2 distribution).
See [GUIDE.md › Windows](GUIDE.md#windows-wsl2) first. This path is untested so far.

Update with `anonbox update`; uninstall with `anonbox purge` then `anonbox uninstall`.

## Supported platforms

| Platform | Container engine | Status |
|---|---|---|
| **Linux** (Debian/Ubuntu, Fedora/RHEL, openSUSE, Arch) | Podman (rootless, recommended) | ✅ Tested on openSUSE Tumbleweed |
| Linux | Docker (rootful, or rootless Docker) | ✅ Tested on openSUSE Tumbleweed and on Ubuntu (GitHub Actions) with rootful Docker |
| **macOS** (recent versions, Intel and Apple silicon) | Podman machine, Docker Desktop, Colima, OrbStack | 🟡 Expected to work, **not yet tested** |
| **Windows 10 (2004+) / 11** | WSL2 + Podman or Docker Desktop (WSL integration) | 🟡 Expected to work, **not yet tested** |
| FreeBSD, native Windows shells, WSL1 | n/a | ❌ Not supported (need Linux containers / user-defined networks) |

Installer detection of apt, dnf, zypper and pacman was exercised on Ubuntu 24.04, Fedora, Arch and openSUSE Tumbleweed. The CLI is checked
under bash 3.2. CPU: x86-64 is tested; arm64 should work because the images use multi-architecture Debian packages.

## Before you install: checklist

`anonbox doctor` checks all of this for you; this is what it looks for and how to fix each item.

| # | Requirement | Check | If missing |
|---|---|---|---|
| 1 | A **container engine**, preferably rootless Podman | `podman --version` or `docker --version` | `--install-deps`, or [GUIDE › Installing a container engine](GUIDE.md#installing-a-container-engine) |
| 2 | The engine is **reachable** | `podman info` / `docker info` | macOS: `podman machine start`. Docker: start the service, join the `docker` group |
| 3 | **Rootless prerequisites** (Linux + Podman) | `grep "^$USER:" /etc/subuid` | `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER && podman system migrate` |
| 4 | **WSL2**, not WSL1 (Windows) | `wsl -l -v` shows VERSION 2 | `wsl --set-version <distro> 2` |
| 5 | **About 1 GB free disk** (the two images are ~470 MB) | `df -h ~` | free some space |
| 6 | **Internet access** to Docker Hub once (base image) and to the Tor network | `curl -I https://registry-1.docker.io/v2/` | check proxy/firewall |
| 7 | A **correct clock** (Tor refuses to bootstrap if it is hours off) | `date` | enable NTP |
| 8 | A **free private subnet** (default `10.89.77.0/24`) | `anonbox doctor` | `ANONBOX_SUBNET=10.201.5.0/24 anonbox up` |
| 9 | **bash 3.2+, tar, curl** (or wget) | `bash --version` | install them (all present by default on macOS/Linux) |
| 10 | Not running as **root** | `id -u` is not 0 | use your normal user |

## Quick tour

```console
$ anonbox doctor          # pre-flight checks
$ anonbox up              # first run builds two small images (1-2 minutes), starts Tor, waits until it is ready
$ anonbox check           # 12 leak tests, from inside the workstation
$ anonbox shell           # a shell in the workstation (user "user", home /home/user)
$ anonbox run curl -s https://check.torproject.org/api/ip
$ anonbox run -C project uv run --with requests script.py     # run in a folder, uv fetches dependencies over Tor
$ anonbox newid           # new Tor circuits (new exit IP)
$ anonbox stop            # pause, keep files   |   anonbox down   # wipe everything
```

| Command | What it does |
|---|---|
| `anonbox up [--rebuild]` | Build (first time), start the gateway, wait for Tor, start the workstation |
| `anonbox shell [--root] [-C DIR]` | Interactive shell. `--root` for `apt install` (still no network powers) |
| `anonbox run [-C DIR] CMD...` | Run one command, optionally inside a folder |
| `anonbox put PATH...` | Copy files/folders **into** the workstation (`~/in`) |
| `anonbox get PATH...` | Copy files/folders **out** to `~/anonbox-out/<timestamp>/` |
| `anonbox check` | Verify Tor routing and the isolation (12 checks) |
| `anonbox ip` | Show the current Tor exit IP |
| `anonbox newid` | Ask Tor for new circuits |
| `anonbox status` / `logs [N]` | Container state and Tor progress / gateway log |
| `anonbox stop` / `down [-y]` | Pause (keep files) / delete the workstation |
| `anonbox purge [-y]` | `down`, plus remove the images |
| `anonbox doctor` | Pre-flight checks for this machine |
| `anonbox update` / `uninstall` / `version` | Maintenance |

## Moving files in and out

```console
$ anonbox put ./script.py ./data/        # host -> workstation: lands in /home/user/in/
$ anonbox run python3 in/script.py       # run it, over Tor
$ anonbox get work/results/              # workstation -> host: lands in ~/anonbox-out/20261113-142530/
```

Files go through a tar stream in the engine, not a shared folder, so the workstation never has access to your disk.

- `put` copies only what you name and does **not follow symlinks**, so a link inside a folder you copy can't smuggle in a file
  you didn't choose.
- `get` writes to a private (`0700`) timestamped folder, never overwrites anything, strips execute bits, and copies symlinks as
  plain files (resolved *inside* the container). **Treat everything you fetch as untrusted.**

## How secure is it?

Short version: **strong against accidental and casual leaks, and a solid sandbox for scripts, but not a substitute for Tails or a
VM when the adversary is capable and targeting you.**

What it gives you:
- Your IP address and DNS stay out of what the workstation connects to, even for programs that ignore proxy settings.
- Code in the workstation cannot read your files or reach your LAN.
- Rootless Podman, no capabilities, `no-new-privileges`, no mounts, no published ports, a Tor control interface that is not a
  network port.

What it does not give you:
- Protection from what *you* do (logging in to your accounts links the session to you).
- Immunity from kernel exploits (containers share the host kernel on Linux; use a VM for hostile code).
- Hiding Tor use from your ISP (bridges are on the [roadmap](#roadmap)), browser anti-fingerprinting, or host amnesia.

Read the full [threat model](SECURITY.md) before relying on it. Run `anonbox check` to test your own installation.

## Use cases

- **Run an unfamiliar script** and be sure it can neither read your files nor reveal your address.
- **Download from sources you'd rather not connect to directly** (`wget`, `aria2c`, `git clone`, package indexes).
- **Research and scraping** with `requests`, `curl` or `uv run` without your own IP in the logs.
- **Reproducible, throw-away environments** for testing installers and packages, then `anonbox down`.
- **Reaching `.onion` services** from scripts and CLI tools.
- **A clean separation** between "things I do anonymously" and your normal machine, without a VM.
- **Privacy-minded development**, e.g. fetching dependencies over Tor.

Please use it lawfully. Tor and anonbox are tools; you are responsible for what you do with them.

## Drawbacks and limitations

- **Not Tails.** Your host still keeps traces: container storage, images, `~/anonbox-out`, your shell history.
- **Shared kernel** on Linux. A container is a strong boundary against scripts, not against a determined kernel exploit.
- **TCP only, through proxies.** No UDP (no QUIC/HTTP3, no ping), no IPv6. Programs that cannot use a SOCKS/HTTP proxy
  (some torrent clients, game launchers) will not connect.
- **Tor is slow** and some sites block Tor exits or show CAPTCHAs.
- **The first build uses your normal network** (Docker Hub and Debian mirrors), once.
- **Tor use is visible to your ISP** until bridges are supported; some networks block Tor entirely.
- **No browser.** It is a CLI workstation; use Tor Browser for web browsing.
- **Identity separation is manual:** circuits may be shared across everything in the workstation. Use `anonbox newid` or
  `down` + `up` between tasks.
- **Docker daemon is root** on Linux (unless rootless Docker); prefer Podman.
- macOS and Windows support has **not been tested yet**.

## How it compares

| | anonbox | Tails | Whonix | Tor Browser | torsocks / proxychains |
|---|---|---|---|---|---|
| Form | 2 containers, CLI | Live OS (USB) | 2 VMs | Browser | Wrapper command |
| Runs on your existing OS | ✅ | ❌ (reboot) | ✅ (VM) | ✅ | ✅ |
| Fail-closed for all programs | ✅ network-enforced | ✅ | ✅ | n/a | ❌ app must cooperate |
| Runs arbitrary CLI tools/scripts | ✅ | ✅ | ✅ | ❌ | ✅ |
| Isolated from host files | ✅ | ✅ | ✅ | ❌ | ❌ |
| Resists kernel exploits | ❌ (shared kernel) | ✅ | ✅ (VM) | ❌ | ❌ |
| Leaves no trace on the host | ❌ | ✅ | ❌ | ❌ | ❌ |
| Footprint | ~470 MB of images, starts in seconds | USB stick | ~GBs | small | tiny |

anonbox sits between a wrapper command and a full amnesic OS: much stronger than `torsocks`, much lighter than Tails/Whonix.

## Configuration

Environment variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `ANONBOX_ENGINE` | auto (`podman`, else `docker`) | Container engine |
| `ANONBOX_SUBNET` | `10.89.77.0/24` | Private network (an IPv4 /24; the gateway is `.2`). Change if it clashes with yours |
| `ANONBOX_OUT` | `~/anonbox-out` | Where `anonbox get` writes |
| `ANONBOX_NAME` | `anonbox` | Name prefix for the containers and network (use another name and subnet to run a second instance) |
| `ANONBOX_PREFIX`, `ANONBOX_BIN_DIR` | `~/.local/share/anonbox`, `~/.local/bin` | Installer locations |
| `ANONBOX_REF`, `ANONBOX_SHA256` | pinned release, none | Installer: version to install and its expected SHA-256 |

## Project layout

```
anonbox/
├── bin/anonbox                  the CLI (bash 3.2+)
├── images/
│   ├── gateway/                 Tor + privoxy image (templated config, entrypoint)
│   └── workstation/             Debian workstation image
├── install.sh                   curl | bash installer (Linux, macOS, WSL)
├── install.ps1                  Windows front end (runs install.sh inside WSL2)
├── tests/                       lint.sh (shellcheck) and smoke.sh (end-to-end)
├── .github/workflows/ci.yml     lint, bash 3.2 check, image builds
├── README.md  GUIDE.md  SECURITY.md  CONTRIBUTING.md  CHANGELOG.md  LICENSE
```

## Roadmap

- Tor **bridges** / pluggable transports (obfs4, Snowflake) for networks that block Tor
- Multiple isolated sessions at once, with separate circuits (`anonbox --profile`)
- A read-only workstation root and tmpfs home for a stricter amnesic mode
- Verified macOS and Windows (WSL2) support, and prebuilt multi-arch images
- Optional per-session network log of destinations (for auditing what a script contacted)

## Contributing

Issues and pull requests are welcome; please read [CONTRIBUTING.md](CONTRIBUTING.md) first. Report security issues privately as
described in [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 spignelon. anonbox is free software, released under the
**GNU General Public License v3.0 or later**. See [LICENSE](LICENSE). It is distributed without any warranty.

anonbox builds on [Tor](https://www.torproject.org/), [Debian](https://www.debian.org/), [Privoxy](https://www.privoxy.org/),
[Podman](https://podman.io/) and [uv](https://docs.astral.sh/uv/); each remains under its own license.
