param([string]$exe,[string]$dir,[string]$tag,[int]$wait=35)
$ErrorActionPreference='SilentlyContinue'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Remove-Item (Join-Path $dir 'out.log') -Force
$log = Join-Path $dir 'out.log'
$s = 'log verbose "' + $log + '"' + "`r`n" + 'load "' + $dir + '" "' + $dir + '"' + "`r`n" + 'expand all' + "`r`n"
Set-Content -Path (Join-Path $dir 's.txt') -Value $s -NoNewline -Encoding ascii
$p = Start-Process -FilePath $exe -ArgumentList '@s.txt' -WorkingDirectory $dir -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $dir 'o.txt') -RedirectStandardError (Join-Path $dir 'e.txt')
$ex = $p.WaitForExit($wait*1000)
Start-Sleep -Seconds 1
$txt = 'NOEXIT'
if ($ex) { $txt = 'EXIT rc=' + $p.ExitCode }
$ban = 'NOLOG'
if (Test-Path $log) { $b = Select-String -Path $log -Pattern '\*\*\*' | Select-Object -First 1; if ($b) { $ban = $b.Line.Trim() } else { $ban='NOBANNER' } }
Stop-Process -Name BCompare -Force
Write-Output ("$tag | $txt | $ban")
