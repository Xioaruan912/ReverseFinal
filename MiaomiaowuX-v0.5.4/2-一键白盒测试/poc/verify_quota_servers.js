const { chromium } = require('playwright');

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
  if (!(await scope.count())) return { why: 'no-dialog' };
  await page.fill('#remote-name', name).catch(() => {});
  await page.waitForTimeout(300);
  // click "Generate Token" if present
  const gen = scope.locator('button:has-text("Generate Token")').first();
  if (await gen.count()) { await gen.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }); await gen.click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(2500); }
  // find submit
  let clicked = null;
  for (const sel of ['button:has-text("Confirm")', 'button:has-text("Add")', 'button:has-text("Create")',
                     'button:has-text("确认")', 'button:has-text("添加")', 'button:has-text("创建")', 'button:has-text("完成")']) {
    const b = scope.locator(sel).last();
    if (await b.count()) {
      await b.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }).catch(() => {});
      try { await b.click({ timeout: 3000 }); clicked = sel; } catch (e) {}
      if (clicked) break;
    }
  }
  await page.waitForTimeout(4000);
  const res = await page.evaluate(() => window.__last.slice(-8));
  const msgs = res.map(v => v.error || v.code || (v.success ? 'ok' : null)).filter(Boolean);
  const toast = await page.evaluate(() => Array.from(document.querySelectorAll('[data-sonner-toast],[role="status"]'))
    .map(e => e.innerText.replace(/\s+/g, ' ')).join(' | ').slice(0, 160)).catch(() => '');
  return { clicked, msgs: msgs.slice(0, 3), toast };
}

const rows = (page) => page.evaluate(() => document.querySelectorAll('table tbody tr').length);

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/xray-servers`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r0 = await rows(page);
  console.log(`\n##### ${tag} (port ${port})  初始服务器行数=${r0}`);
  for (const n of names) {
    const r = await addServer(port, page, n);
    console.log(`  ${n}: ${JSON.stringify(r).slice(0, 340)}`);
  }
  await page.goto(`http://127.0.0.1:${port}/xray-servers`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r1 = await rows(page);
  console.log(`  ==> 最终行数=${r1}  新增 ${r1 - r0}`);
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_servers.png`, fullPage: true });
  await browser.close();
  return { r0, r1 };
}

(async () => {
  const a = await run(12889, 'S_ORIGINAL', ['srvQ1', 'srvQ2', 'srvQ3']);
  const b = await run(12890, 'S_CRACKED', ['srvR1', 'srvR2', 'srvR3']);
  console.log(`\n===== 服务器配额 A/B =====`);
  console.log(`官方原版 : ${a.r0} -> ${a.r1}`);
  console.log(`破解版本 : ${b.r0} -> ${b.r1}`);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
