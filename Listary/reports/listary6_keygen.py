#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Listary 6 Pro license keygen  (white-box audit PoC)

Reconstructed from Listary.Core.Pro.LicenseChecker (Babel Obfuscator v10, "BabelOut")
after runtime recovery of the AES-encrypted method bodies.

Root cause (CWE-602 / CWE-345):
    The entitlement decision is made 100% client-side by a *reversible, non-cryptographic*
    function of the licensee e-mail only.  Positions 0..159 and 179..191 of the 192-char
    license string are NEVER validated, and no server signature / MAC is verified.

Algorithm:
    email_lc = lowercase(email)
    h96      = F0(email_lc) << 64 | F1(email_lc) << 32 | F2(email_lc)     (96-bit)
    code     = 19 chars, MSB-first 5-bit groups of h96 >> (96 - (i+1)*5), & 31
               mapped through the alphabet "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    license[160:179] must equal `code` ; len(license) must be 192
    reject if md5hex_lower(email_lc + "<SALT_REDACTED>") is in the revocation list.
"""
import hashlib
import sys

ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
SALT = "<SALT_REDACTED>"
LICENSE_LEN = 192
CODE_OFFSET = 160
CODE_LEN = 19

# revoked/blacklisted entries observed in the shipped build (md5hex of email+salt)
BLACKLIST = {
    "<REVOKED_HASH_REDACTED>",
    "<REVOKED_HASH_REDACTED>",
    "<REVOKED_HASH_REDACTED>",
    "<REVOKED_HASH_REDACTED>",
    "<REVOKED_HASH_REDACTED>",
    "<REVOKED_HASH_REDACTED>",
}

M = 0xFFFFFFFF


def f0(s):
    """LicenseChecker::<\u200b> — h = 43*h + char"""
    h = 0
    for ch in s:
        h = (h * 43 + ord(ch)) & M
    return h


def f1(s):
    """LicenseChecker::<\u200b> — ELF hash: h = (h<<4)+c; g=h&0xF0000000; if g: h^=g>>24; h^=g"""
    h = 0
    for ch in s:
        h = ((h << 4) + ord(ch)) & M
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
            h ^= g
        h &= M
    return h


def f2(s):
    """LicenseChecker::<\u200b> — 4-way XOR of chars shifted by 8*j"""
    h = 0
    n = len(s)
    for j in range(4):
        for i in range(j, n, 4):
            h ^= (ord(s[i]) << ((j * 8) & 31))
            h &= M
    return h


def email_code(email):
    e = email.lower()
    h = (f0(e) << 64) | (f1(e) << 32) | f2(e)
    out = []
    for i in range(CODE_LEN):
        idx = (h >> (96 - (i + 1) * 5)) & 31
        out.append(ALPHABET[idx])
    return "".join(out)


def md5hex(s):
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def is_revoked(email):
    return md5hex(email.lower() + SALT) in BLACKLIST


def keygen(email, seed=None, filler=None):
    """Return a 192-char license valid for `email`.

    Only characters [160,179) are actually validated; the remaining 173 characters
    are unconstrained padding.  By default they are filled with pseudo-random
    alphabet characters so the result looks like a genuine vendor key.
    """
    code = email_code(email)
    if filler is not None:
        body = (filler * LICENSE_LEN)[:LICENSE_LEN]
    else:
        import random
        rnd = random.Random(seed if seed is not None else email)
        body = "".join(rnd.choice(ALPHABET) for _ in range(LICENSE_LEN))
    lic = body[:CODE_OFFSET] + code + body[CODE_OFFSET + CODE_LEN:]
    assert len(lic) == LICENSE_LEN
    return lic


def pretty(lic, group=32):
    # Vendor UI asks the user to paste "6 lines" of key;
    # the app strips whitespace with regex \s+ so the wrapping is cosmetic.
    return "\n".join(lic[i:i + group] for i in range(0, len(lic), group))


if __name__ == "__main__":
    email = sys.argv[1] if len(sys.argv) > 1 else "user@example.com"
    print("email      :", email)
    print("h-code     :", email_code(email))
    print("revoked    :", is_revoked(email))
    lic = keygen(email)
    print("license    :", lic)
    print("grouped(6行):")
    print(pretty(lic))
    print("length     :", len(lic))
