BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TARGETS=[
 ("HasFeature",              0x17b4180, 24),
 ("HasFeatureForDataPlane",  0x17b44a0, 24),
 ("QuotaEnforced",           0x17b3180, 24),
 ("EffectiveUserQuota",      0x17b3a20, 24),
 ("EffectiveServerQuota",    0x17b3280, 24),
 ("EffectiveNodeQuota",      0x17b37c0, 24),
]
for name,va,l in TARGETS:
    off=va-0x400000
    print(f"{name:26s} VA={hex(va)} FILEOFF={hex(off)} orig={d[off:off+l].hex(' ')}")
