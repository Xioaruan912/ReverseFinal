const { chromium } = require('playwright');
const crypto = require('crypto');
const sha256hex = s => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

const ENDTIME = 2524579200000, EMAIL = 'audit@hexhub.local', PUBKEY = 'audit-pubkey';
const SIGN = sha256hex(`${ENDTIME}*${EMAIL}*${sha256hex(PUBKEY)}`);
const SESSION = {
  token: 'forged-token-audit', priKey: 'forged-prikey-audit',
  member: { id: 1000001, memberId: 1000001, email: EMAIL, name: 'AuditTester',
    endTime: ENDTIME, isPlus: true, publicKey: PUBKEY, sign: SIGN }
};

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });
  await page.route('**://api.hexhub.cn/**', r => r.abort('connectionfailed'));
  await page.route('**://oss.hexhub.cn/**', r => r.abort('connectionfailed'));

  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(12000);

  // top bar member badge
  const info = await page.evaluate(() => {
    const txt = document.body.innerText;
    const crowns = [...document.querySelectorAll('.mdi-crown')].map(e => e.className);
    const ribbon = [...document.querySelectorAll('.ribbon')].map(e => e.innerText);
    return {
      hasPlus: /Plus/.test(txt),
      hasPro: /\bPro\b/.test(txt),
      crownElements: crowns.length,
      ribbonText: ribbon,
      memberLine: (txt.match(/[^\n]*审计|audit@hexhub\.local[^\n]*/) || [])[0] || null,
      snippet: txt.split('\n').filter(l => /Plus|Pro|终身|会员|续费|免费试用/.test(l)).slice(0, 12),
    };
  });
  console.log('=== member UI evidence ===');
  console.log(JSON.stringify(info, null, 2));

  await page.screenshot({ path: 'exports/poc_vip_unlocked.png' });
  console.log('[+] screenshot -> exports/poc_vip_unlocked.png');

  // ---- negative control: same forged session but server reachable (no block) ----
  await page.unroute('**://api.hexhub.cn/**');
  await page.unroute('**://oss.hexhub.cn/**');
  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(10000);
  const neg = await page.evaluate(() => localStorage.getItem('session'));
  console.log('\n=== negative control (server reachable) -> session AFTER reload ===');
  console.log(neg);

  await browser.close();
})().catch(e => { console.error('ERR', e); process.exit(1); });
