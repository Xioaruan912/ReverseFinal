echo "=== 服务崩溃原因（journal）==="
journalctl -u mmwx --no-pager -n 25 2>&1 | tail -20 | sed 's/^/  /'
