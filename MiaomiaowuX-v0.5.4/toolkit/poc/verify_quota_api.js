const { chromium } = require('playwright');

async function grab(port, tag) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  await page.addInitScript(`
    window.__cap = [];
    (function(){ const o=JSON.parse; JSON.parse=function(t,r){ const v=o.call(this,t,r);
      try{ if(v&&typeof v==='object'){ const s=JSON.stringify(v);
        if(/"usage"|"plan"|max_users|max_nodes|max_servers|features/.test(s)) window.__cap.push(v); } }catch(e){} return v; }; })();
  `);
  await page.goto(`http://127.0.0.1:${port}/login`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1000);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
  await page.goto(`http://127.0.0.1:${port}/system-settings`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  try { await page.locator('[role="tab"]:has-text("许可证"), [role="tab"]:has-text("License")').first().click({ timeout: 4000 }); } catch (e) {}
  await page.waitForTimeout(3500);
  const caps = await page.evaluate(() => window.__cap);
  const uniq = new Map();
  for (const c of caps) { try { uniq.set(JSON.stringify(c), c); } catch (e) {} }
  console.log(`\n##### ${tag} (port ${port})`);
  for (const k of uniq.keys()) {
    if (k.includes('"usage"') || /"plan"/.test(k) || k.includes('max_servers')) console.log('  ', k.slice(0, 600));
  }
  await page.screenshot({ path: `/root/mmwx/pw/out/${tag}_license.png`, fullPage: true });
  await browser.close();
}

(async () => {
  await grab(12889, '90_original');
  await grab(12890, '91_cracked');
})().catch(e => { console.error('FATAL', e); process.exit(1); });
