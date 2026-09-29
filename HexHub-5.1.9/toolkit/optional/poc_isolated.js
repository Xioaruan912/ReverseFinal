/* ============================================================================
 * HexHub VIP 鉴权脆弱性 PoC —— 隔离版（不触碰宿主任何配置）
 * ----------------------------------------------------------------------------
 * 与 poc_offline_vip.js 的差异：
 *   1. 断网只在【页面级】拦截（Playwright route abort），不改 hosts / 防火墙
 *   2. CDP 端口通过环境变量 HEXHUB_CDP_PORT 传入，避免与用户环境冲突
 *   3. 只操作沙箱 profile（由 run_isolated.ps1 通过 junction 重定向）
 *   4. 不调用 browser.close()，避免关闭被连接的 CEF 应用
 * ============================================================================ */
const { chromium } = require('playwright');
const crypto = require('crypto');

const PORT = process.env.HEXHUB_CDP_PORT || '9222';
const sha256hex = s => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

// ---- 伪造会员对象（sign 为客户端可离线自算的自证式哈希） ----
const ENDTIME = 2524579200000;             // 2050-01-01 = 终身版哨兵值
const EMAIL = 'audit@hexhub.local';
const PUBKEY = 'audit-pubkey';
const SIGN = sha256hex(`${ENDTIME}*${EMAIL}*${sha256hex(PUBKEY)}`);
const SESSION = {
  token: 'forged-token-audit',
  priKey: 'forged-prikey-audit',
  member: { id: 1000001, memberId: 1000001, email: EMAIL, name: 'AuditTester',
            endTime: ENDTIME, isPlus: true, publicKey: PUBKEY, sign: SIGN },
};

(async () => {
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`);
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('35580')) || ctx.pages()[0];
  page.on('dialog', d => { d.accept().catch(() => {}); });

  // ① 页面级断网（等价于"阻断厂商授权服务器"，但零系统改动）
  await page.route('**://api.hexhub.cn/**', r => r.abort('connectionfailed'));
  await page.route('**://oss.hexhub.cn/**', r => r.abort('connectionfailed'));
  console.log('[+] 已在页面级阻断 api.hexhub.cn / oss.hexhub.cn（未修改 hosts / 防火墙）');

  // ② 注入伪造会话
  await page.evaluate(s => localStorage.setItem('session', JSON.stringify(s)), SESSION);
  console.log('[+] 已写入伪造 session');

  // ③ 重载使 pinia-persistedstate 恢复伪造状态
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(12000);

  // ④ 取证
  const r = await page.evaluate(() => {
    const txt = document.body.innerText;
    const crowns = [...document.querySelectorAll('.mdi-crown')];
    let sess = {};
    try { sess = JSON.parse(localStorage.getItem('session') || '{}'); } catch (e) {}
    return {
      crownCount: crowns.length,
      hasPlusLabel: /(^|\n)\s*(Plus|Pro)\s*(\n|$)/.test(txt),
      memberKept: !!sess.member,
      endTime: sess.member ? sess.member.endTime : null,
      isLifetimeSentinel: !!(sess.member && sess.member.endTime >= 2524579200000),
      isMemberValid: !!(sess.member && sess.member.endTime > Date.now()),
      loggedIn: /请检查是否登录/.test(txt) ? false : true,
    };
  });

  console.log('\n=== 判定结果 ===');
  console.log(JSON.stringify(r, null, 2));
  console.log('\n=== 结论 ===');
  if (r.crownCount > 0 && r.isLifetimeSentinel) {
    console.log('  ✔ 漏洞成立：未登录 + 厂商服务器不可达，顶栏仍显示会员徽章（VIP 旁路成功）');
  } else {
    console.log('  ✘ 未复现，请检查隔离/断网是否生效');
  }

  await page.screenshot({ path: 'exports/poc_isolated_vip.png' });
  console.log('\n[+] 截图 -> exports/poc_isolated_vip.png');
  process.exit(0);      // 注意：不要 browser.close()，会关掉被测应用
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
