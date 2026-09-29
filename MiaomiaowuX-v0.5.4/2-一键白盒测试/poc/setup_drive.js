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
    try {
      if (v && typeof v === 'object') {
        const s = JSON.stringify(v);
        if (/entitlement|"plan"|license|master_public_key|signing_key/.test(s) && s.length < 200000) {
          window.__cap.push({ kind: 'json', data: v });
        }
      }
    } catch(e) {}
    return v;
  };
})();
`;

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('console', m => { if (m.type() === 'error') console.log('[console.error]', m.text().slice(0, 160)); });
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.addInitScript(hook);

  await page.goto('http://127.0.0.1:12889/', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);

  // --- setup wizard ---
  await page.fill('#setup-username', 'admin');
  await page.fill('#setup-password', 'Admin@12345');
  await page.fill('#setup-nickname', 'admin');
  await page.fill('#setup-email', 'admin@lab.local');
  await page.screenshot({ path: OUT + '/01_setup.png', fullPage: true });
  const btn = page.locator('button:has-text("Create Admin Account"), button:has-text("创建管理员账号")').first();
  await btn.click();
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/02_after_setup.png', fullPage: true });
  console.log('=== URL after setup:', page.url());
  console.log('=== BODY (first 800) ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 800))));

  // --- navigate to settings -> license tab ---
  const clicks = ['a[href*="setting"]', 'button:has-text("Settings")', 'text=Settings', '[aria-label*="etting"]'];
  for (const c of clicks) {
    try { const el = page.locator(c).first(); if (await el.count()) { await el.click({ timeout: 3000 }); await page.waitForTimeout(2000); break; } } catch (e) {}
  }
  await page.waitForTimeout(2000);
  try { const t = page.locator('text=License').first(); if (await t.count()) { await t.click({ timeout: 3000 }); await page.waitForTimeout(2500); } } catch (e) {}
  await page.screenshot({ path: OUT + '/03_settings.png', fullPage: true });
  console.log('=== URL now:', page.url());
  console.log('=== BODY (first 1500) ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 1500))));

  const caps = await page.evaluate(() => window.__cap.slice(0, 40));
  fs.writeFileSync(OUT + '/captured.json', JSON.stringify(caps, null, 2));
  console.log('=== CAPTURED objects:', caps.length);

  const ls = await page.evaluate(() => JSON.stringify(Object.fromEntries(Object.entries(localStorage))).slice(0, 1500));
  console.log('=== localStorage:', ls);

  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
