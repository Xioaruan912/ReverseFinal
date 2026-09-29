#!/bin/bash
cd /root/mmwx/pw
export PATH=/root/.nvm/versions/node/v22.23.2/bin:$PATH
R=/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/reports
node poc_pro_bypass.js > "$R/poc_pro_bypass_output.txt" 2>&1
echo "exit=$?"
ls -la "$R"
