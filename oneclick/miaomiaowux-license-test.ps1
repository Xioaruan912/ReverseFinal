# 妙妙屋X (miaomiaowuX) 白盒鉴权脆弱性测试 —— 一键运行（Windows 侧入口，支持 irm | iex）
#
#  用法一（一行管道，无需落盘）:
#    powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
#
#  用法二（先存盘再跑，可用环境变量调参）:
#    $env:MMWX_DISTRO='Debian'; $env:PORT='12889'
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\miaomiaowux-license-test.ps1
#
#  可选环境变量:
#    MMWX_DISTRO  指定 WSL 发行版（默认自动选 Debian → Ubuntu → 第一个）
#    PORT         面板端口（默认 12889）
#
#  注意：本脚本刻意不使用 param()/[CmdletBinding()] —— 那两者只能出现在脚本文件里，
#        经 iex 以字符串执行时会报 UnexpectedAttribute。故选项一律走环境变量。
#
#  固定版本 : miaomiaowuX v0.5.4
#  前置条件 : 已安装 WSL2 + 任意 Debian/Ubuntu 发行版

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ONECLICK_URL = 'https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh'
$PINNED_VER   = 'v0.5.4'

$Distro = $env:MMWX_DISTRO
$Port   = if ($env:PORT) { [int]$env:PORT } else { 12889 }

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
