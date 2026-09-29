# HexHub - white-box authorization audit - one-command runner
#
# Usage 1 (one-liner, nothing written to disk):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
#
# Usage 2 (save to disk first, then configure via environment variables):
#   $env:HEXHUB_WORKDIR='D:\lab\hexhub'; $env:HEXHUB_STOP_AT_END='1'
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\hexhub-vip-test.ps1
#
# Optional environment variables:
#   HEXHUB_WORKDIR       working directory (default %TEMP%\hexhub-lab)
#   HEXHUB_STOP_AT_END   =1  close the target program when finished
#   HEXHUB_KEEP_FILES    =1  keep the working directory
#
# Notes:
#   * ASCII-only and no param()/[CmdletBinding()] on purpose. param() only parses when
#     the file is the script entry point (so "irm | iex" fails with UnexpectedAttribute),
#     and a UTF-8 BOM survives "irm" as a stray character that breaks the first line.
#   * The 145 MB installer is cached under <workdir>\artifacts, so re-runs do not
#     download it again.
#   * After the PoC runs, this script checks that NEW evidence was produced. If the
#     screenshot is stale it says so loudly instead of silently reporting success.
#
# Pinned version : HexHub 5.1.9
# Artifact source: github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0
# Never fetches  : the vendor's "latest" download

$ErrorActionPreference = 'Stop'

# ---- lock file (only edit here when bumping the version) --------------------
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'HexHub-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = '8e4a0420b2e4b96a82a4abeb648a5c2f70720de00c410be9bd3245b75ec9395a'
$INST_NAME   = 'HexHub-Client-5.1.9-windows-amd64-setup.exe'
$INST_SHA256 = '0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6'
$INST_AS     = 'HexHub-Client-windows-amd64-installer-5.1.9.exe'
$PINNED_VER  = '5.1.9'

# ---- options (environment variables) ----------------------------------------
$WorkDir   = if ($env:HEXHUB_WORKDIR)    { $env:HEXHUB_WORKDIR } else { Join-Path $env:TEMP 'hexhub-lab' }
$StopAtEnd = ($env:HEXHUB_STOP_AT_END -eq '1')
$KeepFiles = ($env:HEXHUB_KEEP_FILES  -eq '1')

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
Write-Host " HexHub white-box authorization audit - one-command run"      -ForegroundColor White
Write-Host " pinned version : $PINNED_VER"                               -ForegroundColor White
Write-Host " artifact source: this repo's release (whitebox-audit-v1.0)" -ForegroundColor White
Write-Host " work directory : $WorkDir"                                 -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# ---- 1) test toolkit --------------------------------------------------------
Head '1/4  fetch test toolkit (this repo release)'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$packZip  = Join-Path $WorkDir $PACK_NAME
$artifact = Join-Path $WorkDir 'artifacts'
New-Item -ItemType Directory -Force -Path $artifact | Out-Null
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 'test toolkit'

$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "extracted to $caseRoot"

# ---- 2) pinned installer (cached outside the case dir) ----------------------
Head "2/4  fetch HexHub $PINNED_VER installer (this repo release)"
$instCache = Join-Path $artifact $INST_NAME
Get-Pinned "$REL_BASE/$INST_NAME" $instCache $INST_SHA256 "HexHub $PINNED_VER installer"
$instPath = Join-Path $caseRoot $INST_AS
Copy-Item $instCache $instPath -Force
Ok "installer staged for the extractor (cached at $instCache)"

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
if (Test-Path $evidence) {
    $fresh = ((Get-Item $evidence).LastWriteTime -ge $started.AddSeconds(-2))
}
if ($fresh) {
    Write-Host "  [V] PoC produced NEW evidence this run." -ForegroundColor Green
    Write-Host "      screenshot : $evidence" -ForegroundColor Green
    Write-Host "      Look at the HexHub window: the top bar should show the Plus badge" -ForegroundColor Green
    Write-Host "      while NOT logged in and with the vendor servers blocked." -ForegroundColor Green
} else {
    Write-Host "  [X] NO new evidence was produced - the audit did NOT run to completion." -ForegroundColor Red
    Write-Host "      Check the output above for the first error (usually Playwright/node path)." -ForegroundColor Red
    Write-Host "      If it complains about Playwright: npm i -g playwright" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " title   : $caseRoot"                                        -ForegroundColor White
Write-Host " evidence: $(Join-Path $caseRoot 'exports\')"                -ForegroundColor White
Write-Host " reports : $(Join-Path $caseRoot 'reports\')"                -ForegroundColor White
Write-Host " rollback: delete the work directory $WorkDir"              -ForegroundColor DarkGray
if ($KeepFiles) { Write-Host " work directory kept (HEXHUB_KEEP_FILES=1)" -ForegroundColor DarkGray }
