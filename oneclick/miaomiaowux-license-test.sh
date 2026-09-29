#!/usr/bin/env bash
# ============================================================================
# 妙妙屋X (miaomiaowuX) v0.5.4 —— 一键取件 · 运行 · 部署
#
#   用法（Linux / WSL）:
#     bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
#
#   两种运行方式（脚本会询问，也可用环境变量跳过）:
#     1) 测试模式 —— 临时启动，停止后自动清理中间产物
#     2) 生产模式 —— 安装到指定目录 + 注册 systemd 服务 + 开机自启，不清清理
#
#   环境变量:
#     MMWX_MODE=test|persist     运行方式
#     MMWX_WORKDIR=~             测试模式的工作目录
#     MMWX_INSTALLDIR=/opt/mmwx  生产模式的安装目录
#     MMWX_EVIDENCE=~            证据留存目录
#     MMWX_YES=1                 非交互，全部用默认值
#     MMWX_KEEP_FILES=1          测试模式也不清理中间产物
#     MMWX_MIRROR=<url>          自建镜像前缀（GitHub 慢时用）
#     PORT=12889                 面板端口
#
#   固定版本 : miaomiaowuX v0.5.4
#   构件来源 : github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0
# ============================================================================
set -euo pipefail

REL_BASE="https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0"
PACK_NAME="miaomiaowuX-whitebox-audit-pack-v1.0.zip"
PACK_SHA256="44f79bc3ecf70e972dcf646b8f5ad396c6e5d786f1a805aeff138204368e24ab"
BIN_NAME="mmwx-v0.5.4-linux-amd64"
BIN_SHA256="ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657"
PINNED_VER="v0.5.4"
CASE_NAME="MiaomiaowuX-v0.5.4"
SERVICE="mmwx"

PORT="${PORT:-12889}"
AUTO="${MMWX_YES:-0}"
KEEP="${MMWX_KEEP_FILES:-0}"
MODE="${MMWX_MODE:-}"
DEFAULT_WORK="${MMWX_WORKDIR:-$HOME/ReverseAudit/miaomiaowuX}"
DEFAULT_INSTALL="${MMWX_INSTALLDIR:-/opt/mmwx}"
EVID_ROOT="${MMWX_EVIDENCE:-$HOME/ReverseAudit-Evidence}"
STAMP="$(date +%Y%m%d-%H%M%S)"

WORKDIR=""; INSTALL_DIR=""; EVID_DIR=""

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
head_(){ echo; c '36' "=== $1 ==="; }
ok(){   c '32' "  [+] $1"; }
warn(){ c '33' "  [!] $1"; }
die(){  c '31' "  [x] $1"; exit 1; }

sha_ok(){ [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ]; }

ask(){
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

cat <<BANNER

============================================================
 妙妙屋X (miaomiaowuX) $PINNED_VER
 固定版本 · 构件来自本仓库 Release
============================================================

BANNER
c '33' ' [!] 构件从 GitHub 下载，中国大陆网络可能较慢（主程序约 35 MB）。'
c '33' '     若下载困难，可任选其一：'
c '90' "       - 自建镜像：  MMWX_MIRROR=https://your-mirror/mmwx 重跑"
c '90' "       - 先手动下载 $BIN_NAME 放进 <工作目录>/artifacts/ 后重跑"

if [ -z "$MODE" ]; then
  echo
  cat <<TIP
 请选择运行方式：
   1) 测试模式（默认）—— 临时启动，停止后自动清理中间产物
   2) 生产模式（持久化）—— 安装到指定目录 + 注册 systemd 服务 + 开机自启，不清理
TIP
  MODE="$(ask '输入 1 或 2' '1')"
  case "$MODE" in
    2|persist|prod|production) MODE="persist" ;;
    *) MODE="test" ;;
  esac
fi

echo
if [ "$MODE" = "persist" ]; then
  INSTALL_DIR="$(ask '选择安装目录（程序与数据都放这里，长期保留）' "$DEFAULT_INSTALL")"
  mkdir -p "$INSTALL_DIR"
  INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
  WORKDIR="$(mktemp -d /tmp/mmwx-deploy.XXXXXX)"
  ok "安装目录: $INSTALL_DIR"
else
  WORKDIR="$(ask '选择工作目录（下载件与测试副本放这里，停止后自动清理）' "$DEFAULT_WORK")"
  mkdir -p "$WORKDIR"
  WORKDIR="$(cd "$WORKDIR" && pwd)"
  ok "工作目录: $WORKDIR"
  c '90' '  提示：若打算长期使用，请重跑并选择「2) 生产模式」，中间产物不会被清理。'
fi

for t in curl unzip python3; do command -v "$t" >/dev/null || die "缺少依赖: $t（请先安装）"; done
command -v upx >/dev/null || warn '未检测到 upx（准备可执行文件时需要；Debian/Ubuntu: apt install upx-ucl）'

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

# ── 脱壳 + 打补丁，产物路径输出到 stdout ────────────────────────────────────
prepare_binary(){
  local src="$1" out="$2"
  cp -f "$src" "$out"
  upx -d -qq "$out" >/dev/null 2>&1 || true
  local p
  # 关键：必须用 printf 的「格式串」写法，不能写成 printf '%s' 或 '%b' ——
  # 只有格式串会解释反斜杠 x 十六进制转义（与 toolkit/run.sh 保持一致）
  p(){ printf "$2" | dd of="$out" bs=1 seek=$(( $1 )) conv=notrunc status=none; }
  p 0x13b4180 '\xb0\x01\xc3'
  p 0x13b44a0 '\xb0\x01\xc3'
  p 0x13b3180 '\x31\xc0\xc3'
  p 0x13b3a20 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'
  p 0x13b3280 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'
  p 0x13b37c0 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'
  p 0x26cb6a0 '\x31\xc0\x31\xdb\x31\xc9\xc3'
  p 0x273a2e0 '\xb9\x01\x00\x00\x00\xc3'
  p 0x9c3a80  '\x31\xc0\x31\xdb\x31\xc9\xc3'
  p 0x83e760  '\x31\xc0\x31\xdb\x31\xc9\xc3'
  p 0x245aa89 '\x90\x90'
  chmod 0755 "$out"
  printf '%s' "$out"
}

save_evidence(){
  [ -d "$WORKDIR/case" ] || return 0
  mkdir -p "$EVID_DIR" 2>/dev/null || return 0
  local src="$WORKDIR/case/$CASE_NAME/reports"
  [ -d "$src" ] && cp -r "$src" "$EVID_DIR/" 2>/dev/null || true
}

cleanup_test(){
  local rc=$?
  echo
  head_ 'cleanup'
  if [ "$KEEP" = "1" ]; then
    warn "MMWX_KEEP_FILES=1 -> 中间产物保留在 $WORKDIR"
  else
    save_evidence; [ -d "$EVID_DIR" ] && ok "证据与报告已留存: $EVID_DIR"
    rm -rf "$WORKDIR/artifacts" "$WORKDIR/$PACK_NAME" "$WORKDIR/case"
    [ -z "$(ls -A "$WORKDIR" 2>/dev/null)" ] && rmdir "$WORKDIR" 2>/dev/null || true
    if [ -e "$WORKDIR/case" ]; then warn "部分中间产物未能删除: $WORKDIR"; else ok "中间产物已清理"; fi
  fi
  echo; echo "============================================================"; echo " done"; echo "============================================================"
  [ -d "$EVID_DIR" ] && echo " evidence : $EVID_DIR"
  echo " pinned   : miaomiaowuX $PINNED_VER"
  exit $rc
}

# ── 取件 ────────────────────────────────────────────────────────────────────
head_ '1/2  取得构件（本仓库 Release + sha256 校验）'
PKG="$WORKDIR/$PACK_NAME"
get_pinned "$REL_BASE/$PACK_NAME" "$PKG" "$PACK_SHA256" '测试工具包'
RUN="$WORKDIR/case"
rm -rf "$RUN"; mkdir -p "$RUN"
unzip -q "$PKG" -d "$RUN"
PKGROOT="$(find "$RUN" -maxdepth 2 -name '使用说明.txt' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || PKGROOT="$(find "$RUN" -maxdepth 2 -name 'README.md' -printf '%h\n' | head -1)"
[ -n "$PKGROOT" ] || die '包结构异常：未找到 README.md / 使用说明.txt'
ok "已展开到 $PKGROOT"

head_ "2/2  取得主程序 $PINNED_VER"
mkdir -p "$WORKDIR/artifacts"
BIN="$WORKDIR/artifacts/$BIN_NAME"
get_pinned "$REL_BASE/$BIN_NAME" "$BIN" "$BIN_SHA256" '主程序'

# ============================================================================
# 生产模式：安装 + 注册服务 + 开机自启（不清理）
# ============================================================================
if [ "$MODE" = "persist" ]; then
  head_ '部署（生产模式）'
  PREP="$(prepare_binary "$BIN" "$WORKDIR/mmwx-tested")"
  install -m 0755 "$PREP" "$INSTALL_DIR/mmwx"
  mkdir -p "$INSTALL_DIR/data"
  ok "程序已安装: $INSTALL_DIR/mmwx"

  EVID_DIR="$EVID_ROOT/$CASE_NAME/$STAMP"
  save_evidence; [ -d "$EVID_DIR" ] && ok "证据与报告已留存: $EVID_DIR"

  if command -v systemctl >/dev/null 2>&1 && systemctl show >/dev/null 2>&1; then
    cat > "/etc/systemd/system/$SERVICE.service" <<UNIT
[Unit]
Description=MiaomiaowuX $PINNED_VER
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment=PORT=$PORT
Environment=MMWX_LISTEN_PORT=$PORT
Environment=MMWX_DATA_DIR=$INSTALL_DIR/data
ExecStart=$INSTALL_DIR/mmwx
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now "$SERVICE" >/dev/null 2>&1
    sleep 4
    ok "systemd 服务已注册并启动：$SERVICE.service（已开启开机自启）"
    echo
    echo "  管理命令："
    echo "    查看状态 : systemctl status $SERVICE"
    echo "    重启     : systemctl restart $SERVICE"
    echo "    停止     : systemctl stop $SERVICE"
    echo "    取消自启 : systemctl disable $SERVICE"
    echo "    实时日志 : journalctl -u $SERVICE -f"
    echo "    卸载     : systemctl disable --now $SERVICE && rm -f /etc/systemd/system/$SERVICE.service"
  else
    warn '未检测到可用的 systemd（WSL 默认未启用），改用后台常驻脚本'
    cat > "$INSTALL_DIR/start.sh" <<START
#!/usr/bin/env bash
cd "$INSTALL_DIR"
PORT=$PORT MMWX_LISTEN_PORT=$PORT MMWX_DATA_DIR="$INSTALL_DIR/data" \\
  nohup "$INSTALL_DIR/mmwx" >> "$INSTALL_DIR/mmwx.log" 2>&1 &
echo \$! > "$INSTALL_DIR/mmwx.pid"
echo "started pid \$(cat "$INSTALL_DIR/mmwx.pid")"
START
    cat > "$INSTALL_DIR/stop.sh" <<STOP
#!/usr/bin/env bash
[ -f "$INSTALL_DIR/mmwx.pid" ] && kill "\$(cat "$INSTALL_DIR/mmwx.pid")" 2>/dev/null || pkill -f "$INSTALL_DIR/mmwx"
rm -f "$INSTALL_DIR/mmwx.pid"
echo stopped
STOP
    chmod 0755 "$INSTALL_DIR/start.sh" "$INSTALL_DIR/stop.sh"
    bash "$INSTALL_DIR/start.sh" >/dev/null 2>&1 || true
    sleep 3
    ok "已后台启动"
    echo
    echo "  管理命令："
    echo "    启动 : bash $INSTALL_DIR/start.sh"
    echo "    停止 : bash $INSTALL_DIR/stop.sh"
    echo "    日志 : tail -f $INSTALL_DIR/mmwx.log"
    echo
    echo "  想开机自启：启用 WSL systemd 后重跑本脚本，或把 start.sh 加入 ~/.bashrc"
  fi

  rm -rf "$WORKDIR"
  echo
  echo "============================================================"
  echo " 部署完成（生产模式 · 中间产物已清理）"
  echo "============================================================"
  echo " 面板地址 : http://<本机IP>:$PORT/"
  echo " 安装目录 : $INSTALL_DIR   （程序 + data/，长期保留）"
  echo " 固定版本 : miaomiaowuX $PINNED_VER"
  [ -d "$EVID_DIR" ] && echo " 证据报告 : $EVID_DIR"
  exit 0
fi

# ============================================================================
# 测试模式：临时启动，停止后清理
# ============================================================================
trap cleanup_test EXIT INT TERM
EVID_DIR="$EVID_ROOT/$CASE_NAME/$STAMP"
head_ '启动实例（测试模式 · 停止后自动清理）'
cat <<TIP
  接下来会在端口 $PORT 启动实例。
  浏览器打开  http://127.0.0.1:$PORT/
    首次进入是初始化向导 → 创建管理员 → 登录
    然后到「系统设置 → 许可证」对照档位与数量上限
  按 Ctrl+C 停止；停止后证据先另存，再自动清理中间产物。

  若打算长期使用，请改用生产模式：
    MMWX_MODE=persist bash <(本脚本地址)
TIP
cd "$PKGROOT/toolkit"
[ -f run.sh ] || die '包结构异常：未找到 toolkit/run.sh'
MMWX_ARTIFACTS="$WORKDIR/artifacts" PORT="$PORT" bash run.sh
