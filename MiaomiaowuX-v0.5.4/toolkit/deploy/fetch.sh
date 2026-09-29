#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 妙妙屋X 许可与配额测试 —— 受控构件获取器
#
#   resolve 顺序（严格，绝不访问上游 latest）：
#     1) 本地已有构件           ./artifacts/<asset>
#     2) 本仓库 Release 固定件   versions.lock.json 中的 base_url
#     3) 显式指定的 MMWX_MIRROR  https://<mirror>/<asset>
#   任一来源取到后，一律用 versions.lock.json 里的 sha256 校验；不匹配即中止。
#
#   用法:  source deploy/fetch.sh ; fetch_asset <key>
#          key = linux_amd64 | windows_amd64 | checksums | guard_manifest | docker_offline_tar
# ---------------------------------------------------------------------------
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"
LOCK="$DEPLOY_DIR/versions.lock.json"
ART_DIR="${MMWX_ARTIFACTS:-$ROOT_DIR/artifacts}"

_lock() { python3 -c "
import json,sys
d=json.load(open('$LOCK'))
k=sys.argv[1]
if k=='docker_offline_tar':
    v=d['docker']['offline_tar']; print(v['asset'], v['sha256']); raise SystemExit
v=d['native'][k]; print(v['asset'], v['sha256'])
" "$1"; }

_base_url() { python3 -c "import json;print(json.load(open('$LOCK'))['source']['base_url'])"; }

sha_ok() { # file expected
  local got; got=$(sha256sum "$1" | awk '{print $1}')
  [ "$got" = "$2" ]
}

fetch_asset() {
  local key="$1" asset expect dest
  read -r asset expect < <(_lock "$key")
  dest="$ART_DIR/$asset"
  mkdir -p "$ART_DIR"

  if [ -f "$dest" ] && sha_ok "$dest" "$expect"; then
    echo "[=] 本地构件命中: $dest" >&2; printf '%s\n' "$dest"; return 0
  fi
  [ -f "$dest" ] && { echo "[!] 本地构件校验失败，重新获取: $dest" >&2; rm -f "$dest"; }

  local urls=()
  urls+=("$(_base_url)/$asset")
  if [ -n "${MMWX_MIRROR:-}" ]; then urls+=("${MMWX_MIRROR%/}/$asset"); fi

  for u in "${urls[@]}"; do
    echo "[*] 下载: $u" >&2
    if curl -fL --retry 3 --connect-timeout 15 --max-time 1800 -o "$dest.part" "$u"; then
      if sha_ok "$dest.part" "$expect"; then
        mv -f "$dest.part" "$dest"
        echo "[+] 校验通过: $asset" >&2
        printf '%s\n' "$dest"; return 0
      fi
      echo "[x] sha256 不匹配，丢弃: $u" >&2
      rm -f "$dest.part"
    else
      echo "[!] 下载失败，尝试下一个源" >&2
    fi
  done

  echo "[x] 无法取得构件 $asset（本地 / Release / 镜像均失败）" >&2
  echo "    可手动放入: $dest  并确保 sha256=$expect" >&2
  return 1
}
