#!/usr/bin/env python3
"""Minimal but complete-enough CIL disassembler (no external deps).

Usage:
  python ild.py <assembly> <Type::Method | Type::Method*> [--bytes]
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil as ilp

# opcode -> (name, operand_encoding)
# encoding: '' none, 'i1','u1','i4','u4','i8','r4','r8','tok','br1','br4','switch'
S = {}
def d(code, name, enc=''):
    S[code] = (name, enc)

d(0x00,'nop'); d(0x01,'break'); d(0x02,'ldarg.0'); d(0x03,'ldarg.1'); d(0x04,'ldarg.2'); d(0x05,'ldarg.3')
d(0x06,'ldloc.0'); d(0x07,'ldloc.1'); d(0x08,'ldloc.2'); d(0x09,'ldloc.3')
d(0x0a,'stloc.0'); d(0x0b,'stloc.1'); d(0x0c,'stloc.2'); d(0x0d,'stloc.3')
d(0x0e,'ldarg.s','u1'); d(0x0f,'ldarga.s','u1'); d(0x10,'starg.s','u1')
d(0x11,'ldloc.s','u1'); d(0x12,'ldloca.s','u1'); d(0x13,'stloc.s','u1')
d(0x14,'ldnull'); d(0x15,'ldc.i4.m1'); d(0x16,'ldc.i4.0'); d(0x17,'ldc.i4.1'); d(0x18,'ldc.i4.2')
d(0x19,'ldc.i4.3'); d(0x1a,'ldc.i4.4'); d(0x1b,'ldc.i4.5'); d(0x1c,'ldc.i4.6'); d(0x1d,'ldc.i4.7'); d(0x1e,'ldc.i4.8')
d(0x1f,'ldc.i4','i4'); d(0x20,'ldc.i4','i4'); d(0x21,'ldc.i8','i8'); d(0x22,'ldc.r4','r4'); d(0x23,'ldc.r8','r8')
d(0x25,'dup'); d(0x26,'pop'); d(0x27,'jmp','tok'); d(0x28,'call','tok'); d(0x29,'calli','tok')
d(0x2a,'ret'); d(0x2b,'br.s','br1'); d(0x2c,'brfalse.s','br1'); d(0x2d,'brtrue.s','br1')
d(0x2e,'beq.s','br1'); d(0x2f,'bge.s','br1'); d(0x30,'bgt.s','br1'); d(0x31,'ble.s','br1'); d(0x32,'blt.s','br1')
d(0x33,'bne.un.s','br1'); d(0x34,'bge.un.s','br1'); d(0x35,'bgt.un.s','br1'); d(0x36,'ble.un.s','br1'); d(0x37,'blt.un.s','br1')
d(0x38,'br','br4'); d(0x39,'brfalse','br4'); d(0x3a,'brtrue','br4'); d(0x3b,'beq','br4'); d(0x3c,'bge','br4')
d(0x3d,'bgt','br4'); d(0x3e,'ble','br4'); d(0x3f,'blt','br4'); d(0x40,'bne.un','br4'); d(0x41,'bge.un','br4')
d(0x42,'bgt.un','br4'); d(0x43,'ble.un','br4'); d(0x44,'blt.un','br4'); d(0x45,'switch','switch')
d(0x46,'ldind.i1'); d(0x47,'ldind.u1'); d(0x48,'ldind.i2'); d(0x49,'ldind.u2'); d(0x4a,'ldind.i4')
d(0x4b,'ldind.u4'); d(0x4c,'ldind.i8'); d(0x4d,'ldind.i'); d(0x4e,'ldind.r4'); d(0x4f,'ldind.r8'); d(0x50,'ldind.ref')
d(0x51,'stind.ref'); d(0x52,'stind.i1'); d(0x53,'stind.i2'); d(0x54,'stind.i4'); d(0x55,'stind.i8'); d(0x56,'stind.r4'); d(0x57,'stind.r8')
d(0x58,'add'); d(0x59,'sub'); d(0x5a,'mul'); d(0x5b,'div'); d(0x5c,'div.un'); d(0x5d,'rem'); d(0x5e,'rem.un')
d(0x5f,'and'); d(0x60,'or'); d(0x61,'xor'); d(0x62,'shl'); d(0x63,'shr'); d(0x64,'shr.un')
d(0x65,'neg'); d(0x66,'not'); d(0x67,'conv.i1'); d(0x68,'conv.i2'); d(0x69,'conv.i4'); d(0x6a,'conv.i8')
d(0x6b,'conv.r4'); d(0x6c,'conv.r8'); d(0x6d,'conv.u4'); d(0x6e,'conv.u8'); d(0x6f,'callvirt','tok')
d(0x70,'cpobj','tok'); d(0x71,'ldobj','tok'); d(0x72,'ldstr','tok'); d(0x73,'newobj','tok'); d(0x74,'castclass','tok')
d(0x75,'isinst','tok'); d(0x76,'conv.r.un'); d(0x79,'unbox','tok'); d(0x7a,'throw')
d(0x7b,'ldfld','tok'); d(0x7c,'ldflda','tok'); d(0x7d,'stfld','tok'); d(0x7e,'ldsfld','tok'); d(0x7f,'ldsflda','tok')
d(0x80,'stsfld','tok'); d(0x81,'stobj','tok'); d(0x82,'conv.ovf.i1.un'); d(0x83,'conv.ovf.i2.un'); d(0x84,'conv.ovf.i4.un')
d(0x85,'conv.ovf.i8.un'); d(0x86,'conv.ovf.u1.un'); d(0x87,'conv.ovf.u2.un'); d(0x88,'conv.ovf.u4.un'); d(0x89,'conv.ovf.u8.un')
d(0x8a,'conv.ovf.i.un'); d(0x8b,'conv.ovf.u.un'); d(0x8c,'box','tok'); d(0x8d,'newarr','tok'); d(0x8e,'ldlen')
d(0x8f,'ldelema','tok'); d(0x90,'ldelem.i1'); d(0x91,'ldelem.u1'); d(0x92,'ldelem.i2'); d(0x93,'ldelem.u2')
d(0x94,'ldelem.i4'); d(0x95,'ldelem.u4'); d(0x96,'ldelem.i8'); d(0x97,'ldelem.i'); d(0x98,'ldelem.r4'); d(0x99,'ldelem.r8')
d(0x9a,'ldelem.ref'); d(0x9b,'stelem.i'); d(0x9c,'stelem.i1'); d(0x9d,'stelem.i2'); d(0x9e,'stelem.i4'); d(0x9f,'stelem.i8')
d(0xa0,'stelem.r4'); d(0xa1,'stelem.r8'); d(0xa2,'stelem.ref'); d(0xa3,'ldelem','tok'); d(0xa4,'stelem','tok')
d(0xa5,'unbox.any','tok')
for c, n in [(0xb3,'conv.ovf.i1'),(0xb4,'conv.ovf.u1'),(0xb5,'conv.ovf.i2'),(0xb6,'conv.ovf.u2'),(0xb7,'conv.ovf.i4'),
             (0xb8,'conv.ovf.u4'),(0xb9,'conv.ovf.i8'),(0xba,'conv.ovf.u8'),(0xc2,'refanyval'),(0xc3,'ckfinite'),
             (0xc6,'mkrefany'),(0xd0,'ldtoken'),(0xd1,'conv.u2'),(0xd2,'conv.u1'),(0xd3,'conv.i'),(0xd4,'conv.ovf.i'),
             (0xd5,'conv.ovf.u'),(0xd6,'add.ovf'),(0xd7,'add.ovf.un'),(0xd8,'mul.ovf'),(0xd9,'mul.ovf.un'),
             (0xda,'sub.ovf'),(0xdb,'sub.ovf.un'),(0xdc,'endfinally'),(0xdd,'leave'),(0xde,'leave.s'),
             (0xdf,'stind.i'),(0xe0,'conv.u')]:
    d(c, n, 'br4' if n == 'leave' else ('br1' if n == 'leave.s' else ('tok' if n in ('refanyval','mkrefany','ldtoken') else '')))
for c, n in [(0x8c,'box'),(0x71,'ldobj'),(0x70,'cpobj'),(0x81,'stobj')]:
    pass
d(0xc2,'refanyval','tok'); d(0xc6,'mkrefany','tok'); d(0xd0,'ldtoken','tok')

FE = {
 0x00:'arglist',0x01:'ceq',0x02:'cgt',0x03:'cgt.un',0x04:'clt',0x05:'clt.un',0x06:'ldftn',0x07:'ldvirtftn',
 0x09:'ldarg',0x0a:'ldarga',0x0b:'starg',0x0c:'ldloc',0x0d:'ldloca',0x0e:'stloc',0x0f:'localloc',
 0x11:'endfilter',0x12:'unaligned.',0x13:'volatile.',0x14:'tail.',0x15:'initobj',0x16:'constrained.',
 0x17:'cpblk',0x18:'initblk',0x19:'no.',0x1a:'rethrow',0x1c:'sizeof',0x1d:'refanytype',0x1e:'readonly.',
}
FE_TOK = {0x06,0x07,0x15,0x16,0x1c}
FE_S1 = {0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x12,0x13,0x14,0x19}

def decode(data, base, size):
    out = []
    p = base
    end = base + size
    while p < end:
        off = p - base
        b = data[p]; p += 1
        if b == 0xfe:
            b2 = data[p]; p += 1
            nm = FE.get(b2, 'fe%02x' % b2)
            if b2 in FE_TOK:
                tok = struct.unpack_from('<I', data, p)[0]; p += 4
                out.append((off, nm, '%#010x' % tok)); continue
            if b2 in FE_S1:
                v = data[p]; p += 1
                out.append((off, nm, str(v))); continue
            if b2 in (0x12,0x13,0x14,0x19):
                out.append((off, nm, str(data[p]))); p += 1; continue
            out.append((off, nm, '')); continue
        if b not in S:
            out.append((off, 'op_%02x' % b, '??')); continue
        nm, enc = S[b]
        if enc == '':
            out.append((off, nm, ''))
        elif enc == 'u1':
            out.append((off, nm, str(data[p]))); p += 1
        elif enc == 'i1':
            out.append((off, nm, str(struct.unpack_from('<b', data, p)[0]))); p += 1
        elif enc == 'u4' or enc == 'tok':
            out.append((off, nm, '%#010x' % struct.unpack_from('<I', data, p)[0])); p += 4
        elif enc == 'i4':
            out.append((off, nm, str(struct.unpack_from('<i', data, p)[0]))); p += 4
        elif enc == 'i8':
            out.append((off, nm, str(struct.unpack_from('<q', data, p)[0]))); p += 8
        elif enc == 'r4':
            out.append((off, nm, str(struct.unpack_from('<f', data, p)[0]))); p += 4
        elif enc == 'r8':
            out.append((off, nm, str(struct.unpack_from('<d', data, p)[0]))); p += 8
        elif enc == 'br1':
            v = struct.unpack_from('<b', data, p)[0]; p += 1
            out.append((off, nm, 'IL_%04x' % (p - base + v)))
        elif enc == 'br4':
            v = struct.unpack_from('<i', data, p)[0]; p += 4
            out.append((off, nm, 'IL_%04x' % (p - base + v)))
        elif enc == 'switch':
            n = struct.unpack_from('<I', data, p)[0]; p += 4
            tgt = []
            for _ in range(n):
                v = struct.unpack_from('<i', data, p)[0]; p += 4
                tgt.append('IL_%04x' % (p - base + v))
            out.append((off, nm, '%d:%s' % (n, ','.join(tgt))))
        else:
            out.append((off, nm, enc))
    return out

def main():
    path = sys.argv[1]
    keys = sys.argv[2:]
    data = open(path, 'rb').read()
    md = ilp.MD(data)
    show_bytes = '--bytes' in keys
    keys = [k for k in keys if k != '--bytes']
    allm = [(t, m, rva) for t, m, rva in md.methods() if rva]
    hits = []
    for key in keys:
        star = key.endswith('*')
        k = key.rstrip('*')
        for t, m, rva in allm:
            full = t + '::' + m
            if (star and k.lower() in full.lower()) or full == key or (t.split('.')[-1] + '::' + m) == key:
                hits.append((t, m, rva))
    seen = set()
    for t, m, rva in hits:
        if (t, m) in seen: continue
        seen.add((t, m))
        off = ilp.rva2off(md.secs, rva)
        co, cs, hdr = ilp.il_body(data, off)
        print('### %s::%s  hdrfile=%#x codefile=%#x size=%d hdr=%r' % (t, m, off, co, cs, hdr))
        if show_bytes:
            print('    bytes: ' + data[co:co+cs].hex(' '))
        for o, nm, op in decode(data, co, cs):
            print('    IL_%04x  %-18s %s' % (o, nm, op))
        print()

main()
