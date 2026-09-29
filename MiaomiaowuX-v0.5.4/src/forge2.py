import sqlite3, json, time, sys
DB='/root/mmwx/run/data/mmwx.db'
mode=sys.argv[1] if len(sys.argv)>1 else 'with-ent'
base = {
  "valid": True,
  "max_servers": 999,
  "expires_at": "2099-12-31T23:59:59Z",
  "last_check": "2099-12-31T23:59:59Z",
  "plan": {
    "name": "PRO", "display_name": "专业版", "description": "forged",
    "max_servers": 999, "max_nodes": 9999, "max_users": 9999,
    "features": ["speed_test","limiter","server_share","embedded","reality_pool"]
  },
}
if mode=='with-ent':
    base["entitlement"]="Zm9yZ2Vk.fG9yZ2Vk.AAAA"
    base["signing_key_certificate"]=""
    base["sig"]="AAAA"
elif mode=='no-ent':
    pass
c=sqlite3.connect(DB)
c.execute("insert into system_settings(key,value,updated_at) values('license_status',?,datetime('now')) on conflict(key) do update set value=excluded.value", (json.dumps(base,ensure_ascii=False),))
c.commit()
print("mode=%s written"%mode)
