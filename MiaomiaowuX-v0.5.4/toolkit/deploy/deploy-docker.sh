#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 妙妙屋X 许可与配额测试 —— Docker 部署（版本固定 · 全自控）
#
#   --online   （默认）按 sha256 摘要拉取锁定镜像，再启动
#   --offline        使用本仓库 Release 里的镜像 tar.gz，docker load 后启动
#                    （完全离线、完全自控，不产生任何对上游/ghcr 的请求）
#
#   用法:
#     bash deploy/deploy-docker.sh --offline
#     PORT=12889 bash deploy/deploy-docker.sh
# ---------------------------------------------------------------------------
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"
source "$DEPLOY_DIR/fetch.sh"

MODE="online"
[ "${1:-}" = "--offline" ] && MODE="offline"

PORT="${PORT:-12889}"
LOCAL_TAG="miaomiaowux:v0.5.4"
PINNED_REF="$(python3 -c "import json;print(json.load(open('$DEPLOY_DIR/versions.lock.json'))['docker']['pinned_ref'])")"

echo "=============================================="
echo " 妙妙屋X 许可与配额测试 · Docker 部署（版本锁定）"
echo " 模式: $MODE   端口: $PORT"
echo "=============================================="

if [ "$MODE" = "offline" ]; then
  TGZ="$(fetch_asset docker_offline_tar)"
  echo "[*] 导入镜像: $TGZ"
  gzip -dc "$TGZ" | docker load
  # docker load 会带出原始 tag；统一再打一个本地固定 tag，避免依赖 ghcr 命名
  SRC_ID="$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk '/miaomiaowux/{print $2; exit}')"
  [ -n "$SRC_ID" ] && docker tag "$SRC_ID" "$LOCAL_TAG"
  IMAGE="$LOCAL_TAG"
  docker image inspect "$IMAGE" >/dev/null
  echo "[+] 已导入并固定为本地镜像: $IMAGE"
else
  echo "[*] 按摘要拉取: $PINNED_REF"
  docker pull "$PINNED_REF"
  IMAGE="$PINNED_REF"
fi

cd "$ROOT_DIR"
mkdir -p data subscribes rule_templates
pkill -f "container_name=mmwx-lab" 2>/dev/null || true
docker rm -f mmwx-lab 2>/dev/null || true

echo "[*] 启动容器 ..."
docker run -d --name mmwx-lab --restart unless-stopped \
  --network host \
  -e PORT="$PORT" -e LOG_LEVEL=info -e MMWX_DATABASE_DRIVER=sqlite \
  -v "$ROOT_DIR/data:/app/data" \
  -v "$ROOT_DIR/subscribes:/app/subscribes" \
  -v "$ROOT_DIR/rule_templates:/app/rule_templates" \
  -v /etc/localtime:/etc/localtime:ro \
  "$IMAGE" >/dev/null

sleep 8
docker ps --filter name=mmwx-lab --format '  {{.Names}}  {{.Image}}  {{.Status}}'
echo
echo "[+] 面板地址: http://127.0.0.1:$PORT/"
echo "    固定镜像: $IMAGE"
echo "    清理: docker rm -f mmwx-lab"
