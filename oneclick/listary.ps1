# Listary 6 Pro - one-command installer
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -File .\listary.ps1
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
#   * ASCII-only source with base64-embedded Chinese (decoded by T()). A raw UTF-8 .ps1
#     without BOM is mis-read as ANSI by Windows PowerShell 5.1, which garbles Chinese
#     output; a BOM on the other hand breaks "irm | iex". Keeping the source ASCII and
#     decoding the strings at runtime avoids both.
#   * No param()/[CmdletBinding()]: param() only parses when the file is the script
#     entry point, so "irm | iex" would fail with UnexpectedAttribute.
#   * Write-Host goes to the host stream, so prompts never pollute returned values.
#
# Pinned version : Listary 6.3.5.94
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

$ErrorActionPreference = 'Stop'

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII ----
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
$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary.ps1'

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
        Write-Host (((T 'ICAgIOm7mOiupCBb')) + $default + (T 'XQ==')) -ForegroundColor DarkGray
        Write-Host -NoNewline (T 'ICAgIOivt+i+k+WFpe+8iOebtOaOpeWbnui9pueUqOm7mOiupO+8iTog') -ForegroundColor DarkGray
        $v = $null
        try { $v = Read-Host } catch { return $default }
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        return $v.Trim().Trim('"')
    }
}

function Safe-Remove($path) {
    $full = [IO.Path]::GetFullPath($path)
    $parts = $full.TrimEnd('\').Split('\') | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 3) { Warn ((T '5ouS57ud5Yig6Zmk6Lev5b6E6L+H5rWF55qE55uu5b2V77ya') + $full); return }
    if (Test-Path $full) { Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-Pinned($url, $dest, $expectSha, $label) {
    if (Test-Path $dest) {
        if ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $expectSha) {
            Ok ($label + (T 'IOW3suWtmOWcqOS4lOagoemqjOmAmui/hw==')); return
        }
        Warn ($label + (T 'IOacrOWcsOWJr+acrOagoemqjOWksei0pe+8jOmHjeaWsOS4i+i9vQ=='))
        Remove-Item $dest -Force
    }
    Write-Host ((T 'ICBbLi5dIOato+WcqOS4i+i9vSA=') + $label)
    Write-Host ((T 'ICAgICAgIA==') + $url)
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
        Warn ((T '5paH5Lu25qCh6aqM5LiN5LiA6Ie077ya') + $u)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    if (-not $done) {
        Die ($label + (T 'IOS4i+i9veWksei0peaIluagoemqjOS4jemAmui/hwogICAgICDmnJ/mnJvmoKHpqozlgLzvvJo=') + $expectSha + (T 'CiAgICAgIOivt+aJi+WKqOS4i+i9veWQjuaUvuWIsO+8mg==') + $dest)
    }
    Move-Item $tmp $dest -Force
    Ok ($label + (T 'IOagoemqjOmAmui/hw=='))
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
        Write-Host (T 'ICBbLi5dIOacquaJvuWIsCBjdXJsLmV4Ze+8jOaUueeUqOezu+e7n+iHquW4pueahOS4i+i9vee7hOS7tg==') -ForegroundColor DarkGray
    }
    if ($need.Count) {
        Die ((T '57y65bCR5Lul5LiL57uE5Lu277yM5LiUIFdpbmRvd3Mg5peg5rOV6Z2Z6buY5a6J6KOF77ya') + ($need -join ', '))
    }
    Ok (T '5L6d6LWW5bey5bCx57uq77yI5YWo6YOo5Li657O757uf6Ieq5bim57uE5Lu277yJ')
}

# ---- banner ----------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor White
Write-Host ((T 'IExpc3Rhcnkg') + $PINNED_VER + (T 'IMK3IOS4gOmUruWuieijhQ==')) -ForegroundColor White
Write-Host (T 'IOe7k+aenO+8muWuieijheWlveS4gOS4quW3sua/gOa0u+eahOS4k+S4mueJiCBMaXN0YXJ5') -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host (T 'IFshXSDmlofku7bku44gR2l0SHViIOS4i+i9ve+8jOS4reWbveWkp+mZhuWPr+iDvei+g+aFou+8iOWuieijheWMhee6piAxMiBNQiArIOS4u+eoi+W6j+e6piAyIE1C77yJ44CC') -ForegroundColor Yellow
Write-Host (T 'ICAgICDlpoLmnpzkuIvovb3lm7Dpmr7vvIzlj6/ku6XvvJo=') -ForegroundColor Yellow
Write-Host (T 'ICAgICAgIC0g5L2/55So6ZWc5YOP77yaICAkZW52OkxJU1RBUllfTUlSUk9SPSdodHRwczovL3lvdXItbWlycm9yL3h4eCc=') -ForegroundColor DarkGray
Write-Host (T 'ICAgICAgIC0g5YWI5omL5Yqo5LiL6L296L+Z5Lik5Liq5paH5Lu25pS+6L+b5Li05pe25paH5Lu25aS577yM5YaN6YeN5paw6L+Q6KGM') -ForegroundColor DarkGray
if (-not (Test-Interactive)) {
    Write-Host (T 'IO+8iOmdnuS6pOS6kui/kOihjO+8muS9v+eUqOm7mOiupOWAvO+8m+WPr+eUqCBMSVNUQVJZX0lOU1RBTExESVIg5oyH5a6a55uu5b2V77yJ') -ForegroundColor DarkGray
}
Write-Host ""

# ---- ask where to install ---------------------------------------------------
$InstallDir = if ($env:LISTARY_INSTALLDIR) { $env:LISTARY_INSTALLDIR } else { Ask-Dir (T '6K+36YCJ5oupIExpc3Rhcnkg5a6J6KOF55uu5b2V') $DefaultInstall }
Ok ((T '5a6J6KOF55uu5b2V77ya') + $InstallDir)
Ok ((T '5L2/55So6YKu566x77ya') + $Email)
Ensure-Deps

$Stage = Join-Path $env:TEMP ('listary-stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

try {
    # ---- 1/3 tool pack ------------------------------------------------------
    Head (T 'MS8zICDkuIvovb3lt6XlhbfljIU=')
    $packZip = Join-Path $Stage $PACK_NAME
    Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 (T '5bel5YW35YyF')
    $case = Join-Path $Stage 'case'
    Expand-Archive -Path $packZip -DestinationPath $case -Force
    Ok (T '5bel5YW35YyF5bey6Kej5Y6L')

    # ---- 2/3 pinned installer + main binary --------------------------------
    Head ((T 'Mi8zICDkuIvovb0gTGlzdGFyeSA=') + $PINNED_VER + (T 'IOWuieijheWMhQ=='))
    $setupPath = Join-Path $Stage $SETUP_NAME
    $mainPath  = Join-Path $Stage $MAIN_NAME
    Get-Pinned "$REL_BASE/$SETUP_NAME" $setupPath $SETUP_SHA ((T 'TGlzdGFyeSA=') + $PINNED_VER + (T 'IOWuieijheWMhQ=='))
    Get-Pinned "$REL_BASE/$MAIN_NAME"  $mainPath  $MAIN_SHA  ((T 'TGlzdGFyeSA=') + $PINNED_VER + (T 'IOS4u+eoi+W6jw=='))

    $tool = Join-Path $case 'tools\Listary6Pro.exe'
    if (-not (Test-Path $tool)) { Die (T '5bel5YW35YyF5YaF5pyq5om+5Yiw5rWL6K+V5bel5YW377yI5paH5Lu257uT5p6E5byC5bi477yJ') }

    if ($Restore) {
        & $tool restore
        Ok (T '5bey56e76Zmk5Lya5ZGY54q25oCB77yM6YCA5Ye6'); exit 0
    }

    # ---- 3/3 install + activate --------------------------------------------
    Head (T 'My8zICDlronoo4Xlubbmv4DmtLs=')
    $installed = Join-Path $InstallDir 'Listary.exe'

    if (Test-Path $installed) {
        $h = (Get-FileHash $installed -Algorithm SHA256).Hash.ToLower()
        if ($h -eq $MAIN_SHA) { Ok ((T '5bey5a6J6KOF5LiU5LiO55uu5qCH54mI5pys5LiA6Ie077yI') + $PINNED_VER + (T '77yJ')) }
        else { Warn (T '5bey5a6J6KOF54mI5pys5LiO55uu5qCH54mI5pys5LiN5LiA6Ie077yM6YeN5paw5a6J6KOF') ; $SkipInstall = $false }
    }

    if (-not (Test-Path $installed) -and -not $SkipInstall) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        Warn ((T '5q2j5Zyo5a6J6KOF55uu5qCH54mI5pys77yI') + $PINNED_VER + (T '77yJ5Yiw77ya') + $InstallDir)
        $rp = Start-Process -FilePath $setupPath `
            -ArgumentList ('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="' + $InstallDir + '"')) `
            -Wait -PassThru
        Ok ((T '5a6J6KOF5a6M5oiQ77yI6YCA5Ye656CBIA==') + $($rp.ExitCode) + (T '77yJ'))
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
Write-Host (T 'IOWujOaIkA==') -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ((T 'IOeoi+W6jyAgICAg77ya') + $(Join-Path $InstallDir 'Listary.exe')) -ForegroundColor White
Write-Host ((T 'IOeJiOacrCAgICAg77ya') + $PINNED_VER) -ForegroundColor DarkGray
Write-Host (T 'IOaJk+W8gOaWueW8jyDvvJrku7vliqHmoI/lm77moIfvvIzmiJbmoYzpnaLlv6vmjbfmlrnlvI8=') -ForegroundColor DarkGray
Write-Host (T 'IOaBouWkjeWOn+eKtiDvvJrorr7nva4gJGVudjpMSVNUQVJZX1JFU1RPUkU9JzEnIOWQjumHjeaWsOi/kOihjOacrOWRveS7pA==') -ForegroundColor DarkGray
Write-Host (T 'IOWIoOmZpOaWueW8jyDvvJrmjqfliLbpnaLmnb/ljbjovb3vvIzmiJbov5DooYzlronoo4Xnm67lvZXph4znmoQgdW5pbnMwMDAuZXhl') -ForegroundColor DarkGray
