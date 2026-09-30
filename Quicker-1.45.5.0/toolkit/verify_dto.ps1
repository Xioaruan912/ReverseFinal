# =============================================================================
#  Quicker 1.45.5.0 - runtime authorisation judge  (A/B verdict tool)
#
#  Loads a Quicker.Common.dll by reflection and prints the licence state the
#  client itself would see.  Run it against the pristine DLL and against the
#  patched DLL to get the before/after verdict.
#
#  Usage:
#     powershell -NoProfile -ExecutionPolicy Bypass -File verify_dto.ps1 <dll>
#
#  The DLL must be loaded from the full application folder: it has assembly
#  references that are resolved from the sibling files.
# =============================================================================

$ErrorActionPreference = 'Stop'
$dll = $args[0]
if (-not $dll) {
  # works both with -File and with irm | iex (where $PSScriptRoot is empty)
  $cand = @()
  if ($PSScriptRoot) { $cand += (Join-Path (Split-Path $PSScriptRoot -Parent) 'toolkit\Quicker.Common.patched.dll') }
  $cand += (Join-Path (Get-Location).Path 'toolkit\Quicker.Common.patched.dll')
  foreach ($c in $cand) { if (Test-Path -LiteralPath $c) { $dll = $c; break } }
}
if (-not $dll) { Write-Host 'usage: verify_dto.ps1 <path to Quicker.Common.dll>'; exit 2 }
if (-not (Test-Path -LiteralPath $dll)) { Write-Host ('missing: ' + $dll); exit 2 }
$dll = (Resolve-Path -LiteralPath $dll).Path

$dir = Split-Path $dll -Parent
# optional sibling assemblies: only needed when the DLL sits inside a full
# Quicker install folder.  Their absence is not fatal for reading the DTO.
foreach ($sib in @('Quicker.Public.dll', 'Newtonsoft.Json.dll')) {
  $sp = Join-Path $dir $sib
  if (Test-Path -LiteralPath $sp) { try { [void][Reflection.Assembly]::LoadFrom($sp) } catch { } }
}

$sha = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLower()
Write-Host ''
Write-Host '============================================================'
Write-Host ' Quicker licence state (client-side authorisation DTO)'
Write-Host '============================================================'
Write-Host ('  assembly : ' + $dll)
Write-Host ('  sha256   : ' + $sha)
Write-Host ''

try { $asm = [Reflection.Assembly]::LoadFrom($dll) }
catch {
  Write-Host ('  cannot load the assembly: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host '  hint: point this script at Quicker.Common.dll inside a full Quicker folder.' -ForegroundColor DarkGray
  exit 2
}

function Show-Props($typeName, $props) {
  $t = $asm.GetType($typeName)
  if (-not $t) { Write-Host ('  TYPE MISSING: ' + $typeName); return }
  $inst = [Activator]::CreateInstance($t)
  foreach ($p in $props) {
    $pi = $t.GetProperty($p)
    if (-not $pi) { Write-Host ('  ' + $p.PadRight(22) + ' = <no such property>'); continue }
    try {
      $v = $pi.GetValue($inst, $null)
      if ($null -eq $v) { $v = '<null>' }
      Write-Host ('  ' + $p.PadRight(22) + ' = ' + $v)
    } catch {
      $e = $_.Exception; $chain = ''
      while ($e) { $chain += '[' + $e.GetType().Name + '] '; $e = $e.InnerException }
      Write-Host ('  ' + $p.PadRight(22) + ' = ERR ' + $chain)
    }
  }
}

Write-Host '-- Quicker.Common.Vm.Account.UserInfo'
Show-Props 'Quicker.Common.Vm.Account.UserInfo' @('MemberLevel', 'MemberExpireTimeUtc', 'UserSerial')
Write-Host ''
Write-Host '-- Quicker.Common.Vm.Account.UserLimitation'
Show-Props 'Quicker.Common.Vm.Account.UserLimitation' @(
  'CanUseMobileApp', 'LockButton', 'EnableActionHistory', 'EnableActionHotKey',
  'EnableStarter', 'EnableFloatButton', 'EnableSearching',
  'MaxPcCount', 'MaxExeCount', 'MaxPagePerExe', 'MaxPageFileSize',
  'TotalPageFileSize', 'MaxIconCount')

# ---- verdict -------------------------------------------------------------
$t = $asm.GetType('Quicker.Common.Vm.Account.UserInfo')
$ui = [Activator]::CreateInstance($t)
$lvl = [string]$t.GetProperty('MemberLevel').GetValue($ui, $null)
$lt = $asm.GetType('Quicker.Common.Vm.Account.UserLimitation')
$ul = [Activator]::CreateInstance($lt)
$maxExe = [int]$lt.GetProperty('MaxExeCount').GetValue($ul, $null)
$search = [bool]$lt.GetProperty('EnableSearching').GetValue($ul, $null)

Write-Host ''
Write-Host '------------------------------------------------------------'
if ($lvl -eq 'Pro' -and $maxExe -ge 999 -and $search) {
  Write-Host ' VERDICT: PRO  (member level lifted, quota ceilings opened)' -ForegroundColor Green
  exit 0
} elseif ($lvl -eq 'Free' -and $maxExe -eq 0 -and -not $search) {
  Write-Host ' VERDICT: FREE (pristine baseline)' -ForegroundColor Yellow
  exit 0
} else {
  Write-Host (' VERDICT: UNEXPECTED  level=' + $lvl + ' maxExe=' + $maxExe + ' search=' + $search) -ForegroundColor Red
  exit 1
}
