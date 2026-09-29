#!/bin/bash
echo "===== FINAL STATE ====="
echo "[service]"
curl -s -o /dev/null -w "  http://127.0.0.1:12889/  -> HTTP %{http_code}\n" http://127.0.0.1:12889/
pgrep -a mmwx | head -3
echo "[hosts]"
grep -c miaomiaowux /etc/hosts || true
echo "[rogue ca]"
ls /usr/local/share/ca-certificates/ 2>/dev/null
echo "[rogue server]"
pgrep -af rogue_license.py || echo "  not running"
echo "[db license rows]"
python3 - <<'PY'
import sqlite3
c=sqlite3.connect('file:/root/mmwx/run/data/mmwx.db?mode=ro',uri=True)
rows=list(c.execute("select key,substr(value,1,80) from system_settings where key like 'license%'"))
print("  ", rows if rows else "(none - clean)")
PY
echo "[artifacts]"
T=/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit
find "$T" -maxdepth 2 -type f | sed "s#^$T/##" | sort | head -40
