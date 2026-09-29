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

  const btn = page.locator('button:has-text("Add User")').first();
  if (!(await btn.count())) return { created: false, why: 'no-add-button' };
  await btn.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); });
  await btn.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(1800);

  const scope = page.locator('[role="dialog"],[data-slot="dialog-content"]').first();
  if (!(await scope.count())) return { created: false, why: 'no-dialog' };
  await page.fill('#create-username', name).catch(() => {});
  await page.fill('#create-nickname', name).catch(() => {});
  await page.fill('#create-password', 'Lab@12345').catch(() => {});
  await page.waitForTimeout(500);
  const confirm = scope.locator('button:has-text("Confirm Create"), button:has-text("确认创建")').first();
  const dis = await confirm.isDisabled().catch(() => true);
  await confirm.evaluate(el => { el.disabled = false; el.removeAttribute('disabled'); }).catch(() => {});
  await confirm.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(3500);

  const res = await page.evaluate(() => window.__last.slice(-8));
  const msgs = res.map(v => v.error || v.code || (v.success ? 'ok' : null)).filter(Boolean);
  const toast = await page.evaluate(() => {
    const els = Array.from(document.querySelectorAll('[data-sonner-toast],[role="status"],[data-slot="toast"]'));
    return els.map(e => e.innerText.replace(/\s+/g, ' ')).join(' | ').slice(0, 160);
  }).catch(() => '');
  const stillOpen = await scope.count() > 0 && await scope.isVisible().catch(() => false);
  return { created: true, confirmDisabled: dis, msgs, toast, dialogOpen: stillOpen };
}

async function rows(page) {
  return page.evaluate(() => document.querySelectorAll('table tbody tr').length);
}

async function run(port, tag, names) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`window.__last=[];(function(){const o=JSON.parse;JSON.parse=function(t,r){const v=o.call(this,t,r);try{if(v&&typeof v==='object')window.__last.push(v);}catch(e){}return v;};})();`);
  await login(page, port);
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r0 = await rows(page);
  console.log(`\n##### ${tag} (port ${port})  初始用户行数 = ${r0}`);
  for (const n of names) {
    const r = await createUser(port, page, n);
    console.log(`  ${n}: ${JSON.stringify(r).slice(0, 320)}`);
  }
  await page.goto(`http://127.0.0.1:${port}/users`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  const r1 = await rows(page);
  console.log(`  ==> 最终用户行数 = ${r1}   (新增 ${r1 - r0})`);
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_users.png`, fullPage: true });
  await browser.close();
  return { r0, r1 };
}

(async () => {
  const a = await run(12889, 'A_ORIGINAL', ['limitA1', 'limitA2', 'limitA3']);
  const b = await run(12890, 'B_CRACKED', ['limitB1', 'limitB2', 'limitB3']);
  console.log(`\n===== 结果 =====`);
  console.log(`官方原版 (trial max_users=3): ${a.r0} -> ${a.r1}  (新增 ${a.r1 - a.r0})`);
  console.log(`破解版本 (配额已移除)      : ${b.r0} -> ${b.r1}  (新增 ${b.r1 - b.r0})`);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
