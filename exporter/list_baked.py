"""Which solid objects (behaviours with a collision model) are still built into the levels standing still, by level."""
import re, glob, os, collections, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import platx as P

bc = X.behavior_collisions()
root = 'X:/mashup-work/sm64decomp/levels'
cnt = collections.defaultdict(collections.Counter)
files = glob.glob(root + '/*/script.c') + glob.glob(root + '/*/areas/*/script.c') + glob.glob(root + '/*/areas/*/*/script.c')
for f in files:
    lvl = f.replace(os.sep, '/').split('/levels/')[1].split('/')[0]
    for m in re.finditer(r'bhv[A-Za-z0-9_]+', open(f, encoding='utf-8', errors='ignore').read()):
        b = m.group(0)
        if b in bc and b not in P.HANDLED:
            cnt[b][lvl] += 1
# macro and special objects too
for f in glob.glob(root + '/*/areas/*/macro.inc.c'):
    lvl = f.replace(os.sep, '/').split('/levels/')[1].split('/')[0]
    cnt['(macro file)'][lvl] += 0
for b, c in sorted(cnt.items(), key=lambda kv: -sum(kv[1].values())):
    if sum(c.values()):
        print(b, bc.get(b), dict(c))
