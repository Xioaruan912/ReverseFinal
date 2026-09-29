const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();

  page.on('console', m => { if (m.type() === 'error') console.log('[console.error]', m.text().slice(0, 200)); });
  page.on('request', r => { if (r.url().includes('/api/')) console.log('[REQ]', r.method(), r.url(), 'sc=' + (r.headers()['x-secure-channel'] || '-')); });
  page.on('response', async r => {
    if (!r.url().includes('/api/')) return;
    let body = '';
    try { const b = await r.body(); body = b.slice(0, 160).toString('latin1'); } catch (e) { body = '<err>'; }
    console.log('[RES]', r.status(), r.url(), 'ct=' + (r.headers()['content-type'] || ''), 'body=' + JSON.stringify(body));
  });

  await page.goto('http://127.0.0.1:12889/', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);

  console.log('=== TITLE:', await page.title());
  const txt = await page.evaluate(() => document.body.innerText.slice(0, 2000));
  console.log('=== BODY TEXT ===\n' + txt);

  const inputs = await page.evaluate(() => Array.from(document.querySelectorAll('input,button,select'))
    .map(e => ({ tag: e.tagName, type: e.type, name: e.name, id: e.id, ph: e.placeholder, txt: (e.innerText || '').slice(0, 40) })));
  console.log('=== FORM ELEMENTS ===');
  console.log(JSON.stringify(inputs, null, 1));

  await page.screenshot({ path: '/root/mmwx/pw/probe.png', fullPage: true });
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
