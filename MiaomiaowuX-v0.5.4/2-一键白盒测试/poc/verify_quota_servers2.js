const { chromium } = require('playwright');

/* 解除"客户端"配额门禁（把 usage.max 放大），使对话框能打开，
   从而单独观测「服务端」是否仍拦截 —— 用于区分 UI 门禁与服务端门禁。 */
const UNLOCK_UI = `
(function(){
  const o = JSON.parse;
  JSON.parse = function(t, r) {
    const v = o.call(this, t, r);
    try {
      if (v && typeof v === 'object' && v.usage) {
        for (const k of ['users','nodes','servers']) if (v.usage[k]) v.usage[k].max = 999999;
      }
    } catch (e) {}
    return v;
  };
})();`;

async function login(page, port) {
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(5000);
}

async function addServer(port, page, name) {
  await page.goto(`http://127.0.0.1:${port}/xray-servers`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  await page.evaluate(() => { window.__last = []; });

  const btn = page.locator('button:has-text("Add Server")').first();
  if (!(await btn.count())) return { why: 'no-add-button' };
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  await btn.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(1800);

  const scope = page.locator('[role="dialog"],[data-slot="dialog-content"]').first();
  if (!(await scope.count())) return { why: 'UI-BLOCKED(no-dialog)' };

  await page.fill('#remote-name', name).catch(() => {});
  await page.waitForTimeout(400);
  const gen = scope.locator('button:has-text("Generate Token")').first();
  if (await gen.count()) {
    await gen.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
    await gen.click({ timeout: 4000 }).catch(() => {});
    await page.waitForTimeout(2500);
  }
  // 提交（对话框底部的主按钮）
  let clicked = null;
  const all = await scope.locator('button').all();
  for (const b of all) {
    const tx = ((await b.innerText()) || '').trim();
    if (/^(Confirm|Add|Create|Done|Save|完成|确认|添加|创建|保存)$/i.test(tx)) {
      await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }).catch(() => {});
      try { await b.click({ timeout: 3000 }); clicked = tx; } catch (e) {}
      if (clicked) break;
    }
  }
  await page.waitForTimeout(4000);
  const res = await page.evaluate(() => window.__last.slice(-10));
  const msgs = res.map(v => v.error || v.code || (v.success ? 'ok' : null)).filter(Boolean);
  const toast = await page.evaluate(() => Array.from(document.querySelectorAll('[data-sonner-toast],[role="status"]'))
    .map(e => e.innerText.replace(/\s+/g, ' ')).join(' | ').slice(0, 200)).catch(() => '');
  return { clicked, msgs: msgs.slice(0, 4), toast };
}

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(UNLOCK_UI);
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await login(page, port);
  console.log(`\n##### ${tag} (port ${port})  [客户端上限已解除，纯测服务端]`);
  for (const n of names) {
    const r = await addServer(port, page, n);
    console.log(`  ${n}: ${JSON.stringify(r).slice(0, 340)}`);
  }
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_servers.png`, fullPage: true });
  await browser.close();
}

(async () => {
  await run(12889, 'S_ORIGINAL', ['srvX1', 'srvX2', 'srvX3']);
  await run(12890, 'S_CRACKED', ['srvY1', 'srvY2', 'srvY3']);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
