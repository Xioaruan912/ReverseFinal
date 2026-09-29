#!/usr/bin/env bash
# ============================================================================
# 妙妙屋X (miaomiaowuX) · 白盒鉴权脆弱性测试 —— 一键运行
#
#   只做一件事：把「测试工具包」和「固定版本主程序」全部从本交付仓库的 Release
#   拉下来，校验 sha256，然后自动跑完整个白盒鉴权测试。
#
#   固定版本 : miaomiaowuX v0.5.4
#   构件来源 : github.com/Xioaruan912/ReverseFinal  Release whitebox-audit-v1.0
#   不访问   : 上游仓库的 releases/latest、ghcr.io 的 :latest 镜像
#
#   用法（Linux / WSL）:
#     bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
#
#   参数（环境变量）:
#     PORT=12889            面板端口
#     WORKDIR=~/mmwx-lab    工作目录
#     MMWX_MIRROR=<url>     自建镜像前缀（可选，作为 Release 的备用源）
# ============================================================================
set -euo pipefail

REL_BASE="https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0"
PACK_NAME="miaomiaowuX-whitebox-audit-pack-v1.0.zip"
PACK_SHA256="a674be1eb5b398107cd4b1cabd45f884818f7db731214255b63eac5cc50b7937"
PINNED_VER="v0.5.4"
PORT="${PORT:-12889}"
WORKDIR="${WORKDIR:-$HOME/mmwx-lab}"

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
head_(){ echo; c '36' "=== $1 ==="; }
ok(){   c '32' "  [+] $1"; }
warn(){ c '33' "  [!] $1"; }
die(){  c '31' "  [x] $1"; exit 1; }

sha_ok(){ [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ]; }

get_pinned(){
  local url="$1" dest="$2" expect="$3" label="$4"
  if [ -f "$dest" ] && sha_ok "$dest" "$expect"; then ok "$label 已存在且校验通过"; return 0; fi
  [ -f "$dest" ] && { warn "$label 本地文件校验不符，重新下载"; rm -f "$dest"; }
  echo "  [..] 下载 $label"; echo "       $url"
  if curl -fL --retry 3 --connect-timeout 15 --max-time 1800 -o "$dest.part" "$url"; then
    if sha_ok "$dest.part" "$expect"; then mv -f "$dest.part" "$dest"; ok "$label 校验通过"; return 0; fi
    rm -f "$dest.part"; die "$label sha256 不匹配（期望 $expect）"
  fi
  die "$label 下载失败"
}

cat <<BANNER

============================================================
 妙妙屋X 白盒鉴权脆弱性测试 · 一键运行
 固定版本 : $PINNED_VER
 构件来源 : 本交付仓库 Release (whitebox-audit-v1.0)
 工作目录 : $WORKDIR
 面板端口 : $PORT
============================================================

BANNER

for t in curl unzip python3; do
  command -v "$t" >/dev/null || die "缺少依赖: $t（请先安装）"
done
command -v upx >/dev/null || warn "未检测到 upx（脚本内部需要它来准备测试副本；Debian/Ubuntu: apt install upx-ucl）"

# ── 1/3 测试工具包 ─────────────────────────────────────────────────────────
head_ '1/3  取得测试工具包（本交付仓库 Release）'
mkdir -p "$WORKDIR"
PKG="$WORKDIR/$PACK_NAME"
get_pinned "$REL_BASE/$PACK_NAME" "$PKG" "$PACK_SHA256" '测试工具包'
RUN="$WORKDIR/case"
rm -rf "$RUN"; mkdir -p "$RUN"
unzip -q "$PKG" -d "$RUN"
PKGROOT="$(find "$RUN" -maxdepth 2 -name '使用说明.txt' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || PKGROOT="$(find "$RUN" -maxdepth 2 -name 'README.md' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || die '包结构异常：未找到 README.md / 使用说明.txt'
ok "已展开到 $PKGROOT"

# ── 2/3 固定版本主程序（由包内 deploy/fetch.sh 按 lock 文件取件并校验）──────
head_ "2/3  取得妙妙屋X $PINNED_VER 主程序（本交付仓库 Release + sha256 校验）"
cd "$PKGROOT/toolkit"
if [ -f deploy/fetch.sh ]; then
  BIN="$(bash -c 'source deploy/fetch.sh; fetch_asset linux_amd64')"
  ok "主程序就绪: $BIN"
else
  warn '包内缺少 deploy/fetch.sh，退回直接下载'
  BIN="$PKGROOT/toolkit/artifacts/mmwx-v0.5.4-linux-amd64"
  mkdir -p "$(dirname "$BIN")"
  get_pinned "$REL_BASE/mmwx-v0.5.4-linux-amd64" "$BIN" \
    'ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657' '主程序'
fi

# ── 3/3 执行白盒鉴权测试 ───────────────────────────────────────────────────
head_ '3/3  执行白盒鉴权测试'
[ -f 'run.sh' ] || die '包结构异常：未找到 toolkit/run.sh'
cat <<TIP
  接下来会：
    · 使用刚校验过的 $PINNED_VER 主程序准备测试副本
    · 在端口 $PORT 启动测试实例
  启动后浏览器打开  http://127.0.0.1:$PORT/
    首次进入是初始化向导 → 创建管理员 → 登录
    然后到「系统设置 → 许可证」对照档位与数量上限
  停止：Ctrl+C

  对照基线（未处理）：档位显示试用、高级主题不生效、到上限后被拦回
  测试之后          ：档位显示专业版、高级主题生效、可继续添加用户与服务器

TIP
exec bash 'run.sh'
