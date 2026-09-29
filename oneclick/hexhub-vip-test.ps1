# HexHub 白盒鉴权脆弱性测试 —— 一键运行（支持 irm | iex）
#
#  用法一（一行管道，无需落盘）:
#    powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
#
#  用法二（先存盘再跑，可用环境变量调参）:
#    $env:HEXHUB_WORKDIR='D:\lab\hexhub'; $env:HEXHUB_STOP_AT_END='1'
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\hexhub-vip-test.ps1
#
#  可选环境变量:
#    HEXHUB_WORKDIR       工作目录（默认 %TEMP%\hexhub-lab）
#    HEXHUB_STOP_AT_END   =1 跑完自动关闭被测程序
#    HEXHUB_KEEP_FILES    =1 保留工作目录并在结束时提示
#
#  注意：本脚本刻意不使用 param()/[CmdletBinding()] —— 那两者只能出现在脚本文件里，
#        经 iex 以字符串执行时会报 UnexpectedAttribute。故选项一律走环境变量。
#
#  固定版本 : HexHub 5.1.9
#  构件来源 : github.com/Xioaruan912/ReverseFinal  Release whitebox-audit-v1.0
#  不访问   : 厂商官网的「最新版」下载地址

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# ── 锁定信息（改版本时只改这里）────────────────────────────────────────────
$REL_BASE    = 'https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0'
$PACK_NAME   = 'HexHub-whitebox-audit-pack-v1.0.zip'
$PACK_SHA256 = 'c49972cf0f0de1b6bf4fed06667a169bf7bd26d759c876aa32029a0cd8be9b3a'
$INST_NAME   = 'HexHub-Client-5.1.9-windows-amd64-setup.exe'
$INST_SHA256 = '0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6'
$INST_AS     = 'HexHub-Client-windows-amd64-installer-5.1.9.exe'
$PINNED_VER  = '5.1.9'

# ── 选项（环境变量）────────────────────────────────────────────────────────
$WorkDir = if ($env:HEXHUB_WORKDIR) { $env:HEXHUB_WORKDIR } else { Join-Path $env:TEMP 'hexhub-lab' }
$StopAtEnd = ($env:HEXHUB_STOP_AT_END -eq '1')
$KeepFiles = ($env:HEXHUB_KEEP_FILES -eq '1')

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
    Write-Host "  [..] 下载 $label"
    Write-Host "       $url"
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
 HexHub 白盒鉴权脆弱性测试 · 一键运行
 固定版本 : $PINNED_VER
 构件来源 : 本交付仓库 Release (whitebox-audit-v1.0)
 工作目录 : $WorkDir
============================================================
"@ -ForegroundColor White

# ── 1) 测试工具包 ───────────────────────────────────────────────────────────
Head '1/4  取得测试工具包（本交付仓库 Release）'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$packZip = Join-Path $WorkDir $PACK_NAME
Get-Pinned "$REL_BASE/$PACK_NAME" $packZip $PACK_SHA256 '测试工具包'

$caseRoot = Join-Path $WorkDir 'case'
if (Test-Path $caseRoot) { Remove-Item $caseRoot -Recurse -Force }
Expand-Archive -Path $packZip -DestinationPath $caseRoot -Force
Ok "已展开到 $caseRoot"

# ── 2) 固定版本安装包 ───────────────────────────────────────────────────────
Head "2/4  取得 HexHub $PINNED_VER 安装包（本交付仓库 Release）"
$instPath = Join-Path $caseRoot $INST_AS
Get-Pinned "$REL_BASE/$INST_NAME" $instPath $INST_SHA256 "HexHub $PINNED_VER 安装包"

# ── 3) 环境自检 ─────────────────────────────────────────────────────────────
Head '3/4  环境自检'
$pre = Join-Path $caseRoot 'preflight.ps1'
if (Test-Path $pre) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pre
    if ($LASTEXITCODE -ne 0) { Warn '自检有未通过项，测试可能无法继续（先按提示补齐环境）' }
} else { Warn '未找到 preflight.ps1，跳过' }

# ── 4) 执行白盒鉴权测试 ─────────────────────────────────────────────────────
Head '4/4  执行白盒鉴权测试'
$run = Join-Path $caseRoot 'run_test.ps1'
if (-not (Test-Path $run)) { Die '未找到 run_test.ps1（包结构异常）' }

$a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$run)
if ($StopAtEnd) { $a += '-StopAtEnd' }
& powershell @a

Write-Host @"

============================================================
 完成
============================================================
 测试工具包 : $caseRoot
 固定安装包 : $instPath
 取证输出   : $(Join-Path $caseRoot 'exports\')
 报告       : $(Join-Path $caseRoot 'reports\')
"@ -ForegroundColor White

Write-Host "  卸载/回滚: 直接删除工作目录 $WorkDir 即可。" -ForegroundColor DarkGray
if ($KeepFiles) { Write-Host "  已按 HEXHUB_KEEP_FILES=1 保留工作目录。" -ForegroundColor DarkGray }
