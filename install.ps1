# SPDX-License-Identifier: GPL-3.0-or-later
#
# anonbox installer for Windows.
#
# anonbox is a Linux tool (Podman/Docker containers), so on Windows it runs inside WSL2. This script checks that WSL2 is
# available, picks a distribution, and runs the regular Linux installer inside it.
#
#   irm https://raw.githubusercontent.com/spignelon/anonbox/main/install.ps1 | iex
#
# Or download it, read it, and run:   powershell -ExecutionPolicy Bypass -File .\install.ps1 [-Distro Ubuntu] [-InstallerArgs "--install-deps"]
#
# NOTE: the Windows path has not been tested yet. Reports and fixes are welcome.

param(
  [string]$Distro = "",
  [string]$InstallerArgs = "",
  [string]$Url = "https://raw.githubusercontent.com/spignelon/anonbox/main/install.sh"
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) { Write-Host "error: $Message" -ForegroundColor Red; exit 1 }
function Info([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Fail "WSL is not installed. In an administrator PowerShell run:  wsl --install  (then reboot and run this script again). See GUIDE.md > Windows."
}

# `wsl -l -v` prints UTF-16; decode it, then pick a WSL2 distribution (never the Docker Desktop helper ones).
$previous = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
$listing = (wsl.exe -l -v) | Out-String
[Console]::OutputEncoding = $previous

$candidates = @()
foreach ($line in ($listing -split "`r?`n" | Select-Object -Skip 1)) {
  $clean = ($line -replace "^\s*\*?\s*", "").Trim()
  if ($clean -match "^(?<name>\S+)\s+(?<state>\S+)\s+(?<version>\d)$") {
    if ($Matches.name -notmatch "^docker-desktop" -and $Matches.version -eq "2") { $candidates += $Matches.name }
  }
}

if ($Distro -eq "") {
  if ($candidates.Count -eq 0) { Fail "no WSL2 Linux distribution found. Install one with:  wsl --install -d Ubuntu  (then run this script again)." }
  $Distro = $candidates[0]
} elseif ($candidates -notcontains $Distro) {
  Fail "'$Distro' is not an installed WSL2 distribution. Available: $($candidates -join ', ')"
}

Info "Installing anonbox inside WSL2 distribution '$Distro'"
$command = "curl -fsSL '$Url' | bash -s -- $InstallerArgs"
wsl.exe -d $Distro -- bash -lc $command
if ($LASTEXITCODE -ne 0) { Fail "the installer failed inside WSL (exit code $LASTEXITCODE)" }

Write-Host ""
Write-Host "Done. Open the '$Distro' terminal and run:  anonbox up" -ForegroundColor Green
Write-Host "Tip: you can reach Windows files from WSL under /mnt/c/..., e.g.  anonbox put /mnt/c/Users/you/script.py"
