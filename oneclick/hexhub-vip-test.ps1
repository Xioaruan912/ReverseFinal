# HexHub - white-box authorization audit - one-command runner
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\hexhub-vip-test.ps1
#
# Behavior:
#   * asks you where to put the working directory (downloads + unpacked copy)
#   * runs the audit
#   * copies evidence to a persistent folder, then removes all intermediates
#
# Optional environment variables:
#   HEXHUB_WORKDIR       working directory (skips the prompt)
#   HEXHUB_EVIDENCE      where evidence is kept (default %USERPROFILE%\ReverseAudit-Evidence)
#   HEXHUB_YES           =1  non-interactive, accept all defaults
#   HEXHUB_KEEP_FILES    =1  do NOT clean up intermediates
#   HEXHUB_STOP_AT_END   =1  close the target program when finished
#   HEXHUB_MIRROR        mirror prefix for the release download (optional)
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose. param() only parses when
#     the file is the script entry point (so "irm | iex" fails with UnexpectedAttribute),
#     and a UTF-8 BOM survives "irm" as a stray character that breaks the first line.
#
# Pinned version : HexHub 5.1.9
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0

$ErrorActionPreference = 'Stop'

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII -----
# A raw UTF-8 .ps1 without BOM is mis-read as ANSI by Windows PowerShell 5.1, which
# garbles the text AND can break parsing; a BOM on the other hand breaks "irm | iex".
# Keeping the source ASCII and decoding at runtime avoids both problems.
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }


# ---- lock file (only edit here when bumping the version) --------------------
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'HexHub-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = '87b4efd7b0b4368629c6bf4400fbfdfcbc58efa72512740aad8af7750b96650a'
$INST_NAME   = 'HexHub-Client-5.1.9-windows-amd64-setup.exe'
$INST_SHA256 = '0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6'
$INST_AS     = 'HexHub-Client-windows-amd64-installer-5.1.9.exe'
$PINNED_VER  = '5.1.9'
$CASE_NAME   = 'HexHub-5.1.9'

# ---- options ----------------------------------------------------------------
$Auto      = ($env:HEXHUB_YES        -eq '1')
$KeepFiles = ($env:HEXHUB_KEEP_FILES -eq '1')
$StopAtEnd = ($env:HEXHUB_STOP_AT_END -eq '1')
$DefaultWork     = Join-Path $env:USERPROFILE 'ReverseAudit\hexhub'
$EvidenceRoot    = if ($env:HEXHUB_EVIDENCE) { $env:HEXHUB_EVIDENCE } else { Join-Path $env:USERPROFILE 'ReverseAudit-Evidence' }

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
    # guard: never delete a drive root or a shallow path
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
    if ($env:HEXHUB_MIRROR) { $urls += ($env:HEXHUB_MIRROR.TrimEnd('/') + '/' + (Split-Path $url -Leaf)) }
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
Write-Host " HexHub white-box authorization audit - one-command run"      -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " artifact source: GitHub (this repo's release)"              -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host (T 'IFshXSDmnoTku7bku44gR2l0SHViIOS4i+i9ve+8jOS4reWbveWkp+mZhue9kee7nOWPr+iDvei+g+aFou+8iOWuieijheWMhee6piAxNDUgTULvvInjgII=') -ForegroundColor Yellow
Write-Host (T 'ICAgICDoi6XkuIvovb3lm7Dpmr7vvIzlj6/ku7vpgInlhbbkuIDvvJo=')                                   -ForegroundColor Yellow
Write-Host (T 'ICAgICAgIC0g6Ieq5bu66ZWc5YOP77yaICAkZW52OkhFWEhVQl9NSVJST1I9J2h0dHBzOi8veW91ci1taXJyb3IveHh4Jw==') -ForegroundColor DarkGray
Write-Host (T 'ICAgICAgIC0g5YWI5omL5Yqo5LiL6L295a6J6KOF5YyF77yM5pS+6L+b5bel5L2c55uu5b2V5ZCO6YeN6LeR77yI5Lya6Ieq5Yqo5qCh6aqMIHNoYTI1Nu+8iQ==')  -ForegroundColor DarkGray
Write-Host ""

# ---- ask where to work ------------------------------------------------------
$WorkDir = if ($env:HEXHUB_WORKDIR) { $env:HEXHUB_WORKDIR } else { Ask-Dir (T '6YCJ5oup5bel5L2c55uu5b2V77yI5LiL6L295Lu25LiO6Kej5YyF5Ymv5pys5pS+6L+Z6YeM77yM5rWL6K+V57uT5p2f6Ieq5Yqo5riF55CG77yJ') $DefaultWork }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Ok "work directory: $WorkDir"
if ($KeepFiles) { Warn 'HEXHUB_KEEP_FILES=1 - intermediates will be kept' }

$evidenceDir = Join-Path $EvidenceRoot (Join-Path $CASE_NAME (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ---- 1) test toolkit --------------------------------------------------------
Head '1/4  fetch test toolkit'
$packZip  = Join-Path $WorkDir $PACK_NAME
$artifact = Join-Path $WorkDir 'artifacts'
New-Item -ItemType Directory -Force -Path $artifact | Out-Null
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'test toolkit'

$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "extracted to $caseRoot"

# ---- 2) pinned installer (cached outside the case dir) ----------------------
Head "2/4  fetch HexHub $PINNED_VER installer"
$instCache = Join-Path $artifact $INST_NAME
Get-Pinned "$REL_BASE/$INST_NAME" $instCache $INST_SHA256 "HexHub $PINNED_VER installer"
$instPath = Join-Path $caseRoot $INST_AS
Copy-Item $instCache $instPath -Force
Ok "installer staged for the extractor"

# ---- 3) environment self-check ---------------------------------------------
Head '3/4  environment self-check'
$pre = Join-Path $caseRoot 'preflight.ps1'
if (Test-Path $pre) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pre
    if ($LASTEXITCODE -ne 0) { Warn 'some checks failed; the audit may not run' }
} else { Warn 'preflight.ps1 not found, skipped' }

# ---- 4) run the audit -------------------------------------------------------
Head '4/4  run the white-box audit'
$run = Join-Path $caseRoot 'run_test.ps1'
if (-not (Test-Path $run)) { Die 'run_test.ps1 not found (unexpected package layout)' }

$evidence = Join-Path $caseRoot 'exports\vip_bypass.png'
if (Test-Path $evidence) { Remove-Item $evidence -Force }   # so the check below is about THIS run
$started = Get-Date

$a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$run)
if ($StopAtEnd) { $a += '-StopAtEnd' }
& powershell @a

# ---- verdict ----------------------------------------------------------------
Write-Host ""
Head 'result'
$fresh = $false
if (Test-Path $evidence) { $fresh = ((Get-Item $evidence).LastWriteTime -ge $started.AddSeconds(-2)) }
if ($fresh) {
    Write-Host "  [V] PoC produced NEW evidence this run." -ForegroundColor Green
    Write-Host "      Look at the HexHub window: the top bar should show the Plus badge" -ForegroundColor Green
    Write-Host "      while NOT logged in and with the vendor servers blocked." -ForegroundColor Green
} else {
    Write-Host "  [X] NO new evidence was produced - the audit did NOT run to completion." -ForegroundColor Red
    Write-Host "      Scroll up for the first error (usually the Playwright/node path)." -ForegroundColor Red
}

# ---- keep evidence, remove intermediates ------------------------------------
Head 'cleanup'
$kept = $false
try {
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    Copy-Item (Join-Path $caseRoot 'exports\*') $evidenceDir -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $caseRoot 'reports\*') $evidenceDir -Force -Recurse -ErrorAction SilentlyContinue
    $kept = $true
    Ok "evidence kept : $evidenceDir"
} catch { Warn "could not copy evidence: $_" }

if ($KeepFiles) {
    Warn "HEXHUB_KEEP_FILES=1 -> intermediates kept at $WorkDir"
} else {
    Safe-Remove $WorkDir
    if (Test-Path $WorkDir) { Warn "some files are still locked (target program running?) -> $WorkDir" }
    else { Ok "intermediates removed: $WorkDir" }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " done" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
if ($kept) { Write-Host " evidence : $evidenceDir" -ForegroundColor White }
Write-Host " pinned   : HexHub $PINNED_VER" -ForegroundColor DarkGray
if (-not $StopAtEnd) {
    Write-Host " note     : the target program may still be running;" -ForegroundColor DarkGray
    Write-Host "            close it with:  taskkill /F /IM HexHub.exe" -ForegroundColor DarkGray
}
