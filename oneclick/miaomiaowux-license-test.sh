#!/usr/bin/env bash
# ============================================================================
# 妙妙屋X (miaomiaowuX) · 白盒鉴权脆弱性测试 —— 一键运行
#
#   用法（Linux / WSL）:
#     bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
#
#   行为:
#     · 询问安装/工作目录（可自定义）
#     · 从本交付仓库 Release 拉取固定版本构件并校验 sha256
#     · 测试实例停止后，自动清理中间产物（证据与报告先另存）
#
#   环境变量（可跳过交互）:
#     MMWX_WORKDIR=~                      安装/工作目录
#     MMWX_EVIDENCE=~                    证据留存目录
#     MMWX_YES=1                          非交互，全部用默认值
#     MMWX_KEEP_FILES=1                   不清理中间产物
#     MMWX_MIRROR=<url>                   自建镜像前缀（Download 慢时用）
#     PORT=12889                          面板端口
#
#   固定版本 : miaomiaowuX v0.5.4
#   构件来源 : github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0
# ============================================================================
set -euo pipefail

REL_BASE="https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0"
PACK_NAME="miaomiaowuX-whitebox-audit-pack-v1.0.zip"
PACK_SHA256="c4f5402373ad17278958ec8dd7c4333490d886d4412190f5cef05fef0025ba6e"
PINNED_VER="v0.5.4"
CASE_NAME="MiaomiaowuX-v0.5.4"

PORT="${PORT:-12889}"
AUTO="${MMWX_YES:-0}"
KEEP="${MMWX_KEEP_FILES:-0}"
DEFAULT_WORK="${MMWX_WORKDIR:-$HOME/ReverseAudit/miaomiaowuX}"
EVID_ROOT="${MMWX_EVIDENCE:-$HOME/ReverseAudit-Evidence}"
STAMP="$(date +%Y%m%d-%H%M%S)"

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
head_(){ echo; c '36' "=== $1 ==="; }
ok(){   c '32' "  [+] $1"; }
warn(){ c '33' "  [!] $1"; }
die(){  c '31' "  [x] $1"; exit 1; }

sha_ok(){ [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ]; }

# ── 交互式询问目录 ──────────────────────────────────────────────────────────
ask_dir(){
  local label="$1" default="$2" v=""
  if [ "$AUTO" = "1" ]; then printf '%s' "$default"; return 0; fi
  if [ -t 0 ] || [ -r /dev/tty ]; then
    printf '%s\n    default [%s]\n    input (Enter = default): ' "$label" "$default"
    read -r v </dev/tty 2>/dev/null || v=""
  fi
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
  [ -z "$v" ] && v="$default"
  printf '%s' "$v"
}

# ── 横幅 + GitHub 慢速提示 ─────────────────────────────────────────────────
cat <<BANNER

============================================================
 妙妙屋X 白盒鉴权脆弱性测试 · 一键运行
 固定版本 : $PINNED_VER
 构件来源 : GitHub（本仓库 Release）
============================================================

BANNER
c '33' ' [!] 构件从 GitHub 下载，中国大陆网络可能较慢（主程序约 35 MB）。'
c '33' '     若下载困难，可任选其一：'
c '90' "       - 自建镜像：  MMWX_MIRROR=https://your-mirror/mmwx 重跑"
c '90' "       - 先手动下载 mmwx-v0.5.4-linux-amd64 放进 <工作目录>/artifacts/ 后重跑"

# ── 询问目录 ────────────────────────────────────────────────────────────────
echo
WORKDIR="$(ask_dir '选择安装/工作目录' "$DEFAULT_WORK")"
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
ok "工作目录: $WORKDIR"
[ "$KEEP" = "1" ] && warn 'MMWX_KEEP_FILES=1 - 中间产物将保留'

EVID_DIR="$EVID_ROOT/$CASE_NAME/$STAMP"

for t in curl unzip python3; do
  command -v "$t" >/dev/null || die "缺少依赖: $t（请先安装）"
done
command -v upx >/dev/null || warn '未检测到 upx（准备测试副本时需要；Debian/Ubuntu: apt install upx-ucl）'

get_pinned(){
  local url="$1" dest="$2" expect="$3" label="$4"
  if [ -f "$dest" ] && sha_ok "$dest" "$expect"; then ok "$label 已存在且校验通过"; return 0; fi
  [ -f "$dest" ] && { warn "$label 本地文件校验不符，重新下载"; rm -f "$dest"; }
  echo "  [..] 下载 $label"; echo "       $url"
  local urls=("$url")
  [ -n "${MMWX_MIRROR:-}" ] && urls+=("${MMWX_MIRROR%/}/$(basename "$url")")
  for u in "${urls[@]}"; do
    if curl -fL --retry 3 --connect-timeout 15 --max-time 1800 -o "$dest.part" "$u"; then
      if sha_ok "$dest.part" "$expect"; then mv -f "$dest.part" "$dest"; ok "$label 校验通过"; return 0; fi
      warn "sha256 不匹配: $u"; rm -f "$dest.part"
    fi
  done
  die "$label 下载失败或校验不通过（期望 $expect）"
}

# ── 退出时自动清理中间产物（证据已先另存）──────────────────────────────────
cleanup(){
  local rc=$?
  echo
  head_ 'cleanup'
  if [ -d "$WORKDIR/case" ] && [ "$KEEP" != "1" ]; then
    mkdir -p "$EVID_DIR" 2>/dev/null || true
    # 先留存证据与报告
    for d in reports; do
      [ -d "$WORKDIR/case/$CASE_NAME/$d" ] && cp -r "$WORKDIR/case/$CASE_NAME/$d" "$EVID_DIR/" 2>/dev/null || true
    done
    [ -d "$EVID_DIR" ] && ok "证据与报告已留存: $EVID_DIR"
    # 再删中间产物
    rm -rf "$WORKDIR/artifacts" "$WORKDIR/$PACK_NAME" "$WORKDIR/case"
    if [ -z "$(ls -A "$WORKDIR" 2>/dev/null)" ]; then rmdir "$WORKDIR" 2>/dev/null || true; fi
    if [ -e "$WORKDIR/case" ]; then warn "部分中间产物未能删除: $WORKDIR"; else ok "中间产物已清理: $WORKDIR"; fi
  elif [ "$KEEP" = "1" ]; then
    warn "MMWX_KEEP_FILES=1 -> 中间产物保留在 $WORKDIR"
  fi
  echo
  echo "============================================================"
  echo " done"
  echo "============================================================"
  [ -d "$EVID_DIR" ] && echo " evidence : $EVID_DIR"
  echo " pinned   : miaomiaowuX $PINNED_VER"
  exit $rc
}
trap cleanup EXIT INT TERM

# ── 1/3 测试工具包 ─────────────────────────────────────────────────────────
head_ '1/3  取得测试工具包（本交付仓库 Release）'
PKG="$WORKDIR/$PACK_NAME"
get_pinned "$REL_BASE/$PACK_NAME" "$PKG" "$PACK_SHA256" '测试工具包'
RUN="$WORKDIR/case"
rm -rf "$RUN"; mkdir -p "$RUN"
unzip -q "$PKG" -d "$RUN"
PKGROOT="$(find "$RUN" -maxdepth 2 -name '使用说明.txt' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || PKGROOT="$(find "$RUN" -maxdepth 2 -name 'README.md' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || die '包结构异常：未找到 README.md / 使用说明.txt'
ok "已展开到 $PKGROOT"

# ── 2/3 固定版本主程序 ─────────────────────────────────────────────────────
head_ "2/3  取得妙妙屋X $PINNED_VER 主程序（sha256 强制校验）"
cd "$PKGROOT/toolkit"
if [ -f deploy/fetch.sh ]; then
  BIN="$(MMWX_MIRROR="${MMWX_MIRROR:-}" bash -c 'source deploy/fetch.sh; fetch_asset linux_amd64')"
  ok "主程序就绪: $BIN"
else
  warn '包内缺少 deploy/fetch.sh，退回直接下载'
  BIN="$(pwd)/artifacts/mmwx-v0.5.4-linux-amd64"
  mkdir -p "$(dirname "$BIN")"
  get_pinned "$REL_BASE/mmwx-v0.5.4-linux-amd64" "$BIN" \
    'ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657' '主程序'
fi

# ── 3/3 执行测试 ───────────────────────────────────────────────────────────
head_ '3/3  执行白盒鉴权测试'
[ -f run.sh ] || die '包结构异常：未找到 toolkit/run.sh'
cat <<TIP
  接下来会：
    · 使用刚校验过的 $PINNED_VER 主程序准备测试副本
    · 在端口 $PORT 启动测试实例
  启动后浏览器打开  http://127.0.0.1:$PORT/
    首次进入是初始化向导 → 创建管理员 → 登录
    然后到「系统设置 → 许可证」对照档位与数量上限
  停止服务后会自动清理中间产物（证据先另存）

TIP
PORT="$PORT" bash run.sh
