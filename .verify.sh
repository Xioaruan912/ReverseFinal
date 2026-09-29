set -e
echo "=== 1) 三个一键入口 URL 可达性 ==="
for u in \
  https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 \
  https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 \
  https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh \
  https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 ; do
  printf "  %-58s " "$(basename $u)"
  curl -fsSL -o /dev/null -w "HTTP %{http_code}  %{size_download} B\n" "$u"
done
echo
echo "=== 2) Release 资产可达性（抽查）==="
B=https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0
for f in miaomiaowuX-whitebox-audit-pack-v1.0.zip mmwx-v0.5.4-linux-amd64 SHA256SUMS.txt; do
  printf "  %-46s " "$f"
  curl -fsSLI -o /dev/null -w "HTTP %{http_code}  %{size_download}\n" "$B/$f" 2>/dev/null || echo "FAIL"
done
echo
echo "=== 3) 妙妙屋一键端到端实测 ==="
export PORT=12896 WORKDIR=/root/mmwx/ok-test
rm -rf $WORKDIR
nohup bash -c "PORT=12896 WORKDIR=$WORKDIR bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh) > /tmp/ok.log 2>&1" &
sleep 50
grep -E "校验通过|已展开到|主程序就绪|\[x\]|\[!\]" /tmp/ok.log | sed 's/^/  /' | head -12
echo
printf "  面板: "; curl -s -o /dev/null -w "HTTP %{http_code}  " http://127.0.0.1:12896/ ; curl -s http://127.0.0.1:12896/ | grep -oE "var ps = '[a-z]+'"
pkill -f "mmwx-tested" 2>/dev/null || true
