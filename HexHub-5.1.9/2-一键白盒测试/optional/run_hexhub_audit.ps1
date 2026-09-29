<#
.SYNOPSIS
  HexHub 客户端 VIP 鉴权脆弱性（CWE-602）白盒验证 —— 一键复现脚本

.DESCRIPTION
  全自动执行：NSIS 解包 → 启动真实客户端(开启 CDP) → 断网 + 伪造会话注入 → 取证截图。
  仅用于【已授权沙盒环境】内的客户端逻辑验证。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1
  powershell -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1 -ApplyPatch      # 额外做二进制补丁 A/B
  powershell -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1 -Restore         # 复原环境
#>
param(
    [switch]$ApplyPatch,
    [switch]$Restore,
    [int]$CdpPort = 9222
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$CaseRoot = $PSScriptRoot
$Py       = 'D:\miniconda3\python.exe'
$NodePath = 'C:\Users\Administrator\.pi\agent\npm\node_modules'
$Extract  = Join-Path $CaseRoot 'samples\extracted'

function Step($n, $t) { Write-Host "`n=== [$n] $t ===" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m)     { Write-Host "  [!] $m" -ForegroundColor Yellow }

function Stop-HexHub {
    foreach ($p in 'HexHub', 'hexhub-backend') {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 4
}

function Start-HexHub([int]$port) {
    Start-Process -FilePath (Join-Path $Extract 'HexHub.exe') `
                  -ArgumentList "--remote-debugging-port=$port" `
                  -WorkingDirectory $Extract | Out-Null
}

function Wait-Cdp([int]$port, [int]$tries = 25) {
    for ($i = 1; $i -le $tries; $i++) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-RestMethod "http://127.0.0.1:$port/json/version" -TimeoutSec 3
            Ok "CDP 就绪: $($r.Browser)"
            return $true
        } catch { }
    }
    return $false
}

# --------------------------------------------------------------------------
if ($Restore) {
    Step 1 '复原环境'
    Stop-HexHub
    $orig = Join-Path $CaseRoot 'patches\hexhub-backend.original.exe'
    if (Test-Path $orig) {
        Copy-Item $orig (Join-Path $Extract 'hexhub-backend.exe') -Force
        Ok 'hexhub-backend.exe 已还原为原始版本'
    }
    Remove-Item "$env:APPDATA\HexHub\cache\Default\Local Storage\leveldb" -Recurse -Force -ErrorAction SilentlyContinue
    Ok '本地会话 leveldb 已清空'
    Warn '如需解封网络，请手动清理 hosts 中的 api.hexhub.cn / oss.hexhub.cn'
    exit 0
}

Step 1 'NSIS 解包（若已解包则跳过）'
if (-not (Test-Path (Join-Path $Extract 'hexhub-backend.exe'))) {
    & $Py (Join-Path $CaseRoot 'extract.py')
    Ok '解包完成'
} else {
    Ok '载荷已存在，跳过'
}

Step 2 '停止残留进程'
Stop-HexHub
Ok '已清理'

Step 3 '启动客户端并开启 CDP 调试端口'
Start-HexHub $CdpPort
if (-not (Wait-Cdp $CdpPort)) { throw "CDP 未就绪（端口 $CdpPort），请检查 HexHub.exe 是否启动" }

if ($ApplyPatch) {
    Step 4 '生成并部署等长二进制补丁'
    Stop-HexHub
    & $Py (Join-Path $CaseRoot 'patch_vip.py')
    Copy-Item (Join-Path $CaseRoot 'patches\hexhub-backend.patched.exe') (Join-Path $Extract 'hexhub-backend.exe') -Force
    Ok '补丁版 backend 已部署'
    Start-HexHub $CdpPort
    if (-not (Wait-Cdp $CdpPort)) { throw '补丁版 CDP 未就绪' }
}

Step 5 '断网 + 伪造会话注入 + 取证'
$env:NODE_PATH = $NodePath
Push-Location $CaseRoot
node (Join-Path $CaseRoot 'poc_offline_vip.js')
Pop-Location

Step 6 '结果'
Write-Host ''
Write-Host '  证据截图: exports\poc_offline_vip.png' -ForegroundColor Green
Write-Host '  报告:     reports\HexHub-5.1.9-VIP鉴权脆弱性评估报告.md' -ForegroundColor Green
Write-Host '  SOP:      reports\HOWTO-白盒鉴权脆弱性测试-SOP.md' -ForegroundColor Green
Warn '验证完毕请执行 -Restore 复原环境'
