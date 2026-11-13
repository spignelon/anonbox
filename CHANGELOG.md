# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-13

First release.

### Added
- `anonbox` CLI: `up`, `shell`, `run`, `put`, `get`, `check`, `ip`, `newid`, `status`, `logs`, `stop`, `down`,
  `purge`, `doctor`, `update`, `uninstall`, `version`.
- Two-container design: a Tor **gateway** (Tor + a pass-through HTTP proxy) and a Debian **workstation** attached
  only to an internal network with no route to the outside world.
- Works with rootless **Podman** (recommended) and **Docker**.
- `anonbox check`: 12 leak and isolation checks, run from inside the workstation.
- `anonbox doctor`: pre-flight checks for the machine (OS, WSL2, engine, rootless setup, subnet, registry access).
- Quarantined file transfer: `put` never follows symlinks, `get` strips execute bits and flattens symlinks.
- `install.sh` (`curl | bash` friendly, optional SHA-256 pinning, refuses to run as root, never uses `sudo` on its own)
  and `install.ps1` (Windows, installs inside WSL2).
- Configurable private subnet (`ANONBOX_SUBNET`), instance name, output folder and engine.
- Tools preinstalled in the workstation: curl, wget, aria2, git, openssh-client, Python 3 + pip/venv/pipx, **uv**,
  archive tools, jq, dnsutils.

[0.1.0]: https://github.com/spignelon/anonbox/releases/tag/v0.1.0
