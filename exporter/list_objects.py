"""Level-script objects (OBJECT / OBJECT_WITH_ACTS) whose behaviour nothing in the exporter takes: not an enemy, not a
platform, not baked in as solid scenery, not named anywhere in build_all.py. By behaviour, with the levels."""
import os, re, sys, glob, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
import sm64x as X
import enemyx as EN
import platx as P

src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build_all.py'), encoding='utf-8').read()
named = set(re.findall(r"'(bhv\w+)'", src))
bc = X.behavior_collisions()
cnt = collections.defaultdict(collections.Counter)
root = 'X:/mashup-work/sm64decomp/levels'
for f in glob.glob(root + '/*/script.c') + glob.glob(root + '/*/areas/*/script.c'):
    lvl = f.replace(os.sep, '/').split('/levels/')[1].split('/')[0]
    t = X.strip_comments(open(f, encoding='utf-8', errors='ignore').read())
    for m in re.finditer(r'OBJECT(?:_WITH_ACTS)?\s*\((.*?)\)\s*,?\s*\n', t):
        bm = re.search(r'(bhv\w+)', m.group(1))
        if not bm:
            continue
        b = bm.group(1)
        if b in named or b in EN.ENEMY_BHVS or b in P.HANDLED or b in bc:
            continue
        cnt[b][lvl] += 1
for b, c in sorted(cnt.items(), key=lambda kv: -sum(kv[1].values())):
    print('%-38s %s' % (b, dict(c)))
