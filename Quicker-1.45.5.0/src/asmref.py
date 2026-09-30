#!/usr/bin/env python3
"""Resolve which assembly the licence accessors actually live in.

Answers two questions for Quicker.exe:
  1. Does its AssemblyRef table reference Quicker.Common?
  2. Which assembly does MemberRef 0x0A002FBE (get_MemberLevel) resolve to?
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil

path = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Administrator\Desktop\Quicker-1.45.5.0\Quicker.exe'
data = open(path, 'rb').read()
md = peil.MD(data)
s, b = md.str_size, md.blob_size

def coded_size(tables, bits):
    return 4 if (max(md.rows.get(t, 0) for t in tables) << bits) >= 0x10000 else 2

TDOR = (0x02, 0x01, 0x1B)          # TypeDefOrRef
RS = (0x00, 0x1A, 0x23, 0x01)      # ResolutionScope

def rd(t, i):
    o = md.toff(t) + i * md.rsize(t)
    return md.tbl[o:o + md.rsize(t)]

def u(buf, o, size):
    return struct.unpack_from('<I' if size == 4 else '<H', buf, o)[0]

# ---- AssemblyRef ----
print('=== AssemblyRef table ===')
n = md.rows.get(0x23, 0)
found = []
for i in range(n):
    o = md.toff(0x23) + i * md.rsize(0x23)
    p = o + 12                      # 4x u16 version + u32 flags
    pk = u(md.tbl, p, b); p += b
    nm = md.str_at(u(md.tbl, p, s)); p += s
    cu = md.str_at(u(md.tbl, p, s))
    found.append(nm)
    if 'Quicker' in nm or 'Common' in nm:
        print('   >>> %s' % nm)
print('   total refs: %d ; any Quicker.* : %s' % (n, [x for x in found if 'Quicker' in x] or 'NONE'))

# ---- TypeRef ----
def typeref(idx):
    o = md.toff(0x01) + (idx - 1) * md.rsize(0x01)
    cs = coded_size(RS, 2)
    scope = u(md.tbl, o, cs)
    nm = md.str_at(u(md.tbl, o + cs, s))
    ns = md.str_at(u(md.tbl, o + cs + s, s))
    return scope, ns, nm

def scope_name(scope):
    kind = scope & 3
    rid = scope >> 2
    if kind == 2:                       # AssemblyRef
        o = md.toff(0x23) + (rid - 1) * md.rsize(0x23)
        p = o + 12 + b
        return 'AssemblyRef:' + md.str_at(u(md.tbl, p, s))
    return 'scope-kind%d rid=%d' % (kind, rid)

# ---- MemberRef ----
def memberref(idx):
    o = md.toff(0x0A) + (idx - 1) * md.rsize(0x0A)
    cs = coded_size(TDOR, 3)
    cls = u(md.tbl, o, cs)
    nm = md.str_at(u(md.tbl, o + cs, s))
    return cls, nm

print()
print('=== MemberRef resolution ===')
for tok, label in [(0x0A002FBE, 'get_MemberLevel'), (0x0A002FBD, 'get_MemberExpireTimeUtc')]:
    rid = tok & 0xFFFFFF
    if rid > md.rows.get(0x0A, 0):
        print('   %s token %#x -> rid %d out of range (%d rows)' % (label, tok, rid, md.rows.get(0x0A, 0)))
        continue
    cls, nm = memberref(rid)
    kind = cls & 3
    trid = cls >> 2
    scope, ns, tname = typeref(trid)
    print('   %-24s rid=%-6d member=%-28s type=%s.%s  owner=%s'
          % (label, rid, nm, ns, tname, scope_name(scope)))

print()
print('=== does Quicker.exe itself define Quicker.Common.Vm.Account.* ? ===')
hits = []
for i in range(md.rows.get(0x02, 0)):
    r = rd(0x02, i)
    nm = md.str_at(u(r, 4, s))
    ns = md.str_at(u(r, 4 + s, s))
    if ns.startswith('Quicker.Common.Vm.Account'):
        hits.append(ns + '.' + nm)
print('   typedefs: %s' % (hits or 'NONE'))

print()
print('=== assemblies that DO define the licence DTO ===')
for cand in ['Quicker.Common.dll', 'Quicker.Public.dll', 'Quicker.3rd.dll']:
    p2 = os.path.join(os.path.dirname(path), cand)
    if not os.path.exists(p2):
        print('   %-22s (missing)' % cand); continue
    d2 = open(p2, 'rb').read(); m2 = peil.MD(d2)
    s2 = m2.str_size
    names = []
    for i in range(m2.rows.get(0x02, 0)):
        r = rd(0x02, i)
        nm = m2.str_at(u(r, 4, s2))
        ns = m2.str_at(u(r, 4 + s2, s2))
        if nm in ('UserInfo', 'UserLimitation') and ns.startswith('Quicker.Common.Vm.Account'):
            names.append(ns + '.' + nm)
    print('   %-22s %s' % (cand, names or 'no account DTO'))
