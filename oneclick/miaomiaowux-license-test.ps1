#Requires -Version 5.1
<#
.SYNOPSIS
  妙妙屋X (miaomiaowuX) 白盒鉴权脆弱性测试 —— 一键运行（Windows 侧入口）

.DESCRIPTION
  妙妙屋X 是 Linux 服务端程序，本脚本负责在 Windows 上把整套流程交给 WSL 执行：
  测试工具包与固定版本主程序全部从本交付仓库 Release 拉取并校验 sha256。

  固定版本 : miaomiaowuX v0.5.4
  前置条件 : 已安装 WSL2 + 任意 Debian/Ubuntu 发行版

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\miaomiaowux-license-test.ps1

.EXAMPLE
  .\miaomiaowux-license-test.ps1 -Distro Debian -Port 12889
#>
[CmdletBinding()]
param(
    [string] $Distro = '',
    [int]    $Port   = 12889
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh'
$PINNED_VER   = 'v0.5.4'

function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }

Write-Host @"
============================================================
 妙妙屋X 白盒鉴权脆弱性测试 · 一键运行（Windows → WSL）
 固定版本 : $PINNED_VER
 构件来源 : 本交付仓库 Release (whitebox-audit-v1.0)
============================================================
"@ -ForegroundColor White

Head '1/3  检查 WSL 环境'
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Die '未检测到 wsl.exe。请先安装 WSL2：wsl --install'
}
$list = (& wsl.exe -l -q) -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
if (-not $list) { Die '未检测到任何 WSL 发行版。请执行：wsl --install -d Debian' }
Ok ("可用发行版: " + ($list -join ', '))

if ([string]::IsNullOrWhiteSpace($Distro)) {
    $pick = $list | Where-Object { $_ -match 'Debian' } | Select-Object -First 1
    if (-not $pick) { $pick = $list | Where-Object { $_ -match 'Ubuntu' } | Select-Object -First 1 }
    if (-not $pick) { $pick = $list[0] }
    $Distro = $pick.Trim()
}
Ok "使用发行版: $Distro"

Head '2/3  检查 WSL 内依赖'
$chk = & wsl.exe -d $Distro -- bash -lc "for t in curl unzip python3; do command -v \$t >/dev/null || echo MISSING:\$t; done; command -v upx >/dev/null || echo MISSING:upx"
if ($chk) {
    Write-Host $chk -ForegroundColor Yellow
    Write-Host "  安装命令（Debian/Ubuntu）:" -ForegroundColor DarkGray
    Write-Host "    wsl -d $Distro -u root -- bash -c 'apt-get update && apt-get install -y curl unzip python3 upx-ucl'" -ForegroundColor DarkGray
    Die '请先补齐依赖后重试'
}
Ok '依赖齐全（curl / unzip / python3 / upx）'

Head '3/3  在 WSL 内执行一键白盒鉴权测试'
Write-Host "  [..] 拉取并执行: $ONECLICK_URL" -ForegroundColor DarkGray
Write-Host "  [..] 端口: $Port  （Ctrl+C 可停止）" -ForegroundColor DarkGray
Write-Host ''

& wsl.exe -d $Distro -- bash -lc "PORT=$Port bash <(curl -fsSL '$ONECLICK_URL')"
