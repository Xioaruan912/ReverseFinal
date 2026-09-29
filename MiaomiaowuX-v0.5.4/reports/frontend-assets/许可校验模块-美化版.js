}
const Hy = ['sea', 'amber', 'ice', 'graphite', 'custom'];

function d0(_0x22c040 = null) {
  const [_0x3892bd, _0x344822] = _0x4eb10f['useState'](_0x22c040);
  return [_0x3892bd, _0x4d6d09 => _0x344822(_0x4bddb7 => _0x4bddb7 === _0x4d6d09 ? null : _0x4d6d09)];
}
const c0 = '1mOqVQuZPyeioJVLzG66z+Xdh3AdpdL0JsTmZ2nlEEA=',
  u0 = 'mmwx-entitlement-v2\x0a',
  p0 = 'mmwx-signing-key-cert-v1\x0a',
  m0 = 'mmwx-entitlement-session-v1\x0a',
  ju = 'license.miaomiaowux.com',
  f0 = 'mmwx-master',
  Hu = 0x12c;

function Yt(_0x4b86c8) {
  const _0x570e0b = atob(_0x4b86c8),
    _0x177f39 = new Uint8Array(_0x570e0b['length']);
  for (let _0x3214e5 = 0x0; _0x3214e5 < _0x570e0b['length']; _0x3214e5++) _0x177f39[_0x3214e5] = _0x570e0b['charCodeAt'](_0x3214e5);
  return _0x177f39;
}

function Ce(_0x649b95) {
  let _0x3d6a61 = _0x649b95['replace'](/-/g, '+')['replace'](/_/g, '/');
  for (; _0x3d6a61['length'] % 0x4;) _0x3d6a61 += '=';
  return Yt(_0x3d6a61);
}
const x0 = new TextEncoder();

function Je(_0x43e37b) {
  return x0['encode'](_0x43e37b);
}

function g0(_0x6101e9) {
  return Array['from'](_0x6101e9, _0x5f21e0 => _0x5f21e0['toString'](0x10)['padStart'](0x2, '0'))['join']('');
}
const h0 = Yt(c0);

function b0(_0x4513eb, _0x2f5ded, _0x455c90) {
  if (_0x4513eb === '') return _0x455c90;
  const _0x2a28d1 = _0x2f5ded['split']('.');
  if (_0x2a28d1['length'] !== 0x2) return null;
  const [_0x5aade2, _0x3d32ab] = _0x2a28d1, _0x2306aa = Ce(_0x3d32ab);
  if (_0x2306aa['length'] !== 0x40 || !_0x42154b['verify'](_0x2306aa, Je(p0 + _0x5aade2), _0x455c90)) return null;
  let _0x357c30;
  try {
    _0x357c30 = JSON['parse'](new TextDecoder()['decode'](Ce(_0x5aade2)));
  } catch {
    return null;
  }
  if (_0x357c30['version'] !== 0x1 || _0x357c30['issuer'] !== ju || _0x357c30['key_id'] !== _0x4513eb) return null;
  const _0x4ae2ba = Math['floor'](Date['now']() / 0x3e8);
  if (_0x357c30['expires_at'] <= _0x357c30['issued_at'] || _0x4ae2ba > _0x357c30['expires_at'] + Hu) return null;
  const _0x23ef0d = Yt(_0x357c30['public_key']);
  return _0x23ef0d['length'] === 0x20 ? _0x23ef0d : null;
}

function y0(_0x7ab10b, _0x416ebf, _0x54097e, _0x139c87, _0x10b5da, _0x472173) {
  const _0x2f2e73 = h0;
  if (!_0x7ab10b) return null;
  const _0x35a25a = _0x7ab10b['split']('.');
  let _0x333886 = '',
    _0x1c1017 = '',
    _0x4fe65a = '';
  if (_0x35a25a['length'] === 0x2)[_0x1c1017, _0x4fe65a] = _0x35a25a;
  else {
    if (_0x35a25a['length'] === 0x3)[_0x333886, _0x1c1017, _0x4fe65a] = _0x35a25a;
    else return null;
  }
  const _0x2eecca = b0(_0x333886, _0x416ebf ?? '', _0x2f2e73);
  if (!_0x2eecca) return null;
  const _0x5d2a00 = Ce(_0x4fe65a);
  if (_0x5d2a00['length'] !== 0x40 || !_0x42154b['verify'](_0x5d2a00, Je(u0 + _0x1c1017), _0x2eecca)) return null;
  let _0x3b0e11;
  try {
    _0x3b0e11 = JSON['parse'](new TextDecoder()['decode'](Ce(_0x1c1017)));
  } catch {
    return null;
  }
  if (_0x3b0e11['version'] !== 0x2 || _0x3b0e11['issuer'] !== ju || _0x3b0e11['audience'] !== f0) return null;
  const _0x2e6fea = Math['floor'](Date['now']() / 0x3e8);
  if (_0x3b0e11['issued_at'] <= 0x0 || _0x3b0e11['expires_at'] <= _0x3b0e11['issued_at'] || _0x2e6fea > _0x3b0e11['expires_at'] + Hu || !_0x54097e || !_0x139c87 || !_0x10b5da || _0x3b0e11['master_public_key'] !== _0x139c87) return null;
  const _0x3bce55 = Ce(_0x139c87);
  if (_0x3bce55['length'] !== 0x20) return null;
  const _0x367a77 = g0(_0x18f172(Je(_0x7ab10b))),
    _0x4ad800 = m0 + _0x10b5da + '\x0a' + _0x367a77,
    _0x3f5b51 = Ce(_0x54097e);
  return _0x3f5b51['length'] !== 0x40 || !_0x42154b['verify'](_0x3f5b51, Je(_0x4ad800), _0x3bce55) ? null : {
    'claims': _0x3b0e11,
    'hasFeature': _0x22f219 => _0x3b0e11['features']?.['includes'](_0x22f219) ?? !0x1
  };
}

function v0(_0xdc17d7) {
  return _0xdc17d7?.['premium_theme'] === !0x0;
}

function S0() {
  const {
    auth: _0x14fb58
  } = _();
  return _0x8fb83({
    'queryKey': ['user-license-status'],
    'queryFn': async () => {
      const _0x3a22e2 = (await N['get']('¤da0940d441a26653'))['data'],
        _0x934a = y0(_0x3a22e2['entitlement'], _0x3a22e2['signing_key_certificate'], _0x3a22e2['entitlement_session_sig'], _0x3a22e2['master_public_key'], te['getSessionId']());
      return _0x3a22e2['_verifiedFeatures'] = _0x934a ? _0x934a['claims']['features'] : null, _0x3a22e2;
    },
    'enabled': !!_0x14fb58['accessToken'],
    'staleTime': 0x12c * 0x3e8
  });
}

function By() {
  const {
    auth: _0x2b7e14
  } = _();
  return _0x8fb83({
    'queryKey': ['admin-license-usage'],
    'queryFn': async () => (await N['get']('§f5443736690ff429'))['data'],
    'enabled': !!_0x2b7e14['accessToken'],
    'staleTime': 0x1e * 0x3e8
  });
}

function Gy(_0x1823f4) {
  const {
    data: _0x52cc07
  } = S0(), _0x160d33 = _0x52cc07?.['_verifiedFeatures'];
  let _0x5c3c11;
  return _0x160d33 ? _0x5c3c11 = _0x160d33['includes'](_0x1823f4) : _0x5c3c11 = _0x52cc07?.['plan']?.['features']?.['includes'](_0x1823f4) ?? !0x1, {
    'hasFeature': _0x5c3c11,
    'plan': _0x52cc07?.['plan']
  };
}
const yn = '0.5.4',
  C0 = 'https://github.com/iluobei/miaomiaowuX/releases';

function W0(_0x412015 = !0x0) {
  const _0x145205 = localStorage['getItem']('mmwx-update-channel') === 'prerelease' ? 'prerelease' : 'stable',
    {
      data: _0x553d0f
    } = _0x8fb83({
      'queryKey': ['update-check', _0x145205],
      'queryFn': async () => (await N['get']('§32a29375dacb94db', {
        'params': {
          'channel': _0x145205
        }
      }))['data'],
      'enabled': _0x412015,
      'staleTime': 0x3e8 * 0x3c * 0x3c,
      'gcTime': 0x3e8 * 0x3c * 0x3c * 0x18,
      'retry': 0x1,
      'refetchOnWindowFocus': !0x1
    });