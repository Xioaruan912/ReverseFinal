#!/bin/bash
T=/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit
mkdir -p "$T/reports/screens"
cp -f /root/mmwx/pw/out/*.png "$T/reports/reports/evidence/" 2>/dev/null
ls -la "$T/reports" "$T/reports/screens" | head -30
