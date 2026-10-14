# =============================================================================
#  Beyond Compare 5.2.6.32774 - whitebox licence audit one-click installer
#  Produces a ready-to-use, offline-licensed Beyond Compare installation.
#
#  Usage (one-liner):
#     powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare.ps1 | iex"
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
  if ($parts.Count -lt 3) { Warn ((T '5ouS57ud5Yig6Zmk6Lev5b6E6L+H5rWF55qE55uu5b2V77ya') + $full); return }
  if (Test-Path $full) { Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-Deps {
  foreach ($c in @('Get-FileHash', 'Invoke-WebRequest', 'Start-Process')) { }
  Write-Host (T '5L6d6LWW5bey5bCx57uq77yI5Y+q55So57O757uf6Ieq5bim57uE5Lu277yM5peg6ZyAIFB5dGhvbiAvIEphdmHvvIk=') -ForegroundColor DarkGray
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
      $probe = Join-Path $v ('.w-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
      Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
      Remove-Item $probe -Force
      return $v
    } catch { Warn ((T '5peg5rOV5YaZ5YWlIA==') + $v + (T '77yM6K+35o2i5LiA5Liq6Lev5b6E')) }
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
    Die ((T '5paH5Lu25aSn5bCP5byC5bi477ya') + $bytes.Length + (T '77yI5bqU5Li6IA==') + $ORIG_SIZE + (T '77yJ4oCU4oCU54mI5pys5LiN5a+577yf'))
  }
  if ((Get-Sha256 $file) -ne $ORIG_SHA256) {
    Die (T '5bey5a6J6KOF55qEIEJDb21wYXJlLmV4ZSDkuI7nm67moIfniYjmnKzkuI3kuIDoh7TvvIzlt7LkuK3mraI=')
  }

  foreach ($p in $CODE_PATCHES) {
    $old = Convert-HexToBytes $p.old
    $new = Convert-HexToBytes $p.new
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ((T '5aSE55CG5L2N572uIDB4ezA6eH0g5LiO55uu5qCH54mI5pys5LiN5LiA6Ie0') -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ((T '5bey5aSE55CGIA==') + $CODE_PATCHES.Count + (T 'IOWkhOS7o+eggQ=='))

  foreach ($p in $STR_PATCHES) {
    $old = [Text.Encoding]::ASCII.GetBytes($p.old)
    $new = [Text.Encoding]::ASCII.GetBytes($p.new)
    if ($new.Length -ne $old.Length) { Die (T '5paH5pys5pu/5o2i6ZW/5bqm5LiN5LiA6Ie0') }
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ((T '5paH5pys5L2N572uIDB4ezA6eH0g5LiO55uu5qCH54mI5pys5LiN5LiA6Ie0') -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ((T '5bey5aSE55CGIA==') + $STR_PATCHES.Count + (T 'IOWkhOe9kee7nOmalOemuw=='))

  # drop the Authenticode certificate table: Beyond Compare verifies its own
  # signature at start-up and refuses to run once the image has been changed
  $lfanew = [BitConverter]::ToUInt32($bytes, 0x3c)
  $dd     = [int]$lfanew + 24 + 112 + 32          # data directory #4 = Security
  $secOff = [BitConverter]::ToUInt32($bytes, $dd)
  $secSz  = [BitConverter]::ToUInt32($bytes, $dd + 4)
  if ($secOff -gt 0) {
    if (($secOff + $secSz) -ne $bytes.Length) { Die (T '6K+B5Lmm57uT5p6E5byC5bi4') }
    $trimmed = New-Object byte[] $secOff
    [Array]::Copy($bytes, 0, $trimmed, 0, $secOff)
    $bytes = $trimmed
    for ($i = 0; $i -lt 8; $i++) { $bytes[$dd + $i] = 0 }
    Ok ((T '5bey56e76Zmk6K+B5Lmm5q6177yI') + $secSz + (T 'IOWtl+iKgu+8ie+8jOWFs+mXreiHquagoemqjA=='))
  }

  [IO.File]::WriteAllBytes($file, $bytes)

  $h = Get-Sha256 $file
  if ($h -ne $GOLD_SHA256) {
    Die ((T '57uT5p6c5LiO6aKE5pyf5LiN5LiA6Ie0') + [Environment]::NewLine + (T 'ICAgICAgICDlrp7pmYXvvJo=') + $h)
  }
  Ok ((T '5qCh6aqM6YCa6L+H77ya') + $h)
}

# ----------------------------------------------------------------- download
function Get-Installer([string]$cacheDir) {
  $name = 'BCompare-' + $BC_VER + '.exe'
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $cached = Join-Path $cacheDir $name
  if (Test-Path $cached) {
    if ((Get-Sha256 $cached) -eq $PKG_SHA256) { Ok ((T '5L2/55So5bey57yT5a2Y55qE5a6J6KOF5YyF77ya') + $cached); return @($cached, $false) }
    Warn (T '57yT5a2Y5a6J6KOF5YyF5qCh6aqM5aSx6LSl77yM6YeN5paw5LiL6L29')
    Remove-Item $cached -Force -ErrorAction SilentlyContinue
  }

  $urls = @($PKG_URL)
  if ($env:BC_MIRROR) { $urls += ($env:BC_MIRROR.TrimEnd('/') + '/' + $name) }

  foreach ($u in $urls) {
    Write-Host ((T 'ICDmraPlnKjlsJ3or5Ug') + $u) -ForegroundColor DarkGray
    try {
      $tmp = $cached + '.part'
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec 600
      if ((Get-Item $tmp).Length -ne $PKG_SIZE) { Warn (T '5paH5Lu25aSn5bCP5LiN5LiA6Ie0'); Remove-Item $tmp -Force; continue }
      if ((Get-Sha256 $tmp) -ne $PKG_SHA256) { Warn (T '5qCh6aqM5LiN5LiA6Ie0'); Remove-Item $tmp -Force; continue }
      Move-Item $tmp $cached -Force
      Ok (T '5bey5LiL6L295bm25qCh6aqM6YCa6L+H')
      return @($cached, $true)
    } catch {
      Warn ((T '5LiL6L295aSx6LSl77ya') + $_.Exception.Message)
    }
  }
  Die ((T '5peg5rOV6I635Y+W5a6J6KOF5YyF') + [Environment]::NewLine +
       (T 'ICAgICAgICDor7fmiYvliqjkuIvovb3vvJo=') + $PKG_URL + [Environment]::NewLine +
       (T 'ICAgICAgICDlubbmlL7liLDvvJo=') + $cacheDir)
}

# --------------------------------------------------------------------- main
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host (T 'IEJleW9uZCBDb21wYXJlIMK3IOS4gOmUruWuieijhQ==') -ForegroundColor White
Write-Host ((T 'IOebruagh+eJiOacrO+8mg==') + $BC_VER) -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

Step (T 'MC81ICDnjq/looPmo4Dmn6U=')
Ensure-Deps
$isAdmin = Test-Admin
if (-not $isAdmin) { Write-Host (T 'ICDmnKrku6XnrqHnkIblkZjov5DooYzigJTigJTlronoo4Xml7bkvJrlvLnkuIDmrKHmnYPpmZDnoa7orqQ=') -ForegroundColor DarkGray }

$desktop = [Environment]::GetFolderPath('Desktop')
$default = Join-Path $desktop ('BeyondCompare-' + $BC_VER)
$outDir  = if ($env:BC_INSTALLDIR) { $env:BC_INSTALLDIR } else { Ask-Dir (T '6K+36YCJ5oup5a6J6KOF55uu5b2V') $default }
if (-not $env:BC_INSTALLDIR -and -not (Test-Interactive)) {
  Write-Host (T 'ICDvvIjpnZ7kuqTkupLov5DooYzvvJrkvb/nlKjpu5jorqTnm67lvZXvvJvlj6/nlKggQkNfSU5TVEFMTERJUiDkv67mlLnvvIk=') -ForegroundColor DarkGray
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path
Write-Host ((T 'ICDlronoo4Xnm67lvZXvvJo=') + $outDir) -ForegroundColor White

$bcExe = Join-Path $outDir 'BCompare.exe'
$needInstall = $true
if ($env:BC_SKIP_INSTALL -eq '1') { $needInstall = $false }
elseif (Test-Path $bcExe) {
  $h0 = Get-Sha256 $bcExe
  if ($h0 -eq $ORIG_SHA256 -or $h0 -eq $GOLD_SHA256) { $needInstall = $false }
}

Step (T 'MS81ICDojrflj5blronoo4XljIU=')
Write-Host ((T 'ICDlronoo4XljIXku44gR2l0SHViIOS4i+i9ve+8iOe6piA=') +
            [Math]::Round($PKG_SIZE / 1MB, 1) + (T 'IE1C77yJ77yb') + [Environment]::NewLine +
            (T 'ICDkuK3lm73lpKfpmYblj6/og73ovoPmhaLvvIzlj6/nlKjplZzlg4/vvJo=') + [Environment]::NewLine +
            (T 'ICAgICAgJGVudjpCQ19NSVJST1I9J2h0dHBzOi8veW91ci1taXJyb3IvcGF0aCcgIOeEtuWQjumHjeaWsOi/kOihjOOAgg==') + [Environment]::NewLine +
            (T 'ICDmlL7lnKggPOWuieijheebruW9lT5cYXJ0aWZhY3RzXCDph4znmoTlia/mnKzkvJrnm7TmjqXkvb/nlKjjgII=')) -ForegroundColor DarkGray
$cacheDir = Join-Path $outDir 'artifacts'
if ($needInstall) {
  $fetched  = @(Get-Installer $cacheDir)
  $pkg      = $fetched[0]
  $download = $fetched[1]
} else {
  Write-Host (T 'ICDml6DpnIDkuIvovb3vvIhCZXlvbmQgQ29tcGFyZSDlt7LlsLHkvY3vvIk=') -ForegroundColor DarkGray
  $pkg = $null; $download = $false
}

Step (T 'Mi81ICDlronoo4U=')
if ($env:BC_SKIP_INSTALL -eq '1') {
  if (-not (Test-Path $bcExe)) { Die ((T '5bey6K6+572uIEJDX1NLSVBfSU5TVEFMTD0x77yM5L2G5om+5LiN5YiwIA==') + $bcExe) }
  Write-Host (T 'ICDlt7Lot7Pov4fvvIhCQ19TS0lQX0lOU1RBTEw9Me+8iQ==')
} elseif (-not $needInstall) {
  Write-Host ((T 'ICBCZXlvbmQgQ29tcGFyZSA=') + $BC_VER + (T 'IOW3suWuieijheS4lOS4juebruagh+eJiOacrOS4gOiHtA==')) -ForegroundColor DarkGray
} else {
  if (Test-Path $bcExe) { Warn (T '5qOA5rWL5Yiw5LiN5ZCM55qEIEJDb21wYXJlLmV4Ze+8jOmHjeaWsOWuieijhQ==') }
  $args = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/SP-', ('/DIR=' + $outDir))
  Write-Host (T 'ICDmraPlnKjpnZnpu5jlronoo4XvvIjlj6/og73lvLnkuIDmrKHmnYPpmZDnoa7orqTvvIkuLi4=') -ForegroundColor DarkGray
  if (Test-Admin) {
    $pr = Start-Process -FilePath $pkg -ArgumentList $args -Wait -PassThru
  } else {
    $pr = Start-Process -FilePath $pkg -ArgumentList $args -Wait -PassThru -Verb RunAs
  }
  Start-Sleep -Seconds 3
  if (-not (Test-Path $bcExe)) { Die (T '5a6J6KOF5ZCO5pyq55Sf5oiQIEJDb21wYXJlLmV4ZQ==') }
  Ok ((T '5bey5a6J6KOFIEJleW9uZCBDb21wYXJlIA==') + $BC_VER)
}

Step (T 'My81ICDlpITnkIY=')
if ((Get-Sha256 $bcExe) -eq $GOLD_SHA256) {
  Ok (T '5bey5aSE55CG6L+H77yI5qCh6aqM5LiA6Ie077yJ77yM5peg6ZyA5pON5L2c')
} else {
  Invoke-Patch $bcExe
}

Step (T 'NC81ICDoh6rmo4A=')
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
  Write-Host ((T 'ICDoh6rmo4Dnm67lvZXvvJo=') + $smoke) -ForegroundColor DarkGray
  Get-ChildItem $smoke -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('    ' + $_.Name) -ForegroundColor DarkGray }
  Die (T '5aSE55CG5ZCO56iL5bqP5peg5rOV5ZCv5Yqo4oCU4oCU5pyq55Sf5oiQ5pel5b+X')
}
$banner = (Select-String -Path $slog -Pattern '\*\*\*' | Select-Object -First 1)
if ($banner) {
  Safe-Remove $smoke
  Die ((T '5o6I5p2D54q25oCB5pyq55Sf5pWI77ya') + $banner.Line.Trim())
}
Ok (T '56iL5bqP5Y+v5q2j5bi46L+Q6KGM77yM6K+V55So5o+Q56S65bey5raI5aSx77yI5o6I5p2D5qOA5p+l6YCa6L+H77yJ')
Safe-Remove $smoke

Step (T 'NS81ICDmuIXnkIY=')
if ($download -and $env:BC_KEEP_ARTIFACTS -ne '1') {
  Remove-Item $pkg -Force -ErrorAction SilentlyContinue
  Write-Host (T 'ICDlt7LliKDpmaTkuIvovb3nmoTlronoo4XljIXvvIjorr4gQkNfS0VFUF9BUlRJRkFDVFM9MSDlj6/kv53nlZnvvIk=') -ForegroundColor DarkGray
}
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Beyond Compare 5_is1',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Beyond Compare 5_is1')) {
  if (Test-Path $k) { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue }
}
Ok (T '5riF55CG5a6M5oiQ')

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host (T 'IOWujOaIkA==') -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ((T 'IOeoi+W6jyAgICAg77yaQmV5b25kIENvbXBhcmUg') + $BC_VER)
Write-Host ((T 'IOS9jee9riAgICAg77ya') + $bcExe)
Write-Host ((T 'IOeJiOacrCAgICAg77ya') + $BC_VER)
Write-Host (T 'IOaJk+W8gOaWueW8jyDvvJrlj4zlh7sgQkNvbXBhcmUuZXhl')
Write-Host ((T 'IOWIoOmZpOaWueW8jyDvvJrliKDmjonmlofku7blpLkg') + $outDir)
Write-Host (T 'IOivtOaYjiAgICAg77ya5bey5YWz6Zet6Ieq5Yqo5pu05paw77yM5Lmf5LiN5YaN5Zue6L+e5Y6C5ZWG5pyN5Yqh5Zmo44CC')
Write-Host '============================================================' -ForegroundColor Green
