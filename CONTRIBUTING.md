# Contributing to anonbox

Thanks for helping. anonbox is a small project with a security-sensitive purpose, so changes are reviewed with that in mind.

## Ground rules
- **Fail closed.** Any change must keep the property that a program in the workstation with no proxy support has *no* path
  to the network. If a change adds a route, a DNS server, a published port, a mount or a capability to the workstation, it
  needs a written justification in the pull request.
- **Portable shell.** `bin/anonbox` and `install.sh` must run on bash 3.2 (macOS) with BSD userland tools: no associative
  arrays, `mapfile`, `${var,,}`, `readlink -f`, GNU-only `tar`/`sed`/`find` flags on the host side.
- **Both engines.** Test with Podman *and* Docker.
- Keep documentation (`README.md`, `GUIDE.md`, `SECURITY.md`) in step with behaviour, and add a line to `CHANGELOG.md`.

## Development setup
```bash
git clone https://github.com/spignelon/anonbox.git && cd anonbox
bin/anonbox doctor          # run straight from the checkout, no install needed
tests/lint.sh               # bash -n + shellcheck (uses a container if shellcheck is not installed)
tests/smoke.sh              # end-to-end: needs an engine and internet (talks to the real Tor network)
ANONBOX_ENGINE=docker tests/smoke.sh
```
The smoke test uses its own instance name and subnet (`anonbox-smoke`, `10.89.99.0/24`), so it will not touch a real one.

## Pull requests
- One concern per pull request, with a description of what changed, why, and which checks you ran
  (engine, OS, `tests/lint.sh`, `tests/smoke.sh`).
- Conventional commit titles are appreciated (`fix:`, `feat:`, `docs:`, `chore:`).
- By contributing you agree that your work is licensed under the project's license, GPL-3.0-or-later.

## Reporting security problems
Please do **not** open a public issue. See [SECURITY.md](SECURITY.md).
