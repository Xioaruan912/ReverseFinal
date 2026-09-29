const { chromium } = require('playwright');
async function login(page, port) {
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(5000);
}
async function diag(port, path) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}${path}`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  const btns = await page.evaluate(() => Array.from(document.querySelectorAll('button'))
    .map(b => ({ t: (b.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 26), dis: b.disabled, title: b.title || '' }))
    .filter(x => x.t).slice(0, 25));
  console.log(`\n##### ${path} @ ${port}`);
  console.log('BUTTONS:', JSON.stringify(btns));
  const body = await page.evaluate(() => document.body.innerText.slice(0, 700));
  console.log('BODY:\n' + body);
  // try opening the add dialog
  for (const sel of ['button:has-text("Add Server")', 'button:has-text("Add Node")', 'button:has-text("添加")']) {
    const b = page.locator(sel).first();
    if (await b.count()) {
      await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
      await b.click({ timeout: 4000 }).catch(() => {});
      await page.waitForTimeout(1800);
      const dlg = await page.evaluate(() => {
        const d = document.querySelector('[role="dialog"],[data-slot="dialog-content"]');
        if (!d) return null;
        return {
          text: d.innerText.slice(0, 500),
          inputs: Array.from(d.querySelectorAll('input')).map(i => ({ id: i.id, name: i.name, ph: i.placeholder, type: i.type })),
          buttons: Array.from(d.querySelectorAll('button')).map(b => ({ t: b.innerText.trim().slice(0, 24), dis: b.disabled })),
        };
      });
      console.log('DIALOG:', JSON.stringify(dlg, null, 1));
      break;
    }
  }
  const errs = await page.evaluate(() => window.__last.filter(v => v.error || v.code).slice(-3));
  console.log('API errors:', JSON.stringify(errs).slice(0, 300));
  await page.screenshot({ path: `/root/mmwx/pw/out/diag_${path.replace(/\//g, '_')}_${port}.png`, fullPage: true });
  await browser.close();
}
(async () => {
  await diag(12889, '/xray-servers');
  await diag(12889, '/nodes');
})().catch(e => { console.error('FATAL', e); process.exit(1); });
