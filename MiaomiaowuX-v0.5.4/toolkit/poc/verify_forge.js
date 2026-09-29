const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

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
  await page.addInitScript(`
    window.__cap = [];
    (function(){
      const op = JSON.parse;
      JSON.parse = function(t,r){ const v = op.call(this,t,r);
        try { if (v && typeof v==='object') window.__cap.push(v); } catch(e){} return v; };
    })();
  `);
  await login(page);
  await page.goto('http://127.0.0.1:12889/system-settings', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3500);
  try { await page.locator('[role="tab"]:has-text("许可证"), [role="tab"]:has-text("License")').first().click({ timeout: 4000 }); } catch (e) {}
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/50_forged_license.png', fullPage: true });

  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  console.log('=== LICENSE-RELATED CAPTURES ===');
  for (const [k, v] of uniq) {
    if (/"plan"|"usage"|license_key|"valid"|max_users|features/i.test(k) && !/serverName|masterToken/.test(k))
      console.log('*', k.slice(0, 3000), '\n');
  }
  const body = await page.evaluate(() => document.body.innerText);
  const idx = body.indexOf('License Key');
  console.log('=== LICENSE TAB TEXT ===\n' + body.slice(Math.max(0, idx - 2500), idx + 500));
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
