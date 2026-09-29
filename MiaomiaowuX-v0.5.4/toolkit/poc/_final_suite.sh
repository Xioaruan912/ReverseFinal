#!/bin/bash
R=/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/reports
LOG=$R/FINAL_VERIFICATION.txt
cd /root/mmwx/pw
export PATH=/root/.nvm/versions/node/v22.23.2/bin:$PATH
cp -f /mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/poc/*.js /root/mmwx/pw/ 2>/dev/null
{
echo "================================================================================"
echo " 妙妙屋X (miaomiaowux) v0.5.4 —— 白盒鉴权脆弱性 最终验证"
echo " A/B：官方原版 12889  vs  破解版 12890（同一客户端、同一操作序列）"
echo " 破解产物 sha256: 1c1a55979845da533ebe305c6602f411ce32c2d2936938320ae200f3c0636e1c"
echo "================================================================================"
echo
echo "############ [0] 环境指纹 ############"
for p in 12889 12890; do printf "port %s GET / -> " $p; curl -s http://127.0.0.1:$p/ | grep -oE "var ps = '[a-z]+'"; done
echo
echo "############ [1] VIP/PRO 特性 + 高级主题 ############"
node verify_crack_theme.js
echo
echo "############ [2] 许可状态 / 配额面板 ############"
node verify_quota_api.js
echo
echo "############ [3] 用户数量配额（服务端） ############"
node verify_quota_server.js
echo
echo "############ [4] 服务器数量配额（服务端） ############"
node verify_quota_servers2.js
echo
echo "############ [5] 数据库终态（唯一真相） ############"
python3 - <<'PY'
import sqlite3
for tag,db in [('ORIGINAL 12889','/root/mmwx/run/data/mmwx.db'),('CRACKED  12890','/root/mmwx/crack/data/mmwx.db')]:
    c=sqlite3.connect(f'file:{db}?mode=ro',uri=True)
    q=lambda s: c.execute(s).fetchone()[0]
    print(f"  {tag}:  users={q('select count(*) from users')-1}  servers={q('select count(*) from remote_servers')}  nodes={q('select count(*) from nodes')}")
    print(f"            server names = {[r[0] for r in c.execute('select name from remote_servers')]}")
PY
echo
echo "############ [6] 补丁点反汇编复核 ############"
B=/root/mmwx/crack/mmwx-cracked
for va in 0x17b4180 0x17b44a0 0x17b3180 0x17b3a20 0x2acb6a0 0x2b3a2e0 0xdc3a80 0xc3e760 0x285aa89; do
  printf "  VA %-11s : " $va
  objdump -d --start-address=$va --stop-address=$((va+11)) -M intel $B | sed -n '/>:/,$p' | tail -n +2 | head -3 | tr -s ' ' | tr '\n' '|'
  echo
done
} > $LOG 2>&1
echo "exit=$?"
wc -l $LOG
