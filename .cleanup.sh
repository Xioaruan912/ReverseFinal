set -e
echo "=== 清理前 ==="
du -sh /root/mmwx 2>/dev/null | sed 's/^/  WSL: /'

echo "=== 1) WSL 审计工作区 ==="
rm -rf /root/mmwx
echo "  rm -rf /root/mmwx"

echo "=== 2) 交付仓内的解包副本与转储 ==="
D=/mnt/c/Users/Administrator/Desktop/Reverse_OK
rm -rf "$D/HexHub-5.1.9/toolkit/samples"
rm -rf "$D/HexHub-5.1.9/toolkit/exports"
rm -rf "$D/Listary/dump" "$D/Listary/tmp"
rm -rf "$D/MiaomiaowuX-v0.5.4/toolkit/artifacts" "$D/MiaomiaowuX-v0.5.4/toolkit/run-test"
find "$D" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$D" -name "*.pyc" -delete 2>/dev/null || true
echo "  已清理：toolkit/samples(464M) toolkit/exports(464M) Listary/{dump,tmp} 及 __pycache__"

echo "=== 3) Windows 临时工作目录 ==="
rm -rf "$TEMP"/hexhub-lab "$TEMP"/hexhub-lab-smoke "$TEMP"/listary-lab "$TEMP"/mmwx-lab 2>/dev/null || true
ls -d "$TEMP"/hexhub-lab* "$TEMP"/listary-lab* 2>/dev/null || echo "  (已清空)"

echo "=== 4) 下载暂存区 ==="
rm -rf /mnt/c/Users/Administrator/Downloads/_release
rm -f /mnt/c/Users/Administrator/Downloads/HexHub-Client-windows-amd64-installer-5.1.9.exe 2>/dev/null || true
echo "  已删除 Downloads/_release 与 Downloads 下的安装包副本"

echo "=== 清理后 ==="
du -sh /root 2>/dev/null | sed 's/^/  /root: /'
du -sh "$D" 2>/dev/null | sed 's/^/  Reverse_OK: /'
