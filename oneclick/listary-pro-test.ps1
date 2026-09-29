# Listary 6 Pro - white-box authorization audit - one-command runner
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   $env:LISTARY_EMAIL='you@example.com'; $env:LISTARY_SKIP_INSTALL='1'
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\listary-pro-test.ps1
#
# Optional environment variables:
#   LISTARY_EMAIL         email used for the test (default %USERNAME%@lab.local)
#   LISTARY_WORKDIR       working directory (default %TEMP%\listary-lab)
#   LISTARY_SKIP_INSTALL  =1  Listary already installed, skip silent install
#   LISTARY_RESTORE       =1  roll back the test and exit
#
# This script is deliberately ASCII-only and has no param()/[CmdletBinding()]:
#   * param()/[CmdletBinding()] only parse when the file is the script entry point,
#     so "irm | iex" would fail with UnexpectedAttribute.
#   * a UTF-8 BOM survives "irm" as a stray character and breaks the first line.
#   Both invocation styles therefore stay safe with plain ASCII + env vars.
#
# Pinned version : Listary 6.3.5.94
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0
# Never contacts : the vendor account server or its "latest" download

$ErrorActionPreference = 'Stop'

# ---- lock file (only edit here when bumping the version) --------------------
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'Listary-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = '46d55be0531899ab056add204c6a24c00f0582c0803133ebe71437ed6bba678a'
$SETUP_NAME  = 'Listary-6.3.5.94-setup.exe'
$SETUP_SHA   = 'c62249e0d4d49bd3f062d55635cf6a3ab089ea8ee7f6c03947f6febfafaa0288'
$MAIN_NAME   = 'Listary-6.3.5.94-main.exe'
$MAIN_SHA    = 'be2aec5c06d2731cb89a9799ffeeffdb063afe0da7f1dfcdeb33c6929e7b20d9'
$PINNED_VER  = '6.3.5.94'
$INSTALL_DIR = Join-Path $env:ProgramFiles 'Listary'
$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1'

# ---- options (environment variables) ----------------------------------------
$Email       = if ($env:LISTARY_EMAIL)   { $env:LISTARY_EMAIL }   else { "$env:USERNAME@lab.local" }
$WorkDir     = if ($env:LISTARY_WORKDIR) { $env:LISTARY_WORKDIR } else { Join-Path $env:TEMP 'listary-lab' }
$SkipInstall = ($env:LISTARY_SKIP_INSTALL -eq '1')
$Restore     = ($env:LISTARY_RESTORE      -eq '1')

function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

function Get-Pinned($url, $dest, $expectSha, $label) {
    if (Test-Path $dest) {
        if ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $expectSha) {
            Ok "$label already present and verified"; return
        }
        Warn "$label local copy failed verification, re-downloading"
        Remove-Item $dest -Force
    }
    Write-Host "  [..] downloading $label"
    Write-Host "       $url"
    $tmp = "$dest.part"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -fL --retry 3 --connect-timeout 15 --max-time 1800 -o $tmp $url
        if ($LASTEXITCODE -ne 0) { Die "$label download failed" }
    } else {
        try { (New-Object Net.WebClient).DownloadFile($url, $tmp) } catch { Die "$label download failed: $_" }
    }
    $got = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $expectSha) {
        Remove-Item $tmp -Force
        Die "$label sha256 mismatch`n      expected $expectSha`n      actual   $got"
    }
    Move-Item $tmp $dest -Force
    Ok "$label verified"
}

Write-Host "============================================================" -ForegroundColor White
Write-Host " Listary 6 Pro white-box audit - one-command run"            -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " test email     : $Email"                                    -ForegroundColor White
Write-Host " artifact source: this repo's release (whitebox-audit-v1.0)" -ForegroundColor White
Write-Host " work directory : $WorkDir"                                  -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# ---- 1) test toolkit --------------------------------------------------------
Head '1/4  fetch test toolkit (this repo release)'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$packZip = Join-Path $WorkDir $PACK_NAME
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'test toolkit'
$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "extracted to $caseRoot"

# ---- 2) pinned installer + main binary --------------------------------------
Head "2/4  fetch Listary $PINNED_VER installer and main binary (this repo release)"
$setupPath = Join-Path $WorkDir $SETUP_NAME
$mainPath  = Join-Path $WorkDir $MAIN_NAME
Get-Pinned "$REL_BASE/$SETUP_NAME" $setupPath $SETUP_SHA "Listary $PINNED_VER installer"
Get-Pinned "$REL_BASE/$MAIN_NAME"  $mainPath  $MAIN_SHA  "Listary $PINNED_VER main binary"

# ---- 3) prepare the target --------------------------------------------------
Head '3/4  prepare the target'
$installed = Join-Path $INSTALL_DIR 'Listary.exe'

if ($Restore) {
    $tool = Join-Path $caseRoot 'tools\Listary6Pro.exe'
    if (Test-Path $tool) { & $tool restore } else { Warn 'test tool not found, cannot restore' }
    Ok 'restore done, exiting'; exit 0
}

if (Test-Path $installed) {
    $h = (Get-FileHash $installed -Algorithm SHA256).Hash.ToLower()
    if ($h -eq $MAIN_SHA) {
        Ok "installed Listary matches the pinned version ($PINNED_VER)"
    } else {
        Warn 'installed Listary hash differs from the pinned version'
        Write-Host "      installed: $h" -ForegroundColor DarkGray
        Write-Host "      pinned   : $MAIN_SHA" -ForegroundColor DarkGray
        Warn 'conclusion may not apply to this build; re-run on a clean machine'
    }
} elseif ($SkipInstall) {
    Die "Listary not found ($installed) but LISTARY_SKIP_INSTALL=1 was set"
} else {
    Warn "Listary not found - running a silent install of the pinned build ($PINNED_VER)"
    $rp = Start-Process -FilePath $setupPath `
        -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait -PassThru
    Ok "install finished (exit=$($rp.ExitCode))"
    Start-Sleep -Seconds 3
}

# ---- 4) run the audit -------------------------------------------------------
Head '4/4  run the white-box audit'
$tool = Join-Path $caseRoot 'tools\Listary6Pro.exe'
if (-not (Test-Path $tool)) { Die 'tools\Listary6Pro.exe not found (unexpected package layout)' }

Write-Host "  -- current state --" -ForegroundColor DarkGray
& $tool info

Write-Host ""
Write-Host "  -- running the audit (writes a self-consistent entitlement, then restarts) --" -ForegroundColor DarkGray
& $tool activate $Email

Write-Host ""
Write-Host "  -- re-check --" -ForegroundColor DarkGray
& $tool info

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " done"                                                       -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host " Open Listary (tray icon -> Settings) and check the Pro status." -ForegroundColor White
Write-Host ""
Write-Host " roll back to the pre-test state (either one):" -ForegroundColor DarkGray
Write-Host "   `$env:LISTARY_RESTORE='1'; irm $ONECLICK_URL | iex" -ForegroundColor DarkGray
Write-Host "   $caseRoot\tools\Listary6Pro.exe restore" -ForegroundColor DarkGray
Write-Host ""
Write-Host " evidence and report: $caseRoot\reports\" -ForegroundColor White
