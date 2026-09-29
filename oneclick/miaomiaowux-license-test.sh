#!/usr/bin/env bash
# ============================================================================
# 妙妙屋X (miaomiaowuX) v0.5.4 - 一键安装 · 持久化部署
#
#   用法（Linux / WSL）:
#     bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
#
#   行为（纯安装器：只产出可运行的目标，不生成 md / 报告 / 证据目录）:
#     · 告知构件来自 GitHub，中国大陆可能较慢，给出镜像 / 手动放置两条备选
#     · 询问安装目录（回车用默认 /opt/mmwx），并做可写性校验
#     · 取固定版本 v0.5.4 主程序，强制校验 sha256
#     · 安装到 <安装目录>，注册 systemd 服务 + 开机自启
#     · 下载缓存与临时文件自动清理，安装目录长期保留
#
#   环境变量:
#     MMWX_INSTALLDIR=/opt/mmwx  安装目录（程序 + data/）
#     MMWX_YES=1                 非交互，全部用默认值
#     MMWX_MIRROR=<url>          自建镜像前缀（GitHub 慢时用）
#     PORT=12889                 面板端口
#     MMWX_NO_SERVICE=1          只安装不注册服务
#
#   固定版本 : miaomiaowuX v0.5.4
#   构件来源 : github.com/Xioaruan912/ReverseFinal  release whitebox-audit-v1.0
# ============================================================================
set -euo pipefail

REL_BASE="https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0"
BIN_NAME="mmwx-v0.5.4-linux-amd64"
BIN_SHA256="ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657"
PINNED_VER="v0.5.4"
SERVICE="mmwx"

PORT="${PORT:-12889}"
AUTO="${MMWX_YES:-0}"
NO_SERVICE="${MMWX_NO_SERVICE:-0}"
DEFAULT_INSTALL="${MMWX_INSTALLDIR:-/opt/mmwx}"

WORKDIR="$(mktemp -d /tmp/mmwx-install.XXXXXX)"
cleanup(){ rm -rf "$WORKDIR"; }
trap cleanup EXIT

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
head_(){ echo; c '36' "=== $1 ==="; }
ok(){   c '32' "  [+] $1"; }
warn(){ c '33' "  [!] $1"; }
die(){  c '31' "  [x] $1"; exit 1; }

sha_ok(){ [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ]; }

# ── 交互：提示一律走 stderr，且只在真交互终端下提问 ──────────────────────────
# 两个坑都在这里：
#  1) 本函数会被 $( ) 捕获：提示若写 stdout，提示文字会被当成返回值拼进目录名；
#  2) [ -r /dev/tty ] 在管道/非交互执行时同样成立，read 会永久阻塞（卡死）。
#     因此判定交互性必须看「是否真有终端」，并用 read -t 兜底。
is_tty(){
  [ "${AUTO:-0}" = "1" ] && return 1
  [ -t 0 ] && return 0
  [ -t 2 ] && [ -c /dev/tty ] && return 0
  return 1
}

ask(){
  local label="$1" default="$2" v=""
  if ! is_tty; then printf '%s' "$default"; return 0; fi
  {
    printf '[37m%s[0m
' "$label"
    printf '[90m    default [%s][0m
' "$default"
    printf '[90m    input (Enter = default): [0m'
  } >&2
  # 最多等 300 秒；无输入 / 超时 / 无终端 -> 用默认值
  read -r -t 300 v </dev/tty 2>/dev/null || v=""
  v="$(printf '%s' "$v" | tr -d '' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
  [ -z "$v" ] && v="$default"
  printf '%s' "$v"
}

# ── 目录询问 + 可写性校验，非法则重问 ──────────────────────────────────────
ask_dir(){
  local label="$1" default="$2" v
  while :; do
    v="$(ask "$label" "$default")"
    case "$v" in /*) ;; *) warn "请填写绝对路径（以 / 开头）: $v"; continue ;; esac
    if mkdir -p "$v" 2>/dev/null && [ -w "$v" ] && touch "$v/.mmwx-wtest" 2>/dev/null; then
      rm -f "$v/.mmwx-wtest"; printf '%s' "$v"; return 0
    fi
    warn "目录不存在或不可写: $v"
    [ "$AUTO" = "1" ] && die "默认安装目录不可写: $v"
  done
}

cat <<BANNER

============================================================
 妙妙屋X (miaomiaowuX) $PINNED_VER
 一键安装 · 持久化部署（systemd 常驻 + 开机自启）
============================================================

BANNER
c '33' ' [!] 构件从 GitHub 下载，中国大陆网络可能较慢（主程序约 35 MB）。'
c '33' '     若下载困难，可任选其一：'
c '90' "       - 自建镜像：  MMWX_MIRROR=https://your-mirror/mmwx 重跑"
c '90' "       - 先手动下载 $BIN_NAME 放进 <安装目录>/artifacts/ 后重跑"
if ! is_tty; then
  c '90' ' (非交互执行：全部使用默认值；想自选目录请设置 MMWX_INSTALLDIR)'
fi

echo
INSTALL_DIR="$(ask_dir '选择安装目录（程序与数据都放这里，长期保留）' "$DEFAULT_INSTALL")"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
ok "安装目录: $INSTALL_DIR"

for t in curl sha256sum; do command -v "$t" >/dev/null || die "缺少依赖: $t"; done
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

# ── 脱壳 + 打补丁 ───────────────────────────────────────────────────────────
prepare_binary(){
  local src="$1" out="$2"
  cp -f "$src" "$out"
  upx -d -qq "$out" >/dev/null 2>&1 || true
  # 关键：必须用 printf 的「格式串」写法，不能写成 printf '%s' 或 '%b' ——
  # 只有格式串会解释 \xHH 十六进制转义（与 toolkit/run.sh 保持一致）
  local p
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

head_ "取得主程序 $PINNED_VER"
mkdir -p "$INSTALL_DIR/artifacts" "$WORKDIR/artifacts"
# 复用已手动放置的构件
if [ -f "$INSTALL_DIR/artifacts/$BIN_NAME" ]; then
  BIN="$INSTALL_DIR/artifacts/$BIN_NAME"
else
  BIN="$WORKDIR/artifacts/$BIN_NAME"
fi
get_pinned "$REL_BASE/$BIN_NAME" "$BIN" "$BIN_SHA256" '主程序'
install -m 0644 "$BIN" "$INSTALL_DIR/artifacts/$BIN_NAME" 2>/dev/null || true

head_ '安装'
PREP="$(prepare_binary "$BIN" "$WORKDIR/mmwx-prepared")"
install -m 0755 "$PREP" "$INSTALL_DIR/mmwx"
mkdir -p "$INSTALL_DIR/data"
ok "程序已安装: $INSTALL_DIR/mmwx"

# ── 服务：先清理旧 unit，保证幂等（也能治愈历史坏 unit） ────────────────────
if [ "$NO_SERVICE" = "1" ]; then
  warn 'MMWX_NO_SERVICE=1 -> 跳过服务注册'
elif command -v systemctl >/dev/null 2>&1 && systemctl show >/dev/null 2>&1; then
  systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/$SERVICE.service"

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
  if systemctl is-active --quiet "$SERVICE"; then
    ok "systemd 服务已注册并启动：$SERVICE.service（已开启开机自启）"
  else
    warn "服务未能active，最近日志："
    journalctl -u "$SERVICE" -n 10 --no-pager 2>/dev/null | sed 's/^/      /' || true
    die "启动失败。可执行文件或路径可能有问题：$INSTALL_DIR/mmwx"
  fi
  echo
  echo "  管理命令："
  echo "    查看状态 : systemctl status $SERVICE"
  echo "    重启     : systemctl restart $SERVICE"
  echo "    停止     : systemctl stop $SERVICE"
  echo "    取消自启 : systemctl disable $SERVICE"
  echo "    实时日志 : journalctl -u $SERVICE -f"
  echo "    卸载     : systemctl disable --now $SERVICE && rm -f /etc/systemd/system/$SERVICE.service && rm -rf $INSTALL_DIR"
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
[ -f "$INSTALL_DIR/mmwx.pid" ] && kill "\$(cat $INSTALL_DIR/mmwx.pid)" 2>/dev/null || pkill -f "$INSTALL_DIR/mmwx"
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

echo
echo "============================================================"
echo " 安装完成（持久化）"
echo "============================================================"
echo " 面板地址 : http://<本机IP>:$PORT/"
echo " 安装目录 : $INSTALL_DIR   （程序 + data/，长期保留）"
echo " 固定版本 : miaomiaowuX $PINNED_VER"
