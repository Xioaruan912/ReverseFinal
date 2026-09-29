#Requires -Version 5.1
<#
.SYNOPSIS
  Listary 6 Pro 专业版权益 —— 一键白盒鉴权测试

.DESCRIPTION
  把「测试工具包」和「固定版本安装包/主程序」全部从本仓库 Release 拉下来，
  校验 sha256，然后在干净环境里跑完整个白盒鉴权测试。

  固定版本 : Listary 6.3.5.94
  构件来源 : github.com/Xioaruan912/ReverseFinal  Release whitebox-audit-v1.0
  不访问   : 厂商账号服务器与「最新版」下载地址

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\listary-pro-test.ps1

.EXAMPLE
  # 指定测试邮箱；已装好 Listary 时跳过安装
  .\listary-pro-test.ps1 -Email lab@example.com -SkipInstall
#>
[CmdletBinding()]
param(
    [string] $Email    = "$env:USERNAME@lab.local",
    [string] $WorkDir  = (Join-Path $env:TEMP 'listary-lab'),
    [switch] $SkipInstall,
    [switch] $Restore
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# ── 锁定信息（改版本时只改这里）────────────────────────────────────────────
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'Listary-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = '46d55be0531899ab056add204c6a24c00f0582c0803133ebe71437ed6bba678a'
$SETUP_NAME  = 'Listary-6.3.5.94-setup.exe'
$SETUP_SHA   = 'c62249e0d4d49bd3f062d55635cf6a3ab089ea8ee7f6c03947f6febfafaa0288'
$MAIN_NAME   = 'Listary-6.3.5.94-main.exe'
$MAIN_SHA    = 'be2aec5c06d2731cb89a9799ffeeffdb063afe0da7f1dfcdeb33c6929e7b20d9'
$PINNED_VER  = '6.3.5.94'
$INSTALL_DIR = Join-Path $env:ProgramFiles 'Listary'

function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

function Get-Pinned($url, $dest, $expectSha, $label) {
    if (Test-Path $dest) {
        if ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $expectSha) {
            Ok "$label 已存在且校验通过"; return
        }
        Warn "$label 本地文件校验不符，重新下载"; Remove-Item $dest -Force
    }
    Write-Host "  [..] 下载 $label"; Write-Host "       $url"
    $tmp = "$dest.part"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -fL --retry 3 --connect-timeout 15 --max-time 1800 -o $tmp $url
        if ($LASTEXITCODE -ne 0) { Die "$label 下载失败" }
    } else {
        try { (New-Object Net.WebClient).DownloadFile($url, $tmp) } catch { Die "$label 下载失败: $_" }
    }
    $got = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $expectSha) {
        Remove-Item $tmp -Force
        Die "$label sha256 不匹配`n      期望 $expectSha`n      实际 $got"
    }
    Move-Item $tmp $dest -Force
    Ok "$label 校验通过"
}

Write-Host @"
============================================================
 Listary 6 Pro 白盒鉴权测试 · 一键运行
 固定版本 : $PINNED_VER
 测试邮箱 : $Email
 构件来源 : 本仓库 Release (whitebox-audit-v1.0)
 工作目录 : $WorkDir
============================================================
"@ -ForegroundColor White

# ── 1) 测试工具包 ───────────────────────────────────────────────────────────
Head '1/4  取得测试工具包（本仓库 Release）'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$packZip = Join-Path $WorkDir $PACK_NAME
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 '测试工具包'
$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "已展开到 $caseRoot"

# ── 2) 固定版本安装包 + 主程序 ─────────────────────────────────────────────
Head "2/4  取得 Listary $PINNED_VER 安装包与主程序（本仓库 Release）"
$setupPath = Join-Path $WorkDir $SETUP_NAME
$mainPath  = Join-Path $WorkDir $MAIN_NAME
Get-Pinned "$REL_BASE/$SETUP_NAME" $setupPath $SETUP_SHA "Listary $PINNED_VER 安装包"
Get-Pinned "$REL_BASE/$MAIN_NAME"  $mainPath  $MAIN_SHA  "Listary $PINNED_VER 主程序"

# ── 3) 准备被测环境 ─────────────────────────────────────────────────────────
Head '3/4  准备被测环境'
$installed = Join-Path $INSTALL_DIR 'Listary.exe'
if ($Restore) {
    Push-Location $caseRoot
    & (Join-Path $caseRoot 'tools\Listary6Pro.exe') restore
    Pop-Location
    Ok '已执行还原，退出'; exit 0
}

if (Test-Path $installed) {
    $h = (Get-FileHash $installed -Algorithm SHA256).Hash.ToLower()
    if ($h -eq $MAIN_SHA) {
        Ok "已安装的 Listary 与固定版本一致 ($PINNED_VER)"
    } else {
        Warn "已安装的 Listary 哈希与固定版本不一致"
        Write-Host "      已安装: $h" -ForegroundColor DarkGray
        Write-Host "      固定版: $MAIN_SHA" -ForegroundColor DarkGray
        Warn "结论可能不适用于该版本；建议 -SkipInstall 关掉并在干净机器上重跑"
    }
} elseif ($SkipInstall) {
    Die "未检测到已安装的 Listary（$installed），且指定了 -SkipInstall"
} else {
    Warn "未检测到 Listary，使用固定安装包静默安装 ($PINNED_VER)"
    $rp = Start-Process -FilePath $setupPath `
        -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait -PassThru
    Ok "安装完成 (exit=$($rp.ExitCode))"
    Start-Sleep -Seconds 3
}

# ── 4) 执行白盒鉴权测试 ─────────────────────────────────────────────────────
Head '4/4  执行白盒鉴权测试'
$tool = Join-Path $caseRoot 'tools\Listary6Pro.exe'
if (-not (Test-Path $tool)) { Die "未找到测试工具 $tool（包结构异常）" }

Write-Host "  ── 读取当前状态 ──" -ForegroundColor DarkGray
& $tool info

Write-Host "`n  ── 执行鉴权测试（写入自洽授权信息并重启）──" -ForegroundColor DarkGray
& $tool activate $Email

Write-Host "`n  ── 复核 ──" -ForegroundColor DarkGray
& $tool info

Write-Host @"

============================================================
 完成
============================================================
 现在打开 Listary 主界面 / 托盘右键 → 设置，
 查看专业版（Pro）状态是否已生效。

 回滚到测试前状态：
   powershell -ExecutionPolicy Bypass -File $PSCommandPath -Restore

 取证与报告：
   $caseRoot\reports\
"@ -ForegroundColor White
