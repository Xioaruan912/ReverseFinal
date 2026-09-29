pkill -f rogue_license.py 2>/dev/null
sleep 0.5
: > /root/mmwx/rogue/requests.log
ROGUE_MODE="${1:-echo}" nohup python3 /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/poc/rogue_license.py > /root/mmwx/rogue/server.out 2>&1 &
sleep 2
echo "--- listening ---"
ss -ltnp 2>/dev/null | grep ':443' || echo "not listening"
echo "--- local probe ---"
curl -sk https://127.0.0.1:443/api/v1/activate -d '{}' ; echo
