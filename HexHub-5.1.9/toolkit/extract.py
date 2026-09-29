import struct, os, shutil, sys, glob, base64, lzma

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)

STREAM = "exports/nsis_solid_stream.bin"
OUT = "samples/extracted"
DATA_BASE = 21698
TABLE_START = 0xAC0
REC = 28
STR_BASE = 14484

# ---- 自动定位目标安装包（支持放在包目录 / 上级 / Downloads / 参数指定）----
def find_installer():
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        return os.path.abspath(sys.argv[1])
    pats = ["HexHub-Client-windows-amd64-installer-*.exe",
            "HexHub*installer*.exe", "HexHub*.exe"]
    roots = [ROOT, os.path.dirname(ROOT),
             os.path.join(os.path.expanduser("~"), "Downloads"),
             os.path.join(os.path.expanduser("~"), "Desktop")]
    for r in roots:
        for p in pats:
            hits = sorted(glob.glob(os.path.join(r, p)))
            if hits:
                return hits[0]
    return None


# ---- 若解压流不存在，则从安装包现场解出（免 7-Zip / 免安装）----
def build_stream():
    inst = find_installer()
    if not inst:
        sys.exit("[x] 未找到 HexHub 安装包。用法: python extract.py <安装包路径>")
    print(f"[*] 安装包: {inst}")
    d = open(inst, "rb").read()
    sig = d.find(b"\xef\xbe\xad\xdeNullsoftInst")
    if sig < 0:
        sys.exit("[x] 不是 NSIS 安装包（未找到 NullsoftInst 签名）")
    hdr_off = sig + 16
    # firstheader (28 bytes, 7 dwords): flags siginfo nsinst[3] len_header len_data
    base_struct = sig - 4
    flags, siginfo, n1, n2, n3, len_header, len_data = struct.unpack_from("<7I", d, base_struct)
    print(f"[*] firstheader @{base_struct:#x} flags={flags:#x} siginfo={siginfo:#x} "
          f"len_header={len_header} len_data={len_data}")
    # 签名(16B) + len_header(4B) + len_data(4B) 之后才是 LZMA props
    comp_start = sig + 16 + 8
    props = d[comp_start:comp_start + 5]
    dict_size = struct.unpack_from("<I", props, 1)[0]
    print(f"[*] LZMA props={props.hex()} dict={dict_size:#x} header={len_header}")
    f = [{"id": lzma.FILTER_LZMA1, "dict_size": dict_size, "lc": 3, "lp": 0, "pb": 2}]
    dec = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=f)
    src = d[comp_start + 5:]
    os.makedirs(os.path.dirname(STREAM) or ".", exist_ok=True)
    total = 0
    with open(STREAM, "wb") as o:
        CH = 1 << 20
        pos = 0
        while pos < len(src):
            try:
                r = dec.decompress(src[pos:pos + CH])
            except Exception as e:
                print(f"[!] 解压中断于 {pos}: {e}"); break
            if r:
                o.write(r); total += len(r)
            pos += CH
            if dec.eof:
                break
    print(f"[+] 解压流 {total} bytes -> {STREAM}")


if not os.path.isfile(STREAM):
    build_stream()

f = open(STREAM, "rb")
hdr = f.read(21690)


def read_str(off):
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


N = (STR_BASE - TABLE_START) // REC
files = []
for i in range(N):
    o = TABLE_START + i * REC
    fl = struct.unpack_from('<7I', hdr, o)
    if fl[1] == 0x05000090:
        files.append({"name": read_str(fl[2]), "nameoff": fl[2], "off": fl[3], "i": i})
# drop temp/plugin entries (control chars) -> they live in $PLUGINSDIR
files = [e for e in files if e["name"] and all(0x20 <= ord(c) < 0x7f or ord(c) > 0x7f for c in e["name"])]

total = os.path.getsize(STREAM) - DATA_BASE
files.sort(key=lambda x: x["off"])
for i, e in enumerate(files):
    j = i + 1
    while j < len(files) and files[j]["off"] == e["off"]:
        j += 1
    nxt = files[j]["off"] if j < len(files) else total
    e["size"] = nxt - e["off"]

print("files:", len(files), "total", total, "sum", sum(e['size'] for e in files))
print("dups:", [e['name'] for e in files if e['size'] == 0])

ROOT_FILES = {'chrome_100_percent.pak', 'chrome_200_percent.pak', 'resources.pak'}
RES_FILES = {'tray.ico'}

def guess_dir(name):
    if name in ROOT_FILES:
        return ""
    if name in RES_FILES:
        return "res"
    if name.endswith('.pak'):
        return "locales"
    return ""

if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT, exist_ok=True)

# de-duplicate identical offsets: first entry keeps data, others copy it
written = {}
for e in files:
    d = guess_dir(e["name"])
    sub = os.path.join(OUT, d) if d else OUT
    os.makedirs(sub, exist_ok=True)
    p = os.path.join(sub, e["name"])
    if e["off"] in written:
        shutil.copy2(written[e["off"]], p)
        e['size'] = 0
        print(f"DUP  {os.path.relpath(p, OUT)}  <- {os.path.basename(written[e['off']])}")
        continue
    f.seek(DATA_BASE + e["off"])
    with open(p, "wb") as o:
        o.write(f.read(e["size"]))
    written[e["off"]] = p
    print(f"{e['off']:>12} {e['size']:>12}  {os.path.relpath(p, OUT)}")
print("done")
