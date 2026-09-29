const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/mmwx/pw/out';
fs.mkdirSync(OUT, { recursive: true });

const PREMIUM = [
  { key: 'speed_test', label: '节点测速' },
  { key: 'limiter', label: '节点限速' },
  { key: 'server_share', label: '分享服务器' },
  { key: 'embedded', label: '内嵌 Xray' },
  { key: 'reality_pool', label: 'REALITY 域名池' },
];

async function probe(port, tag) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  // 强制选择 premium 主题（前端据此加 theme-premium class，服务端注入 ps 决定是否生效）
  await ctx.addCookies([{ name: 'mmw-theme-style', value: 'premium', url: 'http://127.0.0.1:' + port }]);
  const page = await ctx.newPage();
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(2500);
  const cls = await page.evaluate(() => document.documentElement.className);
  const premiumApplied = /theme-premium/.test(cls);
  const bg = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--g-tone') || '');
  await page.screenshot({ path: OUT + `/${tag}_theme_premium.png`, fullPage: false });
  await browser.close();
  return { cls, premiumApplied };
}

(async () => {
  const a = await probe(12889, '70_original');
  console.log(`ORIGINAL  (12889) <html class="${a.cls}">  premium-theme-applied=${a.premiumApplied}`);
  const b = await probe(12890, '71_cracked');
  console.log(`CRACKED   (12890) <html class="${b.cls}">  premium-theme-applied=${b.premiumApplied}`);
  console.log('\n结论: 未打补丁时服务端注入 ps=false，前端降级到默认主题；');
  console.log('      打补丁后注入 ps=true，同样的前端请求直接应用高级主题。');
})().catch(e => { console.error('FATAL', e); process.exit(1); });
