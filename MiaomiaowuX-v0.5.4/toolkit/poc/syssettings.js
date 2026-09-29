const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

const hook = `
window.__cap = [];
(function(){
  const origParse = JSON.parse;
  JSON.parse = function(t, r) {
    const v = origParse.call(this, t, r);
    try { if (v && typeof v === 'object' && JSON.stringify(v).length < 400000) window.__cap.push(v); } catch(e){}
    return v;
  };
})();
`;

async function login(page) {
  await page.goto('http://127.0.0.1:12889/login', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1200);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.addInitScript(hook);
  await login(page);

  await page.goto('http://127.0.0.1:12889/system-settings', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(4000);
  await page.screenshot({ path: OUT + '/30_systems.png', fullPage: true });
  const tabs = await page.evaluate(() => Array.from(document.querySelectorAll('[role="tab"],button'))
    .map(e => (e.innerText || '').replace(/\s+/g, ' ').trim()).filter(Boolean).slice(0, 60));
  console.log('=== TABS/BUTTONS ===', JSON.stringify(tabs));

  for (const sel of ['[role="tab"]:has-text("License")', 'button:has-text("License")', 'text=License']) {
    try { const l = page.locator(sel).first(); if (await l.count()) { await l.click({ timeout: 4000 }); console.log('clicked', sel); await page.waitForTimeout(3500); break; } } catch (e) {}
  }
  await page.screenshot({ path: OUT + '/31_license.png', fullPage: true });
  console.log('=== BODY ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 3000))));

  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  for (const [k, v] of uniq) {
    if (/"usage"|license_key|license_server|entitlement|signing_key|master_public_key|valid"|max_users/i.test(k)) console.log('CAP*', k.slice(0, 4000), '\n');
  }
  fs.writeFileSync(OUT + '/caps4.json', JSON.stringify([...uniq.values()], null, 2));
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
