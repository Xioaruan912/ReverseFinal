const { chromium } = require('playwright');
async function diag(port) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3500);
  const info = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('button'))
      .map(b => ({ t: (b.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 30), dis: b.disabled, title: b.title || '' }))
      .filter(x => x.t);
    const body = document.body.innerText;
    return { btns, head: body.slice(0, 900) };
  });
  console.log(`\n##### port ${port}`);
  console.log('BUTTONS:', JSON.stringify(info.btns));
  console.log('BODY HEAD:\n' + info.head);
  await browser.close();
}
(async () => { await diag(12889); await diag(12890); })().catch(e => { console.error(e); process.exit(1); });
