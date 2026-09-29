#!/bin/bash
# ============================================================================
# 妙妙屋X (miaomiaowuX) v0.5.4 —— 白盒鉴权「全归零」一键测试（版本固定 · 自控源）
#
#   普通「一条命令跑通」入口；被测程序一律锁定 v0.5.4，绝不使用 releases/latest。
#   构件来源顺序： 本地 ./artifacts/ → 本仓库 Release 固定件 → MMWX_MIRROR
#   取到后强制 sha256 校验，不匹配立即中止。
#
#   只想部署、不打补丁： 见 deploy/deploy-native.sh / deploy/deploy-docker.sh
# ============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

LOCK_SHA="ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657"
ASSET="mmwx-v0.5.4-linux-amd64"
RELEASE_BASE="https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0"
ART_DIR="${MMWX_ARTIFACTS:-$ROOT/artifacts}"
SRC="$ART_DIR/$ASSET"
mkdir -p "$ART_DIR"

sha_ok(){ [ "$(sha256sum "$1" | awk '{print $1}')" = "$LOCK_SHA" ]; }

# ---- 1) 取构件（本地 → 本仓库 Release → 镜像），逐级校验 ----
if [ -f "$SRC" ] && sha_ok "$SRC"; then
  echo "[=] 使用本地构件: $SRC"
else
  got=0
  for u in "$RELEASE_BASE/$ASSET" "${MMWX_MIRROR:+${MMWX_MIRROR%/}/$ASSET}"; do
    [ -z "$u" ] && continue
    echo "[*] 下载: $u"
    if curl -fL --retry 3 --connect-timeout 15 --max-time 1800 -o "$SRC.part" "$u"; then
      if sha_ok "$SRC.part"; then mv -f "$SRC.part" "$SRC"; got=1; break; fi
      echo "[x] sha256 不匹配，丢弃"; rm -f "$SRC.part"
    fi
  done
  if [ "$got" != "1" ]; then
    echo "[x] 无法取得 $ASSET（本地/Release/镜像均失败）"
    echo "    已锁定的 sha256: $LOCK_SHA"
    echo "    请手动放入: $SRC"
    exit 1
  fi
  echo "[+] 校验通过 ($LOCK_SHA)"
fi

# ---- 2) 解包并打补丁（补丁明细见 mmwx-crack.py / 本目录 README） ----
WORK="$ROOT/run-test"
mkdir -p "$WORK"
cp -f "$SRC" "$WORK/mmwx-packed"
cd "$WORK"
cp -f mmwx-packed mmwx-tested 2>/dev/null || true
upx -d -qq mmwx-tested >/dev/null 2>&1 || true

p(){ printf "$2" | dd of=mmwx-tested bs=1 seek=$(( $1 )) conv=notrunc status=none; }
p 0x13b4180 '\xb0\x01\xc3'                                     # 专业版能力总开关
p 0x13b44a0 '\xb0\x01\xc3'                                     # 数据面能力
p 0x13b3180 '\x31\xc0\xc3'                                     # 配额强制开关
p 0x13b3a20 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'     # 用户配额
p 0x13b3280 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'     # 服务器配额
p 0x13b37c0 '\x48\xb8\xff\xff\xff\xff\xff\xff\xff\x7f\xc3'     # 节点配额
p 0x26cb6a0 '\x31\xc0\x31\xdb\x31\xc9\xc3'                     # 用户配额判定
p 0x273a2e0 '\xb9\x01\x00\x00\x00\xc3'                         # 节点配额判定
p 0x9c3a80  '\x31\xc0\x31\xdb\x31\xc9\xc3'                     # 已用用户数
p 0x83e760  '\x31\xc0\x31\xdb\x31\xc9\xc3'                     # 已用节点数
p 0x245aa89 '\x90\x90'                                         # 服务器配额判定
chmod +x mmwx-tested

PORT="${PORT:-12889}"
echo "[+] 测试副本: $WORK/mmwx-tested"
echo "[+] 启动端口: $PORT"
cd "$WORK" && PORT="$PORT" MMWX_LISTEN_PORT="$PORT" MMWX_DATA_DIR="$WORK/data" ./mmwx-tested
