import re
p = "exports/nsis_solid_stream.bin"
f = open(p, "rb")
buf = f.read(30 << 20)
print("bytes at 21690:", buf[21684:21708].hex(' '))
# Chromium pak magic: 05 00 00 00 01 00 00 00 or 05 00 00 00 00 00 00 00
for magic in [b'\x05\x00\x00\x00\x01\x00\x00\x00', b'\x05\x00\x00\x00\x00\x00\x00\x00']:
    pos = [m.start() for m in re.finditer(re.escape(magic), buf)]
    print(magic.hex(), "count", len(pos), pos[:10])
    if len(pos) > 1:
        print("  deltas:", [pos[i+1]-pos[i] for i in range(min(10, len(pos)-1))])
# where is hexhub-backend.exe's MZ? expected 21690+37916036 = 37937726
print("expected HexHub.exe   @", 21690+35904128, "->", buf[21690+35904128:21690+35904128+2])
print("expected backend.exe  @", 21690+37916036, "->", buf[21690+37916036:21690+37916036+2])
print("expected libcef.dll   @", 21690+167499810)
print("expected rg.exe       @", 21690+481307690 if 21690+481307690 < len(buf) else "beyond")
# find all MZ in first 30MB
pos = [m.start() for m in re.finditer(b'MZ', buf)]
print("MZ positions first 20:", pos[:20])
