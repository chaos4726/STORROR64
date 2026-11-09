"""Macro objects the exporter leaves out, by preset, with their behaviour and the levels that place them."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
import sm64x as X
import enemyx as EN
import build_all as BA
import platx as P

handled = set(BA.COIN_FORMATIONS) | set(BA.SINGLE_PICKUPS) | set(BA.PROP_PRESETS)
mp = EN.macro_presets()
cnt = collections.defaultdict(collections.Counter)
for level in sorted(os.listdir('X:/mashup-work/sm64decomp/levels')):
    adir = 'X:/mashup-work/sm64decomp/levels/%s/areas' % level
    if not os.path.isdir(adir):
        continue
    for area in sorted(os.listdir(adir)):
        if not os.path.exists('%s/%s/macro.inc.c' % (adir, area)):
            continue
        try:
            mos = X.parse_macro_objects(level, int(area))
        except Exception as e:
            print('!!', level, area, e)
            continue
        for mo in mos:
            pr = mo['preset']
            b = (mp.get(pr) or ('?',))[0]
            if pr in handled or b in ('bhvExclamationBox', 'bhvBreakableBox', 'bhvBreakableBoxSmall', 'bhvJumpingBox'):
                continue
            if b in EN.ENEMY_BHVS or pr in ('macro_bobomb', 'macro_bobomb_stationary', 'macro_chain_chomp'):
                continue
            if BA.goomba_group(pr):
                continue
            if b in P.MACRO_PLATFORMS or pr.startswith('macro_fish_spawner_') or pr in (
                    'macro_seaweed_bundle', 'macro_hidden_blue_coin', 'macro_hidden_1up', 'macro_hidden_1up_trigger',
                    'macro_hidden_star_trigger'):
                continue
            cnt[(pr, b)][level] += 1
for (pr, b), c in sorted(cnt.items(), key=lambda kv: -sum(kv[1].values())):
    print('%-34s %-34s %s' % (pr, b, dict(c)))
