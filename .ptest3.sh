set -e
rm -rf /opt/mmwx-labtest
echo "=== 生产模式重测（修正 %b 后）==="
MMWX_MODE=persist MMWX_YES=1 MMWX_INSTALLDIR=/opt/mmwx-labtest PORT=12889 \
  bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh) 2>&1 \
  | grep -vE "^ *%|Dload|--:--|^\s*[0-9]+\s+[0-9.]+[kM]?\s" | tail -8
echo
echo "=== 服务与面板 ==="
echo "  enabled: $(systemctl is-enabled mmwx 2>&1)"
echo "  active : $(systemctl is-active mmwx 2>&1)"
systemctl status mmwx --no-pager 2>&1 | sed -n '1,5p' | sed 's/^/  /'
printf "  面板 HTTP: "; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:12889/
printf "  VIP 标志 : "; curl -s http://127.0.0.1:12889/ | grep -oE "var ps = '[a-z]+'" || echo "(无)"
