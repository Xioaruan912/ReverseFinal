import struct

d = open("exports/nsis_solid_stream.bin", "rb").read()
hdr = d[:21690]

STR_BASE = 14484
STR_END = 21690


def read_str(off):
    """off = offset in characters from STR_BASE"""
    p = STR_BASE + off * 2
    if p < 0 or p >= len(hdr):
        return None
    end = p
    while end + 1 < len(hdr) and hdr[end:end+2] != b'\x00\x00':
        end += 2
    try:
        return hdr[p:end].decode('utf-16le')
    except Exception:
        return None


TABLE_START = 0xAC0
REC = 28
N = (STR_BASE - TABLE_START) // REC
print("records:", N)

recs = []
for i in range(N):
    o = TABLE_START + i * REC
    f = struct.unpack_from('<7I', hdr, o)
    recs.append((o, f))

prev = -1
for i, (o, f) in enumerate(recs):
    nameoff = f[2]
    off = f[3]
    nm = read_str(nameoff)
    flag = f[1]
    mark = "" if off >= prev else "  <<< DECREASE"
    if off < prev:
        mark = "  <<< DECREASE"
    prev = max(prev, off)
    print(f"{i:4d} @{o:#07x} f0={f[0]:<12} f1={f[1]:#010x} nameoff={nameoff:6d} off={off:12d} name={nm!r}{mark}")
