PID=$(pgrep -x mmwx | head -1)
echo "PID=$PID"
python3 - "$PID" <<'PY'
import sys
pid=sys.argv[1]
maps=open(f'/proc/{pid}/maps').read().splitlines()
out=open('/root/mmwx/dump/heap2.bin','wb')
mem=open(f'/proc/{pid}/mem','rb',0)
tot=0
for line in maps:
    p=line.split()
    if len(p)<2 or 'r' not in p[1]: continue
    a,b=[int(x,16) for x in p[0].split('-')]
    if b-a>200*1024*1024: continue
    try:
        mem.seek(a); out.write(mem.read(b-a)); tot+=b-a
    except Exception: pass
out.close()
print("dumped MB", tot//1024//1024)
PY
