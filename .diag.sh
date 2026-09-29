B=/opt/mmwx-labtest/mmwx
echo "=== 部署产物 ==="
echo "  size : $(stat -c%s $B)"
echo "  sha256: $(sha256sum $B | cut -c1-64)"
echo
echo "=== 补丁点字节 ==="
for va in 0x17b4180 0x13b4180 0x2acb6a0 0x26cb6a0; do :; done
python3 - <<'PY'
d=open('/opt/mmwx-labtest/mmwx','rb').read()
for name,off,exp in [('HasFeature',0x13b4180,'b001c3'),
                     ('HasFeatureForDataPlane',0x13b44a0,'b001c3'),
                     ('QuotaEnforced',0x13b3180,'31c0c3'),
                     ('wFeRoafTxm',0x26cb6a0,'31c031db31c9c3')]:
    got=d[off:off+len(exp)//2].hex()
    print('  %-24s off=0x%x  %-22s 期望 %s  %s' % (name,off,got,exp,'OK' if got==exp else '**不符**'))
print('  ELF magic:', d[:4])
print('  UPX 残留:', d[:0x1000].find(b'UPX!') if b'UPX!' in d[:0x1000] else 'none')
PY
echo
echo "=== 手动前台运行 ==="
cd /opt/mmwx-labtest && timeout 12 env PORT=12899 MMWX_LISTEN_PORT=12899 MMWX_DATA_DIR=/opt/mmwx-labtest/data ./mmwx 2>&1 | tail -12 || echo "  (退出码 $?)"
