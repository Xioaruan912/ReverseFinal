import struct, re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read(); n=len(d)
for magic in (0xfffffff1,0xfffffff0):
    pat=struct.pack('<I',magic)
    c=0
    for m in re.finditer(re.escape(pat), d):
        off=m.start()
        if off+72>n: continue
        magic_,pad1,pad2,minLC,ptrSize=struct.unpack_from('<IBBBB',d,off)
        (nfunc,nfiles,textStart,funcnameOffset,cuOffset,filetabOffset,pctabOffset,pclnOffset)=struct.unpack_from('<QQQQQQQQ',d,off+8)
        if ptrSize in (4,8) and minLC in (1,2,4) and 1000<nfunc<1000000 and 0x400000<=textStart<0x20000000:
            print(f"HIT off={hex(off)} m={hex(magic)} ptr={ptrSize} minLC={minLC} nfunc={nfunc} nfiles={nfiles} textStart={hex(textStart)} nameOff={hex(funcnameOffset)} ftab_off={hex(off+8+64)}")
            c+=1
            if c>6: break
    print(f"--- magic {hex(magic)} plausible: {c}")
