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
  await page.waitForTimeout(1500);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(7000);
}

const dumpMenu = async (page, label) => {
  const items = await page.evaluate(() => Array.from(document.querySelectorAll('[role="menuitem"],[role="menuitemcheckbox"],a,button,[data-radix-collection-item]'))
    .map(e => ({ tag: e.tagName, role: e.getAttribute('role') || '', txt: (e.innerText || '').replace(/\s+/g, ' ').slice(0, 40), href: e.getAttribute('href') || '' }))
    .filter(x => x.txt));
  console.log(`=== MENU(${label}) ===`);
  console.log(JSON.stringify(items.slice(0, 60)));
};

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.addInitScript(hook);
  await login(page);

  // open System menu
  try { await page.locator('button:has-text("System")').first().click({ timeout: 5000 }); await page.waitForTimeout(1500); } catch (e) { console.log('system click fail', e.message); }
  await page.screenshot({ path: OUT + '/20_sysmenu.png', fullPage: true });
  await dumpMenu(page, 'after System click');

  // try clicking a settings entry
  for (const sel of ['text=System Settings', 'text=系统设置', 'a[href*="settings"]', 'text=Settings']) {
    try { const l = page.locator(sel).first(); if (await l.count()) { await l.click({ timeout: 4000 }); console.log('clicked', sel); await page.waitForTimeout(3000); break; } } catch (e) {}
  }
  await page.screenshot({ path: OUT + '/21_settings.png', fullPage: true });
  console.log('=== URL:', page.url());
  console.log('=== BODY ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 2500))));

  // click License tab
  for (const sel of ['text=License', 'text=许可证', 'button:has-text("License")', '[role="tab"]:has-text("License")']) {
    try { const l = page.locator(sel).first(); if (await l.count()) { await l.click({ timeout: 4000 }); console.log('clicked tab', sel); await page.waitForTimeout(3000); break; } } catch (e) {}
  }
  await page.screenshot({ path: OUT + '/22_license.png', fullPage: true });
  console.log('=== BODY after license tab ===\n' + (await page.evaluate(() => document.body.innerText.slice(0, 3000))));

  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  for (const [k, v] of uniq) {
    if (/entitlement|"plan"|"usage"|license_key|license_server|master_public_key|max_users/i.test(k)) console.log('CAP*', k.slice(0, 3000), '\n');
  }
  fs.writeFileSync(OUT + '/caps3.json', JSON.stringify([...uniq.values()], null, 2));
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
