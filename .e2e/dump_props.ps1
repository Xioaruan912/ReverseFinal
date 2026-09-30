$ErrorActionPreference = 'Stop'
$dll = $args[0]
if (-not $dll) { $dll = 'C:\Users\Administrator\Desktop\Quicker-1.45.5.0\Quicker.Common.dll' }
$dll = (Resolve-Path -LiteralPath $dll).Path
$dir = Split-Path $dll -Parent
foreach ($sib in @('Quicker.Public.dll', 'Newtonsoft.Json.dll')) {
  $sp = Join-Path $dir $sib
  if (Test-Path -LiteralPath $sp) { try { [void][Reflection.Assembly]::LoadFrom($sp) } catch { } }
}
$sha = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLower()
Write-Host ('DLL  : ' + $dll)
Write-Host ('sha  : ' + $sha)
Write-Host ''
$asm = [Reflection.Assembly]::LoadFrom($dll)

foreach ($tn in @('Quicker.Common.Vm.Account.UserInfo', 'Quicker.Common.Vm.Account.UserLimitation')) {
  $t = $asm.GetType($tn)
  if (-not $t) { Write-Host ('MISSING ' + $tn); continue }
  Write-Host ('=== ' + $tn + ' ===')
  $inst = $null
  try { $inst = [Activator]::CreateInstance($t) } catch { Write-Host ('  ctor ERR: ' + $_.Exception.Message) }
  foreach ($p in ($t.GetProperties() | Sort-Object Name)) {
    $type = $p.PropertyType.ToString()
    $val = '<n/a>'
    if ($inst -and $p.CanRead -and $p.GetIndexParameters().Count -eq 0) {
      try { $v = $p.GetValue($inst, $null); if ($null -eq $v) { $v = '<null>' }; $val = [string]$v }
      catch { $val = 'ERR ' + $_.Exception.InnerException.GetType().Name }
    }
    Write-Host ('   {0,-30} : {1,-42} = {2}' -f $p.Name, $type, $val)
  }
  Write-Host ''
}
