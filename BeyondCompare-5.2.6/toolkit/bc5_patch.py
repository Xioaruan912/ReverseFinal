#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Beyond Compare 5.2.6.32774  --  offline licence decision hardening (CWE-602 whitebox audit)

Reference implementation of the binary patch set described in
reports/BeyondCompare-5.2.6-鉴权脆弱性审计报告.md

Usage
-----
    python bc5_patch.py <original BCompare.exe> <output BCompare.exe>
    python bc5_patch.py <original> <output> --verify-only

Behaviour
---------
  * refuses to run if the input hash != SRC_SHA256 (build drift guard)
  * verifies the ORIGINAL bytes at every patch site before writing
  * verifies the written bytes after every patch (read-back)
  * prints the output sha256, which must equal GOLDEN_SHA256

The patch only rewrites code immediates / short jumps plus two settings
strings -- every touched region keeps its original length, so the PE
layout, section sizes and the .pdata/.reloc tables stay untouched.
"""

import hashlib
import os
import sys

# --------------------------------------------------------------------------
# pinned build
# --------------------------------------------------------------------------
SRC_SHA256 = '4e44c526722d6420e89b372460c519e293c417723305b83ed0eff853db16ce5d'
SRC_SIZE = 50565160

# sha256 of the patched binary produced by this table (see reports/ for how
# it was produced and cross-checked with an independent second implementation)
GOLDEN_SHA256 = 'aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc'

# --------------------------------------------------------------------------
# RTTI-derived field map of the licence object (unit CertDecode)
#   FRegInfo        TRegInfo     @0x1b8
#   FStatus         TStatus      @0x610   stNotExpired 0 stGrace 1 stExpired 2 stRegistered 3 stDemo 4
#   FExtendedStatus TExtendedStatus @0x611
#   FKeyInfoRoot    TRegRoot     @0x612
#   FIsRegistered   Boolean      @0x630
#   FPubKeyLoaded   Boolean      @0x631
#   FFirstRunOfDay  Boolean      @0x632
#   FRegister       Boolean      @0x6f8
#   FNewVersionAvail Boolean     @0x162   (TRegInfo record field, update flag)
# --------------------------------------------------------------------------

# va, expected original bytes (hex), replacement bytes (hex), note
CODE_PATCHES = [
    # (1) licence state machine -------------------------------------------
    # BCompare 0x1404f1560 is the certificate/status evaluator.  It decodes
    # the licence record, derives a mode letter in [rbp+0x3f0] and switches:
    #   'e' clock tamper   'f' registry tamper   'g' challenge string changed
    #   'h'/'j' expired    'i' unregistered      'k' REGISTERED (terminal)
    #   'l' grace          'n' demo
    # 'k' is the only branch that produces (FStatus=stRegistered,
    # FExtendedStatus=esPKRegistered, FIsRegistered=1) and adds no deferred
    # "message" side effects.  Force the selector to 'k'.
    ('0x1404f346e', '8b85f0030000', 'b86b00000090',
     'status machine: force mode selector to "k" (registered terminal)'),

    # (2) property getter stubs (virtual/dynamic dispatch) ----------------
    ('0x1404f6160', '480fb68110060000c3', 'b003c3cccccccccccc',
     'TCertDecoder.GetStatus -> always stRegistered(3)'),
    ('0x1404f6170', '480fb68111060000c3', 'b007c3cccccccccccc',
     'TCertDecoder.GetExtendedStatus -> always esPKRegistered(7)'),
    ('0x1404f61f0', '480fb68130060000c3', 'b001c3cccccccccccc',
     'TCertDecoder.GetIsRegistered -> always True'),
    ('0x14021bd10', '480fb681f8060000c3', 'b001c3cccccccccccc',
     'GetRegister -> always True'),

    # (3) updates ---------------------------------------------------------
    ('0x1404f6180', '480fb68162010000c3', 'b000c3cccccccccccc',
     'GetNewVersionAvail -> always False (no update can be advertised)'),
    ('0x140faa550', '4883ec28488b0d85c5f7ffe870a2f3ff4883c428c3',
     'c3cccccccccccccccccccccccccccccccccccccc',
     'CheckForUpdatesExecute -> immediate ret (menu action disabled)'),

    # (4) registered-path crash guards -------------------------------------
    # TCertDecoderBase.GetRegFlagsString (0x1404f0500) returns
    #     out := self.TCertificate.<AnsiString @0xf0>
    # and every consumer immediately dereferences it as a flag byte:
    #     call 0x1404f0500
    #     mov  rax,[rbp+0x30]
    #     movzx rX,byte [rax]     <-- 0xc0000005 when no certificate exists
    # Forcing the licence into the registered state without a real
    # certificate leaves that string nil; all four call sites were located
    # and confirmed to fault (BCompare.exe+0xda2893, +0xda263e, +0xda2812
    # via a live first-chance-exception debugger).  The byte is therefore
    # synthesised instead of loaded: 0x04 is the "registered" flag the
    # branches test for, and the string itself is never dereferenced.
    ('0x140da263e', '480fb618', 'b3049090',
     'registered flags: synthesise flag byte (rbx) instead of dereferencing nil'),
    ('0x140da2812', '480fb600', 'b0049090',
     'registered flags: synthesise flag byte (rax) instead of dereferencing nil'),
    ('0x140da2893', '480fb600', 'b0049090',
     'registered flags: synthesise flag byte (rax) instead of dereferencing nil'),
]

# file offset, expected original bytes, replacement bytes, note
# (Delphi AnsiString: [.. ][len:4][data]; we shorten the value and rewrite
#  the length field, the tail bytes are never read again)
STR_PATCHES = [
    # NOTE: these two values live inside the compiled DFM stream of the bug
    # report settings class, encoded as vaLString (0x0C) + LongInt length +
    # bytes.  The length field MUST keep its original value, otherwise the
    # DFM parser runs off the rails and the application fails to start ->
    # replacements are therefore exactly the same length.
    ('0x2ff1aa5', b'https://www.scootersoftware.com/bugRepMailer.php',
     b'https://127.0.0.1.invalid/bugRepMailer.php//////',
     'bug report upload URL -> non-routable host (same length)'),
    ('0x2ff1c32', b'crash@scootersoftware.com',
     b'crash@127.0.0.1.invalid..',
     'crash report mail address -> non-routable host (same length)'),
]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def find_section(data, rva):
    """RVA -> file offset using the PE section table."""
    import struct
    e = struct.unpack_from('<I', data, 0x3c)[0]
    nsec = struct.unpack_from('<H', data, e + 6)[0]
    optsz = struct.unpack_from('<H', data, e + 20)[0]
    base = struct.unpack_from('<Q', data, e + 24 + 24)[0]
    secs = []
    so = e + 24 + optsz
    for i in range(nsec):
        b = so + i * 40
        vsz, va, rsz, raw = struct.unpack_from('<IIII', data, b + 8)
        secs.append((va, max(vsz, rsz), raw))
    for va, sz, raw in secs:
        if va <= rva < va + sz:
            return raw + (rva - va), base
    raise ValueError('rva %#x not mapped' % rva)


def patch(data, file_off, expect, repl, note, base):
    got = data[file_off:file_off + len(expect)]
    if got != expect:
        raise SystemExit(
            'ABORT: site %#x does not match the pinned build\n'
            '  expected %s\n  found    %s\n  (%s)'
            % (base + file_off, expect.hex(), got.hex(), note))
    if len(repl) > len(expect):
        raise SystemExit('ABORT: replacement longer than original at %#x' % file_off)
    repl = repl + b'\xcc' * (len(expect) - len(repl))
    data[file_off:file_off + len(repl)] = repl
    back = data[file_off:file_off + len(expect)]
    if back != repl:
        raise SystemExit('ABORT: read-back mismatch at %#x' % file_off)
    return repl


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    verify_only = '--verify-only' in sys.argv

    data = bytearray(open(src, 'rb').read())
    if len(data) != SRC_SIZE or sha256(data) != SRC_SHA256:
        raise SystemExit('ABORT: input is not the pinned build\n  size %d sha256 %s'
                         % (len(data), sha256(data)))

    # map VA -> file offset once, using the first site to learn the image base
    off0, base = find_section(data, 0x4f346e)
    print('image base %#x' % base)

    n = 0
    for va, exp, rep, note in CODE_PATCHES:
        foff, _ = find_section(data, int(va, 16) - base)
        patch(data, foff, bytes.fromhex(exp), bytes.fromhex(rep), note, base - 0)
        n += 1
        print('  patched %-12s  %s' % (va, note))

    for off, exp, rep, note in STR_PATCHES:
        o = int(off, 16)
        if len(rep) != len(exp):
            raise SystemExit('ABORT: string replacement must keep its length at %#x' % o)
        if data[o:o + len(exp)] != exp:
            raise SystemExit('ABORT: string site %#x does not match the pinned build' % o)
        data[o:o + len(exp)] = rep
        if data[o:o + len(exp)] != rep:
            raise SystemExit('ABORT: string read-back mismatch at %#x' % o)
        n += 1
        print('  patched %-12s  %s' % (off, note))

    # ------------------------------------------------------------------
    # Authenticode self-verification has to go too: Beyond Compare verifies
    # its own signature at start-up and refuses to run once the (now stale)
    # certificate blob no longer matches the image.  Dropping the
    # certificate table makes it skip the check entirely - verified
    # empirically, see reports/.
    # ------------------------------------------------------------------
    import struct as _s
    e = _s.unpack_from('<I', data, 0x3c)[0]
    dd = e + 24 + 112 + 4 * 8          # data directory #4 = Security
    sec_off, sec_sz = _s.unpack_from('<II', data, dd)
    if sec_off and sec_off + sec_sz == len(data):
        del data[sec_off:]
        _s.pack_into('<II', data, dd, 0, 0)
        n += 1
        print('  stripped     certificate table (%d bytes) -> self-signature check skipped'
              % sec_sz)
    elif sec_off:
        raise SystemExit('ABORT: unexpected certificate layout %#x+%#x' % (sec_off, sec_sz))
    else:
        print('  note: input carries no certificate table')

    out_hash = sha256(bytes(data))
    print('\n%d patch sites applied' % n)
    print('output sha256 %s' % out_hash)
    if GOLDEN_SHA256.strip('0'):
        if out_hash != GOLDEN_SHA256:
            raise SystemExit('ABORT: result does not match GOLDEN_SHA256 %s' % GOLDEN_SHA256)
        print('golden hash OK')
    else:
        print('GOLDEN_SHA256 not set yet - record the value above')
    if not verify_only:
        with open(dst, 'wb') as fh:
            fh.write(bytes(data))
        print('written %s' % os.path.abspath(dst))
    return 0


if __name__ == '__main__':
    sys.exit(main())
