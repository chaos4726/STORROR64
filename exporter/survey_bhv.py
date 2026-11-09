import os, sys, re, collections
os.environ.setdefault('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
import sm64x as X
import sm64scenes as S
import warpx as W
import build_all as BA
cnt = collections.Counter()
where = collections.defaultdict(set)
models = {}
presets = BA.macro_table() if hasattr(BA, 'macro_table') else None
for name, level, area in BA.all_scenes():
    try:
        for o in X.parse_objects(level):
            if o.get('area') != area or 'bhv' not in o: continue
            cnt[o['bhv']] += 1; where[o['bhv']].add(name); models[o['bhv']] = o.get('model')
    except Exception as e:
        print('!!', name, e)
    try:
        blocks = S.area_blocks(level)[area]
        if blocks['macro']:
            for mo in X.parse_macro_objects(level, area):
                b = 'macro:' + mo['preset']
                cnt[b] += 1; where[b].add(name)
    except Exception as e:
        print('!! macro', name, e)
for b, n in cnt.most_common():
    print('%-45s %4d  %-28s %s' % (b, n, models.get(b, ''), ' '.join(sorted(where[b]))[:120]))
