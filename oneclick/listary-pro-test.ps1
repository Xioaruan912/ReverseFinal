# Listary 6 Pro - one-command installer
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\listary-pro-test.ps1
#
# What it does:
#   1. warns that artifacts come from GitHub (slow in mainland China) and offers alternatives
#   2. asks where to install Listary (default: Desktop\Listary) and for a test email
#   3. downloads the pinned installer + tool pack, verifies sha256
#   4. installs the pinned build silently, then writes a self-consistent entitlement
#   5. leaves a normal, activated Listary Pro installation
#
# Result: a regular installed Listary (tray icon -> Settings shows Pro)
# No .md files, no reports, no evidence dumps are produced.
#
# Optional environment variables:
#   LISTARY_INSTALLDIR   install directory (skips the prompt)
#   LISTARY_EMAIL        email used for the entitlement (default %USERNAME%@lab.local)
#   LISTARY_YES          =1  non-interactive, accept all defaults
#   LISTARY_SKIP_INSTALL =1  Listary already installed, skip the installer
#   LISTARY_RESTORE      =1  remove the entitlement and exit
#   LISTARY_MIRROR       mirror prefix for the release download (optional)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose: param() only parses when
#     the file is the script entry point (so "irm | iex" fails), and a UTF-8 BOM
#     survives "irm" as a stray character that breaks the first line.
#   * Write-Host goes to the host stream, so prompts never pollute returned values.
#
# Pinned version : Listary 6.3.5.94
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

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
$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1'

# ---- options ----------------------------------------------------------------
$Auto        = ($env:LISTARY_YES -eq '1')
$SkipInstall = ($env:LISTARY_SKIP_INSTALL -eq '1')
$Restore     = ($env:LISTARY_RESTORE -eq '1')
$Mirror      = $env:LISTARY_MIRROR
$Email       = if ($env:LISTARY_EMAIL) { $env:LISTARY_EMAIL } else { "$env:USERNAME@lab.local" }
$Desktop     = [Environment]::GetFolderPath('Desktop')
$DefaultInstall = Join-Path $Desktop 'Listary'

function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

# Only prompt when a real interactive console is attached. Otherwise a redirected
# stdin makes Read-Host return immediately (or block forever under some hosts),
# so every question must fall back to its default.
function Test-Interactive {
    if ($Auto) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    return $true
}

function Ask-Dir($label, $default) {
    if (-not (Test-Interactive)) { return $default }
    while ($true) {
        Write-Host $label -ForegroundColor White
        Write-Host ("    default [" + $default + "]") -ForegroundColor DarkGray
        Write-Host -NoNewline "    input (Enter = default): " -ForegroundColor DarkGray
        $v = $null
        try { $v = Read-Host } catch { return $default }
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        return $v.Trim().Trim('"')
    }
}

function Safe-Remove($path) {
    $full = [IO.Path]::GetFullPath($path)
    $parts = $full.TrimEnd('\').Split('\') | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 3) { Warn "refusing to delete shallow path: $full"; return }
    if (Test-Path $full) { Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue }
}

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
    $urls = @($url)
    if ($Mirror) { $urls += ($Mirror.TrimEnd('/') + '/' + (Split-Path $url -Leaf)) }
    $done = $false
    foreach ($u in $urls) {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fL --retry 3 --connect-timeout 15 --max-time 1800 -o $tmp $u
            if ($LASTEXITCODE -ne 0) { continue }
        } else {
            try { (New-Object Net.WebClient).DownloadFile($u, $tmp) } catch { continue }
        }
        if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -eq $expectSha) { $done = $true; break }
        Warn "sha256 mismatch from $u"
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    if (-not $done) {
        Die "$label download failed or failed verification`n      expected $expectSha`n      place it manually at $dest"
    }
    Move-Item $tmp $dest -Force
    Ok "$label verified"
}

# ---- dependencies: detect and auto-install ----------------------------------
# One rule: whatever this installer needs, it installs itself.
# Here everything ships with Windows: PowerShell 5.1, Expand-Archive and
# Get-FileHash. There is nothing external to download, so the check is a guard
# (old PowerShell) rather than an installer.
function Ensure-Deps {
    $need = @()
    if ($PSVersionTable.PSVersion.Major -lt 5) { $need += 'PowerShell 5.1 or newer' }
    foreach ($c in @('Expand-Archive','Get-FileHash','Start-Process')) {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { $need += $c }
    }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        Write-Host '  [..] curl.exe missing - falling back to the built-in WebClient downloader' -ForegroundColor DarkGray
    }
    if ($need.Count) {
        Die ('missing, and Windows cannot install these silently: ' + ($need -join ', '))
    }
    Ok 'dependencies OK (all built into Windows PowerShell)'
}

# ---- banner ----------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor White
Write-Host " Listary $PINNED_VER - one-command install"                     -ForegroundColor White
Write-Host " result: a normal, activated Listary Pro installation"        -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host " [!] artifacts are downloaded from GitHub; in mainland China this can be slow (setup ~12 MB + main ~2 MB)." -ForegroundColor Yellow
Write-Host "     if that is a problem, either:" -ForegroundColor Yellow
Write-Host "       - use a mirror:  `$env:LISTARY_MIRROR='https://your-mirror/xxx'" -ForegroundColor DarkGray
Write-Host "       - download the two files manually and put them into the temp folder, then re-run" -ForegroundColor DarkGray
if (-not (Test-Interactive)) {
    Write-Host " (non-interactive run: using defaults; set LISTARY_INSTALLDIR to choose a folder)" -ForegroundColor DarkGray
}
Write-Host ""

# ---- ask where to install ---------------------------------------------------
$InstallDir = if ($env:LISTARY_INSTALLDIR) { $env:LISTARY_INSTALLDIR } else { Ask-Dir "Select the Listary install folder" $DefaultInstall }
Ok "install folder: $InstallDir"
Ok "test email    : $Email"
Ensure-Deps

$Stage = Join-Path $env:TEMP ('listary-stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

try {
    # ---- 1/3 tool pack ------------------------------------------------------
    Head '1/3  fetch tool pack'
    $packZip = Join-Path $Stage $PACK_NAME
    Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'tool pack'
    $case = Join-Path $Stage 'case'
    Expand-Archive -Path $packZip -DestinationPath $case -Force
    Ok "unpacked tool pack"

    # ---- 2/3 pinned installer + main binary --------------------------------
    Head "2/3  fetch Listary $PINNED_VER installer"
    $setupPath = Join-Path $Stage $SETUP_NAME
    $mainPath  = Join-Path $Stage $MAIN_NAME
    Get-Pinned "$REL_BASE/$SETUP_NAME" $setupPath $SETUP_SHA "Listary $PINNED_VER installer"
    Get-Pinned "$REL_BASE/$MAIN_NAME"  $mainPath  $MAIN_SHA  "Listary $PINNED_VER main binary"

    $tool = Join-Path $case 'tools\Listary6Pro.exe'
    if (-not (Test-Path $tool)) { Die 'test tool not found in the pack (unexpected package layout)' }

    if ($Restore) {
        & $tool restore
        Ok 'entitlement removed, exiting'; exit 0
    }

    # ---- 3/3 install + activate --------------------------------------------
    Head '3/3  install and activate'
    $installed = Join-Path $InstallDir 'Listary.exe'

    if (Test-Path $installed) {
        $h = (Get-FileHash $installed -Algorithm SHA256).Hash.ToLower()
        if ($h -eq $MAIN_SHA) { Ok "already installed and matches the pinned version ($PINNED_VER)" }
        else { Warn "installed build differs from the pinned version; reinstalling" ; $SkipInstall = $false }
    }

    if (-not (Test-Path $installed) -and -not $SkipInstall) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        Warn "installing the pinned build ($PINNED_VER) into: $InstallDir"
        $rp = Start-Process -FilePath $setupPath `
            -ArgumentList ('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="' + $InstallDir + '"')) `
            -Wait -PassThru
        Ok "install finished (exit=$($rp.ExitCode))"
        Start-Sleep -Seconds 3
    }

    & $tool info
    Write-Host ""
    & $tool activate $Email
}
finally {
    Safe-Remove $Stage
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " done" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host " Listary  : $(Join-Path $InstallDir 'Listary.exe')" -ForegroundColor White
Write-Host " version  : $PINNED_VER" -ForegroundColor DarkGray
Write-Host " launch   : tray icon, or the desktop shortcut" -ForegroundColor DarkGray
Write-Host " rollback : `$env:LISTARY_RESTORE='1'; irm $ONECLICK_URL | iex" -ForegroundColor DarkGray
Write-Host " uninstall: `"$(Join-Path $InstallDir 'unins000.exe')`" /VERYSILENT" -ForegroundColor DarkGray
