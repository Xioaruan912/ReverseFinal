# =============================================================================
#  Quicker 1.45.5.0 - upstream sinkhole manager  (detach / re-attach)
#
#  Quicker.exe cannot be byte-patched: it is Authenticode-signed and its
#  embedded manifest asks for uiAccess="true", and Windows only grants UIAccess
#  to signature-valid images.  Any edit makes the process refuse to start.
#  The upstream endpoints are therefore pointed at a non-routable host through
#  the hosts file, inside a clearly marked, fully reversible block.
#
#  Usage:
#     powershell -NoProfile -ExecutionPolicy Bypass -File hosts_block.ps1 -Mode on
#     powershell -NoProfile -ExecutionPolicy Bypass -File hosts_block.ps1 -Mode off
#     powershell -NoProfile -ExecutionPolicy Bypass -File hosts_block.ps1 -Mode status
#
#  Environment variables:
#     QK_HOSTS_MODE=on|off   same as -Mode
#     QK_YES=1               never ask anything
# =============================================================================

$ErrorActionPreference = 'Stop'

$BEGIN = '# --- QuickerLab upstream sinkhole (managed block) ---'
$END   = '# --- end QuickerLab upstream sinkhole ---'

# 0.0.0.0 is a non-routable destination: connections fail immediately instead
# of hanging, and no DNS query ever leaves the machine for these names.
$HOSTS = @(
  'getquicker.net',
  'api.getquicker.net',
  'files.getquicker.net',
  'cc.getquicker.net',
  'temp.getquicker.net',
  'download.getquicker.net',
  'getquicker.cn',
  'data.getquicker.cn',
  'connect.getquicker.cn',
  'ocr.getquicker.cn',
  'files.getquicker.cn',
  'tools.getquicker.cn',
  'tmpimg.getquicker.cn',
  'helperservice.getquicker.cn',
  'aiproxy.getquicker.cn',
  'quicker-temp.bj.bcebos.com',
  'quickeruserdata.oss-cn-shanghai.aliyuncs.com',
  'deskpad.oss-cn-shanghai.aliyuncs.com',
  'quickeruserdata.oss-accelerate.aliyuncs.com'
)

function Ok($m)   { Write-Host ('  [ok] ' + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ('  [!]  ' + $m) -ForegroundColor Yellow }
function Die($m)  { Write-Host ('  [x]  ' + $m) -ForegroundColor Red; exit 1 }

function Test-Admin {
  try {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

$path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
if (-not (Test-Path -LiteralPath $path)) { Die ('hosts file not found: ' + $path) }
if (-not (Test-Admin)) { Die 'editing the hosts file requires an elevated shell' }

# read as latin-1 so an existing OEM/ANSI hosts file survives byte-for-byte
$enc = [Text.Encoding]::GetEncoding(28591)
$bak = $path + '.quickerlab.bak'

function Get-Body([string[]]$lines) {
  $out = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($l in $lines) {
    if ($l.Trim() -eq $BEGIN) { $skip = $true; continue }
    if ($l.Trim() -eq $END)   { $skip = $false; continue }
    if (-not $skip) { $out.Add($l) }
  }
  return $out
}

function Save-Body($body) {
  $text = ($body -join "`r`n") + "`r`n"
  [IO.File]::WriteAllText($path, $text, $enc)
}

$mode = $args[0]
if (-not $mode) { $mode = $env:QK_HOSTS_MODE }
$i = [Array]::IndexOf($args, '-Mode')
if ($i -ge 0 -and $args[$i + 1]) { $mode = $args[$i + 1] }
if (-not $mode) { $mode = 'status' }
$mode = $mode.ToLower()

$lines = [IO.File]::ReadAllText($path, $enc) -split "`r?`n"
$body = Get-Body $lines
$present = ($lines | Where-Object { $_.Trim() -eq $BEGIN }).Count -gt 0

switch ($mode) {
  'on' {
    if ($present) { Ok 'sinkhole already active'; break }
    if (-not (Test-Path -LiteralPath $bak)) {
      Copy-Item -LiteralPath $path -Destination $bak -Force
      Ok ('backup written: ' + $bak)
    }
    $body.Add('')
    $body.Add($BEGIN)
    foreach ($h in $HOSTS) { $body.Add('0.0.0.0 ' + $h) }
    $body.Add($END)
    Save-Body $body
    Ok ('upstream sinkhole applied (' + $HOSTS.Count + ' hosts -> 0.0.0.0)')
    Write-Host '  note: Quicker cannot sign in while the sinkhole is active.' -ForegroundColor DarkGray
    Write-Host '        to sign in once:  -Mode off  -> sign in ->  -Mode on' -ForegroundColor DarkGray
    try { & ipconfig /flushdns | Out-Null } catch { }
  }
  'off' {
    if (-not $present) { Ok 'sinkhole not present - nothing to remove'; break }
    Save-Body $body
    Ok 'upstream sinkhole removed - all endpoints reachable again'
    try { & ipconfig /flushdns | Out-Null } catch { }
  }
  'status' {
    if ($present) { Ok 'sinkhole ACTIVE (upstream unreachable)' }
    else { Warn 'sinkhole INACTIVE (upstream reachable)' }
  }
  default { Die ('unknown mode: ' + $mode + ' (use on / off / status)') }
}
