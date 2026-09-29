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
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 300)));
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

  try { await page.locator('[role="tab"]:has-text("许可证")').first().click({ timeout: 4000 }); }
  catch (e) { try { await page.locator('[role="tab"]:has-text("License")').first().click({ timeout: 4000 }); } catch (e2) { console.log('tab click failed'); } }
  await page.waitForTimeout(2500);

  const inputs = await page.evaluate(() => Array.from(document.querySelectorAll('input')).map(i => ({ name: i.name, id: i.id, ph: i.placeholder, val: i.value, ro: i.readOnly })));
  console.log('=== INPUTS ===', JSON.stringify(inputs));

  const keyInput = page.locator('input[placeholder*="许可证"], input[placeholder*="license key"]').first();
  if (await keyInput.count()) {
    await keyInput.fill('MMWX-FAKE-TEST-KEY-0001');
    console.log('filled license key');
  } else { console.log('license key input not found'); }

  await page.screenshot({ path: OUT + '/41_filled.png', fullPage: true });
  const saveBtn = page.locator('button:has-text("保存"), button:has-text("Save")').last();
  try { await saveBtn.click({ timeout: 5000 }); console.log('clicked save'); } catch (e) { console.log('save click fail', e.message); }
  await page.waitForTimeout(8000);
  await page.screenshot({ path: OUT + '/42_after_save.png', fullPage: true });
  console.log('=== PAGE TEXT AFTER SAVE ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 2500))));

  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  console.log('=== CAPTURES ===');
  for (const [k, v] of uniq) if (/license|plan|valid|feature|authorized|error/i.test(k)) console.log('*', k.slice(0, 2000), '\n');
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
