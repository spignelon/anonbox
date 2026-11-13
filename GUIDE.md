# anonbox guide

A step-by-step guide to installing and using anonbox: from a fresh machine to everyday workflows, with every command shown.
For the one-page overview see [README.md](README.md); for the security model see [SECURITY.md](SECURITY.md).

**Contents**

1. [Concepts in two minutes](#1-concepts-in-two-minutes)
2. [Before you install](#2-before-you-install)
   - [Linux](#linux) · [macOS](#macos) · [Windows (WSL2)](#windows-wsl2) · [Installing a container engine](#installing-a-container-engine)
3. [Installing anonbox](#3-installing-anonbox)
4. [First run](#4-first-run)
5. [Everyday use](#5-everyday-use)
6. [Examples](#6-examples)
7. [Moving files in and out](#7-moving-files-in-and-out)
8. [Verifying your anonymity](#8-verifying-your-anonymity)
9. [Good habits](#9-good-habits)
10. [Configuration](#10-configuration)
11. [Updating and uninstalling](#11-updating-and-uninstalling)
12. [Troubleshooting](#12-troubleshooting)
13. [FAQ](#13-faq)

---

## 1. Concepts in two minutes

anonbox runs **two containers** on a private network:

- the **gateway** runs Tor. It is the only thing with access to the internet.
- the **workstation** is a Debian system you work in. It is attached **only** to the private network, so it has *no route*
  to the internet, *no DNS*, and no way to reach your machine. The only thing it can talk to is the gateway's Tor proxy.

Everything you run in the workstation therefore goes through Tor, or goes nowhere. You never have to remember to "turn on" a
proxy for safety: a program that ignores proxy settings simply fails to connect.

Vocabulary used below:

| Term | Meaning |
|---|---|
| **host** | your real machine (laptop, desktop, WSL2 distribution) |
| **workstation** | the Debian container you work in (`anonbox shell`) |
| **gateway** | the Tor container (you rarely touch it) |
| **engine** | Podman or Docker, whatever runs the containers |
| **quarantine** | the folder `~/anonbox-out/<timestamp>/` where files you `get` land |

## 2. Before you install

Run through this once. Or skip to [Installing anonbox](#3-installing-anonbox) and let `anonbox doctor` tell you what's missing:
it checks everything below and prints the fix for each problem.

### Checklist (all platforms)

- [ ] A **container engine** is installed and running: **rootless Podman** (recommended), or Docker. See
  [Installing a container engine](#installing-a-container-engine).
- [ ] You are using your **normal user**, not root.
- [ ] About **1 GB of free disk space** (the two images are about 470 MB).
- [ ] **Internet access** for the first build: Docker Hub (the Debian base image) and the Debian package mirrors. After that, only
  Tor traffic is needed.
- [ ] Your system **clock is correct**. Tor refuses to start if the clock is off by hours: check with `date`, enable NTP if needed.
- [ ] Your network **doesn't block Tor**. Some corporate, school and national networks do. If `anonbox up` stalls at "waiting
  for Tor", see [Troubleshooting](#12-troubleshooting).
- [ ] The default **private subnet `10.89.77.0/24` is free** on your machine. If you use a VPN or Docker setup that already
  uses it, pick another range (`ANONBOX_SUBNET`, see [Configuration](#10-configuration)).
- [ ] `bash` 3.2+ and `tar` (and `curl` or `wget` for the installer). All standard on Linux and macOS.

### Linux

1. **Install Podman** (see the commands per distribution [below](#installing-a-container-engine)).
2. **Rootless prerequisites.** Rootless Podman needs a range of sub-user IDs for your account:
   ```bash
   grep "^$USER:" /etc/subuid /etc/subgid        # should print one line from each file
   ```
   If nothing prints:
   ```bash
   sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
   podman system migrate
   ```
   On Debian/Ubuntu make sure the `uidmap` package is installed (provides `newuidmap`/`newgidmap`).
3. **Check it works:** `podman info` should print without errors.
4. **Ubuntu 24.04+:** unprivileged user namespaces are restricted by AppArmor, but the distribution's own `podman` package ships
   the profile that allows them. Install Podman from `apt`, not from a downloaded binary.
5. **SELinux (Fedora, RHEL):** nothing to do: anonbox mounts no host folders.
6. **Using Docker instead?** Your user must be able to talk to the daemon (`docker info` works without `sudo`). Adding yourself
   to the `docker` group does that, but it is equivalent to giving that user root. Prefer Podman or
   [rootless Docker](https://docs.docker.com/engine/security/rootless/).

### macOS

Containers on macOS run inside a small Linux VM, which also means the container boundary is a VM boundary: stronger than on Linux.

1. Install [Homebrew](https://brew.sh) if you don't have it.
2. Pick **one** engine:
   - **Podman** (recommended, free, no daemon):
     ```bash
     brew install podman
     podman machine init --cpus 2 --memory 2048
     podman machine start
     ```
   - **Docker Desktop**, **Colima** (`brew install colima docker && colima start`) or **OrbStack**: install and start it.
3. Check: `podman info` (or `docker info`) prints without error.
4. macOS ships bash 3.2 and BSD tools. anonbox is written for exactly that, so no extra tools are needed.

> macOS has **not been tested yet**. If something fails, `anonbox doctor` output in an issue is very welcome.

### Windows (WSL2)

anonbox is a Linux tool, so on Windows it runs **inside WSL2**. Native PowerShell, `cmd` and Git Bash are not supported.

1. Windows 10 (version 2004 or later) or Windows 11.
2. Install WSL2 and a distribution. In an **administrator** PowerShell:
   ```powershell
   wsl --install -d Ubuntu
   ```
   Reboot if asked, then open *Ubuntu* from the Start menu and create your Linux user.
3. Confirm it is WSL **2**: `wsl -l -v` must show `VERSION 2`. If it says 1: `wsl --set-version Ubuntu 2`.
4. Inside the Ubuntu terminal, install a container engine:
   - **Podman:** `sudo apt update && sudo apt install -y podman uidmap`
   - or **Docker Desktop** for Windows with *Settings → Resources → WSL integration* enabled for your distribution.
5. If Podman complains about cgroups or systemd, enable systemd in WSL: add the following to `/etc/wsl.conf`, then run
   `wsl --shutdown` from PowerShell and reopen Ubuntu:
   ```ini
   [boot]
   systemd=true
   ```
6. Install anonbox **inside the Ubuntu terminal** with the Linux one-liner (next section), or run
   `irm https://raw.githubusercontent.com/spignelon/anonbox/main/install.ps1 | iex` from PowerShell, which does the same inside WSL.
7. Windows files are under `/mnt/c/...` in WSL, so `anonbox put /mnt/c/Users/you/script.py` works.

> Windows has **not been tested yet**.

### Installing a container engine

`install.sh --install-deps` offers to do the following for you, showing the commands and asking before it runs `sudo`.

| Distribution | Install Podman |
|---|---|
| Debian, Ubuntu, Mint | `sudo apt update && sudo apt install -y podman uidmap` |
| Fedora, RHEL, Rocky, Alma | `sudo dnf install -y podman` |
| openSUSE | `sudo zypper install podman` |
| Arch, Manjaro | `sudo pacman -S podman` |
| Alpine (best effort) | `sudo apk add podman fuse-overlayfs shadow-uidmap bash curl` (rootless needs `/etc/subuid` entries) |
| macOS | `brew install podman && podman machine init && podman machine start` |

If `podman info` complains about a missing network helper, install `passt` (Podman 5+) or `slirp4netns` (older Podman).

Docker: follow [docs.docker.com/engine/install](https://docs.docker.com/engine/install/). Prefer rootless Docker, or accept that
the daemon is root on your machine.

## 3. Installing anonbox

**The one-liner** (Linux, macOS, and inside WSL2):

```bash
curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash
```

What happens: it detects your OS, downloads a pinned release, checks that the archive has the expected files and that
`bin/anonbox` parses, installs to `~/.local/share/anonbox`, links `~/.local/bin/anonbox`, and runs `anonbox doctor`.
What does **not** happen: no `sudo`, no root, no changes outside those two paths, no telemetry. It refuses to run as root.

If `anonbox` isn't found afterwards, `~/.local/bin` isn't in your `PATH`; the installer prints the exact line to add
(`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && exec bash`, or the zsh/fish equivalent).

### Other ways to install

```bash
# Let it install Podman too (asks before running sudo, shows each command first):
curl -fsSL https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh | bash -s -- --install-deps

# Inspect first, then run (recommended if you don't know the project yet):
curl -fsSLO https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh
less install.sh
bash install.sh

# Pin the version and verify the download's SHA-256 (the installer prints the hash it computed):
ANONBOX_REF=v0.1.0 ANONBOX_SHA256=<expected-sha256> bash install.sh

# No download at all: from a clone (also how you develop on it)
git clone https://github.com/spignelon/anonbox.git
cd anonbox && ./install.sh --local          # or just run ./bin/anonbox straight from the checkout

# A different location:
ANONBOX_PREFIX=$HOME/apps/anonbox ANONBOX_BIN_DIR=$HOME/bin bash install.sh
```

All installer options: `bash install.sh --help`.

> **Private forks or a private repository:** the unauthenticated `curl` URL above returns *404* for a private repository. Use
> `gh repo clone <owner>/anonbox && cd anonbox && ./install.sh --local` instead.

## 4. First run

```console
$ anonbox doctor
```
Fix anything marked `[FAIL]` (each comes with a hint). Then:

```console
$ anonbox up
[anonbox] building the gateway image (Tor + privoxy); the build uses your normal network, not Tor
[anonbox] building the workstation image (Debian + tools + uv)
[anonbox] starting the Tor gateway
[anonbox] waiting for Tor to bootstrap (up to 3 minutes)...
[anonbox] Tor is up
[anonbox] creating the workstation
[anonbox] ready. Open a shell with: anonbox shell
```

The first `up` builds the images (1–2 minutes). Later runs start in seconds plus Tor's bootstrap (~10–30 s).

```console
$ anonbox check
[anonbox] leak checks (everything below runs inside the workstation)
  [ OK ] web traffic exits through Tor: {"IsTor":true,"IP":"185.220.101.45"}
  [ OK ] a direct connection that ignores the proxy fails (no route out)
  [ OK ] no local DNS (names are only resolved by Tor)
  [ OK ] no default route
  [ OK ] direct UDP is impossible (OSError)
  [ OK ] raw sockets denied (PermissionError)
  [ OK ] gateway port 22 closed
  ...
```

All twelve should be `[ OK ]`. If any says `[FAIL]`, stop and see [Troubleshooting](#12-troubleshooting).

```console
$ anonbox shell
user@anonbox:~$ curl -s https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.45"}
user@anonbox:~$ exit
```

## 5. Everyday use

| I want to... | Command |
|---|---|
| Start / resume | `anonbox up` |
| Open a shell | `anonbox shell` |
| Open a shell in a folder | `anonbox shell -C project` |
| Run one command | `anonbox run curl -s https://example.com` |
| Run it in a folder | `anonbox run -C project python3 script.py` |
| Install a package with apt | `anonbox shell --root`, then `apt-get update && apt-get install -y <pkg>` |
| Copy a file in | `anonbox put ./file.zip` → `/home/user/in/file.zip` |
| Copy a file out | `anonbox get work/result.csv` → `~/anonbox-out/<time>/result.csv` |
| See my current exit IP | `anonbox ip` |
| Get a different exit IP | `anonbox newid` |
| Check the setup | `anonbox check` |
| Pause (keep files) | `anonbox stop` |
| Wipe everything | `anonbox down` |
| See what's going on | `anonbox status`, `anonbox logs 100` |

Paths given to `-C` and `get` are relative to `/home/user` in the workstation unless they start with `/`.

Where things are in the workstation: `~/in` (what `put` brings), `~/work` (a scratch folder for you), tools in the usual places.

## 6. Examples

All of these were run for real against the Tor network. Commands that go through `anonbox run` work the same inside
`anonbox shell`.

### Download a file

```bash
anonbox run wget -O work/file.iso https://example.org/file.iso
anonbox run aria2c -d work -o file.iso https://example.org/file.iso     # resumable, multi-connection
anonbox run curl -fLO --output-dir work https://example.org/file.iso
anonbox get work/file.iso
```

Long downloads: start them in the background inside the workstation so they survive your terminal closing:
```bash
anonbox run bash -c 'nohup aria2c -d work -c https://example.org/big.iso > work/dl.log 2>&1 &'
anonbox run tail -f work/dl.log        # watch (Ctrl-C stops watching, not the download)
```

### Clone a repository

```bash
anonbox run git clone --depth 1 https://github.com/astral-sh/uv-pre-commit.git work/uv-pre-commit
anonbox run ls work/uv-pre-commit
```

`git` over SSH also goes through Tor (the workstation's SSH client is preconfigured):
```bash
anonbox run ssh -T git@github.com     # "Permission denied (publickey)" means it connected; add a key to authenticate
```

### Run a Python script with dependencies (uv)

`uv` is preinstalled. Dependencies download through Tor.

```bash
cat > fetch_ip.py <<'PY'
# /// script
# dependencies = ["requests"]
# ///
import requests
print(requests.get("https://check.torproject.org/api/ip", timeout=60).json())
PY

anonbox put fetch_ip.py
anonbox run -C in uv run fetch_ip.py
# {'IsTor': True, 'IP': '185.220.101.19'}
```

Without a script file: `anonbox run uv run --no-project --with requests python -c "import requests; print(requests.get('http://example.com').status_code)"`.

Classic virtualenv and pip also work:
```bash
anonbox run bash -c 'cd work && python3 -m venv v && ./v/bin/pip install requests && ./v/bin/python -c "import requests"'
```

### Scrape or call an API

```bash
anonbox run -C in uv run --with requests --with beautifulsoup4 scraper.py
anonbox get work/output.json
```
Use `anonbox newid` between runs if you want a different exit IP, and expect some sites to block Tor.

### Reach a .onion site

```bash
anonbox run curl -s -o /dev/null -w '%{http_code}\n' \
  https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
```

### Install system packages

```bash
anonbox shell --root
root@anonbox:/home/user# apt-get update && apt-get install -y tree ffmpeg
```
`--root` is root **inside** the container: it can install software but has no network powers (no `NET_ADMIN`/`NET_RAW`) and no
access to your files. `apt` itself goes through Tor (SOCKS), so expect it to be slower than usual. Installed packages live
only until `anonbox down`.

### Talk to a service with its own client

Anything that supports a SOCKS5 or HTTP proxy works. Both are already set in the environment; to see them:
```bash
anonbox run bash -c 'echo "$ALL_PROXY / $https_proxy"'      # socks5h://10.89.77.2:9050 / http://10.89.77.2:8118
anonbox run curl -x "$ALL_PROXY" https://example.com        # explicit, if a tool ignores the variable
```
Tools with **no** proxy support (some torrent clients, game launchers) cannot connect at all, by design.

### Two separate sessions

Use a different name and subnet so they don't share anything:
```bash
ANONBOX_NAME=research ANONBOX_SUBNET=10.89.80.0/24 anonbox up
ANONBOX_NAME=research ANONBOX_SUBNET=10.89.80.0/24 anonbox shell
```
(Export the two variables in your shell to avoid repeating them.)

## 7. Moving files in and out

```console
$ anonbox put ./script.py ./data/          # host -> workstation: /home/user/in/script.py, /home/user/in/data/
$ anonbox run python3 in/script.py         # run it, over Tor
$ anonbox get work/results/ work/log.txt   # workstation -> host
[anonbox] copied to /home/you/anonbox-out/20261113-142530
```

- There is **no shared folder.** Files travel as a tar stream through the engine, so the workstation never has access to your disk.
- **`put`** copies exactly what you name, with spaces and subfolders intact. It does **not follow symlinks**: a link inside a
  folder you copy arrives as a (dangling) link, so it can't pull in a file you didn't choose.
- **`get`** goes to `~/anonbox-out/<timestamp>/` (permissions `0700`), never overwrites existing files, **removes execute bits**,
  and copies symlinks as plain files with the content they resolve to *inside the container*.
- Change the destination with `ANONBOX_OUT=/some/folder`.
- **Treat everything you `get` as untrusted.** It came from the internet via code you may not trust: scan it, open it in a
  sandbox, or read it as text before using it. Don't `chmod +x` and run it on your host.

## 8. Verifying your anonymity

- `anonbox check`: twelve automated tests (Tor exit, no direct path, no DNS, no default route, no UDP, no raw sockets, only the
  two proxy ports open on the gateway). Run it after `up`, and after upgrading your engine.
- `anonbox ip`: shows the exit IP; compare with your real one (`curl https://check.torproject.org/api/ip` on the host
  shows `"IsTor":false`).
- `anonbox logs`: the gateway log, including Tor's bootstrap and circuit messages.

To prove to yourself that the isolation is real, try to break it:
```bash
# A program that ignores the proxy settings has no route and no DNS:
anonbox run env -u ALL_PROXY -u all_proxy -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY curl -m 8 https://example.com
# curl: (6) Could not resolve host: example.com
anonbox run python3 -c "import socket; socket.create_connection(('1.1.1.1', 443), timeout=5)"
# OSError: [Errno 101] Network is unreachable
```

## 9. Good habits

- **Don't log in to accounts that identify you**, and don't reuse usernames or upload personal files. Tor hides your address, not
  your behaviour.
- **Use HTTPS/SSH.** The Tor exit relay can read plain HTTP.
- **One task, one identity:** run `anonbox newid` between unrelated tasks, or `anonbox down` then `anonbox up` for a clean slate.
- **Only `put` what the task needs.** Anything you copy in is visible to the code you run.
- **Reset when done:** `anonbox down` deletes the workstation and every file in it. Use `anonbox get` first for results.
- **Keep your engine and system updated.** The boundary is the container runtime and the kernel.
- **For truly hostile code,** run anonbox inside a VM (or on macOS/Windows, where the engine already runs in one).
- Remember the host keeps traces: the images, `~/anonbox-out`, and your shell history. anonbox is not amnesic like Tails.

## 10. Configuration

Set these in your shell profile or per command. All are optional.

| Variable | Default | Meaning |
|---|---|---|
| `ANONBOX_ENGINE` | `podman` if installed, else `docker` | Which engine to use |
| `ANONBOX_SUBNET` | `10.89.77.0/24` | Private network (IPv4 /24; the gateway gets `.2`). Must not overlap networks you use |
| `ANONBOX_NAME` | `anonbox` | Prefix for container and network names: `NAME-gw`, `NAME-ws`, `NAME-net` |
| `ANONBOX_OUT` | `~/anonbox-out` | Quarantine folder for `anonbox get` |
| `ANONBOX_INSTALL_URL` | the project's `install.sh` | Used by `anonbox update` |
| `NO_COLOR` | unset | Set to disable colours |

Changing `ANONBOX_SUBNET` or `ANONBOX_NAME` creates a separate instance: run `anonbox down` for the old one if you no longer
want it. Each subnet gets its own workstation image (built once, with cached layers) because the image embeds the gateway's address.

## 11. Updating and uninstalling

```bash
anonbox update              # re-runs the installer for the latest release
anonbox up --rebuild        # rebuild the images (picks up new Tor/Debian packages)
```

Uninstall:
```bash
anonbox purge -y            # remove the containers, network and images
anonbox uninstall           # remove the program and its link
```
If you uninstalled first, remove the engine objects by hand:
`podman rm -f anonbox-ws anonbox-gw; podman network rm anonbox-net; podman rmi $(podman images -q 'localhost/anonbox-*')`
(use `docker` in place of `podman` if that's your engine). Also delete `~/anonbox-out` if you no longer want the files in it.

## 12. Troubleshooting

Start with `anonbox doctor`, then `anonbox status` and `anonbox logs 100`.

| Symptom | Cause and fix |
|---|---|
| `no container engine found` | Install Podman or Docker ([guide](#installing-a-container-engine)). |
| `cannot talk to podman` (macOS) | The machine isn't running: `podman machine start` (first time: `podman machine init`). For Docker Desktop/Colima/OrbStack, start the app. |
| `permission denied ... docker.sock` | Your user can't use Docker. Join the `docker` group (root-equivalent) and log in again, or use Podman. |
| Rootless Podman errors about `newuidmap`, `subuid` or user namespaces | Install `uidmap`; add subuid/subgid ranges (see [Linux](#linux)); `podman system migrate`; log out and in. On Ubuntu 24.04+ use the `apt` package of Podman. |
| `could not create the private network ... overlaps` | Another network already uses `10.89.77.0/24`. `ANONBOX_SUBNET=10.201.5.0/24 anonbox up`. |
| `anonbox up` stops at `waiting for Tor to bootstrap` / `Tor did not finish bootstrapping` | (1) Check the clock: `date`. (2) Run `anonbox logs 100` for Tor's messages. (3) Your network may block Tor (some corporate/school/national networks do): try another network or a VPN. Bridges are on the roadmap. |
| Build fails with network errors | The first build needs Docker Hub and Debian mirrors on your normal network. Check your proxy/firewall; retry. |
| `anonbox check` shows `[FAIL]` | Don't trust the setup. `anonbox down -y && anonbox up --rebuild`, and run `check` again. If it persists, open an issue with the full output. |
| A site is slow, blocks you, or shows CAPTCHAs | Normal for Tor. `anonbox newid` for a new exit; retry later. |
| A tool can't connect | It doesn't support a SOCKS/HTTP proxy, or ignores the environment. Pass the proxy explicitly (`echo $ALL_PROXY` shows it) or use another tool. By design there is no other way out. |
| `apt` is very slow or fails | It goes through Tor. Retry; it has retries enabled. `anonbox shell --root`, then `apt-get update`. |
| `anonbox: command not found` | `~/.local/bin` isn't in `PATH`; the installer printed the line to add. |
| WSL: engine or cgroup errors | Enable systemd in `/etc/wsl.conf` (see [Windows](#windows-wsl2)), `wsl --shutdown`, reopen. Confirm WSL **2** with `wsl -l -v`. |
| Disk is filling up | `anonbox purge -y` removes images; `podman system prune` clears build cache. |
| `anonbox up` after a reboot stalls once | The gateway restarts and re-bootstraps Tor (about 30 s); this is normal. |

Still stuck? Open an issue with the output of `anonbox version`, `anonbox doctor`, `anonbox status`, `anonbox logs 100`, and your OS
and engine versions. Please **don't** paste secrets or private data; and report anything that looks like a leak privately (see
[SECURITY.md](SECURITY.md)).

## 13. FAQ

**Is this the same as running Tor Browser?** No. Tor Browser is a hardened browser. anonbox is a command-line workstation for
scripts and tools; it does not provide Tor Browser's fingerprinting protections. Use Tor Browser for web browsing.

**Does it make me anonymous?** It hides your IP address and DNS from the sites your code contacts and keeps that code away from
your files. It does not hide what you do or who you log in as, and it does not hide Tor use from your ISP. See
[SECURITY.md](SECURITY.md).

**Why not just `torsocks`/`proxychains`?** Those depend on each program cooperating; one that doesn't leaks your real address. In
anonbox the network layout makes leaking impossible instead of discouraged.

**Why Podman over Docker?** Rootless Podman has no root daemon: even if something escaped the container it would start as your
unprivileged user. Docker works too, but its daemon runs as root on Linux.

**Can I use my host's Tor instead of a Tor container?** Not by design: reaching the host's Tor would require a path from the
container to your machine, which is exactly what anonbox removes. The gateway runs its own Tor.

**Can I run a browser inside it?** Technically you can install one with `apt`, but it won't have Tor Browser's anti-fingerprinting
and there is no display passed through. Not recommended.

**Does it support IPv6, UDP, torrents?** No: Tor carries TCP only, and anonbox has no IPv6 path. Torrent clients that need
UDP/DHT won't work, and torrenting over Tor is discouraged.

**Where is my data?** The workstation's files live in the container's storage until `anonbox down`. Files you fetched are in
`~/anonbox-out`. Nothing is sent anywhere by anonbox itself.

**How do I report a bug or contribute?** See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).
