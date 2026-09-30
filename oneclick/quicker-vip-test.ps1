# =============================================================================
#  Quicker 1.45.5.0 - whitebox licence audit one-click installer
#  Produces a ready-to-use Quicker installation with a Pro client licence
#  state, version updates disabled and every upstream endpoint detached.
#
#  Usage (non-interactive):
#     powershell -NoProfile -ExecutionPolicy Bypass -c "irm <url> | iex"
#
#  Environment variables:
#     QK_INSTALLDIR      target folder (default: Desktop\Quicker-1.45.5.0)
#     QK_YES=1           never ask anything, use defaults
#     QK_MIRROR          mirror prefix for the pinned installer
#     QK_SKIP_INSTALL=1  Quicker already installed in QK_INSTALLDIR
#     QK_KEEP_ARTIFACTS=1 keep the downloaded installer
#     QK_NO_HOSTS=1      do not touch the hosts file (no upstream detachment)
#
#  What this script does and why (short version)
#  ---------------------------------------------
#   * Quicker.Common.dll is NOT Authenticode-signed, so its licence DTO
#     accessors can be rewritten.  14 IL bodies are replaced with constant
#     returns: MemberLevel -> Pro, all feature flags -> true, all quota
#     ceilings -> large.  Every consumer in Quicker.exe reads that DTO, so the
#     whole product runs as Pro.
#   * Quicker.exe IS Authenticode-signed and its embedded manifest asks for
#     uiAccess="true".  Windows only grants UIAccess to signature-valid
#     images, so any byte edit either fails CreateProcess outright or crashes
#     the process at start-up.  Quicker.exe is therefore left byte-identical
#     and the upstream endpoints are detached at the DNS layer instead.
# =============================================================================

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- pinned data
$REL       = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PKG_NAME  = 'Quicker.x64.1.45.5.0.msi'
$PKG_URL   = $REL + '/' + $PKG_NAME
$PKG_SHA   = '97418d96c00e25c8811b3c5fe3d7df6bb07a9b7be0849a6a1e41d9a1b8896a95'
$PKG_SIZE  = 24371200
$QK_VER    = '1.45.5.0'

$DLL_NAME  = 'Quicker.Common.patched.dll'
$DLL_URL   = $REL + '/' + $DLL_NAME
$DLL_SHA   = '3924e21d208fb2a90c0c241a2806365979fe1838a9ea297e3f874fd6c45c421c'
$DLL_SIZE  = 207872

$ORIG_SHA  = '838e949d15b376c087b2bf0d00bf14f3c6c1b0e122a06ffea4213c800f71a594'
$ORIG_SIZE = 207872

# the exact IL bodies that get rewritten (pinned to the build above)
$DLL_PATCHES = @(
  @{ off = 0x004563; old = '027b790300042a'; new = '0020030000002a'; what = 'UserInfo::get_MemberLevel -> Pro' },
  @{ off = 0x00461a; old = '027b820300042a'; new = '0000000000172a'; what = 'UserLimitation::get_CanUseMobileApp -> true' },
  @{ off = 0x00464d; old = '027b850300042a'; new = '0000000000162a'; what = 'UserLimitation::get_LockButton -> false' },
  @{ off = 0x0046a2; old = '027b8a0300042a'; new = '0000000000172a'; what = 'UserLimitation::get_EnableActionHistory -> true' },
  @{ off = 0x0046b3; old = '027b8b0300042a'; new = '0000000000172a'; what = 'UserLimitation::get_EnableActionHotKey -> true' },
  @{ off = 0x0046c4; old = '027b8c0300042a'; new = '0000000000172a'; what = 'UserLimitation::get_EnableStarter -> true' },
  @{ off = 0x0046d5; old = '027b8d0300042a'; new = '0000000000172a'; what = 'UserLimitation::get_EnableFloatButton -> true' },
  @{ off = 0x0046e6; old = '027b8e0300042a'; new = '0000000000172a'; what = 'UserLimitation::get_EnableSearching -> true' },
  @{ off = 0x00462b; old = '027b830300042a'; new = '0020e70300002a'; what = 'UserLimitation::get_MaxPcCount -> 999' },
  @{ off = 0x00463c; old = '027b840300042a'; new = '0020e70300002a'; what = 'UserLimitation::get_MaxExeCount -> 999' },
  @{ off = 0x00465e; old = '027b860300042a'; new = '0020e70300002a'; what = 'UserLimitation::get_MaxPagePerExe -> 999' },
  @{ off = 0x00466f; old = '027b870300042a'; new = '0020009001002a'; what = 'UserLimitation::get_MaxPageFileSize -> 102400' },
  @{ off = 0x004680; old = '027b880300042a'; new = '0020000010002a'; what = 'UserLimitation::get_TotalPageFileSize -> 1048576' },
  @{ off = 0x004691; old = '027b890300042a'; new = '00200f2700002a'; what = 'UserLimitation::get_MaxIconCount -> 9999' }
)

# upstream endpoints -> 0.0.0.0 (non-routable)
$SINK_BEGIN = '# --- QuickerLab upstream sinkhole (managed block) ---'
$SINK_END   = '# --- end QuickerLab upstream sinkhole ---'
$SINK_HOSTS = @(
  'getquicker.net', 'api.getquicker.net', 'files.getquicker.net',
  'cc.getquicker.net', 'temp.getquicker.net', 'download.getquicker.net',
  'getquicker.cn', 'data.getquicker.cn', 'connect.getquicker.cn',
  'ocr.getquicker.cn', 'files.getquicker.cn', 'tools.getquicker.cn',
  'tmpimg.getquicker.cn', 'helperservice.getquicker.cn', 'aiproxy.getquicker.cn',
  'quicker-temp.bj.bcebos.com',
  'quickeruserdata.oss-cn-shanghai.aliyuncs.com',
  'deskpad.oss-cn-shanghai.aliyuncs.com',
  'quickeruserdata.oss-accelerate.aliyuncs.com'
)

# ------------------------------------------------------------------- helpers
function Ok($m)   { Write-Host ('  [ok]   ' + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ('  [!]    ' + $m) -ForegroundColor Yellow }
function Die($m)  { Write-Host ('  [x]    ' + $m) -ForegroundColor Red; exit 1 }
function Step($m) { Write-Host ''; Write-Host ('== ' + $m) -ForegroundColor Cyan }

$Auto = ($env:QK_YES -eq '1')

function Test-Interactive {
  if ($Auto) { return $false }
  if (-not [Environment]::UserInteractive) { return $false }
  try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
  return $true
}

function Test-Admin {
  try {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Get-Sha256($path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

function Convert-HexToBytes([string]$hex) {
  $out = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  return $out
}

function Safe-Remove($path) {
  $full = [IO.Path]::GetFullPath($path)
  $parts = $full.TrimEnd('\').Split('\') | Where-Object { $_ -ne '' }
  if ($parts.Count -lt 3) { Warn ('refusing to delete shallow path: ' + $full); return }
  if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-Deps {
  # only built-in cmdlets are used: Get-FileHash / Invoke-WebRequest / Start-Process.
  # no Python, no Java, no .NET SDK, no radare2 is required.
  foreach ($c in @('Get-FileHash', 'Invoke-WebRequest', 'Get-AuthenticodeSignature')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { Die ('missing required cmdlet: ' + $c) }
  }
  Write-Host '  dependencies OK (built-in cmdlets only)' -ForegroundColor DarkGray
}

# The vendor MSI (WiX 3.14) does NOT expose INSTALLDIR; the install directory
# id is INSTALLFOLDER (all upper case, therefore a public property).
function Get-QuickerProduct {
  $hits = @()
  foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    if (-not (Test-Path $root)) { continue }
    foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
      $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
      if ($p -and $p.DisplayName -eq 'Quicker') {
        $hits += [pscustomobject]@{ Code = $k.PSChildName; Loc = ('' + $p.InstallLocation).TrimEnd('\'); Ver = $p.DisplayVersion }
      }
    }
  }
  return $hits
}

function Invoke-Msiexec([string]$argline) {
  $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argline -Wait -PassThru
  return $p.ExitCode
}

function Ask-Dir($label, $default) {
  if (-not (Test-Interactive)) { return $default }
  while ($true) {
    Write-Host $label -ForegroundColor White
    Write-Host ('    default [' + $default + ']') -ForegroundColor DarkGray
    Write-Host '    (install under Program Files to keep UIAccess for elevated windows)' -ForegroundColor DarkGray
    Write-Host -NoNewline '    input (Enter = default): ' -ForegroundColor DarkGray
    $v = $null
    try { $v = Read-Host } catch { return $default }
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    $v = $v.Trim().Trim('"')
    try {
      New-Item -ItemType Directory -Force -Path $v | Out-Null
      $probe = Join-Path $v ('.w-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
      Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
      Remove-Item $probe -Force
      return $v
    } catch { Warn ("cannot write to '" + $v + "', try another path") }
  }
}

# ----------------------------------------------------------------- download
function Get-Pinned($url, $name, $sha, $size, $cacheDir) {
  $dest = Join-Path $cacheDir $name
  if (Test-Path -LiteralPath $dest) {
    if ((Get-Sha256 $dest) -eq $sha) { Ok ('using cached ' + $name); return @($dest, $false) }
    Warn ('cached ' + $name + ' failed its checksum, downloading again')
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
  }
  $urls = @($url)
  if ($env:QK_MIRROR) { $urls += ($env:QK_MIRROR.TrimEnd('/') + '/' + $name) }
  foreach ($u in $urls) {
    Write-Host ('  trying ' + $u) -ForegroundColor DarkGray
    try {
      $tmp = $dest + '.part'
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec 900
      if ((Get-Item -LiteralPath $tmp).Length -ne $size) { Warn 'size mismatch'; Remove-Item $tmp -Force; continue }
      if ((Get-Sha256 $tmp) -ne $sha) { Warn 'checksum mismatch'; Remove-Item $tmp -Force; continue }
      Move-Item -LiteralPath $tmp -Destination $dest -Force
      Ok ('verified ' + $name)
      return @($dest, $true)
    } catch { Warn ('download failed: ' + $_.Exception.Message) }
  }
  Die ('could not obtain ' + $name + [Environment]::NewLine +
       '        manual step: download ' + $url + [Environment]::NewLine +
       '        place it in ' + $cacheDir + ' and re-run')
}

# --------------------------------------------------------------------- patch
function Invoke-DllPatch([string]$file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if ($bytes.Length -ne $ORIG_SIZE) { Die ('unexpected size ' + $bytes.Length + ' (expected ' + $ORIG_SIZE + ')') }
  $h = Get-Sha256 $file
  if ($h -eq $DLL_SHA) { Ok 'already patched (golden hash matches)'; return }
  if ($h -ne $ORIG_SHA) { Die 'Quicker.Common.dll does not match the pinned build - aborting' }

  foreach ($p in $DLL_PATCHES) {
    $old = Convert-HexToBytes $p.old
    $new = Convert-HexToBytes $p.new
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ('patch site 0x{0:x} does not match: {1}' -f $p.off, $p.what) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
    # read back
    $back = New-Object byte[] $new.Length
    [Array]::Copy($bytes, $p.off, $back, 0, $new.Length)
    for ($i = 0; $i -lt $new.Length; $i++) {
      if ($back[$i] -ne $new[$i]) { Die ('read-back mismatch at 0x{0:x}' -f $p.off) }
    }
    Ok ('  ' + $p.what)
  }
  [IO.File]::WriteAllBytes($file, $bytes)

  $h2 = Get-Sha256 $file
  if ($h2 -ne $DLL_SHA) {
    Die ('result does not match the golden hash' + [Environment]::NewLine + '        got ' + $h2)
  }
  Ok ('14/14 sites applied, golden hash verified: ' + $h2)
}

# ------------------------------------------------------------------- sinkhole
function Invoke-Sinkhole([string]$mode) {
  $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
  if (-not (Test-Path -LiteralPath $path)) { Warn 'hosts file not found'; return }
  if (-not (Test-Admin)) { Warn 'not elevated - skipping the hosts sinkhole'; return }
  $enc = [Text.Encoding]::GetEncoding(28591)
  $bak = $path + '.quickerlab.bak'
  if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $path -Destination $bak -Force }
  $lines = [IO.File]::ReadAllText($path, $enc) -split "`r?`n"
  $body = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($l in $lines) {
    if ($l.Trim() -eq $SINK_BEGIN) { $skip = $true; continue }
    if ($l.Trim() -eq $SINK_END)   { $skip = $false; continue }
    if (-not $skip) { $body.Add($l) }
  }
  if ($mode -eq 'on') {
    $body.Add('')
    $body.Add($SINK_BEGIN)
    foreach ($h in $SINK_HOSTS) { $body.Add('0.0.0.0 ' + $h) }
    $body.Add($SINK_END)
    [IO.File]::WriteAllText($path, (($body -join "`r`n") + "`r`n"), $enc)
    Ok ('upstream sinkhole active (' + $SINK_HOSTS.Count + ' hosts -> 0.0.0.0)')
    try { & ipconfig /flushdns | Out-Null } catch { }
  } else {
    [IO.File]::WriteAllText($path, (($body -join "`r`n") + "`r`n"), $enc)
    Ok 'upstream sinkhole removed'
    try { & ipconfig /flushdns | Out-Null } catch { }
  }
}

# --------------------------------------------------------------------- main
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host ' Quicker - client licence state + upstream detachment' -ForegroundColor White
Write-Host (' target: Quicker ' + $QK_VER + ' (x64, .NET Framework)' ) -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

Step 'stage 0/6  environment'
Ensure-Deps
$isAdmin = Test-Admin
if ($isAdmin) { Write-Host '  elevated shell detected' -ForegroundColor DarkGray }
else { Warn 'not elevated - the MSI install and the hosts sinkhole will need admin rights' }

$desktop = [Environment]::GetFolderPath('Desktop')
$default = Join-Path $desktop ('Quicker-' + $QK_VER)
$outDir = if ($env:QK_INSTALLDIR) { $env:QK_INSTALLDIR } else { Ask-Dir 'Choose the installation folder' $default }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path
Write-Host ('  target: ' + $outDir) -ForegroundColor White

$qkExe = Join-Path $outDir 'Quicker.exe'
$qkDll = Join-Path $outDir 'Quicker.Common.dll'
$needInstall = $true
if ($env:QK_SKIP_INSTALL -eq '1') { $needInstall = $false }
elseif ((Test-Path -LiteralPath $qkExe) -and (Test-Path -LiteralPath $qkDll)) { $needInstall = $false }

Step 'stage 1/6  pinned artifacts'
Write-Host '  the installer and the patched DLL come from GitHub Releases;' -ForegroundColor DarkGray
Write-Host '  in mainland China this can be slow - use a mirror with' -ForegroundColor DarkGray
Write-Host '      $env:QK_MIRROR=''https://your-mirror/path''   then re-run.' -ForegroundColor DarkGray
$cacheDir = Join-Path $outDir 'artifacts'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$downloaded = @()
if ($needInstall) {
  $r = Get-Pinned $PKG_URL $PKG_NAME $PKG_SHA $PKG_SIZE $cacheDir
  $pkg = $r[0]; if ($r[1]) { $downloaded += $pkg }
} else { $pkg = $null }
$r = Get-Pinned $DLL_URL $DLL_NAME $DLL_SHA $DLL_SIZE $cacheDir
$pdl = $r[0]; if ($r[1]) { $downloaded += $pdl }

Step 'stage 2/6  install'
if (-not $needInstall) {
  Write-Host ('  Quicker ' + $QK_VER + ' already present in the target folder - skipping') -ForegroundColor DarkGray
} else {
  foreach ($hp in (Get-QuickerProduct)) {
    if ($hp.Loc -eq $outDir.TrimEnd('\')) { continue }
    Warn ('an existing Quicker ' + $hp.Ver + ' is registered at ' + $hp.Loc + ' - removing it first')
    $rc = Invoke-Msiexec ('/x ' + $hp.Code + ' /qn /norestart')
    if ($rc -ne 0 -and $rc -ne 1605) { Die ('could not remove the existing installation (msiexec exit ' + $rc + ')') }
    Start-Sleep -Seconds 4
  }
  Write-Host '  running the vendor MSI silently (this may take a couple of minutes)...' -ForegroundColor DarkGray
  $rc = Invoke-Msiexec ('/i "' + $pkg + '" /qn /norestart INSTALLFOLDER="' + $outDir + '"')
  Start-Sleep -Seconds 4
  if (-not (Test-Path -LiteralPath $qkExe)) {
    Warn ('msiexec exit code: ' + $rc)
    Die 'installation did not produce Quicker.exe'
  }
  Ok ('installed Quicker ' + $QK_VER + ' -> ' + $outDir)
}

Step 'stage 3/6  licence patch'
$orig = Join-Path $outDir 'Quicker.Common.dll.orig'
if ((Test-Path -LiteralPath $qkDll) -and -not (Test-Path -LiteralPath $orig)) {
  if ((Get-Sha256 $qkDll) -eq $ORIG_SHA) {
    Copy-Item -LiteralPath $qkDll -Destination $orig -Force
    Ok ('pristine DLL backed up: ' + (Split-Path $orig -Leaf))
  }
}
$targetSha = Get-Sha256 $qkDll
if ($targetSha -eq $DLL_SHA) {
  Ok 'already patched (golden hash matches) - nothing to do'
} elseif ($targetSha -eq $ORIG_SHA) {
  Copy-Item -LiteralPath $pdl -Destination $qkDll -Force
  $now = Get-Sha256 $qkDll
  if ($now -ne $DLL_SHA) { Die ('deployed DLL hash mismatch: ' + $now) }
  Ok 'patched DLL deployed, golden hash verified'
} else {
  Warn ('installed Quicker.Common.dll is neither the pinned original nor the patched build (' + $targetSha + ')')
  Warn 'applying the offset patch directly to it anyway (sites are validated first)'
  Invoke-DllPatch $qkDll
}

Step 'stage 4/6  upstream detachment'
if ($env:QK_NO_HOSTS -eq '1') {
  Write-Host '  skipped (QK_NO_HOSTS=1) - upstream endpoints stay reachable' -ForegroundColor DarkGray
} else {
  Invoke-Sinkhole 'on'
  Write-Host '  note: sign-in needs the upstream, so if you still have to log in:' -ForegroundColor DarkGray
  Write-Host '        remove the block, log in once, then re-apply it.' -ForegroundColor DarkGray
  Write-Host '        a helper is provided: toolkit\hosts_block.ps1 -Mode off|on|status' -ForegroundColor DarkGray
}

Step 'stage 5/6  smoke test'
$smoke = Join-Path $outDir ('.smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $smoke | Out-Null
$logFile = Join-Path $env:LOCALAPPDATA 'Quicker\logs\quicker.log'
$logSize0 = -1
if (Test-Path -LiteralPath $logFile) { $logSize0 = (Get-Item -LiteralPath $logFile).Length }
$proc = Start-Process -FilePath $qkExe -WorkingDirectory $smoke -PassThru
Start-Sleep -Seconds 18
$alive = $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (-not $alive) {
  Warn ('smoke folder: ' + $smoke)
  Die 'the patched installation did not stay running'
}
Ok 'Quicker.exe starts and stays alive with the patched licence DTO'
if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt $logSize0) {
  Ok 'startup log written'
}
$pollution = Get-ChildItem -LiteralPath $smoke -ErrorAction SilentlyContinue
if ($pollution) { Write-Host ('  note: the app wrote into the smoke cwd: ' + (($pollution | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor DarkGray }
Safe-Remove $smoke

Step 'stage 6/6  cleanup'
if ($env:QK_KEEP_ARTIFACTS -ne '1') {
  foreach ($f in $downloaded) {
    if ($f -and (Test-Path -LiteralPath $f) -and ($f -like '*Quicker.x64*')) {
      Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
      Write-Host '  removed the downloaded MSI (set QK_KEEP_ARTIFACTS=1 to keep it)' -ForegroundColor DarkGray
    }
  }
}
Ok 'cleanup done'

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' done' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host (' product  : Quicker ' + $QK_VER + '  (Pro client licence state)')
Write-Host (' path     : ' + $qkExe)
Write-Host (' launch   : double-click Quicker.exe')
Write-Host (' check    : powershell -File toolkit\verify_dto.ps1 "' + $qkDll + '"')
Write-Host (' remove   : delete the folder ' + $outDir)
Write-Host ('            powershell -File toolkit\hosts_block.ps1 -Mode off')
Write-Host (' notes    : version updates disabled; all 19 upstream endpoints')
Write-Host ('            detached via a reversible hosts sinkhole.')
Write-Host ('            Quicker.exe itself is left byte-identical because it')
Write-Host ('            is Authenticode-signed with an active uiAccess manifest.')
Write-Host '============================================================' -ForegroundColor Green
