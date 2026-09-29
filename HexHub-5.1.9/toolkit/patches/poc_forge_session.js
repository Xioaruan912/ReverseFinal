/* ============================================================================
 * HexHub 客户端 VIP 鉴权旁路 PoC —— 本地会话凭证伪造（Local Subscription Spoofing）
 * ----------------------------------------------------------------------------
 * 目标：HexHub Client 5.1.9 (windows-amd64)
 * 类型：CWE-602 客户端强行实施服务端安全机制 / CWE-472 外部可控的假定不可变参数
 *
 * 原理（逆向自内嵌前端 bundle）：
 *   session store (pinia, persist=true, storage=localStorage, key="session")
 *     isMemberValid() { return this.member?.endTime ? this.member.endTime > Date.now() : false }
 *   成员对象完整性校验：
 *     ue(m) => SHA256(`${m.endTime}*${m.email}*${SHA256(m.publicKey)}`) === m.sign
 *   -> 校验式为「自证式哈希」，不含任何服务端密钥，客户端可离线自算。
 *   -> 会话落盘于 localStorage["session"]，离线（厂商服务器不可达）时不会被服务端覆盖。
 *
 * 使用方式（三选一）：
 *   A. CEF DevTools 控制台：打开 DevTools，粘贴本文件全部内容后回车，页面自动重载。
 *   B. Playwright/CDP 注入：见 ../poc_offline_vip.js
 *   C. 隐藏入口：设置里 basicDebug 快捷键输入 MD5(localStorage["system-info"].deviceId)
 *      即可唤出 DevTools（厂商自带调试后门，见报告 3.3 节）。
 *
 * 前置条件：让 api.hexhub.cn / oss.hexhub.cn 不可达（离线 / hosts 黑洞 / 防火墙），
 *          否则伪造 token 会被服务端 401 触发 axios 拦截器 logout() 清空会话。
 * ============================================================================ */

(async () => {
  // ★ 完整性校验用的是 SHA-1（crypto chunk 导出 S = _createHelper(SHA1Algo)）
  const sha1hex = async (s) => {
    const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s));
    return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
  };

  // ---- 1. 伪造会员对象 ----------------------------------------------------
  const ENDTIME = 2524579200000;              // 2050-01-01，>= 该值即被 UI 判为「终身版」
  const EMAIL   = 'audit@hexhub.local';
  const PUBKEY  = 'audit-pubkey';
  const SIGN    = await sha1hex(`${ENDTIME}*${EMAIL}*${await sha1hex(PUBKEY)}`);

  const member = {
    id: 1000001,
    memberId: 1000001,
    email: EMAIL,
    name: 'AuditTester',
    endTime: ENDTIME,
    isPlus: true,          // true -> 顶栏显示「Plus / 增强版」；false -> 「Pro / 专业版」
    publicKey: PUBKEY,
    sign: SIGN,            // 自算签名，通过 ue() 完整性校验
  };

  // ---- 2. 写入持久化会话 --------------------------------------------------
  localStorage.setItem('session', JSON.stringify({
    token:  'forged-token-audit',
    priKey: 'forged-prikey-audit',
    member,
  }));

  console.log('%c[HexHub PoC] forged session written', 'color:#0a0;font-weight:bold');
  console.table(member);

  // ---- 3. 重载使 pinia-persistedstate 恢复伪造状态 -------------------------
  location.reload();
})();
