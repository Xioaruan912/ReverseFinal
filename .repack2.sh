set -e
D=/mnt/c/Users/Administrator/Desktop/Reverse_OK
OUT=/mnt/c/Users/Administrator/Downloads/_release
TMP=$OUT/_tmp_pack.zip
rm -f "$TMP" "$OUT/miaomiaowuX-whitebox-audit-pack-v1.0.zip"
cd "$D"
zip -qr "$TMP" "MiaomiaowuX-v0.5.4" -x "*/artifacts/*" "*/run/*" "*/run-test/*" "*/__pycache__/*"
mv -f "$TMP" "$OUT/miaomiaowuX-whitebox-audit-pack-v1.0.zip"
Z="$OUT/miaomiaowuX-whitebox-audit-pack-v1.0.zip"
echo "  条目: $(unzip -l "$Z" | tail -1 | awk '{print $2}')  大小: $(stat -c%s "$Z")"
sha256sum "$Z"
echo "  --- 包内 .sh 行尾检查 ---"
mkdir -p /tmp/chk && rm -rf /tmp/chk/* && unzip -qo "$Z" -d /tmp/chk "*/2-一键白盒测试/一键白盒测试.sh"
S=$(find /tmp/chk -name '一键白盒测试.sh' | head -1)
if grep -qU $'\r' "$S"; then echo "   ✗ 仍为 CRLF"; else echo "   ✓ LF"; fi
