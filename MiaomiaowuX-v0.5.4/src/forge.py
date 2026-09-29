import sqlite3, json, sys, shutil, time
DB='/root/mmwx/run/data/mmwx.db'
shutil.copy(DB, DB+'.bak-%d'%time.time())
forged = {
  "valid": True,
  "max_servers": 999,
  "expires_at": "2099-12-31T23:59:59Z",
  "plan": {
    "name": "PRO",
    "display_name": "专业版",
    "description": "forged-by-lab",
    "max_servers": 999,
    "max_nodes": 9999,
    "max_users": 9999,
    "features": ["speed_test","limiter","server_share","embedded","reality_pool"]
  },
  "sig": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
  "entitlement": "Zm9yZ2VkLWVudGl0bGVtZW50.fG9yZ2VkLXBheWxvYWQ=.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
  "signing_key_certificate": "",
  "entitlement_session_sig": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
  "master_public_key": "",
  "last_check": "2099-12-31T23:59:59Z"
}
c=sqlite3.connect(DB)
c.execute("insert into system_settings(key,value,updated_at) values('license_status',?,datetime('now')) on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at", (json.dumps(forged, ensure_ascii=False),))
c.commit()
print("written:")
for k,v,u in c.execute("select key,value,updated_at from system_settings where key like 'license%'"):
    print(" ", k, "=", v[:400])
