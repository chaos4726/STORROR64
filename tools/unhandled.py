"""Behaviours placed by the level scripts that neither the exporter nor any of the mod's scripts mention.
python tools/unhandled.py   (from X:/mashup-work)"""
import collections
import glob
import re

use = collections.defaultdict(set)
for f in glob.glob('sm64decomp/levels/*/script.c') + glob.glob('sm64decomp/levels/*/areas/*/script.c'):
    lvl = f.replace(chr(92), '/').split('/')[2]
    for m in re.finditer(r'/\*bhv\*/\s*(bhv\w+)', open(f).read()):
        use[m.group(1)].add(lvl)
src = ''
for f in glob.glob('exporter/*.py') + glob.glob('*.lua'):
    if '.before' in f:
        continue
    src += open(f, encoding='utf-8', errors='ignore').read()
for b in sorted(use):
    if not re.search(r'\b' + b + r'\b', src):
        print(b, sorted(use[b]))

# (those whose script loads a collision model come through as solid scenery anyway: shown apart)
bd = open('sm64decomp/data/behavior_data.c').read()
col = set(m.group(1) for m in re.finditer(r'const BehaviorScript (bhv\w+)\[\] = \{(?:(?!\};).)*?LOAD_COLLISION_DATA', bd, re.S))
print('--- of those, with collision:', ' '.join(b for b in sorted(use) if b in col and not re.search(r'\b' + b + r'\b', src)))

# macro objects: preset -> behaviour (include/macro_presets.inc.c), used in levels/*/areas/*/macro.inc.c
pre = {}
for m in re.finditer(r'/\*\s*(macro_\w+)\s*\*/\s*\{\s*(bhv\w+)', open('sm64decomp/include/macro_presets.inc.c').read()):
    pre[m.group(1)] = m.group(2)
muse = collections.defaultdict(set)
for f in glob.glob('sm64decomp/levels/*/areas/*/macro.inc.c'):
    lvl = f.replace(chr(92), '/').split('/')[2]
    for m in re.finditer(r'preset\*/\s*(macro_\w+)', open(f).read()):
        b = pre.get(m.group(1))
        if b:
            muse[b].add(lvl)
print('--- macro behaviours no code names:')
for b in sorted(muse):
    if not re.search(r'\b' + b + r'\b', src):
        print(b, sorted(muse[b]))
