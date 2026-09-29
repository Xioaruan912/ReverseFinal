/* ============================================================================
 * HexHub —— 完全离线「模拟登录」PoC（登录场景下的鉴权旁路）
 * ----------------------------------------------------------------------------
 * 目的：在【没有任何真实账号】的情况下，让客户端认为"已登录 + 已同步"，
 *       并把会员等级置为终身 Plus。
 *
 * 原理（逆向自内嵌 bundle）：
 *   Xs(priKey, token):
 *     n = GET https://api.hexhub.cn/client/member/currentv2   (Authorization: token)
 *     priKey -> PEM -> RSA-2048 (WASM 实现)
 *     member = JSON.parse( concat( RSA_PKCS1v15_decrypt(chunk) for chunk in n ) )
 *   ue(member): SHA256(`${endTime}*${email}*${SHA256(publicKey)}`) === member.sign
 *
 *   ⇒ 私钥在客户端本地（priKey），服务端只是"用客户端公钥加密后下发"。
 *     攻击者自建一对 RSA-2048 密钥、把 priKey 塞进本地会话、把 currentv2 响应
 *     替换成"用自己公钥加密的伪造会员 JSON"，客户端就会完整走通登录流程。
 *     所谓"服务端下发"在此完全不构成信任锚。
 * ============================================================================ */
const { chromium } = require('playwright');
const crypto = require('crypto');

const PORT = process.env.HEXHUB_CDP_PORT || '9222';
// ★ 完整性校验用的是 SHA-1（不是 SHA-256）：crypto chunk 导出 S = _createHelper(SHA1Algo)
const sha1hex = s => crypto.createHash('sha1').update(s, 'utf8').digest('hex');

/* ---------- 1. 自建 RSA-2048 密钥对（完全离线，无需服务端） ---------- */
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const priKeyB64 = privateKey.export({ type: 'pkcs8', format: 'der' }).toString('base64');
console.log(`[i] 已生成自建 RSA-2048 密钥对，priKey(base64 PKCS#8) 长度=${priKeyB64.length}`);

/* ---------- 2. 伪造会员对象（sign 为客户端可离线自算的自证式哈希） ---------- */
const ENDTIME = 2524579200000;
const EMAIL   = 'audit@hexhub.local';
const PUBKEY  = 'audit-pubkey';
const SIGN    = sha1hex(`${ENDTIME}*${EMAIL}*${sha1hex(PUBKEY)}`);

const MEMBER = {
  id: 1000001, memberId: 1000001,
  email: EMAIL, name: 'AuditTester',
  endTime: ENDTIME, isPlus: true,
  publicKey: PUBKEY, sign: SIGN,
};

/* ---------- 3. 用自建公钥加密会员 JSON，切成 PKCS1v15 允许的分片 ---------- */
const CHUNK = 245;                      // RSA-2048 PKCS#1 v1.5 最大明文 245 字节
const payload = Buffer.from(JSON.stringify(MEMBER), 'utf8');
const chunks = [];
for (let i = 0; i < payload.length; i += CHUNK) {
  chunks.push(crypto.publicEncrypt(
    { key: publicKey, padding: crypto.constants.RSA_PKCS1_PADDING },
    payload.subarray(i, i + CHUNK)).toString('base64'));
}
console.log(`[i] 会员 JSON ${payload.length} 字节 -> ${chunks.length} 个 RSA 分片`);

const SESSION = { token: 'offline-sim-token', priKey: priKeyB64, member: null };

(async () => {
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`);
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });
  console.log(`[i] 目标页面: ${page.url()}`);

  /* ---- 4. 拦截所有厂商接口：member 用伪造响应，其余全部阻断 ---- */
  // 单一处理器按 URL 分流：member 接口 -> 伪造响应；其余厂商接口 -> 阻断
  const handle = route => {
    const u = route.request().url();
    if (u.includes('/client/member/currentv2')) {
      console.log('  [route] currentv2 -> 伪造响应');
      // 响应信封（逆向自 axios 响应拦截器）：{code:0,msg,data} -> 拦截器返回 .data
      return route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ code: 0, msg: 'ok', data: chunks }) });
    }
    return route.abort('connectionfailed');
  };
  await page.route('**://api.hexhub.cn/**', handle);
  await page.route('**://oss.hexhub.cn/**', handle);
  console.log('[+] currentv2 -> 伪造响应；其余厂商接口 -> 阻断');

  /* ---- 5. 写入会话（member 留空，交给客户端自己"从服务端拉取"） ---- */
  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  console.log('[+] 已写入 token + 自建 priKey（member 置空，考验完整拉取链路）');

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(14000);

  /* ---- 6. 取证 ---- */
  const r = await page.evaluate(() => {
    const txt = document.body.innerText;
    const crowns = [...document.querySelectorAll('.mdi-crown')];
    let sess = {};
    try { sess = JSON.parse(localStorage.getItem('session') || '{}'); } catch (e) {}
    return {
      crownCount: crowns.length,
      hasPlusLabel: /(^|\n)\s*(Plus|Pro)\s*(\n|$)/.test(txt),
      memberFromServer: !!sess.member,                 // 客户端自己"拉取"到了会员
      email: sess.member ? sess.member.email : null,
      endTime: sess.member ? sess.member.endTime : null,
      isPlus: sess.member ? sess.member.isPlus : null,
      isLifetimeSentinel: !!(sess.member && sess.member.endTime >= 2524579200000),
      isMemberValid: !!(sess.member && sess.member.endTime > Date.now()),
      notLoggedIn: /请检查是否登录/.test(txt),
    };
  });

  console.log('\n=== 判定结果 ===');
  console.log(JSON.stringify(r, null, 2));
  console.log('\n=== 结论 ===');
  if (r.memberFromServer && r.isLifetimeSentinel && r.crownCount > 0) {
    console.log('  ✔ 完全离线模拟登录成功：客户端用【自建密钥】解出【伪造会员】并点亮 👑 Plus');
    console.log('  ✔ 说明 member 下发链路不构成信任锚 —— 私钥与签名算法都在客户端');
  } else if (r.memberFromServer) {
    console.log('  ~ 会员对象已被客户端接受，但 UI 未显示徽章，请人工核对');
  } else {
    console.log('  ✘ 未复现：客户端未接受伪造的 currentv2 响应（检查分片大小 / 响应结构）');
  }

  await page.screenshot({ path: 'exports/fake_login.png' });
  console.log('\n[+] 截图 -> exports/fake_login.png');
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
