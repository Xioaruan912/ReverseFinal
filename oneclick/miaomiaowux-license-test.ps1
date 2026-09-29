# MiaomiaowuX - white-box authorization audit - one-command runner (Windows entry point)
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   $env:MMWX_DISTRO='Debian'; $env:PORT='12889'
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\miaomiaowux-license-test.ps1
#
# Optional environment variables:
#   MMWX_DISTRO  WSL distribution to use (default: Debian, then Ubuntu, then the first found)
#   PORT         panel port (default 12889)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose. param() only parses when
#     the file is the script entry point (so "irm | iex" fails with UnexpectedAttribute),
#     and a UTF-8 BOM survives "irm" as a stray character that breaks the first line.
#   * MiaomiaowuX itself is Linux software, so the real work runs inside WSL.
#
# Pinned version : miaomiaowuX v0.5.4
# Requirement    : WSL2 with any Debian/Ubuntu distribution

$ErrorActionPreference = 'Stop'

$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh'
$PINNED_VER   = 'v0.5.4'

$Distro = $env:MMWX_DISTRO
$Port   = if ($env:PORT) { [int]$env:PORT } else { 12889 }

function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

Write-Host "============================================================" -ForegroundColor White
Write-Host " MiaomiaowuX white-box audit - one-command run (Windows -> WSL)" -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " artifact source: this repo's release (whitebox-audit-v1.0)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

Head '1/3  check WSL'
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Die 'wsl.exe not found. Install WSL2 first:  wsl --install'
}
$list = (& wsl.exe -l -q) -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
if (-not $list) { Die 'no WSL distribution found. Run:  wsl --install -d Debian' }
Ok ("available distributions: " + ($list -join ', '))

if ([string]::IsNullOrWhiteSpace($Distro)) {
    $pick = $list | Where-Object { $_ -match 'Debian' } | Select-Object -First 1
    if (-not $pick) { $pick = $list | Where-Object { $_ -match 'Ubuntu' } | Select-Object -First 1 }
    if (-not $pick) { $pick = $list[0] }
    $Distro = $pick.Trim()
}
Ok "using distribution: $Distro"

Head '2/3  check dependencies inside WSL'
$chk = & wsl.exe -d $Distro -- bash -lc "for t in curl unzip python3; do command -v \$t >/dev/null || echo MISSING:\$t; done; command -v upx >/dev/null || echo MISSING:upx"
if ($chk) {
    Write-Host $chk -ForegroundColor Yellow
    Write-Host "  install them (Debian/Ubuntu):" -ForegroundColor DarkGray
    Write-Host "    wsl -d $Distro -u root -- bash -c 'apt-get update && apt-get install -y curl unzip python3 upx-ucl'" -ForegroundColor DarkGray
    Die 'install the missing packages and re-run'
}
Ok 'dependencies OK (curl / unzip / python3 / upx)'

Head '3/3  run the white-box audit inside WSL'
Write-Host "  [..] fetching and executing: $ONECLICK_URL" -ForegroundColor DarkGray
Write-Host "  [..] port: $Port   (Ctrl+C stops it)" -ForegroundColor DarkGray
Write-Host ""

& wsl.exe -d $Distro -- bash -lc "PORT=$Port bash <(curl -fsSL '$ONECLICK_URL')"
