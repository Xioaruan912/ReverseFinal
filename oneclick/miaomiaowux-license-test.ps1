# MiaomiaowuX - white-box authorization audit - one-command runner (Windows entry point)
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\miaomiaowux-license-test.ps1
#
# Behavior (pure installer: produces a running service, no .md / reports / evidence):
#   * warns that artifacts come from GitHub (slow in mainland China) and offers alternatives
#   * asks you where to install miaomiaowuX inside WSL (default /opt/mmwx)
#   * hands the work to WSL, which fetches the pinned binary and verifies sha256
#   * installs it as a systemd service, enabled at boot, and verifies it came up
#
# Optional environment variables:
#   MMWX_DISTRO     WSL distribution (default: Debian, then Ubuntu, then the first found)
#   MMWX_INSTALLDIR install directory inside WSL (skips the prompt, default /opt/mmwx)
#   MMWX_YES        =1  non-interactive, accept all defaults
#   MMWX_NO_SERVICE =1  install only, do not register the systemd service
#   MMWX_MIRROR     mirror prefix for the release download (optional)
#   PORT            panel port (default 12889)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose. param() only parses when
#     the file is the script entry point (so "irm | iex" fails with UnexpectedAttribute),
#     and a UTF-8 BOM survives "irm" as a stray character that breaks the first line.
#   * MiaomiaowuX is Linux software, so the real work runs inside WSL.
#
# Pinned version : miaomiaowuX v0.5.4
# Requirement    : WSL2 with any Debian/Ubuntu distribution

$ErrorActionPreference = 'Stop'

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII -----
# A raw UTF-8 .ps1 without BOM is mis-read as ANSI by Windows PowerShell 5.1, which
# garbles the text AND can break parsing; a BOM on the other hand breaks "irm | iex".
# Keeping the source ASCII and decoding at runtime avoids both problems.
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }


$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh'
$PINNED_VER   = 'v0.5.4'

$Distro = $env:MMWX_DISTRO
$Port   = if ($env:PORT) { [int]$env:PORT } else { 12889 }
$Auto   = ($env:MMWX_YES -eq '1')
$Mirror = $env:MMWX_MIRROR

function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

Write-Host "============================================================" -ForegroundColor White
Write-Host " MiaomiaowuX white-box audit - one-command run (Windows -> WSL)" -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " artifact source: GitHub (this repo's release)"              -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host (T 'IFshXSDmnoTku7bku44gR2l0SHViIOS4i+i9ve+8jOS4reWbveWkp+mZhue9kee7nOWPr+iDvei+g+aFou+8iOS4u+eoi+W6j+e6piAzNSBNQu+8ieOAgg==') -ForegroundColor Yellow
Write-Host (T 'ICAgICDoi6XkuIvovb3lm7Dpmr7vvJokZW52Ok1NV1hfTUlSUk9SPSdodHRwczovL3lvdXItbWlycm9yL21td3gnIOWQjumHjei3kQ==') -ForegroundColor DarkGray
Write-Host ""

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

Head '2/3  dependencies inside WSL (auto-install)'
# One rule: whatever the script needs, it installs itself.
# The .sh performs the full bootstrap; here we only pre-warm it so the user sees
# progress before the long download, and so the first run works on a bare image.
$Probe = 'miss=""; for t in curl unzip upx; do command -v $t >/dev/null || miss="$miss $t"; done; printf ''%s'' "$miss"'
$miss = (& wsl.exe -d $Distro -- bash -lc $Probe) -join ''
if ($miss.Trim()) {
    Warn ("missing inside WSL:" + $miss + " - installing automatically")
    $Fix = 'set -e; ' +
           'for t in curl unzip; do command -v $t >/dev/null && continue; ' +
           'if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq $t; ' +
           'elif command -v apk >/dev/null; then apk add --no-cache $t; ' +
           'elif command -v dnf >/dev/null; then dnf install -y -q $t; ' +
           'elif command -v yum >/dev/null; then yum install -y -q $t; ' +
           'elif command -v pacman >/dev/null; then pacman -Sy --noconfirm --needed $t; fi; done; ' +
           'command -v upx >/dev/null || { ' +
           'if command -v apt-get >/dev/null; then apt-get update -qq && (apt-get install -y -qq upx-ucl || apt-get install -y -qq upx); ' +
           'elif command -v apk >/dev/null; then apk add --no-cache upx; ' +
           'elif command -v dnf >/dev/null; then dnf install -y -q upx; ' +
           'elif command -v yum >/dev/null; then yum install -y -q upx; ' +
           'elif command -v pacman >/dev/null; then pacman -Sy --noconfirm --needed upx; fi; }'
    & wsl.exe -d $Distro -u root -- bash -lc $Fix | Out-Null
    $still = (& wsl.exe -d $Distro -- bash -lc $Probe) -join ''
    if ($still.Trim()) { Die ("still missing inside WSL:" + $still + " - neither the package manager nor sudo worked") }
    Ok 'missing packages installed automatically'
}
Ok 'dependencies OK (curl / unzip / upx)'

Head "3/3  install inside WSL (port $Port)"
Write-Host "  [..] the WSL script will ask you for the install directory (Enter = /opt/mmwx)." -ForegroundColor DarkGray
Write-Host "  [..] the result is a systemd service, enabled at boot; intermediates are cleaned." -ForegroundColor DarkGray
Write-Host ""

$envbits = "PORT=$Port MMWX_YES=$([int]$Auto)"
if ($Mirror) { $envbits += " MMWX_MIRROR='$Mirror'" }
if ($env:MMWX_NO_SERVICE -eq '1') { $envbits += " MMWX_NO_SERVICE=1" }
if ($env:MMWX_INSTALLDIR) { $envbits += " MMWX_INSTALLDIR='$($env:MMWX_INSTALLDIR)'" }

& wsl.exe -d $Distro -- bash -lc "$envbits bash <(curl -fsSL '$ONECLICK_URL')"
