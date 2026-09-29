#!/bin/bash
cd /root/mmwx/unpacked
python3 /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/scripts/"$1" "${@:2}"
