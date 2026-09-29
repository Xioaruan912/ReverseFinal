const { chromium } = require('playwright');

async function login(page, port) {
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(5000);
}

async function createUser(port, page, name) {
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  await page.evaluate(() => { window.__last = []; });

  const btn = page.locator('button:has-text("Add User"), button:has-text("添加用户")').first();
  if (!(await btn.count())) return { ok: false, why: 'no-add-button' };
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  try { await btn.click({ timeout: 4000 }); } catch (e) { return { ok: false, why: 'click-add-failed' }; }
  await page.waitForTimeout(1800);

  const dlg = page.locator('[role="dialog"],[data-slot="dialog-content"]').first();
  const scope = (await dlg.count()) ? dlg : page;
  const inputs = await scope.locator('input').all();
  if (!inputs.length) return { ok: false, why: 'no-dialog-inputs' };
  for (const inp of inputs) {
    const nm = (await inp.getAttribute('name')) || '';
    const ph = (await inp.getAttribute('placeholder')) || '';
    const t = (await inp.getAttribute('type')) || '';
    if (nm === 'username' || /username|用户名/i.test(ph)) await inp.fill(name).catch(() => {});
    else if (t === 'password') await inp.fill('Lab@12345').catch(() => {});
    else if (/nickname|昵称/i.test(ph)) await inp.fill(name).catch(() => {});
  }
  const btns = await scope.locator('button').all();
  let clicked = null;
  for (const b of btns) {
    const tx = ((await b.innerText()) || '').trim();
    if (/确认|确定|保存|创建|Confirm|Save|Create|Add/i.test(tx) && !/取消|Cancel/i.test(tx)) {
      await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }).catch(() => {});
      try { await b.click({ timeout: 3000 }); clicked = tx; } catch (e) {}
      if (clicked) break;
    }
  }
  await page.waitForTimeout(3500);
  const res = await page.evaluate(() => window.__last.slice(-6));
  const msgs = res.map(v => v.error || v.code || (v.success ? 'ok' : null)).filter(Boolean);
  const toast = await page.evaluate(() => {
    const t = document.querySelector('[data-sonner-toast],[role="status"],.toast,[data-slot="toast"]');
    return t ? t.innerText.replace(/\s+/g, ' ').slice(0, 120) : '';
  }).catch(() => '');
  return { ok: true, clicked, msgs, toast };
}

async function countUsers(page) {
  return page.evaluate(async () => {
    const t = document.body.innerText;
    const m = t.match(/All\s*\((\d+)\)/);
    const rows = document.querySelectorAll('table tbody tr').length;
    return { all: m ? Number(m[1]) : -1, rows };
  });
}

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`
    window.__last = [];
    (function(){ const o=JSON.parse; JSON.parse=function(t,r){ const v=o.call(this,t,r);
      try{ if(v&&typeof v==='object') window.__last.push(v); }catch(e){} return v; }; })();
  `);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const c0 = await countUsers(page);
  console.log(`\n##### ${tag} (${port})  初始: All=${c0.all} rows=${c0.rows}`);
  for (const n of names) {
    const r = await createUser(port, page, n);
    console.log(`  ${n}: ok=${r.ok} why=${r.why || '-'} clicked=${r.clicked || '-'} msgs=${JSON.stringify(r.msgs || []).slice(0, 260)} toast="${r.toast || ''}"`);
  }
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const c1 = await countUsers(page);
  console.log(`  ==> 最终: All=${c1.all} rows=${c1.rows}`);
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_users_final.png`, fullPage: true });
  await browser.close();
}

(async () => {
  await run(12889, 'A_original', ['labu4', 'labu5', 'labu6']);
  await run(12890, 'B_cracked', ['labu4', 'labu5', 'labu6']);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
