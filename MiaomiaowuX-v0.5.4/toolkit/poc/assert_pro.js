const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

const PRO_FEATURES = ['speed_test', 'limiter', 'server_share', 'embedded', 'reality_pool'];
const BYPASS = `
(function(){
  const orig = JSON.parse;
  JSON.parse = function(t, r) {
    const v = orig.call(this, t, r);
    try {
      if (v && typeof v === 'object' && v.plan && typeof v.plan === 'object' && ('valid' in v || 'premium_theme' in v)) {
        v.valid = true; v.premium_theme = true;
        v.plan.name='PRO'; v.plan.display_name='专业版'; v.plan.features=${JSON.stringify(PRO_FEATURES)};
      }
    } catch(e){}
    return v;
  };
})();
`;

async function collect(inject) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  if (inject) await page.addInitScript(BYPASS);
  await page.goto('http://127.0.0.1:12889/login', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1200);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
  await page.goto('http://127.0.0.1:12889/system-settings', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  try { await page.locator('[role="tab"]:has-text("许可证"), [role="tab"]:has-text("License")').first().click({ timeout: 4000 }); } catch (e) {}
  await page.waitForTimeout(3000);

  // find the 5 feature cards and read label + badge text
  const cards = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('div,li,section').forEach(el => {
      const t = (el.innerText || '').replace(/\s+/g, ' ').trim();
      if (/^(节点测速|节点限速|分享服务器|内嵌 Xray|REALITY 域名池)\s*\S{0,12}$/.test(t) && t.length < 40) out.push(t);
    });
    return [...new Set(out)];
  });
  const status = await page.evaluate(() => {
    const t = document.body.innerText;
    const m = t.match(/Current Status:\s*([^\n]+)\n?[^\n]*\n?[^\n]*Plan:\s*([^\n]+)/);
    return m ? { current: m[1].trim(), plan: m[2].trim() } : null;
  });
  await browser.close();
  return { cards, status };
}

(async () => {
  const base = await collect(false);
  console.log('BASELINE  status =', JSON.stringify(base.status));
  console.log('BASELINE  cards  =', JSON.stringify(base.cards, null, 1));
  const byp = await collect(true);
  console.log('\nBYPASSED  status =', JSON.stringify(byp.status));
  console.log('BYPASSED  cards  =', JSON.stringify(byp.cards, null, 1));
})().catch(e => { console.error('FATAL', e); process.exit(1); });
