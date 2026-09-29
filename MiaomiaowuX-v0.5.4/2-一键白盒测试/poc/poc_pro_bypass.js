/*
 * MMWX (妙妙屋X) licence PRO-gate bypass PoC  —  CWE-602 / CWE-345
 *
 * Threat model reproduced here:
 *   The PRO feature gate (`hasFeature`) and the `premium_theme` flag are evaluated
 *   ONLY inside the browser bundle (assets/index-*.js).  When the signed entitlement
 *   cannot be verified the code *fails open* and trusts the unsigned
 *   `plan.features` array coming from /api/user/license/status.
 *
 *   Consequently anybody able to control that payload *before* the gate runs
 *   (patched/self-hosted master, modified bundle, injecting reverse proxy,
 *   devtools) unlocks every PRO feature without any key material.
 *
 * This script demonstrates exactly that by rewriting the decrypted licence payload
 * in the page, then proving:
 *   - the "Pro" lock badges disappear / PRO card turns active
 *   - the premium/glass theme becomes selectable
 */
const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

const PRO_FEATURES = ['speed_test', 'limiter', 'server_share', 'embedded', 'reality_pool'];

const BYPASS = `
window.__bypassHits = 0;
(function(){
  const orig = JSON.parse;
  JSON.parse = function(t, r) {
    const v = orig.call(this, t, r);
    try {
      if (v && typeof v === 'object' && v.plan && typeof v.plan === 'object' &&
          ('valid' in v || 'premium_theme' in v)) {
        v.valid = true;
        v.premium_theme = true;
        v.plan.name = 'PRO';
        v.plan.display_name = '专业版';
        v.plan.max_servers = 999; v.plan.max_nodes = 9999; v.plan.max_users = 9999;
        v.plan.features = ${JSON.stringify(PRO_FEATURES)};
        window.__bypassHits++;
      }
      if (v && v.license && v.license.plan) {
        v.license.valid = true;
        v.license.max_servers = 999;
        v.license.plan.name = 'PRO';
        v.license.plan.display_name = '专业版';
        v.license.plan.features = ${JSON.stringify(PRO_FEATURES)};
        window.__bypassHits++;
      }
    } catch (e) {}
    return v;
  };
})();
`;

async function login(page) {
  await page.goto('http://127.0.0.1:12889/login', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1200);
  await page.fill('input[name="username"]', 'admin');
  await page.fill('input[name="password"]', 'Admin@12345');
  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(6000);
}

async function run(injectBypass) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  if (injectBypass) await page.addInitScript(BYPASS);
  await page.addInitScript(`
    window.__lic = [];
    (function(){ const o = JSON.parse; JSON.parse = function(t,r){ const v=o.call(this,t,r);
      try { if (v && v.plan) window.__lic.push(v); } catch(e){} return v; }; })();
  `);
  await login(page);
  await page.goto('http://127.0.0.1:12889/system-settings', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  try { await page.locator('[role="tab"]:has-text("许可证"), [role="tab"]:has-text("License")').first().click({ timeout: 4000 }); } catch (e) {}
  await page.waitForTimeout(3000);

  const lic = await page.evaluate(() => window.__lic);
  const text = await page.evaluate(() => document.body.innerText);
  const i = text.indexOf('License');
  const tail = text.slice(Math.max(0, i), i + 1800);
  const proBadges = (tail.match(/\bPro\b/g) || []).length;
  const hits = await page.evaluate(() => window.__bypassHits || 0);
  const themeOk = await page.evaluate(() => {
    const el = document.querySelector('html');
    return el ? el.className : '';
  });
  await page.screenshot({ path: OUT + (injectBypass ? '/62_after_bypass.png' : '/61_baseline.png'), fullPage: true });
  await browser.close();
  return { lic: lic[0], proBadges, hits, themeOk, tail };
}

(async () => {
  console.log('\n################ BASELINE (untouched client) ################');
  const base = await run(false);
  console.log('license status seen by UI :', JSON.stringify(base.lic));
  console.log('html class               :', base.themeOk);
  console.log('"Pro" badges on license UI:', base.proBadges);
  console.log('--- UI tail ---\n' + base.tail);

  console.log('\n################ AFTER INJECTING UNSIGNED plan.features ################');
  const byp = await run(true);
  console.log('license status seen by UI :', JSON.stringify(byp.lic));
  console.log('html class               :', byp.themeOk);
  console.log('"Pro" badges on license UI:', byp.proBadges);
  console.log('bypass rewrite hits      :', byp.hits);
  console.log('--- UI tail ---\n' + byp.tail);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
