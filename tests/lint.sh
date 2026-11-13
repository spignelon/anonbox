#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Static checks: bash syntax + shellcheck on every shell script. Uses a local shellcheck if present,
# otherwise the official shellcheck image through podman/docker.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=(bin/anonbox install.sh images/gateway/entrypoint.sh tests/lint.sh tests/smoke.sh)

for f in "${files[@]}"; do bash -n "$f"; done
echo "bash -n: ok (${#files[@]} files)"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S style "${files[@]}"
else
  engine=""
  for e in podman docker; do command -v "$e" >/dev/null 2>&1 && { engine="$e"; break; }; done
  [ -n "$engine" ] || { echo "shellcheck not found and no container engine to run it" >&2; exit 1; }
  "$engine" run --rm --user 0 -v "$PWD:/mnt:ro,Z" docker.io/koalaman/shellcheck:stable -x -S style "${files[@]}"
fi
echo "shellcheck: ok"
