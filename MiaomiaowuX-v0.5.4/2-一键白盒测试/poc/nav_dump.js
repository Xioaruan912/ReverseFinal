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

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.addInitScript(hook);
  await login(page);

  const nav = await page.evaluate(() => Array.from(document.querySelectorAll('a,button'))
    .map(e => ({ tag: e.tagName, href: e.getAttribute('href') || '', txt: (e.innerText || '').replace(/\s+/g, ' ').slice(0, 50) }))
    .filter(x => x.txt || x.href));
  console.log('=== NAV ===');
  console.log(JSON.stringify(nav.slice(0, 80), null, 1));

  const ls = await page.evaluate(() => JSON.stringify(Object.fromEntries(Object.entries(localStorage))));
  console.log('=== localStorage:', ls.slice(0, 800));

  // dedupe captures of interest
  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  console.log('=== unique captures:', uniq.size);
  for (const [k, v] of uniq) {
    if (/entitlement|"plan"|"usage"|license_key|master_public_key/i.test(k)) console.log('*', k.slice(0, 2500), '\n');
  }
  fs.writeFileSync(OUT + '/caps2.json', JSON.stringify([...uniq.values()], null, 2));
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
