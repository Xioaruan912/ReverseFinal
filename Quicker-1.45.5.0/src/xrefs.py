#!/usr/bin/env python3
"""Find callers of a method by token (MethodDef rid -> 0x06xxxxxx call token)."""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil as ilp

path = sys.argv[1]
names = sys.argv[2:]
data = open(path, 'rb').read()
md = ilp.MD(data)

# rid -> (type, name)
want = {}
for rid, t, m, rva, sig in ilp.method_rows(md):
    for n in names:
        if m == n or (t + '::' + m) == n:
            want[rid] = (t, m)
print('targets:', {k: v for k, v in want.items()})
tokens = {}
for rid, (t, m) in want.items():
    for tok in (0x06000000 | rid, 0x0a000000 | rid, 0x2b000000 | rid):
        tokens[tok] = '%s::%s' % (t, m)

for rid, t, m, rva, sig in ilp.method_rows(md):
    if not rva:
        continue
    off = ilp.rva2off(md.secs, rva)
    if off is None:
        continue
    co, cs, hdr = ilp.il_body(data, off)
    body = data[co:co+cs]
    for tok, tgt in tokens.items():
        pat = struct.pack('<I', tok)
        i = body.find(pat)
        while i >= 0:
            if (i - 1) % 1 == 0 and body[max(0, i-1)] in (0x28, 0x6f, 0x73, 0x7b, 0x7c, 0x7e, 0x8c, 0x8d):
                print('  caller %-58s @IL_%04x op=%02x -> %s' % (t + '::' + m, i-1, body[i-1], tgt))
                break
            i = body.find(pat, i+1)
