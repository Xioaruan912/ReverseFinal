# HexHub - one-command installer (patched portable build)
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\hexhub-vip-test.ps1
#
# What it does:
#   1. warns that artifacts come from GitHub (slow in mainland China) and offers alternatives
#   2. asks where to put the result (default: Desktop\HexHub-5.1.9)
#   3. downloads the pinned installer + tool pack, verifies sha256
#   4. unpacks the installer statically (never runs it) and applies the byte patch
#   5. leaves a ready-to-run portable HexHub in the chosen folder
#
# Result: <output dir>\HexHub.exe   -- a normal, self-contained HexHub
# No .md files, no reports, no evidence dumps are produced.
#
# Optional environment variables:
#   HEXHUB_OUTDIR        output directory (skips the prompt)
#   HEXHUB_YES           =1  non-interactive, accept all defaults
#   HEXHUB_MIRROR        mirror prefix for the release download (optional)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose: param() only parses when
#     the file is the script entry point (so "irm | iex" fails), and a UTF-8 BOM
#     survives "irm" as a stray character that breaks the first line.
#   * Write-Host goes to the host stream, so prompts never pollute returned values.
#
# Pinned version : HexHub 5.1.9
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

$ErrorActionPreference = 'Stop'

# ---- lock file (only edit here when bumping the version) --------------------
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'HexHub-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = 'd1f320e152214b66e4bd0d9cd872c563bccc874ba959ce474876b2a50cb8c372'
$INST_NAME   = 'HexHub-Client-5.1.9-windows-amd64-setup.exe'
$INST_SHA256 = '0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6'
$INST_AS     = 'HexHub-Client-windows-amd64-installer-5.1.9.exe'
$PINNED_VER  = '5.1.9'

# ---- options ----------------------------------------------------------------
$Auto    = ($env:HEXHUB_YES -eq '1')
$Mirror  = $env:HEXHUB_MIRROR
$Desktop = [Environment]::GetFolderPath('Desktop')
$DefaultOut = Join-Path $Desktop 'HexHub-5.1.9'

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
        $v = $v.Trim().Trim('"')
        try {
            New-Item -ItemType Directory -Force -Path $v | Out-Null
            $probe = Join-Path $v ('.w-' + [guid]::NewGuid().ToString('N').Substring(0,8))
            Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
            Remove-Item $probe -Force
            return $v
        } catch { Warn "cannot write to '$v', try another path" }
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
# extract.py / patch_vip.py use nothing but the standard library, so a portable
# Python is always enough -- no admin rights, no system-wide install.
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# The Microsoft Store ships a fake python.exe stub that exits 49; never trust a
# path, always run it once.
function Test-PythonUsable($exe) {
    if (-not (Test-Path $exe)) { return $false }
    try {
        $out = & $exe -c "print('ok')" 2>$null
        return ($LASTEXITCODE -eq 0 -and (($out -join '') -match 'ok'))
    } catch { return $false }
}

function Find-Python {
    foreach ($c in @('python','python3')) {
        $g = Get-Command $c -ErrorAction SilentlyContinue
        if ($g -and (Test-PythonUsable $g.Source)) { return $g.Source }
    }
    foreach ($d in @((Join-Path $env:LOCALAPPDATA 'miniconda3'),
                     (Join-Path $env:USERPROFILE 'miniconda3'),
                     (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
                     'C:\miniconda3', 'D:\miniconda3')) {
        $exe = Join-Path $d 'python.exe'
        if (Test-PythonUsable $exe) { return $exe }
        if (Test-Path $d) {
            $hit = Get-ChildItem $d -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit -and (Test-PythonUsable $hit.FullName)) { return $hit.FullName }
        }
    }
    return $null
}

function Install-PythonPortable {
    $dst = Join-Path $env:LOCALAPPDATA 'hexhub-python'
    $exe = Join-Path $dst 'python.exe'
    if (Test-PythonUsable $exe) { return $exe }
    $ver = '3.12.8'
    $zip = Join-Path $env:TEMP ('python-embed-' + $ver + '.zip')
    $url = "https://www.python.org/ftp/python/$ver/python-$ver-embed-amd64.zip"
    Write-Host "  [..] fetching a portable Python $ver (no install, no admin)"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fL --retry 3 --connect-timeout 15 -o $zip $url
            if ($LASTEXITCODE -ne 0) { return $null }
        } else {
            (New-Object Net.WebClient).DownloadFile($url, $zip)
        }
        Expand-Archive -Path $zip -DestinationPath $dst -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } catch { return $null }
    if (Test-PythonUsable $exe) { return $exe }
    return $null
}

function Ensure-Python {
    $py = Find-Python
    if ($py) { Ok "python: $py"; return $py }
    Warn 'Python not found - installing it automatically'
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-Host '  [..] winget install Python.Python.3.12 (user scope, no admin)'
        & winget.exe install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        Refresh-Path
        $py = Find-Python
        if ($py) { Ok "python installed: $py"; return $py }
    }
    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        Write-Host '  [..] choco install python'
        & choco.exe install python -y --no-progress 2>&1 | Out-Null
        Refresh-Path
        $py = Find-Python
        if ($py) { Ok "python installed: $py"; return $py }
    }
    $py = Install-PythonPortable
    if ($py) { Ok "portable python ready: $py"; return $py }
    Die 'cannot install Python automatically; install Python 3 manually and re-run'
}

# ---- banner ----------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor White
Write-Host " HexHub $PINNED_VER - one-command install"                      -ForegroundColor White
Write-Host " result: a ready-to-run portable HexHub folder"              -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host " [!] artifacts are downloaded from GitHub; in mainland China this can be slow (installer ~145 MB)." -ForegroundColor Yellow
Write-Host "     if that is a problem, either:" -ForegroundColor Yellow
Write-Host "       - use a mirror:  `$env:HEXHUB_MIRROR='https://your-mirror/xxx'" -ForegroundColor DarkGray
Write-Host "       - download the installer manually and put it into the temp folder, then re-run" -ForegroundColor DarkGray
if (-not (Test-Interactive)) {
    Write-Host " (non-interactive run: using defaults; set HEXHUB_OUTDIR to choose a folder)" -ForegroundColor DarkGray
}
Write-Host ""

# ---- ask where to install ---------------------------------------------------
$OutDir = if ($env:HEXHUB_OUTDIR) { $env:HEXHUB_OUTDIR } else { Ask-Dir "Select the install folder (the portable HexHub will live here)" $DefaultOut }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Ok "install folder: $OutDir"

$Stage = Join-Path $env:TEMP ('hexhub-stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

try {
    # ---- 1/3 tool pack ------------------------------------------------------
    Head '1/3  fetch tool pack'
    $packZip = Join-Path $Stage $PACK_NAME
    Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'tool pack'
    $case = Join-Path $Stage 'case'
    Expand-Archive -Path $packZip -DestinationPath $case -Force
    Ok "unpacked tool pack"

    # ---- 2/3 pinned installer ----------------------------------------------
    Head "2/3  fetch HexHub $PINNED_VER installer"
    $inst = Join-Path $case $INST_AS
    Get-Pinned "$REL_BASE/$INST_NAME" $inst $INST_SHA256 "HexHub $PINNED_VER installer"

    # ---- 3/3 static unpack + patch -----------------------------------------
    Head '3/3  unpack and patch'
    $py = Ensure-Python

    Push-Location $case
    & $py 'extract.py' 2>&1 | Select-Object -Last 2
    Pop-Location
    $extracted = Join-Path $case 'samples\extracted'
    if (-not (Test-Path (Join-Path $extracted 'HexHub.exe'))) { Die 'unpack failed: HexHub.exe not found' }
    Ok "statically unpacked (the installer was never executed)"

    Push-Location $case
    & $py 'patch_vip.py' 2>&1 | Select-Object -Last 4
    Pop-Location
    $patched = Join-Path $case 'patches\hexhub-backend.patched.exe'
    if (-not (Test-Path $patched)) { Die 'patch failed: patched backend not produced' }
    Ok "byte patch applied"

    # ---- assemble the portable app ------------------------------------------
    Head 'install'
    Get-ChildItem -Path $OutDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $extracted '*') $OutDir -Recurse -Force
    Copy-Item $patched (Join-Path $OutDir 'hexhub-backend.exe') -Force
    Ok "installed to $OutDir"
}
finally {
    Safe-Remove $Stage
}

$exe = Join-Path $OutDir 'HexHub.exe'
Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " done" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host " HexHub   : $exe" -ForegroundColor White
Write-Host " version  : $PINNED_VER" -ForegroundColor DarkGray
Write-Host " launch   : double-click HexHub.exe (portable, no installer needed)" -ForegroundColor DarkGray
Write-Host " remove   : just delete the folder $OutDir" -ForegroundColor DarkGray
