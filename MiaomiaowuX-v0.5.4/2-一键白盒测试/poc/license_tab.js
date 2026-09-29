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
  await page.waitForTimeout(3000);
  // click License tab
  try { await page.locator('text=许可证').first().click({ timeout: 5000 }); } catch (e) { try { await page.locator('text=License').first().click({ timeout: 5000 }); } catch (e2) {} }
  await page.waitForTimeout(2500);
  await page.screenshot({ path: OUT + '/40_license_tab.png', fullPage: true });

  // find the license key input (the dialog one) - open the dialog first
  const dbg = await page.evaluate(() => document.body.innerText.slice(0, 3000));
  console.log('=== PAGE TEXT ===\n' + dbg);

  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
