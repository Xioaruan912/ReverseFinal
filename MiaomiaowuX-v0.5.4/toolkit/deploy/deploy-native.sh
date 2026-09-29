#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 妙妙屋X 许可与配额测试 —— 本机（命令）部署 · 版本固定 · 全自控
#
#   与官方 install.sh 的区别：
#     · 不使用 releases/latest，只认 versions.lock.json 里锁定的 v0.5.4
#     · 构件来源：本地 artifacts/ → 本仓库 Release → 自建镜像（MMWX_MIRROR）
#     · 下载后强制 sha256 校验，不匹配即中止，绝不安装未经验证的二进制
#     · 不使用 systemd / 不改系统配置，数据目录可控、可一键清理
#
#   用法:
#     bash deploy/deploy-native.sh                 # 默认端口 12889
#     PORT=12889 DATA_DIR=/opt/mmwx-lab/data bash deploy/deploy-native.sh
#     MMWX_MIRROR=https://your-mirror/mmwx bash deploy/deploy-native.sh
# ---------------------------------------------------------------------------
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"
source "$DEPLOY_DIR/fetch.sh"

PORT="${PORT:-12889}"
DATA_DIR="${DATA_DIR:-$ROOT_DIR/run/data}"
BIN_DIR="${BIN_DIR:-$ROOT_DIR/run}"
LOG="$BIN_DIR/mmwx.log"

echo "=============================================="
echo " 妙妙屋X 许可与配额测试 · 本机部署（版本锁定）"
echo " 版本: v0.5.4   端口: $PORT"
echo " 数据: $DATA_DIR"
echo "=============================================="

BIN="$(fetch_asset linux_amd64)"
mkdir -p "$BIN_DIR" "$DATA_DIR"
install -m 0755 "$BIN" "$BIN_DIR/mmwx-v0.5.4"

# 记录锁定信息，便于事后复核
python3 - "$BIN_DIR/mmwx-v0.5.4" > "$BIN_DIR/DEPLOYED.txt" <<'PY'
import hashlib,sys,json,datetime
p=sys.argv[1]
h=hashlib.sha256(open(p,'rb').read()).hexdigest()
print("product        : miaomiaowuX")
print("pinned_version : v0.5.4")
print("binary         : %s"%p)
print("sha256         : %s"%h)
print("deployed_at    : %s"%datetime.datetime.now().isoformat(timespec='seconds'))
PY
cat "$BIN_DIR/DEPLOYED.txt"

pkill -f "$BIN_DIR/mmwx-v0.5.4" 2>/dev/null || true
sleep 1
cd "$BIN_DIR"
PORT="$PORT" MMWX_LISTEN_PORT="$PORT" MMWX_DATA_DIR="$DATA_DIR" \
  nohup ./mmwx-v0.5.4 > "$LOG" 2>&1 &
echo "[*] 已启动，日志: $LOG"
sleep 6
tail -3 "$LOG" || true
echo
echo "[+] 面板地址: http://127.0.0.1:$PORT/"
echo "    首次进入为初始化向导；登录后到「系统设置 → 许可证」查看档位与数量上限。"
