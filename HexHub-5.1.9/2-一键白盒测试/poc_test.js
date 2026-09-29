/* ============================================================================
 * HexHub VIP 鉴权脆弱性 PoC（精简版 · 主流程）
 * ----------------------------------------------------------------------------
 * 只做三件事，不做任何系统改动、不做任何回滚：
 *   ① 页面级断网（Playwright route abort）—— 等价于"阻断厂商授权服务器比对"
 *   ② 注入伪造的 localStorage["session"] —— 会员判定 = member.endTime > Date.now()
 *   ③ 重载取证 —— 截图 + 控制台输出判定结果
 *
 * 环境变量：
 *   HEXHUB_CDP_PORT    CDP 端口（默认 9222）
 *   NEGATIVE_CONTROL   设为 1 时额外跑一次"服务器可达"的负向对照
 * ============================================================================ */
const { chromium } = require('playwright');
const crypto = require('crypto');

const PORT = process.env.HEXHUB_CDP_PORT || '9222';
const NEG  = process.env.NEGATIVE_CONTROL === '1';
// ★ 完整性校验用的是 SHA-1：sign = SHA1(`${endTime}*${email}*${SHA1(publicKey)}`)
const sha1hex = s => crypto.createHash('sha1').update(s, 'utf8').digest('hex');

/* ---------- 伪造会员对象 ----------
 * 客户端校验式（逆向自内嵌 bundle）：
 *   sign = SHA256(`${endTime}*${email}*${SHA256(publicKey)}`)   ← 自证式哈希，无密钥
 * 权益判据：
 *   isMemberValid() => member.endTime > Date.now()
 * endTime >= 2524579200000 (2050-01-01) 会被 UI 判为「终身版」
 * ---------------------------------- */
const ENDTIME = 2524579200000;
const EMAIL   = 'audit@hexhub.local';
const PUBKEY  = 'audit-pubkey';
const SIGN    = sha1hex(`${ENDTIME}*${EMAIL}*${sha1hex(PUBKEY)}`);

const SESSION = {
  token:  'forged-token-audit',
  priKey: 'forged-prikey-audit',
  member: {
    id: 1000001, memberId: 1000001,
    email: EMAIL, name: 'AuditTester',
    endTime: ENDTIME, isPlus: true,
    publicKey: PUBKEY, sign: SIGN,
  },
};

async function blockVendor(page) {
  await page.route('**://api.hexhub.cn/**', r => r.abort('connectionfailed'));
  await page.route('**://oss.hexhub.cn/**', r => r.abort('connectionfailed'));
}

async function probe(page) {
  return page.evaluate(() => {
    const txt = document.body.innerText;
    const crowns = [...document.querySelectorAll('.mdi-crown')];
    let sess = {};
    try { sess = JSON.parse(localStorage.getItem('session') || '{}'); } catch (e) {}
    return {
      crownCount: crowns.length,
      hasPlusLabel: /(^|\n)\s*(Plus|Pro)\s*(\n|$)/.test(txt),
      memberKept: !!sess.member,
      endTime: sess.member ? sess.member.endTime : null,
      isLifetimeSentinel: !!(sess.member && sess.member.endTime >= 2524579200000),
      isMemberValid: !!(sess.member && sess.member.endTime > Date.now()),
      notLoggedIn: /请检查是否登录/.test(txt),
    };
  });
}

(async () => {
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`);
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });
  console.log(`[i] 目标页面: ${page.url()}`);

  /* ---------------- 主用例：阻断厂商服务器 + 伪造会话 ---------------- */
  console.log('\n========== 用例 1：厂商服务器不可达 + 伪造会话 ==========');
  await blockVendor(page);
  console.log('[+] 已在页面级阻断 api.hexhub.cn / oss.hexhub.cn');

  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  console.log(`[+] 已注入伪造 session (sign=${SIGN.slice(0, 16)}...)`);

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(12000);

  const r1 = await probe(page);
  console.log(JSON.stringify(r1, null, 2));
  await page.screenshot({ path: 'exports/vip_bypass.png' });
  console.log('[+] 截图 -> exports/vip_bypass.png');

  const bypassed = r1.crownCount > 0 && r1.isLifetimeSentinel;
  console.log('\n【结论】' + (bypassed
    ? '✔ 漏洞成立：未登录 + 厂商服务器不可达，顶栏仍显示会员徽章 → VIP 鉴权旁路成功'
    : '✘ 未复现，请检查断网/注入是否生效'));

  /* ---------------- 可选：负向对照 ---------------- */
  if (NEG) {
    console.log('\n========== 用例 2（负向对照）：服务器可达 ==========');
    await page.unroute('**://api.hexhub.cn/**');
    await page.unroute('**://oss.hexhub.cn/**');
    await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(10000);
    const after = await page.evaluate(() => localStorage.getItem('session'));
    console.log('[i] 重载后 session =', after);
    console.log('【对照结论】' + (/\"member\":null/.test(after)
      ? '✔ 服务器可达时伪造 token 被 401 拦截器清空 → 说明只有服务端在把关'
      : '⚠ 未观察到清空，请人工确认'));
  }

  console.log('\n[i] 被测客户端仍在运行，可直接查看 UI；结束时执行：');
  console.log('    taskkill /IM HexHub.exe /F & taskkill /IM hexhub-backend.exe /F');
  process.exit(0);   // 不要 browser.close()，会关掉被测应用
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
