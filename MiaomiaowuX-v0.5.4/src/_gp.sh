#!/bin/bash
echo "=== pDPNeDgo / wFeRoafTxm / FvrKQt2U / aQ1HCwcWO call sequences ==="
cd /root/mmwx/unpacked
for f in pDPNeDgo wFeRoafTxm FvrKQt2U sFUaa_mys; do
  python3 /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/scripts/callseq2.py "$f" 2>/dev/null | tr -d '\000' | head -22
done
