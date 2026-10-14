# =============================================================================
#  Quicker 1.45.5.0 - whitebox licence audit one-click installer
#  Produces a ready-to-use Quicker installation with a Pro client licence
#  state, version updates disabled and every upstream endpoint detached.
#
#  Usage (one-liner):
#     powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker.ps1 | iex"
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

# ---- Chinese strings are embedded as base64 so this file stays pure ASCII ----
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }

# ---------------------------------------------------------------- pinned data
$REL       = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PKG_NAME  = 'Quicker.x64.1.45.5.0.msi'
$PKG_URL   = $REL + '/' + $PKG_NAME
$PKG_SHA   = '97418d96c00e25c8811b3c5fe3d7df6bb07a9b7be0849a6a1e41d9a1b8896a95'
$PKG_SIZE  = 24371200
$QK_VER    = '1.45.5.0'

$DLL_NAME  = 'Quicker.Common.patched.dll'
$DLL_URL   = $REL + '/' + $DLL_NAME
$DLL_SHA   = '350c56e04ed0e7b0ec0e88df2e59f6298a24fb1c951e7aab4099afd1128275fa'
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
  if ($parts.Count -lt 3) { Warn ((T '5ouS57ud5Yig6Zmk6Lev5b6E6L+H5rWF55qE55uu5b2V77ya') + $full); return }
  if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-Deps {
  # only built-in cmdlets are used: Get-FileHash / Invoke-WebRequest / Start-Process.
  # no Python, no Java, no .NET SDK, no radare2 is required.
  foreach ($c in @('Get-FileHash', 'Invoke-WebRequest', 'Get-AuthenticodeSignature')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { Die ((T '57y65bCR5b+F6ZyA57uE5Lu277ya') + $c) }
  }
  Write-Host (T '5L6d6LWW5bey5bCx57uq77yI5Y+q55So57O757uf6Ieq5bim57uE5Lu277yJ') -ForegroundColor DarkGray
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
    Write-Host (((T 'ICAgIOm7mOiupCBb')) + $default + (T 'XQ==')) -ForegroundColor DarkGray
    Write-Host (T 'ICAgIO+8iOW7uuiuruijheWcqCBQcm9ncmFtIEZpbGVz77yM5Lul5L+d6K+B5Lul566h55CG5ZGY6L+Q6KGM5pe25Yqf6IO95q2j5bi477yJ') -ForegroundColor DarkGray
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

# ----------------------------------------------------------------- download
function Get-Pinned($url, $name, $sha, $size, $cacheDir) {
  $dest = Join-Path $cacheDir $name
  if (Test-Path -LiteralPath $dest) {
    if ((Get-Sha256 $dest) -eq $sha) { Ok ((T '5L2/55So5bey57yT5a2Y77ya') + $name); return @($dest, $false) }
    Warn ((T '57yT5a2YIA==') + $name + (T 'IOagoemqjOWksei0pe+8jOmHjeaWsOS4i+i9vQ=='))
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
  }
  $urls = @($url)
  if ($env:QK_MIRROR) { $urls += ($env:QK_MIRROR.TrimEnd('/') + '/' + $name) }
  foreach ($u in $urls) {
    Write-Host ((T 'ICDmraPlnKjlsJ3or5Ug') + $u) -ForegroundColor DarkGray
    try {
      $tmp = $dest + '.part'
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec 900
      if ((Get-Item -LiteralPath $tmp).Length -ne $size) { Warn (T '5paH5Lu25aSn5bCP5LiN5LiA6Ie0'); Remove-Item $tmp -Force; continue }
      if ((Get-Sha256 $tmp) -ne $sha) { Warn (T '5qCh6aqM5LiN5LiA6Ie0'); Remove-Item $tmp -Force; continue }
      Move-Item -LiteralPath $tmp -Destination $dest -Force
      Ok ((T '5qCh6aqM6YCa6L+H77ya') + $name)
      return @($dest, $true)
    } catch { Warn ((T '5LiL6L295aSx6LSl77ya') + $_.Exception.Message) }
  }
  Die ((T '5peg5rOV6I635Y+WIA==') + $name + [Environment]::NewLine +
       (T 'ICAgICAgICDor7fmiYvliqjkuIvovb3vvJo=') + $url + [Environment]::NewLine +
       (T 'ICAgICAgICDmlL7liLAg') + $cacheDir + (T 'IOWQjumHjeaWsOi/kOihjA=='))
}

# ------------------------------------------------------------------- sinkhole
function Invoke-Sinkhole([string]$mode) {
  $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
  if (-not (Test-Path -LiteralPath $path)) { Warn (T '5pyq5om+5Yiw57O757uf572R57uc6YWN572u5paH5Lu277yM5bey6Lez6L+H'); return }
  if (-not (Test-Admin)) { Warn (T '5pyq5Lul566h55CG5ZGY6L+Q6KGM4oCU4oCU6Lez6L+H572R57uc6ZqU56a7'); return }
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
    Ok ((T '5bey5ZCv55So572R57uc6ZqU56a777yI') + $SINK_HOSTS.Count + (T 'IOS4quWcsOWdgOW3suWxj+iUve+8iQ=='))
    try { & ipconfig /flushdns | Out-Null } catch { }
  } else {
    [IO.File]::WriteAllText($path, (($body -join "`r`n") + "`r`n"), $enc)
    Ok (T '572R57uc6ZqU56a75bey6Kej6Zmk')
    try { & ipconfig /flushdns | Out-Null } catch { }
  }
}

# --------------------------------------------------------------------- main
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host (T 'IFF1aWNrZXIgwrcg5LiA6ZSu5a6J6KOF') -ForegroundColor White
Write-Host ((T 'IOebruagh+eJiOacrO+8mlF1aWNrZXIg') + $QK_VER) -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

Step (T 'MC82ICDnjq/looPmo4Dmn6U=')
Ensure-Deps
$isAdmin = Test-Admin
if ($isAdmin) { Write-Host (T 'ICDlt7Lku6XnrqHnkIblkZjov5DooYw=') -ForegroundColor DarkGray }
else { Warn (T '5pyq5Lul566h55CG5ZGY6L+Q6KGM4oCU4oCU5a6J6KOF5ZKM572R57uc6ZqU56a76ZyA6KaB566h55CG5ZGY5p2D6ZmQ') }

$desktop = [Environment]::GetFolderPath('Desktop')
$default = Join-Path $desktop ('Quicker-' + $QK_VER)
$outDir = if ($env:QK_INSTALLDIR) { $env:QK_INSTALLDIR } else { Ask-Dir (T '6K+36YCJ5oup5a6J6KOF55uu5b2V') $default }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path
Write-Host ((T 'ICDlronoo4Xnm67lvZXvvJo=') + $outDir) -ForegroundColor White

$qkExe = Join-Path $outDir 'Quicker.exe'
$qkDll = Join-Path $outDir 'Quicker.Common.dll'
$needInstall = $true
if ($env:QK_SKIP_INSTALL -eq '1') { $needInstall = $false }
elseif ((Test-Path -LiteralPath $qkExe) -and (Test-Path -LiteralPath $qkDll)) { $needInstall = $false }

Step (T 'MS82ICDojrflj5bmlofku7Y=')
Write-Host (T 'ICDlronoo4XljIXlkozmlofku7bku44gR2l0SHViIOS4i+i9ve+8mw==') -ForegroundColor DarkGray
Write-Host (T 'ICDkuK3lm73lpKfpmYblj6/og73ovoPmhaLvvIzlj6/nlKjplZzlg4/vvJo=') -ForegroundColor DarkGray
Write-Host (T 'ICAgICAgJGVudjpRS19NSVJST1I9J2h0dHBzOi8veW91ci1taXJyb3IvcGF0aCcgIOeEtuWQjumHjeaWsOi/kOihjOOAgg==') -ForegroundColor DarkGray
$cacheDir = Join-Path $outDir 'artifacts'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$downloaded = @()
if ($needInstall) {
  $r = Get-Pinned $PKG_URL $PKG_NAME $PKG_SHA $PKG_SIZE $cacheDir
  $pkg = $r[0]; if ($r[1]) { $downloaded += $pkg }
} else { $pkg = $null }
$r = Get-Pinned $DLL_URL $DLL_NAME $DLL_SHA $DLL_SIZE $cacheDir
$pdl = $r[0]; if ($r[1]) { $downloaded += $pdl }

Step (T 'Mi82ICDlronoo4U=')
if (-not $needInstall) {
  Write-Host ((T 'ICBRdWlja2VyIA==') + $QK_VER + (T 'IOW3suWtmOWcqO+8jOi3s+i/h+WuieijhQ==')) -ForegroundColor DarkGray
} else {
  foreach ($hp in (Get-QuickerProduct)) {
    if ($hp.Loc -eq $outDir.TrimEnd('\')) { continue }
    Warn ((T '5qOA5rWL5Yiw5bey5a6J6KOF55qEIFF1aWNrZXIg') + $hp.Ver + (T '77yI5L2N572uIA==') + $hp.Loc + (T '77yJ77yM5YWI5Y246L29'))
    $rc = Invoke-Msiexec ('/x ' + $hp.Code + ' /qn /norestart')
    if ($rc -ne 0 -and $rc -ne 1605) { Die ((T '5peg5rOV5Y246L295bey5a6J6KOF55qE54mI5pys77yI6ZSZ6K+v56CBIA==') + $rc + (T '77yJ')) }
    Start-Sleep -Seconds 4
  }
  Write-Host (T 'ICDmraPlnKjpnZnpu5jlronoo4XvvIjlj6/og73pnIDopoHkuIDkuKTliIbpkp/vvIkuLi4=') -ForegroundColor DarkGray
  $rc = Invoke-Msiexec ('/i "' + $pkg + '" /qn /norestart INSTALLFOLDER="' + $outDir + '"')
  Start-Sleep -Seconds 4
  if (-not (Test-Path -LiteralPath $qkExe)) {
    Warn ((T '5a6J6KOF56iL5bqP6L+U5Zue56CB77ya') + $rc)
    Die (T '5a6J6KOF5ZCO5pyq55Sf5oiQIFF1aWNrZXIuZXhl')
  }
  Ok ((T '5bey5a6J6KOFIFF1aWNrZXIg') + $QK_VER + (T 'IOWIsCA=') + $outDir)
}

Step (T 'My82ICDlpITnkIbmjojmnYPnirbmgIE=')
# The Pro gate in Quicker.exe is DataService::tuE6DqVP75B:
#     IsPro == MemberExpireTimeUtc.HasValue && MemberExpireTimeUtc.Value > DateTime.UtcNow
# MemberLevel and every UserLimitation flag are ignored by it, so the only lever
# inside the unsigned Quicker.Common.dll is the expiry accessor.  Returning a future
# date needs System.DateTime::AddYears, which the assembly does not reference, so the
# pinned artefact already carries a minimal metadata extension (one #Strings entry,
# two #Blob entries, two MemberRef rows, one relocated method body).  This stage just
# deploys it and verifies the golden hash.
$orig = Join-Path $outDir 'Quicker.Common.dll.orig'
$targetSha = Get-Sha256 $qkDll
if ($targetSha -eq $DLL_SHA) {
  Ok (T '5bey5aSE55CG6L+H77yI5qCh6aqM5LiA6Ie077yJ77yM5peg6ZyA5pON5L2c')
} elseif ($targetSha -eq $ORIG_SHA) {
  if (-not (Test-Path -LiteralPath $orig)) {
    Copy-Item -LiteralPath $qkDll -Destination $orig -Force
    Ok (T '5bey5aSH5Lu95Y6f5aeL5paH5Lu277yaUXVpY2tlci5Db21tb24uZGxsLm9yaWc=')
  }
  Copy-Item -LiteralPath $pdl -Destination $qkDll -Force
  $now = Get-Sha256 $qkDll
  if ($now -ne $DLL_SHA) { Die ((T '5paH5Lu25qCh6aqM5LiN5LiA6Ie077ya') + $now) }
  Ok (T '5bey5aSE55CG5bm25qCh6aqM6YCa6L+H')
} else {
  Warn (T '5bey5a6J6KOF55qEIFF1aWNrZXIuQ29tbW9uLmRsbCDml6LkuI3mmK/ljp/lp4vniYjmnKzkuZ/kuI3mmK/nm67moIfniYjmnKw=')
  Warn ((T 'ICDlvZPliY3vvJo=') + $targetSha)
  Warn ((T 'ICDljp/lp4vvvJo=') + $ORIG_SHA)
  Warn ((T 'ICDnm67moIfvvJo=') + $DLL_SHA)
  Die (T '54mI5pys5peg5rOV6K+G5Yir77yM5bey5Lit5q2i')
}

Step (T 'NC82ICDnvZHnu5zpmpTnprs=')
if ($env:QK_NO_HOSTS -eq '1') {
  Write-Host (T 'ICDlt7Lot7Pov4fvvIhRS19OT19IT1NUUz0x77yJ4oCU4oCU5LuN5Y+v6L+e5o6l5Y6C5ZWG5pyN5Yqh5Zmo') -ForegroundColor DarkGray
} else {
  Invoke-Sinkhole 'on'
  Write-Host (T 'ICDmj5DnpLrvvJrnmbvlvZXpnIDopoHov57mjqXljoLllYbmnI3liqHlmajjgII=') -ForegroundColor DarkGray
  Write-Host (T 'ICAgICAgICDlpoLmnpzov5jpnIDopoHnmbvlvZXvvJrlhYjop6PpmaTpmpTnprvvvIznmbvlvZXkuIDmrKHvvIzlho3ph43mlrDpmpTnprvjgII=') -ForegroundColor DarkGray
  Write-Host (T 'ICAgICAgICDlpoLpgYfpl67popjor7fogZTns7vmioDmnK/kurrlkZjljY/liqnjgII=') -ForegroundColor DarkGray
}

Step (T 'NS82ICDoh6rmo4A=')
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
  Warn ((T '6Ieq5qOA55uu5b2V77ya') + $smoke)
  Die (T '5aSE55CG5ZCO56iL5bqP5pyq6IO95L+d5oyB6L+Q6KGM')
}
Ok (T 'UXVpY2tlci5leGUg5Y+v5q2j5bi45ZCv5Yqo5bm25L+d5oyB6L+Q6KGM')
if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt $logSize0) {
  Ok (T '5bey55Sf5oiQ5ZCv5Yqo5pel5b+X')
}
$pollution = Get-ChildItem -LiteralPath $smoke -ErrorAction SilentlyContinue
if ($pollution) { Write-Host ((T 'ICDmj5DnpLrvvJrnqIvluo/lnKjoh6rmo4Dnm67lvZXlhpnlhaXkuobmlofku7bvvJo=') + (($pollution | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor DarkGray }
Safe-Remove $smoke

Step (T 'Ni82ICDmuIXnkIY=')
if ($env:QK_KEEP_ARTIFACTS -ne '1') {
  foreach ($f in $downloaded) {
    if ($f -and (Test-Path -LiteralPath $f) -and ($f -like '*Quicker.x64*')) {
      Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
      Write-Host (T 'ICDlt7LliKDpmaTkuIvovb3nmoTlronoo4XljIXvvIjorr4gUUtfS0VFUF9BUlRJRkFDVFM9MSDlj6/kv53nlZnvvIk=') -ForegroundColor DarkGray
    }
  }
}
Ok (T '5riF55CG5a6M5oiQ')

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host (T 'IOWujOaIkA==') -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ((T 'IOeoi+W6jyAgICAg77yaUXVpY2tlciA=') + $QK_VER + (T '77yI5LiT5Lia54mI77yJ'))
Write-Host ((T 'IOS9jee9riAgICAg77ya') + $qkExe)
Write-Host (T 'IOaJk+W8gOaWueW8jyDvvJrlj4zlh7sgUXVpY2tlci5leGU=')
Write-Host ((T 'IOWIoOmZpOaWueW8jyDvvJrmjqfliLbpnaLmnb/ljbjovb3vvIzlho3liKDmjonmlofku7blpLkg') + $outDir)
Write-Host (T 'IOivtOaYjiAgICAg77ya5bey5YWz6Zet6Ieq5Yqo5pu05paw77yM5bm25bGP6JS95Y6C5ZWG5pyN5Yqh5Zmo6L+e5o6l44CC')
Write-Host (T 'ICAgICAgICAgICAg6aaW5qyh5L2/55So6Iul5o+Q56S655m75b2V77yM55So5YWN6LS56LSm5Y+355m75b2V5LiA5qyh5Y2z5Y+v44CC')
Write-Host '============================================================' -ForegroundColor Green
