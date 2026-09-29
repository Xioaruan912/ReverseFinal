import re

def strs(path, minlen=4):
    d = open(path, 'rb').read()
    for m in re.finditer(rb'[\x20-\x7e]{%d,}' % minlen, d):
        yield m.start(), m.group().decode('ascii', 'ignore')

if __name__ == '__main__':
    import sys
    path = sys.argv[1]
    pats = [p.lower() for p in sys.argv[2:]]
    seen = set()
    for off, s in strs(path, 5):
        ls = s.lower()
        if any(p in ls for p in pats):
            k = s[:200]
            if k in seen:
                continue
            seen.add(k)
            print(f"{off:>10}  {s[:220]}")
