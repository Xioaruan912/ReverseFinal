// A/B 验证：注入【已过期 + 签名伪造】的会员对象，检查顶栏是否出现会员徽章
const { chromium } = require('playwright');

const ENDTIME = 1700000000000;        // 2023-11-15 -> 已过期
const EMAIL = 'expired@hexhub.local';
const PUBKEY = 'bogus-pubkey';
const SIGN = 'deadbeef'.repeat(8);    // 伪造签名（不匹配）

const SESSION = {
  token: 'forged-token-audit', priKey: 'forged-prikey-audit',
  member: { id: 1000001, memberId: 1000001, email: EMAIL, name: 'ExpiredUser',
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
  await page.waitForTimeout(11000);

  const r = await page.evaluate(() => {
    const txt = document.body.innerText;
    const crowns = [...document.querySelectorAll('.mdi-crown')];
    const sess = JSON.parse(localStorage.getItem('session') || '{}');
    return {
      crownCount: crowns.length,
      badgeText: crowns.length ? (crowns[0].closest('button,.v-btn') || crowns[0].parentElement).innerText.trim() : null,
      isMemberValid: !!(sess.member && sess.member.endTime > Date.now()),
      endTime: sess.member ? sess.member.endTime : null,
      hasPlusLabel: /(^|\n)\s*(Plus|Pro)\s*(\n|$)/.test(txt),
      sessionKept: !!sess.member,
    };
  });
  console.log(JSON.stringify(r));
  await page.screenshot({ path: process.env.SHOT || 'exports/ab.png' });
  // 注意：不调用 browser.close()，避免关闭被连接的 CEF 应用
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
