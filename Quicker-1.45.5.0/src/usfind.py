#!/usr/bin/env python3
"""Find which method produces a UI string, then show what it reads.

Usage: python usfind.py <assembly> <utf-16 substring>
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil

path = sys.argv[1]
needle = sys.argv[2].encode('utf-16-le')
data = open(path, 'rb').read()
md = peil.MD(data)

us_off, us_size = md.streams['#US']
us = md.base[us_off:us_off + us_size]

hits = []
start = 0
while True:
    i = us.find(needle, start)
    if i < 0:
        break
    # walk back to the string start (US entries: compressed length then UTF-16, NUL-terminated)
    b = i
    while b - 2 >= 0 and us[b - 2] != 0:
        b -= 2
    s = b
    e = i + len(needle)
    while e + 1 < len(us) and us[e] != 0:
        e += 2
    try:
        txt = us[s:e].decode('utf-16-le', 'replace')
    except Exception:
        txt = '?'
    hits.append((i, txt))
    start = i + 2

print('=== #US entries containing %r ===' % sys.argv[2])
for off, txt in hits[:12]:
    tok = 0x70000000 | off
    print('   us_off=%#08x  token=%#010x  %r' % (off, tok, txt[:70]))
if not hits:
    sys.exit(1)

toks = set(0x70000000 | off for off, _ in hits)
print()
print('=== methods that ldstr any of these ===')
rows = list(peil.method_rows(md))
for rid, t, m, rva, sig in rows:
    if not rva:
        continue
    o = peil.rva2off(md.secs, rva)
    if o is None:
        continue
    co, cs, hdr = peil.il_body(data, o)
    body = data[co:co + cs]
    for tok in toks:
        pat = b'\x72' + struct.pack('<I', tok)
        if pat in body:
            print('   %s::%s   rid=%d  rva=%#x  file=%#x' % (t, m, rid, rva, o))
            break
