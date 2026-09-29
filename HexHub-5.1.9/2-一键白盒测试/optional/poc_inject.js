const { chromium } = require('playwright');
const crypto = require('crypto');

const sha256hex = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

// ---- forge member object exactly as the client validates it ----
const ENDTIME = 2524579200000;          // 2050-01-01 -> "终身版" sentinel
const EMAIL = 'audit@hexhub.local';
const PUBKEY = 'audit-pubkey';
const SIGN = sha256hex(`${ENDTIME}*${EMAIL}*${sha256hex(PUBKEY)}`);

const MEMBER = {
  id: 1000001,
  memberId: 1000001,
  email: EMAIL,
  name: 'AuditTester',
  endTime: ENDTIME,
  isPlus: true,
  publicKey: PUBKEY,
  sign: SIGN,
};
const SESSION = { token: 'forged-token-audit', priKey: 'forged-prikey-audit', member: MEMBER };

console.log('[i] forged sign =', SIGN);

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });

  await page.evaluate((s) => {
    localStorage.setItem('session', JSON.stringify(s));
  }, SESSION);
  console.log('[+] injected localStorage["session"]');

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(9000);

  const after = await page.evaluate(() => localStorage.getItem('session'));
  console.log('\n=== localStorage["session"] after reload ===');
  console.log(after);

  const dom = await page.evaluate(() => document.body.innerText.replace(/\n{2,}/g, '\n').slice(0, 1500));
  console.log('\n=== page text (first 1500 chars) ===');
  console.log(dom);

  await page.screenshot({ path: 'exports/after_inject.png', fullPage: false });
  console.log('\n[+] screenshot -> exports/after_inject.png');
  await browser.close();
})().catch(e => { console.error('ERR', e); process.exit(1); });
