const { chromium } = require('playwright');

/* 客户端解除 UI 层限制（把 usage.max 改大，让对话框能打开），
   从而可以观测「服务端」是否真的拦截超额建号 —— 用于区分 UI 门禁与服务端门禁。 */
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

async function createUser(port, page, name) {
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2200);
  await page.evaluate(() => { window.__last = []; });
  const btn = page.locator('button:has-text("Add User")').first();
  if (!(await btn.count())) return { why: 'no-add-button' };
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  await btn.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(1500);
  const scope = page.locator('[role="dialog"],[data-slot="dialog-content"]').first();
  if (!(await scope.count())) return { why: 'UI-BLOCKED(no-dialog)' };
  await page.fill('#create-username', name).catch(() => {});
  await page.fill('#create-nickname', name).catch(() => {});
  await page.fill('#create-password', 'Lab@12345').catch(() => {});
  await page.waitForTimeout(400);
  const confirm = scope.locator('button:has-text("Confirm Create")').first();
  await confirm.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }).catch(() => {});
  await confirm.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(3500);
  const res = await page.evaluate(() => window.__last.slice(-8));
  const msgs = res.map(v => v.error || v.code || (v.success ? 'ok' : null)).filter(Boolean);
  const toast = await page.evaluate(() => Array.from(document.querySelectorAll('[data-sonner-toast],[role="status"]'))
    .map(e => e.innerText.replace(/\s+/g, ' ')).join(' | ').slice(0, 160)).catch(() => '');
  return { msgs: msgs.slice(0, 4), toast };
}

const rows = (page) => page.evaluate(() => document.querySelectorAll('table tbody tr').length);

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(UNLOCK_UI);
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r0 = await rows(page);
  console.log(`\n##### ${tag} (port ${port})  初始用户行数=${r0}  [UI 上限已解除，纯测服务端]`);
  for (const n of names) {
    const r = await createUser(port, page, n);
    console.log(`  ${n}: ${JSON.stringify(r).slice(0, 300)}`);
  }
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r1 = await rows(page);
  console.log(`  ==> 最终行数=${r1}  新增 ${r1 - r0}`);
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_quota.png`, fullPage: true });
  await browser.close();
  return { r0, r1 };
}

(async () => {
  const a = await run(12889, 'A_ORIGINAL', ['qA1','qA2','qA3','qA4','qA5']);
  const b = await run(12890, 'B_CRACKED', ['qB1','qB2','qB3','qB4','qB5']);
  console.log(`\n===== 服务端配额拦截 A/B =====`);
  console.log(`官方原版 : ${a.r0} -> ${a.r1}`);
  console.log(`破解版本 : ${b.r0} -> ${b.r1}`);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
