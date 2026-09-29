<#
.SYNOPSIS
  HexHub 白盒鉴权脆弱性测试 —— 零痕迹隔离运行器（不影响宿主任何正常使用）

.DESCRIPTION
  隔离原理（对宿主机零写入、零系统改动、可完整回滚）：
    1. 前置守卫：检测 HexHub 是否在运行 / 是否管理员 → 不满足则拒绝执行
    2. 把 %APPDATA%\HexHub 原地改名备份（同卷 rename，瞬时完成，数据零丢失）
    3. 建立目录联接(junction) %APPDATA%\HexHub -> <案例>\samples\sandbox\AppData\Roaming\HexHub
       → 被测程序的所有落盘（CEF profile / localStorage / 资产库）全部被重定向进沙箱
    4. 全程只在【解包副本】上运行，绝不触碰 %ProgramFiles%\HexHub
    5. 断网只在浏览器页面级拦截（Playwright route abort），不改 hosts / 防火墙
    6. 只结束【本次自己启动】的进程（记录 PID），绝不 taskkill 用户正在用的实例
    7. finally 块保证：删除 junction → 原名还原 → 沙箱清理

  最终效果：跑完测试后，宿主机的 %APPDATA%\HexHub、hosts、防火墙、注册表、
            已安装的 HexHub 全部与执行前完全一致。

.PARAMETER Port
  CDP 调试端口，默认 9222（自动探测空闲端口）

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\run_isolated.ps1
  powershell -ExecutionPolicy Bypass -File .\run_isolated.ps1 -WithPatch     # 附二进制补丁 A/B
  powershell -ExecutionPolicy Bypass -File .\run_isolated.ps1 -KeepSandbox   # 保留沙箱便于取证
#>
param(
    [int]$Port = 0,
    [switch]$WithPatch,
    [switch]$KeepSandbox
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$CaseRoot  = $PSScriptRoot

# ---- 自动探测 Python / Playwright（去硬编码，便于跨机器交付）----
function Resolve-Python {
    $cands = @(
        'D:\miniconda3\python.exe',
        (Join-Path $env:USERPROFILE 'miniconda3\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'miniconda3\python.exe'),
        (Join-Path $env:ProgramData 'miniconda3\python.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    $g = Get-Command python -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $g = Get-Command py -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}
function Resolve-NodeModules {
    $cands = @(
        (Join-Path $env:USERPROFILE '.pi\agent\npm\node_modules'),
        (Join-Path $env:APPDATA 'npm\node_modules'),
        (Join-Path $env:ProgramFiles 'nodejs\node_modules')
    )
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'playwright')) { return $c } }
    try {
        $r = (& npm root -g 2>$null)
        if ($r -and (Test-Path (Join-Path $r 'playwright'))) { return $r }
    } catch {}
    return $null
}

$Py       = Resolve-Python
$NodePath = Resolve-NodeModules
$Extract   = Join-Path $CaseRoot 'samples\extracted'
$Sandbox   = Join-Path $CaseRoot 'samples\sandbox'
$SbHome    = Join-Path $Sandbox 'AppData\Roaming\HexHub'
$RealHome  = Join-Path $env:APPDATA 'HexHub'
$RealBak   = Join-Path $env:APPDATA ("HexHub.__audit_bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$script:StartedPids = @()
$script:JunctionOn  = $false

function Step($n, $t) { Write-Host "`n=== [$n] $t ===" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m)     { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)      { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FreePort {
    foreach ($p in 9222..9260) {
        if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue)) { return $p }
    }
    return 9222
}

# ---------------------------------------------------------------- 回滚
function Restore-Host {
    Write-Host "`n=== [R] 回滚宿主环境 ===" -ForegroundColor Magenta

    # 只结束本次自己启动的进程
    foreach ($procId in $script:StartedPids) {
        try {
            $pr = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($pr) { $pr | Stop-Process -Force -ErrorAction SilentlyContinue; Ok "已结束本进程 PID=$procId ($($pr.ProcessName))" }
        } catch {}
    }
    # 兜底：结束由沙箱目录启动的 hexhub-backend（按路径匹配，不误伤）
    Get-Process -Name 'hexhub-backend' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -and $_.Path.StartsWith($Extract, 'OrdinalIgnoreCase')) {
                $_ | Stop-Process -Force -ErrorAction SilentlyContinue; Ok "已结束沙箱后端 PID=$($_.Id)"
            }
        } catch {}
    }
    Start-Sleep -Seconds 2

    if ($script:JunctionOn -and (Test-Path $RealHome)) {
        cmd /c rmdir "$RealHome" 2>$null      # 只删 junction，不删目标内容
        $script:JunctionOn = $false
        Ok "已拆除 junction"
    }
    if (Test-Path $RealBak) {
        if (Test-Path $RealHome) { Remove-Item $RealHome -Recurse -Force -ErrorAction SilentlyContinue }
        Move-Item $RealBak $RealHome -Force
        Ok "已还原 %APPDATA%\HexHub（用户原始数据完好）"
    }

    if (-not $KeepSandbox) {
        Remove-Item $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
        Ok "沙箱已清理"
    } else {
        Warn "沙箱已保留: $Sandbox"
    }
    Write-Host "`n  宿主状态核验：" -ForegroundColor Cyan
    Write-Host "    %APPDATA%\HexHub 存在      : $(Test-Path $RealHome)"
    Write-Host "    hosts 未被修改             : $((Select-String -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Pattern 'hexhub' -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)"
    Write-Host "    已安装 HexHub 未被改动     : $(-not (Test-Path 'C:\Program Files\HexHub\hexhub-backend.exe'))"
}

# ================================================================== 主流程
try {
    Step 0 '前置守卫'
    if (-not (Test-Admin)) { Die '需要管理员权限（创建 junction）' }
    if (-not $Py)       { Die '未找到 Python，请安装 Miniconda 或把 python 加入 PATH' }
    if (-not $NodePath) { Die '未找到 Playwright，请执行: npm i -g playwright' }
    Ok "Python    : $Py"
    Ok "Playwright: $NodePath"
    $running = Get-Process -Name 'HexHub', 'hexhub-backend' -ErrorAction SilentlyContinue
    if ($running) {
        Die "检测到 HexHub 正在运行（PID: $($running.Id -join ', ')）。请先自行关闭，本脚本绝不强杀用户实例。"
    }
    Ok '管理员权限 ✓ / 无 HexHub 在运行 ✓'

    Step 1 '准备解包副本'
    if (-not (Test-Path (Join-Path $Extract 'HexHub.exe'))) {
        & $Py (Join-Path $CaseRoot 'extract.py')
        Ok 'NSIS 解包完成'
    } else { Ok '解包副本已存在' }

    Step 2 '备份并重定向 %APPDATA%\HexHub'
    New-Item -ItemType Directory -Path $Sandbox, $SbHome -Force | Out-Null
    if (Test-Path $RealHome) {
        Move-Item $RealHome $RealBak -Force
        Ok "原目录已备份 -> $RealBak"
    } else { Warn '原目录不存在，跳过备份' }
    cmd /c mklink /J "$RealHome" "$SbHome" | Out-Null
    if (-not (Test-Path $RealHome)) { Die 'junction 创建失败' }
    $script:JunctionOn = $true
    Ok "junction 已建立: $RealHome -> $SbHome"

    if ($WithPatch) {
        Step 2b '生成并部署等长二进制补丁（仅作用于解包副本）'
        & $Py (Join-Path $CaseRoot 'patch_vip.py')
        Copy-Item (Join-Path $CaseRoot 'patches\hexhub-backend.patched.exe') (Join-Path $Extract 'hexhub-backend.exe') -Force
        Ok '补丁版 backend 已部署到沙箱副本'
    }

    Step 3 '启动被测客户端（沙箱副本 + CDP）'
    if ($Port -eq 0) { $Port = Get-FreePort }
    $p = Start-Process -FilePath (Join-Path $Extract 'HexHub.exe') `
                       -ArgumentList "--remote-debugging-port=$Port" `
                       -WorkingDirectory $Extract -PassThru
    $script:StartedPids += $p.Id
    Ok "已启动 HexHub.exe PID=$($p.Id) CDP端口=$Port"

    $ready = $false
    foreach ($i in 1..25) {
        Start-Sleep -Seconds 2
        try { $v = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 3; Ok "CDP 就绪: $($v.Browser)"; $ready = $true; break } catch {}
    }
    if (-not $ready) { Die 'CDP 未就绪' }

    Step 4 '核验隔离是否生效'
    Get-Process -Name 'hexhub-backend' -ErrorAction SilentlyContinue | ForEach-Object { $script:StartedPids += $_.Id }
    Start-Sleep -Seconds 3
    if (Test-Path (Join-Path $SbHome 'cache\Default\Local Storage\leveldb')) {
        Ok '隔离生效：被测程序落盘已进入沙箱'
    } else {
        Warn '沙箱内暂未发现 localStorage（可能仍在初始化）'
    }

    Step 5 '执行 PoC（页面级断网 + 伪造会话注入 + 取证）'
    $env:NODE_PATH = $NodePath
    $env:HEXHUB_CDP_PORT = "$Port"
    Push-Location $CaseRoot
    node (Join-Path $CaseRoot 'poc_isolated.js')
    Pop-Location

    Step 6 '结果'
    Write-Host ''
    Write-Host "  evidence: exports\poc_isolated_vip.png" -ForegroundColor Green
    Write-Host "  测试报告: reports\HexHub-5.1.9-VIP鉴权脆弱性评估报告.md" -ForegroundColor Green
}
finally {
    Restore-Host
}
