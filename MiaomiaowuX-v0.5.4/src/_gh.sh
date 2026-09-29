#!/bin/bash
cd /root/mmwx/unpacked
python3 /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/scripts/namehunt.py | tr -d '\000' | head -70
echo "=== installing gdb ==="
apt-get install -y -qq gdb >/dev/null 2>&1 && which gdb || echo "gdb install failed"
