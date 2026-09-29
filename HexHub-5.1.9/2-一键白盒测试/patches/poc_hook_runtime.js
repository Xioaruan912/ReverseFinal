/* ============================================================================
 * HexHub VIP 鉴权旁路 PoC —— 运行时 Hook（无需伪造持久化数据）
 * ----------------------------------------------------------------------------
 * 场景：用户持有一个【已过期】或【免费】的真实账号。
 *       登录后服务端会返回真实 member 对象并覆盖本地持久化数据，
 *       因此单纯伪造 localStorage 会被刷新覆盖 —— 此时改用运行时 Hook。
 *
 * 原理：session store 的 isMemberValid() 只读取 this.member.endTime 做比较。
 *       将 store action 替换为恒真即可，无需触碰服务端数据。
 *       同时 hook ue() 完整性校验（可选），以兼容被篡改的 member。
 *
 * 注意：本文件需在页面 JS 加载完成后执行；store action 是对象字面量方法，
 *       无法直接通过全局句柄拿到，因此采用「原型级 endTime 拦截 + 兜底」策略：
 *       实际推荐直接用 ../patch_vip.py 对 bundle 做等长二进制补丁（已验证）。
 * ============================================================================ */

(() => {
  const LIFETIME = 2524579200000;   // 2050-01-01

  // ---- 策略 1：拦截 JSON.parse，篡改 pinia 恢复出的 member ----------------
  const _parse = JSON.parse;
  JSON.parse = function (text, reviver) {
    const out = _parse.call(this, text, reviver);
    try {
      if (out && typeof out === 'object' && out.member && typeof out.member === 'object') {
        out.member.endTime = LIFETIME;
        out.member.isPlus = true;
        console.log('%c[Hook] member restored -> lifetime Plus', 'color:#0a0');
      }
    } catch (e) {}
    return out;
  };

  // ---- 策略 2：兜底 —— 让任何读取 endTime 的对象都返回终身值 --------------
  // （仅在策略 1 失效时启用；副作用较大，谨慎使用）
  if (new URLSearchParams(location.search).get('hook2') === '1') {
    Object.defineProperty(Object.prototype, 'endTime', {
      configurable: true,
      get() { return LIFETIME; },
      set() {},
    });
    console.log('%c[Hook2] Object.prototype.endTime -> lifetime', 'color:#a00');
  }

  console.log('%c[HexHub PoC] runtime hook installed', 'color:#0a0;font-weight:bold');
  location.reload();
})();
