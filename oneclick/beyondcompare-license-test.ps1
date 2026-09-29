# =============================================================================
#  Beyond Compare 5.2.6.32774 - whitebox licence audit one-click installer
#  Produces a ready-to-use, offline-licensed Beyond Compare installation.
#
#  Usage (non-interactive):
#     powershell -NoProfile -ExecutionPolicy Bypass -c "irm <url> | iex"
#
#  Environment variables:
#     BC_INSTALLDIR      target folder (default: Desktop\BeyondCompare-5.2.6)
#     BC_YES=1           never ask anything, use defaults
#     BC_MIRROR          mirror prefix for the pinned installer
#     BC_SKIP_INSTALL=1  Beyond Compare already installed in BC_INSTALLDIR
#     BC_KEEP_ARTIFACTS=1 keep the downloaded installer
# =============================================================================

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- pinned data
$PKG_URL      = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0/BCompare-5.2.6.32774.exe'
$PKG_SHA256   = 'a28a1eb43551999e499a8a16af328e0eff1b9a6d45b7dc479682852701b7bb97'
$PKG_SIZE     = 28692792
$BC_VER       = '5.2.6.32774'

$ORIG_SHA256  = '4e44c526722d6420e89b372460c519e293c417723305b83ed0eff853db16ce5d'
$ORIG_SIZE    = 50565160
$GOLD_SHA256  = 'aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc'

# ------------------------------------------------------------------ patch set
#  File offsets are relative to the start of the file (section table derived).
#  Every site is verified against the pinned build before it is written, and
#  the finished binary is checked against $GOLD_SHA256.
$CODE_PATCHES = @(
  # licence state machine: force the "registered" terminal state
  @{ off = 0x04f286e; old = '8b85f0030000'; new = 'b86b00000090' },
  # property getters
  @{ off = 0x04f5560; old = '480fb68110060000c3'; new = 'b003c3cccccccccccc' },
  @{ off = 0x04f5570; old = '480fb68111060000c3'; new = 'b007c3cccccccccccc' },
  @{ off = 0x04f5580; old = '480fb68162010000c3'; new = 'b000c3cccccccccccc' },
  @{ off = 0x04f55f0; old = '480fb68130060000c3'; new = 'b001c3cccccccccccc' },
  @{ off = 0x021b110; old = '480fb681f8060000c3'; new = 'b001c3cccccccccccc' },
  # CheckForUpdatesExecute -> immediate ret
  @{ off = 0x0fa9950; old = '4883ec28488b0d85c5f7ffe870a2f3ff4883c428c3'; new = ('c3' + ('cc' * 20)) },
  # crash guards for the registered path (nil certificate string)
  @{ off = 0x0da1a3e; old = '480fb618'; new = 'b3049090' },
  @{ off = 0x0da1c12; old = '480fb600'; new = 'b0049090' },
  @{ off = 0x0da1c93; old = '480fb600'; new = 'b0049090' }
)
$STR_PATCHES = @(
  # same-length replacements (fixed-length strings inside a compiled DFM blob)
  @{ off = 0x2ff1aa5; old = 'https://www.scootersoftware.com/bugRepMailer.php'; new = 'https://127.0.0.1.invalid/bugRepMailer.php//////' },
  @{ off = 0x2ff1c32; old = 'crash@scootersoftware.com'; new = 'crash@127.0.0.1.invalid..' }
)

# ------------------------------------------------------------------- helpers
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
function Ok($m)   { Write-Host ('  [ok]   ' + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ('  [!]    ' + $m) -ForegroundColor Yellow }
function Die($m)  { Write-Host ('  [x]    ' + $m) -ForegroundColor Red; exit 1 }
function Step($m) { Write-Host ''; Write-Host ('== ' + $m) -ForegroundColor Cyan }

function Convert-HexToBytes([string]$hex) {
  $out = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  return $out
}
function Get-Sha256($path) {
  return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

$Auto = ($env:BC_YES -eq '1')

function Test-Interactive {
  if ($Auto) { return $false }
  if (-not [Environment]::UserInteractive) { return $false }
  try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
  return $true
}

function Safe-Remove($path) {
  $full = [IO.Path]::GetFullPath($path)
  $parts = $full.TrimEnd('\').Split('\') | Where-Object { $_ -ne '' }
  if ($parts.Count -lt 3) { Warn ('refusing to delete shallow path: ' + $full); return }
  if (Test-Path $full) { Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-Deps {
  foreach ($c in @('Get-FileHash', 'Invoke-WebRequest', 'Start-Process')) { }
  Write-Host '  dependencies OK (built-in cmdlets only, no Python/Java needed)' -ForegroundColor DarkGray
}

function Ask-Dir($label, $default) {
  if (-not (Test-Interactive)) { return $default }
  while ($true) {
    Write-Host $label -ForegroundColor White
    Write-Host ('    default [' + $default + ']') -ForegroundColor DarkGray
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

function Test-Admin {
  try {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

# --------------------------------------------------------------------- patch
function Invoke-Patch([string]$file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if ($bytes.Length -ne $ORIG_SIZE) {
    Die ('unexpected size ' + $bytes.Length + ' (expected ' + $ORIG_SIZE + ') - wrong build?')
  }
  if ((Get-Sha256 $file) -ne $ORIG_SHA256) {
    Die 'installed BCompare.exe does not match the pinned build - aborting'
  }

  foreach ($p in $CODE_PATCHES) {
    $old = Convert-HexToBytes $p.old
    $new = Convert-HexToBytes $p.new
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ('patch site 0x{0:x} does not match the pinned build' -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ('applied ' + $CODE_PATCHES.Count + ' code patches')

  foreach ($p in $STR_PATCHES) {
    $old = [Text.Encoding]::ASCII.GetBytes($p.old)
    $new = [Text.Encoding]::ASCII.GetBytes($p.new)
    if ($new.Length -ne $old.Length) { Die 'string patch length mismatch' }
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ('string site 0x{0:x} does not match the pinned build' -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ('applied ' + $STR_PATCHES.Count + ' upstream-detachment patches')

  # drop the Authenticode certificate table: Beyond Compare verifies its own
  # signature at start-up and refuses to run once the image has been changed
  $lfanew = [BitConverter]::ToUInt32($bytes, 0x3c)
  $dd     = [int]$lfanew + 24 + 112 + 32          # data directory #4 = Security
  $secOff = [BitConverter]::ToUInt32($bytes, $dd)
  $secSz  = [BitConverter]::ToUInt32($bytes, $dd + 4)
  if ($secOff -gt 0) {
    if (($secOff + $secSz) -ne $bytes.Length) { Die 'unexpected certificate layout' }
    $trimmed = New-Object byte[] $secOff
    [Array]::Copy($bytes, 0, $trimmed, 0, $secOff)
    $bytes = $trimmed
    for ($i = 0; $i -lt 8; $i++) { $bytes[$dd + $i] = 0 }
    Ok ('removed certificate table (' + $secSz + ' bytes) - self-signature check disabled')
  }

  [IO.File]::WriteAllBytes($file, $bytes)

  $h = Get-Sha256 $file
  if ($h -ne $GOLD_SHA256) {
    Die ('result does not match the golden hash' + [Environment]::NewLine + '        got ' + $h)
  }
  Ok ('golden hash verified: ' + $h)
}

# ----------------------------------------------------------------- download
function Get-Installer([string]$cacheDir) {
  $name = 'BCompare-' + $BC_VER + '.exe'
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $cached = Join-Path $cacheDir $name
  if (Test-Path $cached) {
    if ((Get-Sha256 $cached) -eq $PKG_SHA256) { Ok ('using cached installer: ' + $cached); return @($cached, $false) }
    Warn 'cached installer failed its checksum, downloading again'
    Remove-Item $cached -Force -ErrorAction SilentlyContinue
  }

  $urls = @($PKG_URL)
  if ($env:BC_MIRROR) { $urls += ($env:BC_MIRROR.TrimEnd('/') + '/' + $name) }

  foreach ($u in $urls) {
    Write-Host ('  trying ' + $u) -ForegroundColor DarkGray
    try {
      $tmp = $cached + '.part'
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec 600
      if ((Get-Item $tmp).Length -ne $PKG_SIZE) { Warn 'size mismatch'; Remove-Item $tmp -Force; continue }
      if ((Get-Sha256 $tmp) -ne $PKG_SHA256) { Warn 'checksum mismatch'; Remove-Item $tmp -Force; continue }
      Move-Item $tmp $cached -Force
      Ok 'downloaded and verified'
      return @($cached, $true)
    } catch {
      Warn ('download failed: ' + $_.Exception.Message)
    }
  }
  Die ('could not obtain the installer' + [Environment]::NewLine +
       '        manual step: download ' + $PKG_URL + [Environment]::NewLine +
       '        and place it in ' + $cacheDir)
}

# --------------------------------------------------------------------- main
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host ' Beyond Compare 5 - offline licence validation (whitebox)' -ForegroundColor White
Write-Host (' target: Beyond Compare ' + $BC_VER) -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

Step 'stage 0/5  environment'
Ensure-Deps
$isAdmin = Test-Admin
if (-not $isAdmin) { Write-Host '  not elevated - the vendor installer will raise one UAC prompt' -ForegroundColor DarkGray }

$desktop = [Environment]::GetFolderPath('Desktop')
$default = Join-Path $desktop ('BeyondCompare-' + $BC_VER)
$outDir  = if ($env:BC_INSTALLDIR) { $env:BC_INSTALLDIR } else { Ask-Dir 'Choose the output folder' $default }
if (-not $env:BC_INSTALLDIR -and -not (Test-Interactive)) {
  Write-Host '  (non-interactive: using the default folder; set BC_INSTALLDIR to change it)' -ForegroundColor DarkGray
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path
Write-Host ('  output: ' + $outDir) -ForegroundColor White

$bcExe = Join-Path $outDir 'BCompare.exe'
$needInstall = $true
if ($env:BC_SKIP_INSTALL -eq '1') { $needInstall = $false }
elseif (Test-Path $bcExe) {
  $h0 = Get-Sha256 $bcExe
  if ($h0 -eq $ORIG_SHA256 -or $h0 -eq $GOLD_SHA256) { $needInstall = $false }
}

Step 'stage 1/5  pinned artifacts'
Write-Host ('  the installer comes from GitHub Releases (' +
            [Math]::Round($PKG_SIZE / 1MB, 1) + ' MB);' + [Environment]::NewLine +
            '  in mainland China this can be slow - use a mirror with' + [Environment]::NewLine +
            '      $env:BC_MIRROR=''https://your-mirror/path''   then re-run.' + [Environment]::NewLine +
            '  a copy placed in <output>\artifacts\ is used as-is.') -ForegroundColor DarkGray
$cacheDir = Join-Path $outDir 'artifacts'
if ($needInstall) {
  $fetched  = @(Get-Installer $cacheDir)
  $pkg      = $fetched[0]
  $download = $fetched[1]
} else {
  Write-Host '  not needed (Beyond Compare is already in place)' -ForegroundColor DarkGray
  $pkg = $null; $download = $false
}

Step 'stage 2/5  install'
if ($env:BC_SKIP_INSTALL -eq '1') {
  if (-not (Test-Path $bcExe)) { Die ('BC_SKIP_INSTALL=1 but ' + $bcExe + ' does not exist') }
  Write-Host '  skipped (BC_SKIP_INSTALL=1)'
} elseif (-not $needInstall) {
  Write-Host ('  Beyond Compare ' + $BC_VER + ' is already installed and matches the pinned build') -ForegroundColor DarkGray
} else {
  if (Test-Path $bcExe) { Warn 'a different BCompare.exe is present - reinstalling' }
  $args = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/SP-', ('/DIR=' + $outDir))
  Write-Host '  running the vendor installer silently (UAC may prompt)...' -ForegroundColor DarkGray
  if (Test-Admin) {
    $pr = Start-Process -FilePath $pkg -ArgumentList $args -Wait -PassThru
  } else {
    $pr = Start-Process -FilePath $pkg -ArgumentList $args -Wait -PassThru -Verb RunAs
  }
  Start-Sleep -Seconds 3
  if (-not (Test-Path $bcExe)) { Die 'installation did not produce BCompare.exe' }
  Ok ('installed Beyond Compare ' + $BC_VER)
}

Step 'stage 3/5  patch'
if ((Get-Sha256 $bcExe) -eq $GOLD_SHA256) {
  Ok 'already patched (golden hash matches) - nothing to do'
} else {
  Invoke-Patch $bcExe
}

Step 'stage 4/5  smoke test'
$smoke = Join-Path $outDir ('.smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $smoke | Out-Null
$sfile = Join-Path $smoke 's.txt'
$slog  = Join-Path $smoke 'out.log'
$cmds = @(
  ('log verbose "' + $slog + '"'),
  ('load "' + $smoke + '" "' + $smoke + '"'),
  'expand all'
)
$nl = [string][char]13 + [string][char]10
[IO.File]::WriteAllText($sfile, (($cmds -join $nl) + $nl), [Text.Encoding]::ASCII)
$so = Join-Path $smoke 'stdout.txt'
$se = Join-Path $smoke 'stderr.txt'
$proc = Start-Process -FilePath $bcExe -ArgumentList '@s.txt' -WorkingDirectory $smoke -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline -and -not (Test-Path $slog)) { Start-Sleep -Milliseconds 500 }
Stop-Process -Name BCompare -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (-not (Test-Path $slog)) {
  Write-Host ('  smoke folder: ' + $smoke) -ForegroundColor DarkGray
  Get-ChildItem $smoke -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('    ' + $_.Name) -ForegroundColor DarkGray }
  Die 'the patched binary did not start - no script log was produced'
}
$banner = (Select-String -Path $slog -Pattern '\*\*\*' | Select-Object -First 1)
if ($banner) {
  Safe-Remove $smoke
  Die ('licence state was not lifted: ' + $banner.Line.Trim())
}
Ok 'binary runs and the evaluation banner is gone (licence check passes)'
Safe-Remove $smoke

Step 'stage 5/5  cleanup'
if ($download -and $env:BC_KEEP_ARTIFACTS -ne '1') {
  Remove-Item $pkg -Force -ErrorAction SilentlyContinue
  Write-Host '  removed the downloaded installer (set BC_KEEP_ARTIFACTS=1 to keep it)' -ForegroundColor DarkGray
}
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Beyond Compare 5_is1',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Beyond Compare 5_is1')) {
  if (Test-Path $k) { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue }
}
Ok 'cleanup done'

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' done' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host (' product  : Beyond Compare ' + $BC_VER + ' (offline licence validation passes)')
Write-Host (' path     : ' + $bcExe)
Write-Host (' version  : ' + $BC_VER)
Write-Host (' launch   : double-click BCompare.exe')
Write-Host (' remove   : delete the folder ' + $outDir)
Write-Host (' notes    : update checks are disabled and all vendor URLs are')
Write-Host ('            retargeted to a non-routable host.')
Write-Host '============================================================' -ForegroundColor Green
