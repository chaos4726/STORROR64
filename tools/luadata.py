"""Read the mod's exported Lua data files (return { ... }) into Python: dicts, lists, numbers, strings, booleans."""
import re

_tok = re.compile(r'\s*(?:(--[^\n]*)|(-?\d+\.?\d*(?:[eE][-+]?\d+)?)|("(?:[^"\\]|\\.)*")|([A-Za-z_]\w*)|(\[|\]|\{|\}|=|,|;))')


def load(path):
    s = open(path, encoding='utf-8').read()
    toks, i = [], 0
    while i < len(s):
        m = _tok.match(s, i)
        if not m:
            if s[i:].strip() == '':
                break
            raise ValueError('bad char at %d: %r' % (i, s[i:i + 20]))
        i = m.end()
        if m.group(1):
            continue
        if m.group(2):
            toks.append(('n', float(m.group(2))))
        elif m.group(3):
            toks.append(('s', m.group(3)[1:-1]))
        elif m.group(4):
            toks.append(('id', m.group(4)))
        else:
            toks.append(('p', m.group(5)))
    pos = [0]

    def peek(k=0):
        return toks[pos[0] + k] if pos[0] + k < len(toks) else (None, None)

    def nxt():
        t = toks[pos[0]]
        pos[0] += 1
        return t

    def value():
        t = nxt()
        if t[0] in ('n', 's'):
            return t[1]
        if t[0] == 'id':
            if t[1] == 'true':
                return True
            if t[1] == 'false':
                return False
            if t[1] == 'nil':
                return None
            if t[1] == 'return':
                return value()
            raise ValueError('id ' + t[1])
        if t == ('p', '{'):
            return table()
        raise ValueError(str(t))

    def table():
        arr, d = [], {}
        while True:
            t = peek()
            if t == ('p', '}'):
                nxt()
                break
            if t[0] == 'id' and peek(1) == ('p', '='):
                k = nxt()[1]
                nxt()
                d[k] = value()
            elif t == ('p', '['):
                nxt()
                k = value()
                nxt()
                nxt()
                d[k] = value()
            else:
                arr.append(value())
            if peek() in (('p', ','), ('p', ';')):
                nxt()
        if d and arr:
            for j, v in enumerate(arr):
                d[j + 1] = v
            return d
        return d if d else arr

    return value()
