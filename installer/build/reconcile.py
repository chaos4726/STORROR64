#!/usr/bin/env python3
"""The mod's data files as they were when it was made, from the same files built fresh from the player's ROM.

Some of the mod's data files were fixed by hand after the exporter wrote them, or come from an earlier run of it (the
penguin's eye picture, the Bullet Bill's colours, the scenes exported before the exporter changed). The installer
builds every file fresh from the player's ROM; for those, a patch turns the fresh file into the mod's. A patch holds
no game content: only "copy tokens a..b of the fresh file" and the few words written by hand ("_blend", "1", a comment).

  reconcile.py make <fresh dir> <made dir> <patch dir> <file>...   (where the mod is made: writes <patch dir>/<file>.json)
  reconcile.py apply <data dir> <patch dir>                       (the installer: every patch in <patch dir> applied)
"""
import difflib, json, os, re, sys

TOK = re.compile(r'\s+|-?\d+(?:\.\d+)?(?:e[-+]?\d+)?|[A-Za-z_][A-Za-z_0-9]*|"(?:[^"\\]|\\.)*"|.', re.S)


def line_tokens(line):
    return TOK.findall(line)


def tokens(text):
    # (line by line, so that a run of spaces never runs over a line's end: make and apply split alike)
    return [t for l in text.splitlines(True) for t in TOK.findall(l)]


def make(fresh, made):
    # (by lines first - a scene file is a few thousand lines, some of them long lists - then token by token inside the
    # lines that differ: the whole files token by token took far too long)
    la, lb = fresh.splitlines(True), made.splitlines(True)
    ta = [line_tokens(l) for l in la]
    start = [0]
    for t in ta:
        start.append(start[-1] + len(t))
    ops = []

    def copy(i, n):
        if n <= 0:
            return
        if ops and ops[-1][0] == 'c' and ops[-1][1] + ops[-1][2] == i:
            ops[-1][2] += n
        else:
            ops.append(['c', i, n])

    def lit(s):
        if not s:
            return
        if ops and ops[-1][0] == 'l':
            ops[-1][1] += s
        else:
            ops.append(['l', s])

    def tokdiff(i1, i2, j1, j2):
        a = [t for l in ta[i1:i2] for t in l]
        b = [t for l in lb[j1:j2] for t in line_tokens(l)]
        sm2 = difflib.SequenceMatcher(None, a, b, autojunk=False)
        for t2, k1, k2, m1, m2 in sm2.get_opcodes():
            if t2 == 'equal':
                copy(start[i1] + k1, k2 - k1)
            elif m2 > m1:
                lit(''.join(b[m1:m2]))

    def key(line):
        m = re.match(r'\s*([A-Za-z_]\w*)\s*=', line)
        return m.group(1) if m else line.strip()[:1]

    sm = difflib.SequenceMatcher(None, la, lb, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            copy(start[i1], start[i2] - start[i1])
            continue
        if j2 == j1:
            continue
        if (i2 - i1) * (j2 - j1) > 1 and (i2 - i1) > 1:
            # (a long stretch changed - a scene's sections laid out anew: its lines paired by what they hold, "pos =" with
            # "pos =" in order, and each pair compared token by token; a line with no partner written as it is)
            ka = [key(l) for l in la[i1:i2]]
            kb = [key(l) for l in lb[j1:j2]]
            pairs = difflib.SequenceMatcher(None, ka, kb, autojunk=False).get_opcodes()
            for t3, p1, p2, q1, q2 in pairs:
                if t3 == 'equal':
                    for k in range(p2 - p1):
                        tokdiff(i1 + p1 + k, i1 + p1 + k + 1, j1 + q1 + k, j1 + q1 + k + 1)
                elif q2 > q1:
                    if p2 > p1 and (p2 - p1) * (q2 - q1) <= 4:
                        tokdiff(i1 + p1, i1 + p2, j1 + q1, j1 + q2)
                    else:
                        lit(''.join(lb[j1 + q1:j1 + q2]))
            continue
        tokdiff(i1, i2, j1, j2)
    return {'tokens': start[-1], 'ops': ops}


def apply(fresh, patch):
    a = tokens(fresh)
    if len(a) != patch['tokens']:
        raise ValueError('the fresh file is not the one the patch was made for (%d tokens, %d)' % (len(a), patch['tokens']))
    out = []
    for op in patch['ops']:
        out.append(''.join(a[op[1]:op[1] + op[2]]) if op[0] == 'c' else op[1])
    return ''.join(out)


def literals(patch):
    return [op[1] for op in patch['ops'] if op[0] == 'l']


def main():
    if len(sys.argv) >= 6 and sys.argv[1] == 'make':
        fresh_dir, made_dir, patch_dir = sys.argv[2:5]
        os.makedirs(patch_dir, exist_ok=True)
        for name in sys.argv[5:]:
            fresh = open(os.path.join(fresh_dir, name), encoding='utf-8', newline='').read()
            made = open(os.path.join(made_dir, name), encoding='utf-8', newline='').read()
            p = make(fresh, made)
            if apply(fresh, p) != made:
                print('%s: the patch does not give the file back' % name)
                continue
            json.dump(p, open(os.path.join(patch_dir, name + '.json'), 'w', encoding='utf-8'), separators=(',', ':'))
            lit = literals(p)
            print('%s: %d copies, %d words by hand (%d characters)%s' % (name, sum(1 for o in p['ops'] if o[0] == 'c'), len(lit),
                                                                       sum(len(x) for x in lit), (': ' + repr(lit[:6])[:300]) if lit else ''))
    elif len(sys.argv) == 4 and sys.argv[1] == 'apply':
        data_dir, patch_dir = sys.argv[2:4]
        for f in sorted(os.listdir(patch_dir)):
            if not f.endswith('.json'):
                continue
            name = f[:-5]
            path = os.path.join(data_dir, name)
            fresh = open(path, encoding='utf-8', newline='').read()
            out = apply(fresh, json.load(open(os.path.join(patch_dir, f), encoding='utf-8')))
            open(path, 'w', encoding='utf-8', newline='').write(out)
            print('patched', name)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
