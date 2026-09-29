const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await page.goto('http://127.0.0.1:12890/login', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(5000);
  await page.goto('http://127.0.0.1:12890/users', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);

  const btn = page.locator('button:has-text("Add User")').first();
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  await btn.click();
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/root/mmwx/pw/out/95_dialog.png', fullPage: true });

  const dlgInfo = await page.evaluate(() => {
    const dlgs = Array.from(document.querySelectorAll('[role="dialog"],[data-slot="dialog-content"]'));
    return dlgs.map(d => ({
      text: d.innerText.slice(0, 500),
      inputs: Array.from(d.querySelectorAll('input')).map(i => ({ name: i.name, type: i.type, ph: i.placeholder, id: i.id })),
      buttons: Array.from(d.querySelectorAll('button')).map(b => ({ t: b.innerText.trim().slice(0, 30), dis: b.disabled })),
    }));
  });
  console.log('DIALOGS:', JSON.stringify(dlgInfo, null, 1));

  // fill and submit
  const scope = page.locator('[role="dialog"],[data-slot="dialog-content"]').first();
  const inputs = await scope.locator('input').all();
  for (const inp of inputs) {
    const nm = (await inp.getAttribute('name')) || '';
    const ph = (await inp.getAttribute('placeholder')) || '';
    const t = (await inp.getAttribute('type')) || '';
    if (nm === 'username' || /username|用户名/i.test(ph)) await inp.fill('labq9').catch(()=>{});
    else if (t === 'password') await inp.fill('Lab@12345').catch(()=>{});
    else if (/nickname|昵称/i.test(ph)) await inp.fill('labq9').catch(()=>{});
  }
  await page.screenshot({ path: '/root/mmwx/pw/out/96_filled.png', fullPage: true });

  for (const b of await scope.locator('button').all()) {
    const tx = ((await b.innerText()) || '').trim();
    if (/确认|确定|保存|创建|Confirm|Create|Save/i.test(tx)) {
      console.log('clicking:', tx);
      await b.click({ timeout: 3000 }).catch(e => console.log('click err', e.message));
      break;
    }
  }
  await page.waitForTimeout(4000);
  await page.screenshot({ path: '/root/mmwx/pw/out/97_after.png', fullPage: true });
  const after = await page.evaluate(() => {
    const d = document.querySelector('[role="dialog"],[data-slot="dialog-content"]');
    return { dialogStillOpen: !!d, dialogText: d ? d.innerText.slice(0, 400) : '', body: document.body.innerText.slice(0, 600) };
  });
  console.log('AFTER:', JSON.stringify(after).slice(0, 900));
  console.log('API resp:', JSON.stringify(await page.evaluate(() => window.__last.slice(-5))).slice(0, 700));
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
