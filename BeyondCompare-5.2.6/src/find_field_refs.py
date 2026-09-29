import sys, struct, re, collections, bisect
sys.path.insert(0,'.')
from pe import PE
from pdata import funcs
p,F=funcs(r'C:/Users/Administrator/Downloads/bc5-recon/extracted/BCompare.exe')
TEXTOFF=0x400; TEXTSZ=29997568; TEXTVA=0x1000
t=p.d[TEXTOFF:TEXTOFF+TEXTSZ]
starts=[s for s,e in F]
def func_of(va):
    i=bisect.bisect_right(starts, va)-1
    if i<0: return None
    s,e=F[i]
    return (s,e) if s<=va<e else None
# field offsets of interest
FIELDS={0x610:'FStatus',0x611:'FExtendedStatus',0x612:'FKeyInfoRoot',0x618:'FKeyInfoPath',0x620:'FKeyInfoKey',0x628:'FPKKey',
 0x630:'FIsRegistered',0x631:'FPubKeyLoaded',0x632:'FFirstRunOfDay',0x638:'FCertReject',0x648:'FCertRevoked',0x658:'FCertExpired',
 0x668:'FCertAccept',0x678:'FClockMovedBack',0x688:'FExpired',0x698:'FExtend',0x6a8:'FFirstStart',0x6b8:'FInGracePeriod',
 0x6c8:'FNoInitCert',0x6d8:'FRegInfoTamper',0x6e8:'FRegInfoChanged',0x6f8:'FRegister',0x708:'FRegWriteErr',0x718:'FReminder',
 0x728:'FReset',0x738:'FTrialInfoTamper',0x748:'FTerminate',0x758:'FWrongUnlockCode',0x768:'ctx',0x17d0:'FpXl',0x17d8:'FpXr',
 0x162:'FNewVersionAvail',0x168:'FNewVersionURL',0x1a8:'FLastError',0x1b8:'FRegInfo',0x1f0:'Fn',0x400:'Fe',0x158:'FScanLastModPath',
 0x160:'FMessageFlags',0x170:'FNow',0x178:'FExeName',0x1a0:'FRevokedSerials'}
S=set(FIELDS)
RX=re.compile(rb'(?:(?:\x66|\x67)?(?:[\x40-\x4f])?)'   # prefixes
              rb'(?:'
              rb'\x0f\xb6'      # movzx r32, r/m8
              rb'|\x0f\xbe'     # movsx
              rb'|\x8a|\x8b|\x88|\x89|\x8d|\x01|\x03|\x09|\x29|\x2b|\x39|\x3b|\x85|\xc6|\xc7|\x80|\xf6|\x83|\xfe|\xff|\xff\x50|\x0f\x10|\x0f\x11|\x0f\xb7'
              rb')'
              rb'[\x80-\x87\x40-\x7f](....)', re.S)
hits=collections.defaultdict(lambda: collections.defaultdict(set))  # func -> field -> {vas}
for m in RX.finditer(t):
    g=m.group(1)
    disp=None
    if len(g)==4: disp=struct.unpack('<i',g)[0]
    elif len(g)==1: disp=struct.unpack('<b',g)[0]
    if disp is None or disp not in S: continue
    if g[0] if len(g)==1 else True:
        pass
    va=p.imgbase+TEXTVA+m.start()
    fn=func_of(va)
    if not fn: continue
    hits[fn][disp].add(va)
scored=[]
for fn,mp in hits.items():
    if len(mp)>=3:
        scored.append((len(mp), sum(len(v) for v in mp.values()), fn, mp))
scored.sort(key=lambda x:(-x[0],-x[1]))
print('functions with >=3 distinct license fields:', len(scored))
for d,tot,fn,mp in scored[:40]:
    print('%#x-%#x distinct=%d total=%d : %s'%(fn[0],fn[1],d,tot, ', '.join('%s(%#x)x%d'%(FIELDS[k],k,len(v)) for k,v in sorted(mp.items()))[:400]))
