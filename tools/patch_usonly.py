def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/sm64x.py', [
('''def strip_comments(t):
    t = re.sub(r'/\\*.*?\\*/', '', t, flags=re.S)
    t = re.sub(r'//[^\\n]*', '', t)
    return t
''', '''def _us_defines():
    """The macros the US game's data is built with: VERSION_US, and config.h's BUGFIX_* (each an expression of
    VERSION_*), evaluated."""
    d = {'VERSION_US': 1, 'VERSION_JP': 0, 'VERSION_EU': 0, 'VERSION_SH': 0, 'VERSION_CN': 0}
    p = os.path.join(D, 'include', 'config.h')
    if os.path.exists(p):
        for m in re.finditer(r'^#define\\s+(BUGFIX_\\w+)\\s+(.+)$', open(p, encoding='utf-8', errors='replace').read(), re.M):
            v = _eval_cond(m.group(2), d)
            if v is not None:
                d[m.group(1)] = int(v)
    return d


def _eval_cond(expr, d):
    """A preprocessor condition over known macros (defined(X), X, !, ||, &&, numbers), or None when it names
    anything else"""
    e = re.sub(r'defined\\s*\\(\\s*(\\w+)\\s*\\)', lambda m: ' 1 ' if d.get(m.group(1)) else ' 0 ', expr)
    e = re.sub(r'defined\\s+(\\w+)', lambda m: ' 1 ' if d.get(m.group(1)) else ' 0 ', e)
    for name in set(re.findall(r'\\b[A-Za-z_]\\w*\\b', e)):
        if name not in d:
            return None
    e = re.sub(r'\\b[A-Za-z_]\\w*\\b', lambda m: ' %d ' % d[m.group(0)], e)
    e = e.replace('||', ' or ').replace('&&', ' and ')
    e = re.sub(r'!(?!=)', ' not ', e)
    try:
        return bool(eval(e, {'__builtins__': {}}, {}))
    except Exception:
        return None


_US = None


def us_only(t):
    """C source as the US game is built: of each #if/#ifdef/#ifndef block over VERSION_* or BUGFIX_* macros, only
    the half the US build takes (both halves were read before 2026-10-15: JP and US vertices, collision and objects
    side by side - JRB's star box held a loose JP star and a Wing Cap). Blocks over anything else are left whole."""
    global _US
    if '#if' not in t:
        return t
    if _US is None:
        _US = _us_defines()
    out, stack = [], []            # each: [resolved?, this branch on?, a branch taken?]
    for line in t.split('\\n'):
        s = line.strip()
        if s.startswith('#if'):
            if s.startswith('#ifdef'):
                c = _eval_cond('defined(%s)' % s[6:].strip(), _US)
            elif s.startswith('#ifndef'):
                c = _eval_cond('!defined(%s)' % s[7:].strip(), _US)
            else:
                c = _eval_cond(s[3:], _US)
            if c is None:
                stack.append([False, True, True])
                out.append(line)
            else:
                stack.append([True, c, c])
                out.append('')
            continue
        if stack and (s.startswith('#elif') or s.startswith('#else') or s.startswith('#endif')):
            top = stack[-1]
            if not top[0]:
                out.append(line)
                if s.startswith('#endif'):
                    stack.pop()
                continue
            if s.startswith('#elif'):
                c = _eval_cond(s[5:], _US)
                c = bool(c) and not top[2]
                top[1], top[2] = c, top[2] or c
            elif s.startswith('#else'):
                top[1], top[2] = not top[2], True
            else:
                stack.pop()
            out.append('')
            continue
        out.append(line if all(e[1] for e in stack) else '')
    return '\\n'.join(out)


def strip_comments(t):
    t = re.sub(r'/\\*.*?\\*/', '', t, flags=re.S)
    t = re.sub(r'//[^\\n]*', '', t)
    return us_only(t)
'''),
])
print('ok')
