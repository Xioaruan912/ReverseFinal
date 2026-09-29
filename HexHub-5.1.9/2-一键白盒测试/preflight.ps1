<#
.SYNOPSIS
  HexHub 白盒鉴权脆弱性测试包 —— 交付前环境自检

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$CaseRoot = $PSScriptRoot
$ok = 0; $bad = 0

function Chk($name, [bool]$pass, $hint) {
    if ($pass) { Write-Host ("  [OK]   {0}" -f $name) -ForegroundColor Green; $script:ok++ }
    else       { Write-Host ("  [FAIL] {0}  -> {1}" -f $name, $hint) -ForegroundColor Red; $script:bad++ }
}

Write-Host "`n=== HexHub 白盒鉴权脆弱性测试包 · 环境自检 ===" -ForegroundColor Cyan
Write-Host "包目录: $CaseRoot`n"

# 1 Python
$py = $null
foreach ($c in @('D:\miniconda3\python.exe',
                 (Join-Path $env:USERPROFILE 'miniconda3\python.exe'),
                 (Join-Path $env:LOCALAPPDATA 'miniconda3\python.exe'))) {
    if ($c -and (Test-Path $c)) { $py = $c; break }
}
if (-not $py) { $g = Get-Command python -ErrorAction SilentlyContinue; if ($g) { $py = $g.Source } }
Chk "Python 可用 ($py)" ([bool]$py) '安装 Miniconda / Python 3，或把 python 加入 PATH'

# 2 Node
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
Chk "Node.js 可用" ([bool]$node) '安装 Node.js'

# 3 Playwright
$npmMod = $null
foreach ($c in @((Join-Path $env:USERPROFILE '.pi\agent\npm\node_modules'),
                 (Join-Path $env:APPDATA 'npm\node_modules'))) {
    if (Test-Path (Join-Path $c 'playwright')) { $npmMod = $c; break }
}
if (-not $npmMod) { try { $r = (& npm root -g 2>$null); if (Test-Path (Join-Path $r 'playwright')) { $npmMod = $r } } catch {} }
Chk "Playwright 已安装 ($npmMod)" ([bool]$npmMod) 'npm i -g playwright'

# 4 目标安装包（本包目录 / 上级 / Downloads / Desktop）
$installer = Get-ChildItem -Path $CaseRoot, (Split-Path $CaseRoot -Parent),
             (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop') `
             -Filter 'HexHub-Client-windows-amd64-installer-*.exe' -ErrorAction SilentlyContinue |
             Select-Object -First 1
Chk "目标安装包存在 ($(if($installer){$installer.Name}else{'未找到'}))" ([bool]$installer) `
    '把 HexHub-Client-windows-amd64-installer-5.1.9.exe 放到本包目录 / Downloads / Desktop'

# 5 解包副本（缺失时可自动生成）
$ex = Join-Path $CaseRoot 'samples\extracted\HexHub.exe'
Chk '解包副本已就绪（缺失则自动解包）' ((Test-Path $ex) -or [bool]$installer) '先运行 python extract.py'

# 6 关键脚本
foreach ($f in 'run_test.ps1','poc_test.js','extract.py','patch_vip.py') {
    Chk "脚本 $f" (Test-Path (Join-Path $CaseRoot $f)) '交付包不完整，请重新解压'
}

# 7 空闲 CDP 端口
$freePort = 0
foreach ($p in 9222..9240) {
    if (-not (Test-NetConnection 127.0.0.1 -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue)) { $freePort = $p; break }
}
Chk "CDP 端口可用（首个空闲: $freePort）" ($freePort -ne 0) '关闭占用端口的程序，或用 -Port 指定'

# 8 hosts 干净（本包不需要改 hosts）
$hostsHit = (Select-String -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Pattern 'hexhub' -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count
Chk 'hosts 无 hexhub 条目（本包不需要改 hosts）' ($hostsHit -eq 0) '建议清理，恢复干净基线'

# 9 提示：可选隔离模式需要管理员
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("  [i]    管理员权限: {0}  (仅 optional\run_isolated.ps1 隔离模式需要)" -f $isAdmin) -ForegroundColor Gray

Write-Host ""
if ($bad -eq 0) {
    Write-Host "  全部通过（$ok 项）—— 可以执行： powershell -ExecutionPolicy Bypass -File .\run_test.ps1" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  $bad 项未通过（$ok 项通过）—— 请先按提示修复" -ForegroundColor Yellow
    exit 1
}
