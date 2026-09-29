<#
.SYNOPSIS
  HexHub 白盒鉴权脆弱性测试 —— 一键执行（精简版，无回滚）

.DESCRIPTION
  流程：静态解包 → 启动被测客户端(CDP) → 页面级断网 + 伪造会话注入 → 取证截图。
  不做任何系统改动（不改 hosts / 防火墙 / 注册表），不做任何备份回滚。
  被测客户端跑完后保持运行，便于人工查看 UI；用 -StopAtEnd 可自动关闭。

.PARAMETER Port
  CDP 调试端口，默认自动探测空闲端口

.PARAMETER StopAtEnd
  取证完成后自动关闭本次启动的客户端

.PARAMETER NegativeControl
  额外跑一次"服务器可达"的负向对照，用于证明只有服务端在把关

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\run_test.ps1
  powershell -ExecutionPolicy Bypass -File .\run_test.ps1 -NegativeControl
  powershell -ExecutionPolicy Bypass -File .\run_test.ps1 -StopAtEnd
#>
param(
    [int]$Port = 0,
    [switch]$StopAtEnd,
    [switch]$NegativeControl
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$CaseRoot = $PSScriptRoot
$Extract  = Join-Path $CaseRoot 'samples\extracted'

function Step($n, $t) { Write-Host "`n=== [$n] $t ===" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m)     { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)      { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

function Resolve-Python {
    foreach ($c in @('D:\miniconda3\python.exe',
                     (Join-Path $env:USERPROFILE 'miniconda3\python.exe'),
                     (Join-Path $env:LOCALAPPDATA 'miniconda3\python.exe'))) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $g = Get-Command python -ErrorAction SilentlyContinue; if ($g) { return $g.Source }
    return $null
}
function Resolve-NodeModules {
    foreach ($c in @((Join-Path $env:USERPROFILE '.pi\agent\npm\node_modules'),
                     (Join-Path $env:APPDATA 'npm\node_modules'))) {
        if (Test-Path (Join-Path $c 'playwright')) { return $c }
    }
    try { $r = (& npm root -g 2>$null); if ($r -and (Test-Path (Join-Path $r 'playwright'))) { return $r } } catch {}
    return $null
}
function Get-FreePort {
    foreach ($p in 9222..9260) {
        if (-not (Test-NetConnection 127.0.0.1 -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue)) { return $p }
    }
    return 9222
}

$Py       = Resolve-Python
$NodePath = Resolve-NodeModules
$Pids     = @()

try {
    Step 0 '环境检查'
    if (-not $Py)       { Die '未找到 Python，请安装 Miniconda 或把 python 加入 PATH' }
    if (-not $NodePath) { Die '未找到 Playwright，请执行: npm i -g playwright' }
    Ok "Python    : $Py"
    Ok "Playwright: $NodePath"

    Step 1 '静态解包（不执行安装器）'
    if (-not (Test-Path (Join-Path $Extract 'HexHub.exe'))) {
        & $Py (Join-Path $CaseRoot 'extract.py')
        Ok '解包完成'
    } else { Ok '解包副本已存在' }

    Step 2 '启动被测客户端（解包副本 + CDP）'
    if ($Port -eq 0) { $Port = Get-FreePort }
    $p = Start-Process -FilePath (Join-Path $Extract 'HexHub.exe') `
                       -ArgumentList "--remote-debugging-port=$Port" `
                       -WorkingDirectory $Extract -PassThru
    $Pids += $p.Id
    Ok "已启动 HexHub.exe PID=$($p.Id)  CDP端口=$Port"

    $ready = $false
    foreach ($i in 1..25) {
        Start-Sleep -Seconds 2
        try { $v = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 3
              Ok "CDP 就绪: $($v.Browser)"; $ready = $true; break } catch {}
    }
    if (-not $ready) { Die 'CDP 未就绪，检查 exports 日志或 -Port 参数' }

    Step 3 '执行鉴权脆弱性测试'
    $env:NODE_PATH         = $NodePath
    $env:HEXHUB_CDP_PORT   = "$Port"
    $env:NEGATIVE_CONTROL  = if ($NegativeControl) { '1' } else { '0' }
    Push-Location $CaseRoot
    node (Join-Path $CaseRoot 'poc_test.js')
    $code = $LASTEXITCODE
    Pop-Location

    Step 4 '结果'
    Write-Host "  evidence : exports\vip_bypass.png" -ForegroundColor Green
    Write-Host "  评估报告 : reports\HexHub-5.1.9-VIP鉴权脆弱性评估报告.md" -ForegroundColor Green
    Write-Host "  方法论   : reports\HOWTO-白盒鉴权脆弱性测试-SOP.md" -ForegroundColor Green
    if ($code -ne 0) { Warn "PoC 退出码 $code" }
}
finally {
    if ($StopAtEnd) {
        Write-Host "`n=== [S] 关闭本次启动的客户端 ===" -ForegroundColor Magenta
        foreach ($procId in $Pids) {
            Get-Process -Id $procId -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Get-Process -Name 'hexhub-backend' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Path -and $_.Path.StartsWith($Extract, 'OrdinalIgnoreCase')) {
                $_ | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
        Ok '已关闭'
    } else {
        Write-Host "`n  [i] 被测客户端保持运行（便于查看 UI）。关闭： " -ForegroundColor Yellow
        Write-Host "      taskkill /IM HexHub.exe /F ; taskkill /IM hexhub-backend.exe /F" -ForegroundColor Yellow
    }
}
