import re, sys

BIN = "samples/extracted/hexhub-backend.exe"
d = open(BIN, 'rb').read()


def beautify(js):
    out = []
    depth = 0
    i = 0
    n = len(js)
    buf = []
    while i < n:
        c = js[i]
        if c == '"' or c == "'" or c == '`':
            q = c
            j = i + 1
            while j < n:
                if js[j] == '\\':
                    j += 2
                    continue
                if js[j] == q:
                    break
                j += 1
            buf.append(js[i:j+1])
            i = j + 1
            continue
        if c == '{':
            depth += 1
            buf.append('{')
            out.append(''.join(buf))
            buf = ['    ' * depth]
            i += 1
            continue
        if c == '}':
            out.append(''.join(buf))
            buf = []
            depth = max(0, depth - 1)
            buf.append('    ' * depth)
            buf.append('}')
            i += 1
            continue
        if c == ';':
            buf.append(';')
            out.append(''.join(buf))
            buf = ['    ' * depth]
            i += 1
            continue
        buf.append(c)
        i += 1
    out.append(''.join(buf))
    return '\n'.join(x for x in out if x.strip())


if __name__ == '__main__':
    start = int(sys.argv[1])
    end = int(sys.argv[2])
    js = d[start:end].decode('latin1')
    print(beautify(js))
