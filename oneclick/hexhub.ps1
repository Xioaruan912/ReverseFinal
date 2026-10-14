# HexHub - one-command installer (patched portable build)
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -File .\hexhub.ps1
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
#   * ASCII-only source with base64-embedded Chinese (decoded by T()). A raw UTF-8 .ps1
#     without BOM is mis-read as ANSI by Windows PowerShell 5.1, which garbles Chinese
#     output; a BOM on the other hand breaks "irm | iex". Keeping the source ASCII and
#     decoding the strings at runtime avoids both.
#   * No param()/[CmdletBinding()]: param() only parses when the file is the script
#     entry point, so "irm | iex" would fail with UnexpectedAttribute.
#   * Write-Host goes to the host stream, so prompts never pollute returned values.
#
# Pinned version : HexHub 5.1.9
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

$ErrorActionPreference = 'Stop'

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII ----
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }

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
        Write-Host (((T 'ICAgIOm7mOiupCBb')) + $default + (T 'XQ==')) -ForegroundColor DarkGray
        Write-Host -NoNewline (T 'ICAgIOivt+i+k+WFpe+8iOebtOaOpeWbnui9pueUqOm7mOiupO+8iTog') -ForegroundColor DarkGray
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
        } catch { Warn ((T '5peg5rOV5YaZ5YWlIA==') + $v + (T '77yM6K+35o2i5LiA5Liq6Lev5b6E')) }
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
    Write-Host ((T 'ICBbLi5dIOato+WcqOiOt+WPluS+v+aQuueJiCBQeXRob24g') + $ver + (T '77yI5YWN5a6J6KOF44CB5peg6ZyA566h55CG5ZGY77yJ'))
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
    if ($py) { Ok ((T 'UHl0aG9u77ya') + $py); return $py }
    Warn (T '5pyq5om+5YiwIFB5dGhvbu+8jOato+WcqOiHquWKqOWuieijhQ==')
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-Host (T 'ICBbLi5dIOeUqCB3aW5nZXQg5a6J6KOFIFB5dGhvbiAzLjEy77yI55So5oi357qn44CB5YWN566h55CG5ZGY77yJ')
        & winget.exe install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        Refresh-Path
        $py = Find-Python
        if ($py) { Ok ((T 'UHl0aG9uIOW3suWuieijhe+8mg==') + $py); return $py }
    }
    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        Write-Host (T 'ICBbLi5dIOeUqCBjaG9jbyDlronoo4UgUHl0aG9u')
        & choco.exe install python -y --no-progress 2>&1 | Out-Null
        Refresh-Path
        $py = Find-Python
        if ($py) { Ok ((T 'UHl0aG9uIOW3suWuieijhe+8mg==') + $py); return $py }
    }
    $py = Install-PythonPortable
    if ($py) { Ok ((T '5L6/5pC654mIIFB5dGhvbiDlsLHnu6rvvJo=') + $py); return $py }
    Die (T '5peg5rOV6Ieq5Yqo5a6J6KOFIFB5dGhvbu+8jOivt+aJi+WKqOWuieijhSBQeXRob24gMyDlkI7ph43or5U=')
}

# ---- banner ----------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor White
Write-Host ((T 'IEhleEh1YiA=') + $PINNED_VER + (T 'IMK3IOS4gOmUruWuieijhQ==')) -ForegroundColor White
Write-Host (T 'IOe7k+aenO+8muW+l+WIsOS4gOS4quWFjeWuieijheOAgeWPr+ebtOaOpei/kOihjOeahCBIZXhIdWIg5paH5Lu25aS5') -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host (T 'IFshXSDmlofku7bku44gR2l0SHViIOS4i+i9ve+8jOS4reWbveWkp+mZhuWPr+iDvei+g+aFou+8iOWuieijheWMhee6piAxNDUgTULvvInjgII=') -ForegroundColor Yellow
Write-Host (T 'ICAgICDlpoLmnpzkuIvovb3lm7Dpmr7vvIzlj6/ku6XvvJo=') -ForegroundColor Yellow
Write-Host (T 'ICAgICAgIC0g5L2/55So6ZWc5YOP77yaICAkZW52OkhFWEhVQl9NSVJST1I9J2h0dHBzOi8veW91ci1taXJyb3IveHh4Jw==') -ForegroundColor DarkGray
Write-Host (T 'ICAgICAgIC0g5YWI5omL5Yqo5LiL6L295a6J6KOF5YyF5pS+6L+b5Li05pe25paH5Lu25aS577yM5YaN6YeN5paw6L+Q6KGM') -ForegroundColor DarkGray
if (-not (Test-Interactive)) {
    Write-Host (T 'IO+8iOmdnuS6pOS6kui/kOihjO+8muS9v+eUqOm7mOiupOWAvO+8m+WPr+eUqCBIRVhIVUJfT1VURElSIOaMh+WumuebruW9le+8iQ==') -ForegroundColor DarkGray
}
Write-Host ""

# ---- ask where to install ---------------------------------------------------
$OutDir = if ($env:HEXHUB_OUTDIR) { $env:HEXHUB_OUTDIR } else { Ask-Dir (T '6K+36YCJ5oup5a6J6KOF55uu5b2V77yI5YWN5a6J6KOF54mIIEhleEh1YiDkvJrmlL7lnKjov5nph4zvvIk=') $DefaultOut }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Ok ((T '5a6J6KOF55uu5b2V77ya') + $OutDir)

$Stage = Join-Path $env:TEMP ('hexhub-stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

try {
    # ---- 1/3 tool pack ------------------------------------------------------
    Head (T 'MS8zICDkuIvovb3lt6XlhbfljIU=')
    $packZip = Join-Path $Stage $PACK_NAME
    Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 (T '5bel5YW35YyF')
    $case = Join-Path $Stage 'case'
    Expand-Archive -Path $packZip -DestinationPath $case -Force
    Ok (T '5bel5YW35YyF5bey6Kej5Y6L')

    # ---- 2/3 pinned installer ----------------------------------------------
    Head ((T 'Mi8zICDkuIvovb0gSGV4SHViIA==') + $PINNED_VER + (T 'IOWuieijheWMhQ=='))
    $inst = Join-Path $case $INST_AS
    Get-Pinned "$REL_BASE/$INST_NAME" $inst $INST_SHA256 ((T 'SGV4SHViIA==') + $PINNED_VER + (T 'IOWuieijheWMhQ=='))

    # ---- 3/3 static unpack + patch -----------------------------------------
    Head (T 'My8zICDop6PljIXlubblpITnkIY=')
    $py = Ensure-Python

    Push-Location $case
    & $py 'extract.py' 2>&1 | Select-Object -Last 2
    Pop-Location
    $extracted = Join-Path $case 'samples\extracted'
    if (-not (Test-Path (Join-Path $extracted 'HexHub.exe'))) { Die (T '6Kej5YyF5aSx6LSl77ya5pyq5om+5YiwIEhleEh1Yi5leGU=') }
    Ok (T '5bey6Kej5YyF77yI5pyq6L+Q6KGM5a6J6KOF56iL5bqP77yJ')

    Push-Location $case
    & $py 'patch_vip.py' 2>&1 | Select-Object -Last 4
    Pop-Location
    $patched = Join-Path $case 'patches\hexhub-backend.patched.exe'
    if (-not (Test-Path $patched)) { Die (T '5aSE55CG5aSx6LSl77ya5pyq55Sf5oiQ55uu5qCH5paH5Lu2') }
    Ok (T '5aSE55CG5a6M5oiQ')

    # ---- assemble the portable app ------------------------------------------
    Head (T '5a6J6KOF')
    Get-ChildItem -Path $OutDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $extracted '*') $OutDir -Recurse -Force
    Copy-Item $patched (Join-Path $OutDir 'hexhub-backend.exe') -Force
    Ok ((T '5bey5a6J6KOF5YiwIA==') + $OutDir)
}
finally {
    Safe-Remove $Stage
}

$exe = Join-Path $OutDir 'HexHub.exe'
Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host (T 'IOWujOaIkA==') -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ((T 'IOeoi+W6jyAgICAg77ya') + $exe) -ForegroundColor White
Write-Host ((T 'IOeJiOacrCAgICAg77ya') + $PINNED_VER) -ForegroundColor DarkGray
Write-Host (T 'IOaJk+W8gOaWueW8jyDvvJrlj4zlh7sgSGV4SHViLmV4Ze+8iOWFjeWuieijhe+8jOebtOaOpeWPr+eUqO+8iQ==') -ForegroundColor DarkGray
Write-Host ((T 'IOWIoOmZpOaWueW8jyDvvJrnm7TmjqXliKDmjonmlofku7blpLkg') + $OutDir) -ForegroundColor DarkGray
