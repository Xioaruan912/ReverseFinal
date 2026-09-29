import struct, json

BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read(); n=len(d)
PCLN_OFF=0x582b7a0; PCLN_VA=0x5c2b7a0; TEXT_VA=0x401000; TEXT_OFF=0x1000

print("first 32 bytes at pclntab:", d[PCLN_OFF:PCLN_OFF+32].hex())
magic,pad1,pad2,minLC,ptrSize=struct.unpack_from('<IBBBB',d,PCLN_OFF)
print(f"magic={hex(magic)} minLC={minLC} ptrSize={ptrSize}")
(nfunc,nfiles,textStart,funcnameOffset,cuOffset,filetabOffset,pctabOffset,pclnOffset)=struct.unpack_from('<QQQQQQQQ',d,PCLN_OFF+8)
print(f"nfunc={nfunc} nfiles={nfiles} textStart={hex(textStart)} nameOff={hex(funcnameOffset)} cuOff={hex(cuOffset)} filetabOff={hex(filetabOffset)} pctabOff={hex(pctabOffset)} pclnOff={hex(pclnOffset)}")
