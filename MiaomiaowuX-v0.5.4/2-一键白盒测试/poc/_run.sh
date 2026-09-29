#!/bin/bash
SRC=/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/poc
cd /root/mmwx/pw
cp -f $SRC/*.js /root/mmwx/pw/ 2>/dev/null
export PATH=/root/.nvm/versions/node/v22.23.2/bin:$PATH
node "$(basename "$1")" "${@:2}"
