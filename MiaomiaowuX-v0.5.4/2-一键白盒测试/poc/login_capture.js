const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

const hook = `
window.__cap = [];
window.__raw = [];
(function(){
  const origParse = JSON.parse;
  JSON.parse = function(t, r) {
    const v = origParse.call(this, t, r);
    try {
      if (v && typeof v === 'object') {
        const s = JSON.stringify(v);
        if (s.length < 400000) window.__cap.push({ kind:'json', data:v });
      }
    } catch(e) {}
    return v;
  };
  const oDec = TextDecoder.prototype.decode;
  TextDecoder.prototype.decode = function(buf) {
    const s = oDec.call(this, buf);
    try { if (s && s.length > 2 && s.length < 300000) window.__raw.push(s); } catch(e){}
    return s;
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

  // ---- login ----
  await page.goto('http://127.0.0.1:12889/login', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2000);
  const inputs = await page.$$('input');
  console.log('inputs:', await Promise.all(inputs.map(i => i.getAttribute('name'))));
  for (const i of inputs) {
    const nm = await i.getAttribute('name');
    if (nm === 'username' || (await i.getAttribute('type')) === 'text') await i.fill('admin');
    else if ((await i.getAttribute('type')) === 'password') await i.fill('Admin@12345');
  }
  await page.screenshot({ path: OUT + '/10_login_filled.png', fullPage: true });
  await page.locator('button:has-text("Sign In"), button[type="submit"]').first().click();
  await page.waitForTimeout(8000);
  console.log('=== URL after login:', page.url());
  await page.screenshot({ path: OUT + '/11_dashboard.png', fullPage: true });
  console.log('=== BODY (first 1200) ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 1200))));

  // ---- go to settings -> license ----
  const tryClick = async (sel) => { try { const l = page.locator(sel).first(); if (await l.count()) { await l.click({ timeout: 4000 }); await page.waitForTimeout(2000); return true; } } catch (e) {} return false; };
  await tryClick('a[href="#/settings"]');
  await tryClick('text=System Settings');
  await page.waitForTimeout(1500);
  await tryClick('text=License');
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/12_license_page.png', fullPage: true });
  console.log('=== URL now:', page.url());
  console.log('=== BODY (first 2000) ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 2000))));

  const ls = await page.evaluate(() => JSON.stringify(Object.fromEntries(Object.entries(localStorage))));
  console.log('=== localStorage:', ls.slice(0, 2000));
  fs.writeFileSync(OUT + '/localStorage.json', ls);

  const caps = await page.evaluate(() => window.__cap);
  fs.writeFileSync(OUT + '/captured_all.json', JSON.stringify(caps, null, 2));
  console.log('=== captured objects:', caps.length);
  // print ones that look like license status
  const lic = caps.filter(c => c.data && (c.data.entitlement !== undefined || c.data.plan !== undefined || c.data.usage !== undefined));
  console.log('=== license-ish captures:', lic.length);
  for (const c of lic.slice(0, 10)) console.log(JSON.stringify(c.data).slice(0, 2500), '\n---');

  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
