#!/bin/bash
PID=$(pgrep -x mmwx | head -1)
echo "PID=$PID"
cd /root/mmwx/unpacked
python3 /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/scripts/strloc.py "$PID"
