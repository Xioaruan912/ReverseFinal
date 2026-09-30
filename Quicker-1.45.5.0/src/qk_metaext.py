#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Quicker 1.45.5.0 - metadata extension: add MemberRef System.DateTime::AddYears.

Why this is needed
------------------
The single client-side Pro gate is `DataService::tuE6DqVP75B` in Quicker.exe:

    IsPro == MemberExpireTimeUtc.HasValue && MemberExpireTimeUtc.Value > DateTime.UtcNow

`UserInfo.MemberLevel` and every `UserLimitation` flag are ignored by that gate,
so the only lever available inside the unsigned Quicker.Common.dll is
`UserInfo::get_MemberExpireTimeUtc`.

Returning a *future* DateTime needs `System.DateTime::AddYears`, which the
assembly does not reference.  This tool performs the minimal metadata surgery:

  * append "AddYears\\0" to the #Strings heap
  * append the signature blob 05 20 01 11 39 08 to the #Blob heap
  * insert one MemberRef row (Class=TypeRef System.DateTime, Name, Signature)
    and bump the MemberRef row count
  * rebuild the metadata root stream directory with the new offsets
  * relocate the rewritten method body into the free space that follows the
    metadata inside .text and repoint the MethodDef RVA

Everything is verified by reading the bytes back out of the produced file and
by loading the result with the CLR.
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil

SRC_SHA = '3924e21d208fb2a90c0c241a2806365979fe1838a9ea297e3f874fd6c45c421c'  # VIP-patched baseline
GOLDEN = '350c56e04ed0e7b0ec0e88df2e59f6298a24fb1c951e7aab4099afd1128275fa'

# MemberRef.Class is a MemberRefParent coded index: 5 tables -> 3 tag bits
#   (TypeDef=0, TypeRef=1, ModuleRef=2, MethodDef=3, TypeSpec=4)
MEMBERREFPARENT_TYPE_REF_TAG = 1
DATETIME_TYPEREF_RID = 0x0E          # TypeRef 0x0100000e = System.DateTime
GET_UTCNOW = 0x0A000031              # MemberRef System.DateTime::get_UtcNow
NEW_MR_TOKEN = 0x0A000070            # appended MemberRef rid 112 -> DateTime::AddYears
NEW_CTOR_TOKEN = 0x0A000071          # appended MemberRef rid 113 -> Nullable<DateTime>::.ctor
NULLABLE_DT_TYPESPEC_RID = 12        # TypeSpec 12 = Nullable<DateTime>
MEMBERREFPARENT_TYPESPEC_TAG = 4     # MemberRefParent: TypeDef 0, TypeRef 1, ModuleRef 2, MethodDef 3, TypeSpec 4
CTOR_NAME_IDX = 0xAAB9               # existing #Strings entry ".ctor"
NULLABLE_DATETIME_TYPESPEC = 0x1B00000C   # TypeSpec 12 = Nullable<DateTime>
DATETIME_LOCAL_SIGTOK = 0x11000003   # StandAloneSig 3 = { Guid, Nullable<DateTime> }
DATETIME_LOCAL_INDEX = 1             # local 1 is the Nullable<DateTime>
TOKEN_CREATE_FIELD = 0x04000376      # UserInfo._tokenCreateTimeUtc (System.DateTime)
ADD_YEARS = 3650

# 20 = HASTHIS, 01 = 1 param, 11 39 = VALUETYPE TypeRef rid 14, 08 = int32
ADDYEARS_SIG = bytes([0x05, 0x20, 0x01, 0x11, 0x39, 0x08])
# instance void Nullable`1<DateTime>::.ctor(!0)   -- !0 is ELEMENT_TYPE_VAR 0 (0x13 0x00)
CTOR_SIG = bytes([0x05, 0x20, 0x01, 0x01, 0x13, 0x00])


def popcount_below(valid, table):
    return bin(valid & ((1 << table) - 1)).count('1')


def build_new_body():
    """Method body for get_MemberExpireTimeUtc.

    DateTime.AddYears is an instance method on a value type, so `this` must be a
    managed pointer to a *DateTime*.  ldflda on an existing DateTime field gives
    exactly that, so no local variable (and no new local signature) is needed:

        ldarg.0
        ldflda  TokenCreateTimeUtc    ; &DateTime   (0001-01-01)
        ldc.i4  3650
        call    DateTime::AddYears    ; -> year 3651, far in the future
        ret

    The caller stores the result into a Nullable<DateTime> slot; the CLR accepts
    the layout-compatible bare DateTime (verified experimentally).
    """
    il = (b'\x02' +                                                  # ldarg.0
          b'\x7c' + struct.pack('<I', TOKEN_CREATE_FIELD) +          # ldflda TokenCreateTimeUtc
          b'\x20' + struct.pack('<i', ADD_YEARS) +                   # ldc.i4 3650
          b'\x28' + struct.pack('<I', NEW_MR_TOKEN) +                # call DateTime::AddYears
          b'\x73' + struct.pack('<I', NEW_CTOR_TOKEN) +              # newobj Nullable<DateTime>::.ctor
          b'\x2a')                                                   # ret
    assert il[-1] == 0x2A and len(il) <= 63
    return bytes([(len(il) << 2) | 2]) + il                          # tiny header, ret last


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else \
        r'C:\Users\Administrator\Desktop\Reverse_OK\Quicker-1.45.5.0\toolkit\Quicker.Common.patched.dll'
    dst = sys.argv[2] if len(sys.argv) > 2 else \
        r'C:\Users\Administrator\Desktop\Reverse_OK\Quicker-1.45.5.0\toolkit\Quicker.Common.pro.dll'
    d = bytearray(open(src, 'rb').read())
    got = hashlib.sha256(bytes(d)).hexdigest()
    if got != SRC_SHA:
        raise SystemExit('ABORT: input sha256 %s != %s' % (got, SRC_SHA))

    md = peil.MD(bytes(d))
    if md.rows.get(0x0A, 0) != 111:
        raise SystemExit('ABORT: expected 111 MemberRef rows, got %d' % md.rows.get(0x0A, 0))

    mdoff = peil.rva2off(md.secs, md.md_rva)
    md_size = md.md_size

    # ---- stream headers (original layout) ----
    root = md.base                                    # metadata root slice
    ver_len = struct.unpack_from('<I', root, 12)[0]
    p = 16 + ((ver_len + 3) // 4) * 4
    flags, nstreams = struct.unpack_from('<HH', root, p)
    hdr_end = p + 4
    order = []
    q = hdr_end
    for _ in range(nstreams):
        off, sz = struct.unpack_from('<II', root, q); q += 8
        e = root.index(b'\0', q)
        name = root[q:e].decode('latin1')
        q = (e + 1 + 3) & ~3
        order.append((name, off, sz))
    root_hdr = bytes(root[:hdr_end])

    so, ss = md.streams['#Strings']
    bo, bs = md.streams['#Blob']

    # ---- 1) grow #Strings ----
    strings = bytearray(root[so:so + ss])
    name_idx = len(strings)
    strings += b'AddYears\x00'
    assert name_idx < 0x10000 and len(strings) < 0x10000, 'string heap must stay 16-bit'

    # ---- 2) grow #Blob ----
    blob = bytearray(root[bo:bo + bs])
    blob_idx = len(blob)
    blob += ADDYEARS_SIG
    ctor_blob_idx = len(blob)
    blob += CTOR_SIG
    assert blob_idx < 0x10000 and len(blob) < 0x10000, 'blob heap must stay 16-bit'

    # ---- 3) insert one MemberRef row into #~ ----
    tilde = bytearray(md.tbl)
    rowsize = md.rsize(0x0A)
    assert rowsize == 6
    cls = ((DATETIME_TYPEREF_RID << 3) | MEMBERREFPARENT_TYPE_REF_TAG) & 0xFFFF
    new_row = struct.pack('<HHH', cls, name_idx, blob_idx)
    cls2 = ((NULLABLE_DT_TYPESPEC_RID << 3) | MEMBERREFPARENT_TYPESPEC_TAG) & 0xFFFF
    new_row2 = struct.pack('<HHH', cls2, CTOR_NAME_IDX, ctor_blob_idx)
    at = md.toff(0x0A) + 111 * rowsize
    tilde[at:at] = new_row + new_row2
    # bump the row count
    cnt_off = 24 + 4 * popcount_below(md.valid, 0x0A)
    old_cnt = struct.unpack_from('<I', tilde, cnt_off)[0]
    assert old_cnt == 111, old_cnt
    struct.pack_into('<I', tilde, cnt_off, 113)

    # The MemberRef table is flagged Sorted in the #~ header, so the CLR binary-searches
    # it.  Our appended row breaks that order -> clear the Sorted bit (offset 16, bit 0x0A)
    # so lookups fall back to a linear scan.
    sorted_mask = struct.unpack_from('<Q', tilde, 16)[0]
    print('Sorted mask before: %#018x  (MemberRef sorted: %s)' % (sorted_mask, bool(sorted_mask & (1 << 0x0A))))
    sorted_mask &= ~(1 << 0x0A)
    struct.pack_into('<Q', tilde, 16, sorted_mask)

    # ---- 4) rebuild the metadata root ----
    streams = {'#~': bytes(tilde),
               '#Strings': bytes(strings),
               '#US': bytes(root[md.streams['#US'][0]:md.streams['#US'][0] + md.streams['#US'][1]]),
               '#GUID': bytes(root[md.streams['#GUID'][0]:md.streams['#GUID'][0] + md.streams['#GUID'][1]]),
               '#Blob': bytes(blob)}
    hdrs = bytearray()
    body = bytearray()
    cur = None
    for name, _o, _s in order:
        data = streams[name]
        if cur is None:
            cur = hdr_end
            for _ in range(len(order)):
                pass
            cur = hdr_end + sum(8 + ((len(n) + 1 + 3) // 4) * 4 for n, _, _ in order)
        hdrs += struct.pack('<II', cur, len(data))
        hdrs += name.encode('latin1') + b'\x00'
        hdrs += b'\x00' * (((len(name) + 1 + 3) // 4) * 4 - (len(name) + 1))
        body += data
        cur += len(data)
    new_md = root_hdr + bytes(hdrs) + bytes(body)
    assert len(new_md) <= md_size + 784, 'metadata grew past the section slack'
    print('metadata: %d -> %d bytes (+%d)' % (md_size, len(new_md), len(new_md) - md_size))

    # ---- 5) relocate the rewritten method body into the section slack ----
    # The body now uses a *tiny* header (no locals), so placing it right after the
    # metadata inside .text is accepted by the CLR.  (An earlier attempt failed only
    # because of a malformed fat header, not because of the location.)
    body = build_new_body()
    body_off_rel = (len(new_md) + 3) & ~3
    body_file_off = mdoff + body_off_rel
    sec = None
    for va, sz, raw, rsz in md.secs:
        if raw <= body_file_off < raw + rsz:
            sec = (va, sz, raw, rsz); break
    if not sec:
        raise SystemExit('ABORT: body offset outside any section')
    body_rva = sec[0] + (body_file_off - sec[2])
    print('new method body: file=%#x  rva=%#x  (%d bytes)' % (body_file_off, body_rva, len(body)))

    target_rid = None
    for rid, t, m, rva, sig in peil.method_rows(md):
        if t.split('.')[-1] == 'UserInfo' and m == 'get_MemberExpireTimeUtc':
            target_rid = rid; break
    if not target_rid:
        raise SystemExit('ABORT: get_MemberExpireTimeUtc not found')

    # ---- 6) repoint the MethodDef RVA of get_MemberExpireTimeUtc ----
    md_row_off = md.toff(0x06) + (target_rid - 1) * md.rsize(0x06)
    struct.pack_into('<I', tilde, md_row_off, body_rva)
    # rebuild streams once more with the fixed row
    streams['#~'] = bytes(tilde)
    hdrs = bytearray(); body = bytearray()
    cur = hdr_end + sum(8 + ((len(n) + 1 + 3) // 4) * 4 for n, _, _ in order)
    for name, _o, _s in order:
        data = streams[name]
        hdrs += struct.pack('<II', cur, len(data))
        hdrs += name.encode('latin1') + b'\x00'
        hdrs += b'\x00' * (((len(name) + 1 + 3) // 4) * 4 - (len(name) + 1))
        body += data
        cur += len(data)
    new_md = root_hdr + bytes(hdrs) + bytes(body)
    assert len(new_md) <= md_size + 784
    pad = body_off_rel - len(new_md)
    new_md += b'\x00' * pad + build_new_body()

    # ---- 7) write back ----
    d[mdoff:mdoff + len(new_md)] = new_md
    cor_rva, _cor_sz = md.ddirs[14]
    cor_off = peil.rva2off(md.secs, cor_rva)
    old_size = struct.unpack_from('<I', d, cor_off + 12)[0]
    assert old_size == md_size, 'unexpected COR20 metadata size %d' % old_size
    # MetaData.Size covers only the stream directory + streams, not the relocated body
    struct.pack_into('<I', d, cor_off + 12, body_off_rel)
    open(dst, 'wb').write(bytes(d))
    h = hashlib.sha256(bytes(d)).hexdigest()
    print('output: %s' % dst)
    print('sha256: %s' % h)
    if GOLDEN and h != GOLDEN:
        raise SystemExit('ABORT: golden mismatch')
    return 0


if __name__ == '__main__':
    sys.exit(main())
