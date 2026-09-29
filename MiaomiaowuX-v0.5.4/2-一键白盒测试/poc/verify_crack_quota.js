const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';

async function login(page, port) {
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1200);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
}

async function addUsers(port, n, tag) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 160)));
  await page.addInitScript(`
    window.__res = [];
    (function(){ const o = JSON.parse; JSON.parse = function(t,r){ const v=o.call(this,t,r);
      try { if (v && typeof v==='object') window.__res.push(v); } catch(e){} return v; }; })();
  `);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);

  const before = await page.evaluate(() => window.__res.slice());
  const created = [];
  for (let i = 0; i < n; i++) {
    // open dialog
    let opened = false;
    for (const sel of ['button:has-text("Add User")', 'button:has-text("添加用户")', 'button:has-text("Add")', 'button:has-text("添加")']) {
      try {
        const b = page.locator(sel).last();
        if (await b.count()) {
          await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
          await b.click({ timeout: 4000 }); opened = true; break;
        }
      } catch (e) {}
    }
    if (!opened) { console.log(`  [${tag}] 打开新增用户对话框失败`); break; }
    await page.waitForTimeout(1500);
    const u = `labuser${i + 1}`;
    const inputs = await page.$$('input');
    let filled = false;
    for (const inp of inputs) {
      const nm = (await inp.getAttribute('name')) || '';
      const ph = (await inp.getAttribute('placeholder')) || '';
      const t = (await inp.getAttribute('type')) || '';
      if (nm === 'username' || /用户名|username/i.test(ph)) { await inp.fill(u); filled = true; }
      else if (t === 'password') { await inp.fill('Lab@12345'); }
      else if (/昵称|nickname/i.test(ph)) { await inp.fill(u); }
    }
    if (!filled) { console.log(`  [${tag}] 未找到用户名输入框`); break; }
    // submit
    const btns = await page.$$('button');
    let submitted = false;
    for (const b of btns) {
      const tx = ((await b.innerText()) || '').trim();
      if (/确认|保存|创建|确定|Confirm|Save|Create|Add/i.test(tx)) {
        await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
        try { await b.click({ timeout: 3000 }); submitted = true; } catch (e) {}
        if (submitted) break;
      }
    }
    await page.waitForTimeout(3000);
    const res = await page.evaluate(() => window.__res.slice());
    const flat = JSON.stringify(res);
    const lastMsg = (flat.match(/\{"(success|error|message|code)"[^}]{0,200}\}/g) || []).slice(-3);
    console.log(`  [${tag}] create ${u} submitted=${submitted} 最近响应: ${JSON.stringify(lastMsg).slice(0, 400)}`);
    created.push(u);
  }
  await page.screenshot({ path: OUT + `/${tag}_users.png`, fullPage: true });
  await browser.close();
  return created;
}

(async () => {
  console.log('=== ORIGINAL (12889, trial max_users=3) ===');
  await addUsers(12889, 4, '80_original');
  console.log('\n=== CRACKED (12890, HasFeature+配额已移除) ===');
  await addUsers(12890, 4, '81_cracked');
})().catch(e => { console.error('FATAL', e); process.exit(1); });
