const { chromium } = require('playwright');

async function login(page, port) {
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(5000);
}

const countUsers = (page) => page.evaluate(() => {
  const m = document.body.innerText.match(/All\s*\((\d+)\)/);
  return m ? Number(m[1]) : -1;
});

async function tryCreate(page, name) {
  // click the (possibly disabled) "Add User" button
  const btn = page.locator('button:has-text("Add User")').first();
  if (!(await btn.count())) return 'no-add-button';
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  try { await btn.click({ timeout: 4000 }); } catch (e) { return 'click-failed'; }
  await page.waitForTimeout(1500);

  const dlgInputs = await page.$$('div[role="dialog"] input, [data-slot="dialog-content"] input');
  const inputs = dlgInputs.length ? dlgInputs : await page.$$('input');
  for (const inp of inputs) {
    const nm = (await inp.getAttribute('name')) || '';
    const ph = (await inp.getAttribute('placeholder')) || '';
    const t = (await inp.getAttribute('type')) || '';
    if (nm === 'username' || /username|用户名/i.test(ph)) await inp.fill(name);
    else if (t === 'password') await inp.fill('Lab@12345');
    else if (/nickname|昵称/i.test(ph)) await inp.fill(name);
  }
  const dlgBtns = await page.$$('div[role="dialog"] button, [data-slot="dialog-content"] button');
  const btns = dlgBtns.length ? dlgBtns : await page.$$('button');
  for (const b of btns) {
    const tx = ((await b.innerText()) || '').trim();
    if (/^(确认|确定|保存|创建|Confirm|Save|Create)$/i.test(tx)) {
      await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
      try { await b.click({ timeout: 3000 }); } catch (e) {}
      break;
    }
  }
  await page.waitForTimeout(3500);
  return 'submitted';
}

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`
    window.__last = [];
    (function(){ const o=JSON.parse; JSON.parse=function(t,r){ const v=o.call(this,t,r);
      try{ if(v&&typeof v==='object'){ const s=JSON.stringify(v); if(/user|error|limit|PRO|license/i.test(s)) window.__last.push(v);} }catch(e){} return v; }; })();
  `);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  const before = await countUsers(page);
  console.log(`\n##### ${tag} (port ${port})  初始用户数 = ${before}`);
  for (const n of names) {
    await page.evaluate(() => { window.__last = []; });
    const r = await tryCreate(page, n);
    const res = await page.evaluate(() => window.__last.slice(-4));
    const errs = res.map(x => x.error || x.code || (x.success ? 'success' : '?')).filter(Boolean);
    console.log(`  create ${n}: ${r} | 响应: ${JSON.stringify(errs).slice(0, 200)}`);
    await page.waitForTimeout(800);
  }
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const after = await countUsers(page);
  console.log(`  ==> 最终用户数 = ${after}`);
  await browser.close();
  return { before, after };
}

(async () => {
  // 12889 = 官方原版（trial 上限 3 用户）: labuser1/2 已存在
  const a = await run(12889, 'ORIGINAL 未打补丁', ['labq3', 'labq4', 'labq5']);
  // 12890 = HasFeature + 配额已移除
  const b = await run(12890, 'CRACKED 已打补丁', ['labq3', 'labq4', 'labq5']);
  console.log(`\n===== 结论 =====`);
  console.log(`ORIGINAL: ${a.before} -> ${a.after}   CRACKED: ${b.before} -> ${b.after}`);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
