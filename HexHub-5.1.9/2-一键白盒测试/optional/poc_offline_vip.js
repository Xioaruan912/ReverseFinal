const { chromium } = require('playwright');
const crypto = require('crypto');
const sha256hex = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

const ENDTIME = 2524579200000;
const EMAIL = 'audit@hexhub.local';
const PUBKEY = 'audit-pubkey';
const SIGN = sha256hex(`${ENDTIME}*${EMAIL}*${sha256hex(PUBKEY)}`);
const MEMBER = { id: 1000001, memberId: 1000001, email: EMAIL, name: 'AuditTester',
  endTime: ENDTIME, isPlus: true, publicKey: PUBKEY, sign: SIGN };
const SESSION = { token: 'forged-token-audit', priKey: 'forged-prikey-audit', member: MEMBER };

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });

  const netlog = [];
  page.on('request', r => { const u = r.url(); if (/hexhub|member|35580/.test(u)) netlog.push('REQ  ' + u); });
  page.on('response', r => { const u = r.url(); if (/hexhub|member|35580/.test(u)) netlog.push('RESP ' + r.status() + ' ' + u); });

  // ---- simulate "block the vendor server" (offline / hosts blackhole) ----
  await page.route('**://api.hexhub.cn/**', r => r.abort('connectionfailed'));
  await page.route('**://oss.hexhub.cn/**', r => r.abort('connectionfailed'));
  console.log('[+] blocked api.hexhub.cn / oss.hexhub.cn at network layer');

  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  console.log('[+] injected forged session');

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(12000);

  const after = await page.evaluate(() => localStorage.getItem('session'));
  console.log('\n=== localStorage["session"] AFTER reload ===');
  console.log(after);

  const state = await page.evaluate(() => {
    const raw = localStorage.getItem('session');
    let m = null;
    try { m = JSON.parse(raw).member; } catch (e) {}
    return {
      member: m,
      isMemberValid_js: !!(m && m.endTime && m.endTime > Date.now()),
      isLifetime: !!(m && m.endTime >= 2524579200000),
    };
  });
  console.log('\n=== evaluated ===');
  console.log(JSON.stringify(state, null, 2));

  console.log('\n=== network log (hexhub/member) ===');
  console.log([...new Set(netlog)].slice(0, 40).join('\n'));

  await page.screenshot({ path: 'exports/poc_offline_vip.png' });
  console.log('\n[+] screenshot -> exports/poc_offline_vip.png');
  await browser.close();
})().catch(e => { console.error('ERR', e); process.exit(1); });
