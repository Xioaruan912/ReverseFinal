#!/usr/bin/env python3
"""Search every method body for `call/callvirt/newobj/ldfld ... <token>` hits.

Usage: python tokscan.py <assembly> <token-hex> [token-hex ...]
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil

path = sys.argv[1]
toks = [int(t, 16) for t in sys.argv[2:]]
data = open(path, 'rb').read()
md = peil.MD(data)

# name lookup for MethodDef / MemberRef
md_names = {}
for rid, t, m, rva, sig in peil.method_rows(md):
    md_names[0x06000000 | rid] = t + '::' + m
mr_names = {}
try:
    import dnfile
    _pe = dnfile.dnPE(path)
    for i, r in enumerate(_pe.net.mdtables.MemberRef.rows):
        mr_names[0x0A000000 | (i + 1)] = str(r.Name)
except Exception:
    pass

OPS = {0x28: 'call', 0x6F: 'callvirt', 0x73: 'newobj', 0x7B: 'ldfld', 0x7E: 'ldsfld',
       0x7C: 'ldflda', 0x80: 'stsfld', 0x7D: 'stfld', 0x72: 'ldstr', 0x8C: 'box',
       0xD0: 'ldtoken', 0x74: 'castclass', 0x75: 'isinst', 0x27: 'jmp'}

found = {}
for rid, t, m, rva, sig in peil.method_rows(md):
    if not rva:
        continue
    o = peil.rva2off(md.secs, rva)
    if o is None:
        continue
    try:
        co, cs, hdr = peil.il_body(data, o)
    except Exception:
        continue
    body = data[co:co + cs]
    for tok in toks:
        pat = struct.pack('<I', tok)
        i = body.find(pat)
        while i >= 0:
            op = body[i - 1] if i > 0 else 0
            if op in OPS:
                found.setdefault(tok, []).append((t + '::' + m, i - 1, OPS[op]))
            i = body.find(pat, i + 1)

for tok in toks:
    nm = md_names.get(tok) or mr_names.get(tok) or '?'
    print('=== %#010x  %s ===' % (tok, nm))
    for caller, off, op in found.get(tok, []):
        print('   %-8s @IL_%04x  <- %s' % (op, off, caller))
    if tok not in found:
        print('   (no references)')
