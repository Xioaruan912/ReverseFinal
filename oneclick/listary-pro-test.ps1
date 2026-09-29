# Listary 6 Pro - white-box authorization audit - one-command runner
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\listary-pro-test.ps1
#
# Behavior:
#   * asks you where to install Listary and where to put the working directory
#   * installs the pinned build if needed, then runs the audit
#   * copies evidence to a persistent folder, then removes all intermediates
#
# Optional environment variables:
#   LISTARY_INSTALLDIR   where Listary is installed  (skips the prompt)
#   LISTARY_WORKDIR      working directory           (skips the prompt)
#   LISTARY_EVIDENCE     where evidence is kept (default %USERPROFILE%\ReverseAudit-Evidence)
#   LISTARY_EMAIL        email used for the test (default %USERNAME%@lab.local)
#   LISTARY_YES          =1  non-interactive, accept all defaults
#   LISTARY_KEEP_FILES   =1  do NOT clean up intermediates
#   LISTARY_SKIP_INSTALL =1  Listary already installed, skip the installer
#   LISTARY_RESTORE      =1  roll back the test and exit
#   LISTARY_MIRROR       mirror prefix for the release download (optional)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose. param() only parses when
#     the file is the script entry point (so "irm | iex" fails with UnexpectedAttribute),
#     and a UTF-8 BOM survives "irm" as a stray character that breaks the first line.
#
# Pinned version : Listary 6.3.5.94
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

$ErrorActionPreference = 'Stop'

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII -----
# A raw UTF-8 .ps1 without BOM is mis-read as ANSI by Windows PowerShell 5.1, which
# garbles the text AND can break parsing; a BOM on the other hand breaks "irm | iex".
# Keeping the source ASCII and decoding at runtime avoids both problems.
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }


# ---- lock file (only edit here when bumping the version) --------------------
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'Listary-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = '46d55be0531899ab056add204c6a24c00f0582c0803133ebe71437ed6bba678a'
$SETUP_NAME  = 'Listary-6.3.5.94-setup.exe'
$SETUP_SHA   = 'c62249e0d4d49bd3f062d55635cf6a3ab089ea8ee7f6c03947f6febfafaa0288'
$MAIN_NAME   = 'Listary-6.3.5.94-main.exe'
$MAIN_SHA    = 'be2aec5c06d2731cb89a9799ffeeffdb063afe0da7f1dfcdeb33c6929e7b20d9'
$PINNED_VER  = '6.3.5.94'
$CASE_NAME   = 'Listary'
$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1'

# ---- options ----------------------------------------------------------------
$Auto        = ($env:LISTARY_YES        -eq '1')
$KeepFiles   = ($env:LISTARY_KEEP_FILES -eq '1')
$SkipInstall = ($env:LISTARY_SKIP_INSTALL -eq '1')
$Restore     = ($env:LISTARY_RESTORE      -eq '1')
$Email       = if ($env:LISTARY_EMAIL) { $env:LISTARY_EMAIL } else { "$env:USERNAME@lab.local" }
$DefaultInstall = Join-Path $env:ProgramFiles 'Listary'
$DefaultWork    = Join-Path $env:USERPROFILE 'ReverseAudit\listary'
$EvidenceRoot   = if ($env:LISTARY_EVIDENCE) { $env:LISTARY_EVIDENCE } else { Join-Path $env:USERPROFILE 'ReverseAudit-Evidence' }

function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

function Ask-Dir($label, $default) {
    if ($Auto) { return $default }
    while ($true) {
        $v = $null
        try { $v = Read-Host "$label`n    default [$default]`n    input (Enter = default)" } catch { return $default }
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
    if ($env:LISTARY_MIRROR) { $urls += ($env:LISTARY_MIRROR.TrimEnd('/') + '/' + (Split-Path $url -Leaf)) }
    $done = $false
    foreach ($u in $urls) {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fL --retry 3 --connect-timeout 15 --max-time 1800 -o $tmp $u
            if ($LASTEXITCODE -ne 0) { continue }
        } else {
            try { (New-Object Net.WebClient).DownloadFile($u, $tmp) } catch { continue }
        }
        $got = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
        if ($got -eq $expectSha) { $done = $true; break }
        Warn "sha256 mismatch from $u"
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    if (-not $done) {
        Die "$label download failed or failed verification`n      expected $expectSha`n      place it manually at $dest"
    }
    Move-Item $tmp $dest -Force
    Ok "$label verified"
}

# ---- banner ----------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor White
Write-Host " Listary 6 Pro white-box audit - one-command run"              -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " artifact source: GitHub (this repo's release)"              -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host (T 'IFshXSDmnoTku7bku44gR2l0SHViIOS4i+i9ve+8jOS4reWbveWkp+mZhue9kee7nOWPr+iDvei+g+aFou+8iOWuieijheWMhee6piAxMiBNQiArIOS4u+eoi+W6jyAyIE1C77yJ44CC') -ForegroundColor Yellow
Write-Host (T 'ICAgICDoi6XkuIvovb3lm7Dpmr7vvIzlj6/ku7vpgInlhbbkuIDvvJo=')                                       -ForegroundColor Yellow
Write-Host (T 'ICAgICAgIC0g6Ieq5bu66ZWc5YOP77yaICAkZW52OkxJU1RBUllfTUlSUk9SPSdodHRwczovL3lvdXItbWlycm9yL3h4eCc=')  -ForegroundColor DarkGray
Write-Host (T 'ICAgICAgIC0g5YWI5omL5Yqo5LiL6L295pS+6L+b5bel5L2c55uu5b2V5ZCO6YeN6LeR77yI5Lya6Ieq5Yqo5qCh6aqMIHNoYTI1Nu+8iQ==')             -ForegroundColor DarkGray
Write-Host ""

# ---- ask install dir + work dir --------------------------------------------
$InstallDir = if ($env:LISTARY_INSTALLDIR) { $env:LISTARY_INSTALLDIR } else { Ask-Dir (T '6YCJ5oupIExpc3Rhcnkg5a6J6KOF55uu5b2V') $DefaultInstall }
$WorkDir    = if ($env:LISTARY_WORKDIR)    { $env:LISTARY_WORKDIR }    else { Ask-Dir (T '6YCJ5oup5bel5L2c55uu5b2V77yI5LiL6L295Lu25LiO5bel6KOF5Ymv5pys5pS+6L+Z6YeM77yM5rWL6K+V57uT5p2f6Ieq5Yqo5riF55CG77yJ') $DefaultWork }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Ok "install directory: $InstallDir"
Ok "work directory   : $WorkDir"
if ($KeepFiles) { Warn 'LISTARY_KEEP_FILES=1 - intermediates will be kept' }

$evidenceDir = Join-Path $EvidenceRoot (Join-Path $CASE_NAME (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ---- 1) test toolkit --------------------------------------------------------
Head '1/4  fetch test toolkit'
$packZip = Join-Path $WorkDir $PACK_NAME
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'test toolkit'
$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "extracted to $caseRoot"

# ---- 2) pinned installer + main binary --------------------------------------
Head "2/4  fetch Listary $PINNED_VER installer and main binary"
$setupPath = Join-Path $WorkDir $SETUP_NAME
$mainPath  = Join-Path $WorkDir $MAIN_NAME
Get-Pinned "$REL_BASE/$SETUP_NAME" $setupPath $SETUP_SHA "Listary $PINNED_VER installer"
Get-Pinned "$REL_BASE/$MAIN_NAME"  $mainPath  $MAIN_SHA  "Listary $PINNED_VER main binary"

# ---- 3) prepare the target --------------------------------------------------
Head '3/4  prepare the target'
$installed = Join-Path $InstallDir 'Listary.exe'
$tool      = Join-Path $caseRoot 'tools\Listary6Pro.exe'

if ($Restore) {
    if (Test-Path $tool) { & $tool restore } else { Warn 'test tool not found, cannot restore' }
    Ok 'restore done, exiting'; exit 0
}

if (Test-Path $installed) {
    $h = (Get-FileHash $installed -Algorithm SHA256).Hash.ToLower()
    if ($h -eq $MAIN_SHA) { Ok "installed Listary matches the pinned version ($PINNED_VER)" }
    else {
        Warn 'installed Listary hash differs from the pinned version'
        Write-Host "      installed: $h" -ForegroundColor DarkGray
        Write-Host "      pinned   : $MAIN_SHA" -ForegroundColor DarkGray
        Warn 'conclusion may not apply to this build'
    }
} elseif ($SkipInstall) {
    Die "Listary not found at $installed but LISTARY_SKIP_INSTALL=1 was set"
} else {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Warn "installing the pinned build ($PINNED_VER) into: $InstallDir"
    $rp = Start-Process -FilePath $setupPath `
        -ArgumentList ('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="' + $InstallDir + '"')) `
        -Wait -PassThru
    Ok "install finished (exit=$($rp.ExitCode))"
    Start-Sleep -Seconds 3
    if (-not (Test-Path $installed)) { Warn "Listary.exe not found at $installed - the tool may fall back to the registry" }
}

# ---- 4) run the audit -------------------------------------------------------
Head '4/4  run the white-box audit'
if (-not (Test-Path $tool)) { Die 'tools\Listary6Pro.exe not found (unexpected package layout)' }

Write-Host "  -- current state --" -ForegroundColor DarkGray
& $tool info

Write-Host ""
Write-Host "  -- running the audit (writes a self-consistent entitlement, then restarts) --" -ForegroundColor DarkGray
& $tool activate $Email

Write-Host ""
Write-Host "  -- re-check --" -ForegroundColor DarkGray
& $tool info

# ---- keep evidence, remove intermediates ------------------------------------
Head 'cleanup'
$kept = $false
try {
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    Copy-Item (Join-Path $caseRoot 'reports\*') $evidenceDir -Force -Recurse -ErrorAction SilentlyContinue
    $kept = $true
    Ok "evidence kept : $evidenceDir"
} catch { Warn "could not copy evidence: $_" }

if ($KeepFiles) {
    Warn "LISTARY_KEEP_FILES=1 -> intermediates kept at $WorkDir"
} else {
    Safe-Remove $WorkDir
    if (Test-Path $WorkDir) { Warn "some files are still locked -> $WorkDir" }
    else { Ok "intermediates removed: $WorkDir" }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " done" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host " Open Listary (tray icon -> Settings) and check the Pro status." -ForegroundColor White
if ($kept) { Write-Host " evidence : $evidenceDir" -ForegroundColor White }
Write-Host ""
Write-Host " roll back the entitlement (Listary stays installed):" -ForegroundColor DarkGray
Write-Host "   `$env:LISTARY_RESTORE='1'; irm $ONECLICK_URL | iex" -ForegroundColor DarkGray
Write-Host " uninstall Listary:" -ForegroundColor DarkGray
Write-Host "   `"$InstallDir\unins000.exe`" /VERYSILENT" -ForegroundColor DarkGray
