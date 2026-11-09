"""Special objects (SPECIAL_OBJECT in the levels' collision files) and whether the exporter handles each preset."""
import re, glob, collections
use = collections.defaultdict(set)
for f in glob.glob('sm64decomp/levels/*/areas/*/collision.inc.c'):
    lvl = f.replace(chr(92), '/').split('/')[2]
    t = open(f).read()
    for m in re.finditer(r'SPECIAL_OBJECT\w*\s*\(\s*(?:/\*preset\*/\s*)?(special_\w+)', t):
        use[m.group(1)].add(lvl)
src = open('exporter/build_all.py', encoding='utf-8').read() + open('exporter/warpx.py', encoding='utf-8').read() + open('exporter/platx.py', encoding='utf-8').read()
pres = open('sm64decomp/include/special_presets.inc.c').read()
for p in sorted(use):
    bm = re.search(r'\{\s*' + p + r'\s*,\s*\w+\s*,\s*\w+\s*,\s*(\w+)', pres)
    bhv = bm.group(1) if bm else '?'
    handled = p in src or bhv in src
    print('ok       ' if handled else 'MISSING  ', p, bhv, sorted(use[p]))
