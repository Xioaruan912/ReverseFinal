#!/usr/bin/env python3
"""Minimal, precise single-site IL body patcher for .NET assemblies.

Usage:
  python ilp.py <dll> list
  python ilp.py <dll> patch <out> <Type::Method> <hexbytes>
"""
import hashlib, struct, sys

def pe_off(data):
    e = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[e:e+4] == b'PE\0\0'
    coff = e + 4
    nsec, = struct.unpack_from('<H', data, coff+2)
    optsz, = struct.unpack_from('<H', data, coff+16)
    opt = coff + 20
    pe32plus = struct.unpack_from('<H', data, opt)[0] == 0x20B
    ddir = opt + (112 if pe32plus else 96)
    ddirs = [struct.unpack_from('<II', data, ddir+i*8) for i in range(16)]
    sect = opt + optsz
    secs = []
    for i in range(nsec):
        o = sect + i*40
        vsz, va, rsz, raw = struct.unpack_from('<IIII', data, o+8)
        secs.append((va, max(vsz, rsz), raw, rsz))
    return ddirs, secs

def rva2off(secs, rva):
    for va, sz, raw, rsz in secs:
        if va <= rva < va + sz:
            return raw + (rva - va)
    return None

class MD:
    def __init__(self, data):
        self.d = data
        self.ddirs, self.secs = pe_off(data)
        rva, _ = self.ddirs[14]
        mdo = rva2off(self.secs, rva)
        self.md_rva, self.md_size = struct.unpack_from('<II', data, mdo+8)
        base = data[rva2off(self.secs, self.md_rva): rva2off(self.secs, self.md_rva)+self.md_size]
        self.base = base
        vlen, = struct.unpack_from('<I', base, 12)
        p = 16 + ((vlen+3)//4)*4
        _f, ns = struct.unpack_from('<HH', base, p); p += 4
        self.streams = {}
        for _ in range(ns):
            off, sz = struct.unpack_from('<II', base, p); p += 8
            end = base.index(b'\0', p)
            self.streams[base[p:end].decode('latin1')] = (off, sz)
            p = (end+1+3) & ~3
        name = '#~' if '#~' in self.streams else '#-'
        off, sz = self.streams[name]
        t = base[off:off+sz]
        self.heap = t[6]
        self.valid, self.sorted_ = struct.unpack_from('<QQ', t, 8)
        p = 24
        self.rows = {}
        for i in range(64):
            if self.valid & (1 << i):
                self.rows[i] = struct.unpack_from('<I', t, p)[0]; p += 4
        self.tbl = t; self.tbl_off = p
        self.str_size = 4 if self.heap & 1 else 2
        self.guid_size = 4 if self.heap & 2 else 2
        self.blob_size = 4 if self.heap & 4 else 2
    def s(self, t): return 4 if self.rows.get(t,0) >= 0x10000 else 2
    def c(self, ts, bits): return 4 if (max(self.rows.get(t,0) for t in ts) << bits) >= 0x10000 else 2
    RS = {
        0x00: lambda s,g,b,r,c: 2 + s + 3*g,
        0x01: lambda s,g,b,r,c: c([0x00,0x1A,0x23,0x02],2) + 2*s,
        0x02: lambda s,g,b,r,c: 4 + 2*s + c([0x02,0x01,0x1B],2) + r(0x04) + r(0x06),
        0x03: lambda s,g,b,r,c: r(0x04),
        0x04: lambda s,g,b,r,c: 2 + s + b,
        0x05: lambda s,g,b,r,c: r(0x06),
        0x06: lambda s,g,b,r,c: 4+2+2+s+b+r(0x08),
        0x07: lambda s,g,b,r,c: r(0x08),
        0x08: lambda s,g,b,r,c: 2+2+s,
        0x09: lambda s,g,b,r,c: r(0x02)+c([0x02,0x01,0x1B],2),
        0x0A: lambda s,g,b,r,c: c([0x02,0x01,0x1B,0x06,0x04],3)+s+b,
        0x0B: lambda s,g,b,r,c: 2+c([0x04,0x08,0x17],2)+b,
        0x0C: lambda s,g,b,r,c: c([0x06,0x04,0x01],5)+c([0x00,0x0A],3)+b,
        0x0D: lambda s,g,b,r,c: c([0x04,0x08],1)+b,
        0x0E: lambda s,g,b,r,c: 2+c([0x02,0x06,0x20],2)+b,
        0x0F: lambda s,g,b,r,c: 2+4+r(0x02),
        0x10: lambda s,g,b,r,c: 4+r(0x04),
        0x11: lambda s,g,b,r,c: b,
        0x12: lambda s,g,b,r,c: r(0x02)+r(0x14),
        0x13: lambda s,g,b,r,c: r(0x14),
        0x14: lambda s,g,b,r,c: 2+s+c([0x02,0x01,0x1B],2),
        0x15: lambda s,g,b,r,c: r(0x02)+r(0x17),
        0x16: lambda s,g,b,r,c: r(0x17),
        0x17: lambda s,g,b,r,c: 2+s+b,
        0x18: lambda s,g,b,r,c: 2+r(0x06)+c([0x14,0x17],1),
        0x19: lambda s,g,b,r,c: r(0x02)+c([0x06,0x0A],1),
        0x1A: lambda s,g,b,r,c: s,
        0x1B: lambda s,g,b,r,c: b,
        0x1C: lambda s,g,b,r,c: 2+c([0x06,0x0A],1)+s+r(0x1A),
        0x1D: lambda s,g,b,r,c: 4+r(0x04),
        0x1E: lambda s,g,b,r,c: 8,
        0x1F: lambda s,g,b,r,c: 4,
        0x20: lambda s,g,b,r,c: 4+2+2+2+2+4+b+s+s,
        0x21: lambda s,g,b,r,c: 4,
        0x22: lambda s,g,b,r,c: 12,
        0x23: lambda s,g,b,r,c: 2+2+2+2+4+b+s+s+b,
        0x24: lambda s,g,b,r,c: 4,
        0x25: lambda s,g,b,r,c: 12,
        0x26: lambda s,g,b,r,c: 4+s+b,
        0x27: lambda s,g,b,r,c: 4+4+s+s+c([0x26,0x27,0x02],2),
        0x28: lambda s,g,b,r,c: 4+4+s+c([0x26,0x27],1),
        0x29: lambda s,g,b,r,c: r(0x02)+r(0x02),
        0x2A: lambda s,g,b,r,c: 2+2+c([0x02,0x1B],1)+s,
        0x2B: lambda s,g,b,r,c: c([0x06,0x0A],1)+b,
        0x2C: lambda s,g,b,r,c: r(0x2A)+c([0x02,0x1B],1),
    }
    def rsize(self, t):
        return self.RS[t](self.str_size, self.guid_size, self.blob_size, self.s, self.c)
    def toff(self, t):
        o = self.tbl_off
        for i in range(t):
            if self.valid & (1 << i):
                o += self.rows[i] * self.rsize(i)
        return o
    def row(self, t, i):
        o = self.toff(t) + i*self.rsize(t)
        return self.tbl[o:o+self.rsize(t)]
    def str_at(self, idx):
        off, _ = self.streams['#Strings']
        e = self.base.index(b'\0', off+idx)
        return self.base[off+idx:e].decode('utf-8', 'replace')
    def u16(self, buf, o):
        return struct.unpack_from('<I' if self.str_size == 4 else '<H', buf, o)[0]
    def methods(self):
        tds = []
        for i in range(self.rows.get(0x02, 0)):
            r = self.row(0x02, i)
            nm = self.str_at(self.u16(r, 4))
            ns = self.str_at(self.u16(r, 4+self.str_size))
            ml_off = 4 + 2*self.str_size + self.c([0x02,0x01,0x1B],2) + self.s(0x04)
            ml = struct.unpack_from('<I' if self.s(0x06)==4 else '<H', r, ml_off)[0]
            tds.append(((ns+'.' if ns else '')+nm, ml))
        total = self.rows.get(0x06, 0)
        out = []
        for k, (tname, ml) in enumerate(tds):
            nxt = tds[k+1][1] if k+1 < len(tds) else total+1
            for m in range(ml, nxt):
                r = self.row(0x06, m-1)
                rva, = struct.unpack_from('<I', r, 0)
                out.append((tname, self.str_at(self.u16(r, 8)), rva))
        return out

def il_body(data, off):
    b = data[off]
    if (b & 3) == 2:
        return off+1, b >> 2, ('tiny', b)
    flags, = struct.unpack_from('<H', data, off)
    hdr = ((flags >> 12) & 0xF)*4
    size, = struct.unpack_from('<I', data, off+4)
    return off+hdr, size, ('fat', flags)

def field_sig(md, rid):
    r = md.row(0x04, rid-1)
    idx = md.u16(r, 2+md.str_size)
    off, _ = md.streams['#Blob']
    p = off+idx
    b0 = md.base[p]
    if b0 & 0x80 == 0: n = b0; p += 1
    elif b0 & 0xC0 == 0x80: n = ((b0 & 0x3F) << 8) | md.base[p+1]; p += 2
    else: n = ((b0 & 0x1F) << 24)|(md.base[p+1] << 16)|(md.base[p+2] << 8)|md.base[p+3]; p += 4
    return md.base[p:p+n]

def main():
    data = open(sys.argv[1], 'rb').read()
    md = MD(data)
    if sys.argv[2] == 'list':
        for tname, mname, rva in md.methods():
            if not rva: continue
            off = rva2off(md.secs, rva)
            if off is None: continue
            try: co, cs, hdr = il_body(data, off)
            except Exception: continue
            if cs == 7 and co+cs <= len(data):
                body = data[co:co+cs]
                if body[0] == 0x02 and body[1] == 0x7B and body[6] == 0x2A:
                    tok, = struct.unpack_from('<I', body, 2)
                    try: sig = field_sig(md, tok & 0xFFFFFF).hex()
                    except Exception: sig = '?'
                    print('%-70s file=%#08x hdr=%s size=%d tok=%#010x sig=%s' % (tname+'::'+mname, off, hdr[0], cs, tok, sig))
        return
    if sys.argv[2] == 'patch':
        src, dst, key, hexb = sys.argv[1], sys.argv[3], sys.argv[4], sys.argv[5]
        new = bytes.fromhex(hexb.replace(' ', ''))
        hit = None
        for tname, mname, rva in md.methods():
            if not rva: continue
            if (tname.split('.')[-1] + '::' + mname) == key or (tname + '::' + mname) == key:
                off = rva2off(md.secs, rva)
                co, cs, hdr = il_body(data, off)
                hit = (tname, mname, off, co, cs, hdr, rva)
                break
        if not hit: raise SystemExit('method not found: ' + key)
        tname, mname, off, co, cs, hdr, rva = hit
        orig = data[co:co+cs]
        print('TARGET %s::%s RVA=%#x file=%#x code=%#x size=%d hdr=%r' % (tname, mname, rva, off, co, cs, hdr))
        print('  orig IL : ' + orig.hex(' '))
        if len(new) != cs:
            print('  !! new len %d != %d' % (len(new), cs))
        d = bytearray(data)
        d[co:co+cs] = new
        open(dst, 'wb').write(bytes(d))
        print('  new  IL : ' + new.hex(' '))
        print('  out     : %s  sha256=%s' % (dst, hashlib.sha256(bytes(d)).hexdigest()))
        return
    raise SystemExit('usage: ilp.py <dll> list | ilp.py <dll> patch <out> <Type::Method> <hex>')

if __name__ == '__main__':
    main()

# ---- extended helpers appended ----
def method_rows(md):
    """yield (rid, type_name, method_name, rva, sig_idx) for every MethodDef."""
    tds = []
    for i in range(md.rows.get(0x02, 0)):
        r = md.row(0x02, i)
        nm = md.str_at(md.u16(r, 4))
        ns = md.str_at(md.u16(r, 4+md.str_size))
        ml_off = 4 + 2*md.str_size + md.c([0x02,0x01,0x1B],2) + md.s(0x04)
        ml = struct.unpack_from('<I' if md.s(0x06)==4 else '<H', r, ml_off)[0]
        tds.append(((ns+'.' if ns else '')+nm, ml))
    total = md.rows.get(0x06, 0)
    for k, (tname, ml) in enumerate(tds):
        nxt = tds[k+1][1] if k+1 < len(tds) else total+1
        for m in range(ml, nxt):
            r = md.row(0x06, m-1)
            rva, = struct.unpack_from('<I', r, 0)
            sig = md.u16(r, 8 + md.str_size)
            yield m, tname, md.str_at(md.u16(r, 8)), rva, sig

def blob_at(md, idx):
    off, _ = md.streams['#Blob']
    p = off + idx
    b0 = md.base[p]
    if b0 & 0x80 == 0: n = b0; p += 1
    elif b0 & 0xC0 == 0x80: n = ((b0 & 0x3F) << 8) | md.base[p+1]; p += 2
    else: n = ((b0 & 0x1F) << 24)|(md.base[p+1] << 16)|(md.base[p+2] << 8)|md.base[p+3]; p += 4
    return md.base[p:p+n]

ELEM = {0x01:'void',0x02:'bool',0x03:'char',0x04:'int8',0x05:'uint8',0x06:'int16',0x07:'uint16',
        0x08:'int32',0x09:'uint32',0x0a:'int64',0x0b:'uint64',0x0c:'float32',0x0d:'float64',
        0x0e:'string',0x0f:'ptr',0x11:'valuetype',0x12:'class',0x13:'var',0x1c:'object',0x1e:'typedref'}

def retsig(md, sig_idx):
    b = blob_at(md, sig_idx)
    p = 0
    cc = b[p]; p += 1
    if cc & 0x10:                      # GENERIC, skip generic param count
        if b[p] & 0x80 == 0: p += 1
        elif b[p] & 0xC0 == 0x80: p += 2
        else: p += 4
    # param count
    n = b[p]
    if n & 0x80 == 0: p += 1
    elif n & 0xC0 == 0x80: p += 2
    else: p += 4
    et = b[p]
    name = ELEM.get(et, hex(et))
    if et in (0x11, 0x12):
        # compressed TypeDefOrRef
        q = p + 1
        if b[q] & 0x80 == 0: p = q + 1
        elif b[q] & 0xC0 == 0x80: p = q + 2
        else: p = q + 4
        return name
    return name
