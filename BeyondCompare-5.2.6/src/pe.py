import struct, sys
class PE:
    def __init__(s, path):
        s.path = path
        s.d = open(path,'rb').read()
        e = struct.unpack_from('<I', s.d, 0x3c)[0]
        assert s.d[e:e+4] == b'PE\0\0', 'no PE'
        s.nsec = struct.unpack_from('<H', s.d, e+6)[0]
        optsz  = struct.unpack_from('<H', s.d, e+20)[0]
        s.opt = e+24
        magic = struct.unpack_from('<H', s.d, s.opt)[0]
        s.pe32 = (magic == 0x10b)
        if s.pe32: s.imgbase = struct.unpack_from('<I', s.d, s.opt+28)[0]
        else:      s.imgbase = struct.unpack_from('<Q', s.d, s.opt+24)[0]
        s.secs = []
        so = s.opt + optsz
        for i in range(s.nsec):
            b = so + i*40
            name = s.d[b:b+8].rstrip(b'\0').decode('latin1')
            vsz, va, rsz, raw = struct.unpack_from('<IIII', s.d, b+8)
            s.secs.append(dict(name=name, va=va, vsz=vsz, raw=raw, rsz=rsz))
    def off2va(s, off):
        for x in s.secs:
            if x['raw'] <= off < x['raw']+max(x['rsz'],x['vsz']):
                return s.imgbase + x['va'] + (off - x['raw'])
        return None
    def va2off(s, va):
        r = va - s.imgbase
        for x in s.secs:
            if x['va'] <= r < x['va']+max(x['rsz'],x['vsz']):
                o = x['raw'] + (r - x['va'])
                if o < len(s.d): return o
        return None
    def sec_of_va(s, va):
        r = va - s.imgbase
        for x in s.secs:
            if x['va'] <= r < x['va']+x['vsz']: return x['name']
        return None
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def u64(d,o): return struct.unpack_from('<Q',d,o)[0]
