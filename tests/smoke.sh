#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end smoke test: brings anonbox up, runs the leak checks, round-trips a file, resets everything.
# Needs a working container engine and internet access (it talks to the Tor network).
#
#   tests/smoke.sh                       # uses podman if present, else docker
#   ANONBOX_ENGINE=docker tests/smoke.sh
#   ANONBOX_SUBNET=10.89.99.0/24 ANONBOX_NAME=anonbox-test tests/smoke.sh   # avoid clashing with a real instance
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export ANONBOX_NAME="${ANONBOX_NAME:-anonbox-smoke}"
export ANONBOX_SUBNET="${ANONBOX_SUBNET:-10.89.99.0/24}"
work="$(mktemp -d)"
export ANONBOX_OUT="$work/out"
A=./bin/anonbox
fail=0

trap '"$A" down -y >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

step() { printf '\n== %s\n' "$*"; }
expect() { if "$@"; then printf '  ok:   %s\n' "$*"; else printf '  FAIL: %s\n' "$*"; fail=1; fi; }

step "doctor";  "$A" doctor
step "up";      "$A" up
step "check (12 leak checks)"; expect "$A" check
step "exit IP is a Tor exit"; expect bash -c "$A ip | grep -q '\"IsTor\":true'"
step "new identity";          expect "$A" newid

step "file round trip (host -> workstation -> host)"
mkdir -p "$work/in dir"; echo "round-trip payload" > "$work/in dir/payload file.txt"
expect "$A" put "$work/in dir"
expect "$A" run bash -c 'cp "in/in dir/payload file.txt" work/result.txt'
expect "$A" get work/result.txt
expect bash -c "grep -q 'round-trip payload' \"$work\"/out/*/result.txt"
expect bash -c "[ -z \"\$(find \"$work/out\" -type f -perm -u+x)\" ]"

step "run -C and uv"
expect "$A" run -C in uv --version

step "stop and resume keep the files"
"$A" stop
expect "$A" up
expect "$A" run test -f work/result.txt

if [ "$fail" -ne 0 ]; then echo; echo "SMOKE TEST FAILED"; exit 1; fi
echo; echo "SMOKE TEST PASSED"
