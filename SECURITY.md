# Security policy and threat model

anonbox reduces what a script, tool or download can learn about **you** and **your machine**. It is not magic, and it is not
Tails. This document states exactly what it is designed to do, how, and where it stops.

- [What anonbox protects](#what-anonbox-protects)
- [What anonbox does not protect](#what-anonbox-does-not-protect)
- [How the protection works](#how-the-protection-works)
- [Hardening applied](#hardening-applied)
- [Attack surface](#attack-surface)
- [What has been tested](#what-has-been-tested)
- [Operational advice](#operational-advice)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## What anonbox protects

| Goal | How it is achieved |
|---|---|
| **Your IP address is not revealed to the sites and servers the workstation talks to** | The workstation has no route to the internet. Every connection it makes goes through the Tor gateway, so the far end sees a Tor exit relay. |
| **No DNS leaks** | The workstation has no DNS resolver. Names are resolved by Tor itself (`socks5h`), never by your resolver or ISP. |
| **Software that ignores proxy settings cannot leak** | Setting `ALL_PROXY` is only a convenience. Enforcement is the network layout: a program that ignores the variable has nowhere to connect and fails (`anonbox check` proves it on every run). |
| **Scripts you run cannot read your files** | The workstation has no bind mounts and no shared folders. It sees only what you explicitly copy in with `anonbox put`. |
| **Scripts cannot see or reach your local network or host services** | No route to the host or LAN; the host's loopback is not mapped in. |
| **A hostile download cannot silently follow a symlink to your files** | `get` copies symlinks as plain files (resolved *inside* the container) and strips execute bits; `put` never follows symlinks. |
| **A broken or stopped Tor does not downgrade to a direct connection** | There is no direct path to fall back to. If Tor is down, connections fail. |

## What anonbox does not protect

Be honest with yourself about these before relying on it.

- **Who you are, if you tell the site.** Logging in to your own accounts, reusing usernames, uploading identifying files, or
  putting personal data into forms ties the session to you. Tor hides the network address, not behaviour.
- **Your ISP can see that you use Tor.** Your machine connects to the Tor network from your real IP (to bootstrap and to carry
  the circuits). Bridges/pluggable transports are not implemented yet (see the roadmap).
- **Traffic analysis by a global observer**, malicious relays at both ends of a circuit, and other limits of Tor itself. See
  the [Tor project's documentation](https://support.torproject.org/).
- **Plaintext traffic is visible to the exit relay.** Use HTTPS/SSH. Tor does not encrypt the last hop to the destination.
- **Browser or device fingerprinting.** anonbox is a CLI workstation. It does not run Tor Browser's anti-fingerprinting
  measures; do not use it to run a normal browser and expect Tor Browser's guarantees.
- **A kernel-level container escape.** Containers share the host's kernel (on Linux). A determined, kernel-exploiting
  program can break out of any container. anonbox makes that harder (rootless, no capabilities, no mounts) but is not a
  virtual machine. If the code is actively hostile and targeted at you, run anonbox inside a VM.
- **Amnesia of the host.** Unlike Tails, anonbox does not hide that it was used from the host machine: images, shell history
  of the host (commands you typed), `~/anonbox-out` and container storage all live on your disk. `anonbox down` wipes the
  workstation, not forensic traces on the host.
- **Identity separation between tasks.** All traffic from the workstation can share Tor circuits and the same exit. Use
  `anonbox newid` between tasks, or `anonbox down` and `up` for a clean slate, if you need separation.
- **Anything before Tor is up.** Building the images downloads a Debian base image and packages over your normal network, not
  through Tor, once.

## How the protection works

```
 host machine                    anonbox-net  (--internal: no gateway, no route out)
 ┌────────────┐                 ┌──────────────────────────────────────────────────────┐
 │ your files │   nothing       │  workstation (Debian, uid 1000)                      │
 │ your LAN   │◄── shared ──╳───│   no default route · no DNS · no capabilities        │
 └────────────┘                 │   env: ALL_PROXY=socks5h://GW:9050, http(s)_proxy=GW:8118
                                └───────────────┬──────────────────────────────────────┘
                                                │ only these two TCP ports on one address
                                ┌───────────────▼──────────────────────────────────────┐
                                │  gateway: tor (SOCKS 9050) + privoxy (HTTP 8118→9050)│
                                │  also attached to the engine's normal bridge ────────┼──► Tor network
                                └──────────────────────────────────────────────────────┘
```

The **workstation** is attached to one network only, created with `--internal` (the engine installs no default gateway and
does not NAT it). The **gateway** is attached to that internal network at a fixed address *and* to the engine's normal bridge
so that Tor itself can reach the Tor network. The workstation can reach exactly two TCP ports on the gateway; both end in Tor.

## Hardening applied

Workstation:
- Internal-only network: no default route, no DNS server, no UDP/ICMP path, no raw sockets (`--cap-drop ALL`).
- `--cap-drop ALL`, with only `CHOWN DAC_OVERRIDE FOWNER SETUID SETGID KILL` added back so `apt` works for the root shell
  (`anonbox shell --root`). No `NET_ADMIN`, `NET_RAW`, `SYS_ADMIN`.
- `no-new-privileges`, PID limit, runs as unprivileged `user` (uid 1000) by default.
- No volumes, no bind mounts, no published ports, no host networking, not privileged.

Gateway:
- `--cap-drop ALL`, `no-new-privileges`, PID limit; Tor runs as the unprivileged `debian-tor` user.
- SOCKS and HTTP proxy ports are bound to the internal-network address only; they are not published to the host.
- Tor's control interface is a unix socket **inside the gateway**; it is not a network port, so the workstation cannot reach it.
- privoxy runs with filtering and its web interface disabled; it is a pass-through into Tor's SOCKS port.

Engine:
- With **rootless Podman** (recommended) "root" in a container is an unprivileged user on your machine, so even a successful
  breakout starts without root. The engine's default seccomp profile applies.
- With **Docker** the daemon runs as root (unless you use rootless Docker). `anonbox doctor` warns about this.

Installer:
- Refuses to run as root, never calls `sudo` on its own, verifies the archive layout and (if you set `ANONBOX_SHA256`) its
  SHA-256, installs only to `~/.local/share/anonbox` and `~/.local/bin`, and is written so a truncated download cannot execute
  half a script (everything runs from one `main` call at the end).

## Attack surface

| Component | Exposure | Notes |
|---|---|---|
| Tor SOCKS port (gateway:9050) | reachable by the workstation | By design. Anything in the workstation can use Tor. |
| privoxy (gateway:8118) | reachable by the workstation | Small, filtering disabled; reaches only Tor. A vulnerability here would be reachable by workstation code. |
| Container runtime and kernel | shared with the host | The usual container boundary. |
| `anonbox put` / `get` | host ↔ workstation tar streams | `put` is limited to paths you name; `get` extracts only into a private quarantine folder and removes execute bits. |
| Image build | host network, once | Debian packages are installed with the distribution's package signatures. |

## What has been tested

- Linux (openSUSE Tumbleweed, kernel 7.x), **Podman 6.1 rootless** and **Docker 29.7 (rootful)**: `anonbox check` (12 checks), file
  transfer, stop/resume, reset, `.onion` access, and common tools (curl, wget, aria2, git, pip, uv, ssh, apt) through Tor.
- The full end-to-end smoke test (`tests/smoke.sh`) also runs on an Ubuntu GitHub Actions runner with Docker.
- Installer on Ubuntu 24.04, Fedora, Arch Linux containers (platform and package-manager detection, program install).
- The CLI and installer run under bash 3.2 (the macOS bash) in a container.
- **Not yet tested:** macOS (Podman machine, Docker Desktop, Colima, OrbStack), Windows (WSL2), Apple silicon. They are expected to
  work because the design only needs a container engine with user-defined internal networks; reports are welcome.

`anonbox check` runs these tests against your own installation any time you like.

## Operational advice

- Run `anonbox check` after `up` and after any engine upgrade.
- Treat everything you `get` as untrusted; scan it, open it in a sandbox, or inspect it as text first.
- Do not put secrets, SSH keys or tokens into the workstation unless the task needs them; `down` deletes them.
- Use `anonbox newid` between tasks that should not share an exit, or reset with `down`.
- Keep the engine and your distribution up to date; the container boundary is only as good as the kernel under it.
- Prefer rootless Podman. If you use Docker, know that its daemon is root on your machine.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue.

- Email **spignelon@proton.me** with the subject `anonbox security`, or
- use GitHub's *Report a vulnerability* button under the repository's **Security** tab once it is enabled.

Please include the version (`anonbox version`), your OS and engine, what you observed and how to reproduce it. You will get an
acknowledgement and an assessment; fixes are released as a patch version and credited in the changelog unless you prefer
otherwise.

Supported versions: the latest release only.
