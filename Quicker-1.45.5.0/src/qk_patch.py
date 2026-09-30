#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Quicker 1.45.5.0 - whitebox client-authorisation patch driver (CWE-602).

Two independent edits are produced:

  A. VIP unlock  -- Quicker.Common.dll
     14 licence-DTO accessors are rewritten to return constant Pro/unlimited
     values.  These are the *only* place the client stores its authorisation
     state, so every consumer (feature gates, quota checks, panel display)
     sees a Pro account with the quota ceilings lifted.

  B. Update kill / upstream detach -- NOT deployable as a binary patch
     Quicker.exe carries a valid Authenticode signature and its embedded
     manifest requests uiAccess="true".  Windows only grants UIAccess to
     Authenticode-valid images, so *any* byte edit either
        (a) makes CreateProcess fail with ERROR_ELEVATION_REQUIRED, or
        (b) crashes the process at start-up if the manifest is relaxed to
            uiAccess="false" (verified by bisect; see reports/).
     Therefore the version-update entry points and the upstream endpoints are
     neutralised at the DNS layer instead -- `qk_hosts_block` is emitted by
     this tool and applied by the installer.  `--with-exe` still builds the
     patched exe for completeness/evidence, but it is not installed.

Why the IL rewrite works (the finding that unblocked this case)
--------------------------------------------------------------
A method body's last byte must be the terminating `ret`.  Padding a constant
return with NOPs *after* the `ret` -- the obvious thing to do -- makes the CLR
raise InvalidProgramException for that method.  Padding *before* it is fine.
Earlier work mis-read that symptom as a method-body integrity guard; it is
simply an IL stream that the importer refuses to consume.

Usage
-----
  python qk_patch.py <install_dir> <out_dir>
  python qk_patch.py <install_dir> <out_dir> --with-exe
  python qk_patch.py <install_dir> <out_dir> --hosts out_hosts_block.txt
  python qk_patch.py <install_dir> <out_dir> --dry-run
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peil

# ---------------------------------------------------------------- pinned inputs
SRC_SHA = {
    'Quicker.Common.dll': '838e949d15b376c087b2bf0d00bf14f3c6c1b0e122a06ffea4213c800f71a594',
    'Quicker.exe':        'ac815c9280dee1ff2e476da5f6035a0451d07d3c0c4e12a02f0861f19fd4d8bd',
}
GOLDEN = {
    'Quicker.Common.dll': '3924e21d208fb2a90c0c241a2806365979fe1838a9ea297e3f874fd6c45c421c',
    'Quicker.exe':        '',
}

# ---------------------------------------------------------- A. licence unlock
# (declaring type, method, ret kind, value)
LICENCE = [
    ('UserInfo',        'get_MemberLevel',          'enum', 3),
    ('UserLimitation',  'get_CanUseMobileApp',      'bool', 1),
    ('UserLimitation',  'get_LockButton',           'bool', 0),
    ('UserLimitation',  'get_EnableActionHistory',  'bool', 1),
    ('UserLimitation',  'get_EnableActionHotKey',   'bool', 1),
    ('UserLimitation',  'get_EnableStarter',        'bool', 1),
    ('UserLimitation',  'get_EnableFloatButton',    'bool', 1),
    ('UserLimitation',  'get_EnableSearching',      'bool', 1),
    ('UserLimitation',  'get_MaxPcCount',           'int', 999),
    ('UserLimitation',  'get_MaxExeCount',          'int', 999),
    ('UserLimitation',  'get_MaxPagePerExe',        'int', 999),
    ('UserLimitation',  'get_MaxPageFileSize',      'int', 102400),
    ('UserLimitation',  'get_TotalPageFileSize',    'int', 1048576),
    ('UserLimitation',  'get_MaxIconCount',         'int', 9999),
]

# ------------------------------------------------------------- B. update kill
UPDATE_KILL = [
    ('.SoftVersionHelper',           'CheckVersionUpdateAfterFirstSync', 'void'),
    ('<MenuCheckUpdate_OnClick>',    'MoveNext', 'void'),
    ('<MenuUpdateVersion_OnClick>',  'MoveNext', 'void'),
    ('<BtnCheckVersion_OnClick>',    'MoveNext', 'void'),
]

UIACCESS_OLD = b'uiAccess="true" />'
UIACCESS_NEW = b'uiAccess="false"/>'      # same length: no manifest surgery

# ------------------------------------------------------- C. upstream detach
SINK_TLD = '.invalid'
UPSTREAM = [
    'getquicker.net',
    'getquicker.cn',
    'getquicker.',
    'oss-cn-shanghai',
    'oss-accelerate',
    'quicker-temp.bj.bcebos.com',
]
# concrete hostnames that must resolve nowhere (hosts file has no wildcards)
SINK_HOSTS = [
    'getquicker.net', 'api.getquicker.net', 'files.getquicker.net',
    'cc.getquicker.net', 'temp.getquicker.net', 'download.getquicker.net',
    'getquicker.cn', 'data.getquicker.cn', 'connect.getquicker.cn',
    'ocr.getquicker.cn', 'files.getquicker.cn', 'tools.getquicker.cn',
    'tmpimg.getquicker.cn', 'helperservice.getquicker.cn', 'aiproxy.getquicker.cn',
    'quicker-temp.bj.bcebos.com',
    'quickeruserdata.oss-cn-shanghai.aliyuncs.com',
    'deskpad.oss-cn-shanghai.aliyuncs.com',
    'quickeruserdata.oss-accelerate.aliyuncs.com',
]
HOSTS_BEGIN = '# --- QuickerLab upstream sinkhole (managed block) ---'
HOSTS_END = '# --- end QuickerLab upstream sinkhole ---'


def sink_for(old, seed='void'):
    """Equal-length replacement name under the RFC-6761 reserved .invalid TLD."""
    label_len = len(old) - len(SINK_TLD)
    if label_len < 1:
        raise ValueError('too short to sink: %r' % old)
    return (seed + '0' * label_len)[:label_len] + SINK_TLD


def body_const(ret, value):
    """IL that returns a constant.  `ret` MUST be the final byte."""
    if ret == 'void':
        return b'\x2a'
    if ret == 'bool':
        return (b'\x17' if value else b'\x16') + b'\x2a'
    if ret in ('int', 'enum'):
        return b'\x20' + struct.pack('<i', value) + b'\x2a'
    if ret in ('string', 'class', 'object'):
        return b'\x14\x2a'
    raise ValueError('unsupported return kind %r' % ret)


def find_method(md, type_marker, method):
    hits = []
    for rid, t, m, rva, sig in peil.method_rows(md):
        if m != method or not rva:
            continue
        if type_marker.startswith('<'):
            if type_marker in t:
                hits.append((rid, t, m, rva, sig))
        elif t.endswith(type_marker) or t == type_marker or t.split('.')[-1] == type_marker:
            hits.append((rid, t, m, rva, sig))
    return hits


def write_stub(data, header_off, il):
    """Convert the method at header_off into a tiny-header body carrying `il`.

    Tiny header = (code_size << 2) | 0x02.  The old fat header (MaxStack,
    LocalVarSigTok, EH clauses) becomes unreferenced dead bytes -- the CLR only
    ever reads the header the MethodDef RVA points at.
    """
    assert 1 <= len(il) <= 63 and il[-1] == 0x2a, il.hex()
    hdr = ((len(il) << 2) | 0x02) & 0xFF
    data[header_off] = hdr
    data[header_off + 1:header_off + 1 + len(il)] = il
    return bytes(data[header_off:header_off + 1 + len(il)]) == bytes([hdr]) + il


def patch_licence(data, log):
    md = peil.MD(bytes(data))
    done = 0
    for type_name, method, ret, value in LICENCE:
        hits = find_method(md, type_name, method)
        if len(hits) != 1:
            raise SystemExit('ABORT: %s::%s -> %d matches' % (type_name, method, len(hits)))
        rid, tname, mname, rva, sig = hits[0]
        real_ret = peil.retsig(md, sig)
        if ret == 'enum' and real_ret == 'valuetype':
            kind = 'enum'
        elif ret == 'int' and real_ret == 'int32':
            kind = 'int'
        elif ret == 'bool' and real_ret == 'bool':
            kind = 'bool'
        else:
            raise SystemExit('ABORT: %s::%s return type is %s, expected %s'
                             % (type_name, method, real_ret, ret))

        off = peil.rva2off(md.secs, rva)
        code_off, code_size, hdr = peil.il_body(bytes(data), off)
        old = bytes(data[code_off:code_off + code_size])
        if not (code_size == 7 and old[0] == 0x02 and old[1] == 0x7B and old[6] == 0x2A):
            raise SystemExit('ABORT: %s::%s unexpected body %s' % (tname, mname, old.hex()))

        tok, = struct.unpack_from('<I', old, 2)
        fsig = peil.field_sig(md, tok & 0xFFFFFF)
        elem = fsig[1] if len(fsig) > 1 else None
        want_elem = {'bool': 0x02, 'int': 0x08, 'enum': 0x11}[ret]
        if elem != want_elem:
            raise SystemExit('ABORT: %s::%s field elem %s != %s'
                             % (tname, mname, hex(elem) if elem else '?', hex(want_elem)))

        il = body_const(kind, value)
        new = b'\x00' * (code_size - len(il)) + il       # ret stays last
        assert len(new) == code_size and new[-1] == 0x2A
        data[code_off:code_off + code_size] = new
        if bytes(data[code_off:code_off + code_size]) != new:
            raise SystemExit('ABORT: read-back mismatch at %s::%s' % (tname, mname))
        log('  [VIP] %-46s %s -> %s' % (tname.split('.')[-1] + '::' + mname,
                                        old.hex(' '), new.hex(' ')))
        done += 1
    return done


def patch_update(data, log):
    md = peil.MD(bytes(data))
    done = 0
    for marker, method, expect in UPDATE_KILL:
        hits = find_method(md, marker, method)
        if len(hits) != 1:
            raise SystemExit('ABORT: %s?::%s -> %d matches' % (marker, method, len(hits)))
        rid, tname, mname, rva, sig = hits[0]
        real_ret = peil.retsig(md, sig)
        if real_ret != expect:
            raise SystemExit('ABORT: %s::%s return %s != %s' % (tname, mname, real_ret, expect))
        off = peil.rva2off(md.secs, rva)
        hdr_byte = data[off]
        if not write_stub(data, off, b'\x2a'):
            raise SystemExit('ABORT: stub read-back mismatch at ' + tname)
        log('  [UPD] %-46s %s -> tiny stub' % (tname.split('.')[-1] + '::' + mname,
                                               'hdr %#04x' % hdr_byte))
        done += 1
    return done


def relax_uiaccess(data, log):
    assert len(UIACCESS_OLD) == len(UIACCESS_NEW)
    n, i = 0, data.find(UIACCESS_OLD)
    while i >= 0:
        data[i:i + len(UIACCESS_OLD)] = UIACCESS_NEW
        if bytes(data[i:i + len(UIACCESS_NEW)]) != UIACCESS_NEW:
            raise SystemExit('ABORT: read-back mismatch relaxing uiAccess')
        n += 1
        i = data.find(UIACCESS_OLD, i + len(UIACCESS_NEW))
    if n != 1:
        raise SystemExit('ABORT: expected exactly 1 active uiAccess element, got %d' % n)
    log('  [MAN] embedded manifest uiAccess="true" -> "false"  (x%d)' % n)
    return n


def detach_upstream(data, log):
    total = 0
    for host in UPSTREAM:
        new = sink_for(host)
        assert len(new) == len(host)
        for enc in ('latin1', 'utf-16-le'):
            pat, rep = host.encode(enc), new.encode(enc)
            n, i = 0, data.find(pat)
            while i >= 0:
                data[i:i + len(pat)] = rep
                if bytes(data[i:i + len(pat)]) != rep:
                    raise SystemExit('ABORT: read-back mismatch sinking ' + host)
                n += 1
                i = data.find(pat, i + len(pat))
            if n:
                log('  [NET] %-30s -> %-30s %s x%d' % (host, new, enc, n))
                total += n
    return total


def hosts_block():
    out = [HOSTS_BEGIN]
    for h in SINK_HOSTS:
        out.append('0.0.0.0 ' + h)
    out.append(HOSTS_END)
    return '\r\n'.join(out) + '\r\n'


def verify_artifacts(src_dir, out_dir):
    """Independent re-check: offsets + bytes re-read from the produced file."""
    src = open(os.path.join(src_dir, 'Quicker.Common.dll'), 'rb').read()
    dst = open(os.path.join(out_dir, 'Quicker.Common.dll'), 'rb').read()
    md = peil.MD(src)
    bad = 0
    for type_name, method, ret, value in LICENCE:
        hits = find_method(md, type_name, method)
        rid, t, m, rva, sig = hits[0]
        off = peil.rva2off(md.secs, rva)
        co, cs, _ = peil.il_body(src, off)
        il = body_const(ret, value)
        want = b'\x00' * (cs - len(il)) + il
        got = dst[co:co + cs]
        if got != want:
            print('   VERIFY FAIL %s::%s' % (t, m)); bad += 1
    return bad


def process(src_dir, out_dir, dry_run, with_exe, log):
    plan = {'Quicker.Common.dll': (patch_licence, detach_upstream)}
    if with_exe:
        plan['Quicker.exe'] = (relax_uiaccess, patch_update, detach_upstream)
    artifacts = {}
    for name, funcs in plan.items():
        src = os.path.join(src_dir, name)
        data = bytearray(open(src, 'rb').read())
        got = hashlib.sha256(bytes(data)).hexdigest()
        pinned = SRC_SHA.get(name, '')
        if pinned and got != pinned:
            raise SystemExit('ABORT: %s sha256 %s != pinned %s' % (name, got, pinned))
        log('== %s  (%d bytes, sha256 %s)' % (name, len(data), got[:16]))
        for f in funcs:
            f(data, log)
        out = os.path.join(out_dir, name)
        artifacts[name] = hashlib.sha256(bytes(data)).hexdigest()
        if not dry_run:
            open(out, 'wb').write(bytes(data))
        log('   -> %s' % out)
        log('      sha256 %s' % artifacts[name])
        log('')
    return artifacts


def main():
    argv = sys.argv[1:]
    flags = [a for a in argv if a.startswith('--')]
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in flags
    with_exe = '--with-exe' in flags
    hosts_path = None
    if '--hosts' in flags:
        hosts_path = argv[argv.index('--hosts') + 1]
        if hosts_path in args:
            args.remove(hosts_path)
    if len(args) < 2:
        print(__doc__)
        return 2
    src_dir, out_dir = args[0], args[1]
    if not dry:
        os.makedirs(out_dir, exist_ok=True)
    lines = []
    log = lines.append
    arts = process(src_dir, out_dir, dry, with_exe, log)
    if hosts_path and not dry:
        open(hosts_path, 'wb').write(hosts_block().encode('ascii'))
        log('== hosts sinkhole block -> %s (%d hosts)' % (hosts_path, len(SINK_HOSTS)))
        log('')
    print('\n'.join(lines))
    if not dry:
        bad = verify_artifacts(src_dir, out_dir)
        print('independent re-verification: %s' % ('FAILED (%d sites)' % bad if bad else 'all 14 sites OK'))
    print('---- golden hashes ----')
    ok = True
    for k, v in arts.items():
        g = GOLDEN.get(k, '')
        state = 'pinned-ok' if (g and g == v) else ('PIN-NOW' if not g else 'MISMATCH')
        if state == 'MISMATCH':
            ok = False
        print('  %-22s %s  [%s]' % (k, v, state))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
