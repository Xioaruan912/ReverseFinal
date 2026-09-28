#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Minimal .NET (ECMA-335) method-body patcher.
Locates a MethodDef by name inside a PE file and overwrites its IL body.

Used here to neuter Listary.Core.Pro.LicenseChecker::CheckLicense
    original stub IL : ldc.i4.2; newarr object; ...; call <babel VM>; unbox.any bool; ret
    patched     IL   : ldc.i4.1; ret; nop x N
so the method unconditionally returns true.

Usage:
    python net_ilpatch.py <in.exe> <out.exe> <MethodName> [--ret-int N] [--list]
"""
import struct
import sys
import os

# ---------------------------------------------------------------- PE


class PE:
    def __init__(self, data):
        self.d = data
        e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
        assert data[e_lfanew:e_lfanew + 4] == b"PE\0\0", "not a PE"
        coff = e_lfanew + 4
        self.nsec, = struct.unpack_from("<H", data, coff + 2)
        opt_size, = struct.unpack_from("<H", data, coff + 16)
        opt = coff + 20
        magic, = struct.unpack_from("<H", data, opt)
        self.pe32plus = (magic == 0x20B)
        ddir = opt + (112 if self.pe32plus else 96)
        self.ddir = []
        for i in range(16):
            rva, size = struct.unpack_from("<II", data, ddir + i * 8)
            self.ddir.append((rva, size))
        sect = opt + opt_size
        self.sections = []
        for i in range(self.nsec):
            off = sect + i * 40
            name = data[off:off + 8].rstrip(b"\0").decode("latin1")
            vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
            self.sections.append((name, vaddr, vsize, rawptr, rawsize))

    def rva2off(self, rva):
        for name, vaddr, vsize, rawptr, rawsize in self.sections:
            if vaddr <= rva < vaddr + max(vsize, rawsize):
                return rawptr + (rva - vaddr)
        raise ValueError("RVA %#x not mapped" % rva)

    def read(self, rva, size):
        o = self.rva2off(rva)
        return self.d[o:o + size], o


# ---------------------------------------------------------------- metadata


class MD:
    def __init__(self, pe):
        rva, size = pe.ddir[14]
        assert rva, "no CLR directory"
        hdr, _ = pe.read(rva, 16)
        md_rva, md_size = struct.unpack_from("<II", hdr, 8)
        base, _ = pe.read(md_rva, md_size)
        self.pe = pe
        self.base_rva = md_rva
        sig, = struct.unpack_from("<I", base, 0)
        assert sig == 0x424A5342, "bad metadata signature"
        ver_len, = struct.unpack_from("<I", base, 12)
        p = 16 + ((ver_len + 3) // 4) * 4
        flags, streams = struct.unpack_from("<HH", base, p)
        p += 4
        self.streams = {}
        for _ in range(streams):
            off, sz = struct.unpack_from("<II", base, p)
            p += 8
            end = base.index(b"\0", p)
            name = base[p:end].decode("latin1")
            p = end + 1
            p = (p + 3) & ~3
            self.streams[name] = (off, sz)
        self.parse_tables(base)

    def parse_tables(self, base):
        tname = "#~" if "#~" in self.streams else "#-"
        off, sz = self.streams[tname]
        t = base[off:off + sz]
        p = 4  # reserved
        self.major, self.minor, self.heapsizes, self.res2 = t[p], t[p + 1], t[p + 2], t[p + 3]
        p += 4
        self.valid, self.sorted = struct.unpack_from("<QQ", t, p)
        p += 16
        self.rows = {}
        for i in range(64):
            if self.valid & (1 << i):
                self.rows[i] = struct.unpack_from("<I", t, p)[0]
                p += 4
        self.tbl = t
        self.tbl_off = off + p   # absolute offset of the first table row inside the metadata root
        # heap index sizes
        self.str_size = 4 if (self.heapsizes & 1) else 2
        self.guid_size = 4 if (self.heapsizes & 2) else 2
        self.blob_size = 4 if (self.heapsizes & 4) else 2

    def simple(self, table):
        return 4 if self.rows.get(table, 0) >= 0x10000 else 2

    def coded(self, tables, tagbits):
        mx = max(self.rows.get(t, 0) for t in tables)
        return 4 if (mx << tagbits) >= (1 << 16) else 2

    def row_size(self, table):
        s, g, b = self.str_size, self.guid_size, self.blob_size
        rs = self.simple
        if table == 0x00:  # Module
            return 2 + s + 3 * g
        if table == 0x01:  # TypeRef
            return self.coded([0x00, 0x1A, 0x23, 0x02], 2) + s * 2
        if table == 0x02:  # TypeDef
            return 4 + s * 2 + self.coded([0x02, 0x01, 0x1B], 2) + rs(0x04) + rs(0x06)
        if table == 0x03:  # FieldPtr
            return rs(0x04)
        if table == 0x04:  # Field
            return 2 + s + b
        if table == 0x05:  # MethodPtr
            return rs(0x06)
        if table == 0x06:  # MethodDef
            return 4 + 2 + 2 + s + b + rs(0x08)
        raise NotImplementedError("table %#x row size not implemented" % table)

    def table_offset(self, table):
        o = self.tbl_off
        for i in range(table):
            if self.valid & (1 << i):
                o += self.rows[i] * self.row_size(i)
        return o

    def strings(self, idx):
        off, sz = self.streams["#Strings"]
        base = self.tbl  # not used
        return None


def get_string(md, idx):
    # rebuild full metadata blob to reach the heaps (they are relative to metadata root)
    pe = md.pe
    base, _ = pe.read(md.base_rva, 0x1000 if False else 0)
    return None


class Patcher:
    def __init__(self, path):
        self.data = bytearray(open(path, "rb").read())
        self.pe = PE(bytes(self.data))
        self.md = MD(self.pe)
        rva, size = self.pe.ddir[14]
        self.md_rva, self.md_size = struct.unpack_from("<II", self.pe.read(rva, 16)[0], 8)
        self.meta = bytes(self.pe.read(self.md_rva, self.md_size)[0])

    def strings_heap(self):
        off, sz = self.md.streams["#Strings"]
        return self.meta[off:off + sz]

    def blob_heap(self):
        off, sz = self.md.streams["#Blob"]
        return self.meta[off:off + sz]

    def sname(self, idx):
        h = self.strings_heap()
        end = h.index(b"\0", idx)
        return h[idx:end].decode("utf-8", "replace")

    def methoddefs(self):
        md = self.md
        off = md.table_offset(0x06)
        rs = md.row_size(0x06)
        out = []
        for i in range(md.rows.get(0x06, 0)):
            o = off + i * rs
            rva, impl, flags = struct.unpack_from("<IHH", self.meta, o)
            p = o + 8
            name_idx = struct.unpack_from("<I" if md.str_size == 4 else "<H", self.meta, p)[0]
            p += md.str_size
            sig_idx = struct.unpack_from("<I" if md.blob_size == 4 else "<H", self.meta, p)[0]
            out.append((i + 1, rva, flags, self.sname(name_idx), self.ret_elem(sig_idx)))
        return out

    def ret_elem(self, blob_idx):
        """element type of the return value of a METHOD_DEF signature (0x01=void,0x02=bool)"""
        h = self.blob_heap()
        i = blob_idx
        b = h[i]
        if b & 0x80:      # compressed length (only low bits used here)
            i += 1
            b &= 0x7F
        i += 1            # compressed-length byte(s); keep it simple: single byte form
        i += 1            # calling convention
        if h[i] == 0x20:  # HASTHIS (instance)
            i += 1
        c = h[i]
        if c & 0x80 == 0:
            i += 1
        elif c & 0xC0 == 0x80:
            i += 2
        else:
            i += 4
        return h[i]

    def patch(self, name, ret_int=1, occurrences=None):
        md = self.md
        res = []
        for row, rva, flags, nm, ret in self.methoddefs():
            if nm != name:
                continue
            if not rva:
                continue
            if ret != 0x02:          # only boolean methods
                continue
            off = self.pe.rva2off(rva)
            b = self.data[off]
            if (b & 3) == 2:  # tiny header
                code_size = b >> 2
                code_off = off + 1
                hdr_size = 1
            else:  # fat header
                flags_fh, = struct.unpack_from("<H", self.data, off)
                hdr_size = ((flags_fh >> 12) & 0xF) * 4
                code_size, = struct.unpack_from("<I", self.data, off + 4)
                code_off = off + hdr_size
            new = bytes([0x17 if ret_int == 1 else 0x16 if ret_int == 0 else 0x1F, 0x2A])
            if ret_int not in (0, 1):
                new = bytes([0x20]) + struct.pack("<i", ret_int) + b"\x2A"
            assert len(new) <= code_size, "new IL longer than original"
            patch_bytes = new + b"\x00" * (code_size - len(new))
            self.data[code_off:code_off + code_size] = patch_bytes
            res.append((row, rva, code_size, hdr_size))
        return res


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else "CheckLicense"
    ret = 1
    if "--ret-int" in sys.argv:
        ret = int(sys.argv[sys.argv.index("--ret-int") + 1])
    p = Patcher(src)
    if name == "--list":
        for row, rva, flags, nm, ret in p.methoddefs():
            if rva:
                print("%6d  %#010x  ret=%#04x  %s" % (row, rva, ret, nm))
        sys.exit(0)
    hits = p.patch(name, ret)
    if not hits:
        print("method %r not found" % name)
        sys.exit(2)
    open(dst, "wb").write(bytes(p.data))
    for row, rva, cs, hs in hits:
        print("patched MethodDef row=%d rva=%#x codeSize=%d hdr=%d -> return %d" % (row, rva, cs, hs, ret))
    print("written:", dst, os.path.getsize(dst), "bytes")
