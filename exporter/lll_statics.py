# lll_statics.py: Lethal Lava Land's level pieces that Mario 64 places as objects (bhvStaticObject) and the scene export
# left undrawn - two of its four MODEL_LEVEL_GEOMETRY_0C (lll_geo_000AC0) wedges, the ones at (-4607, 0, 3456) and
# (-5119, 0, -511) - as static platforms with no collision of their own (their floors are in the level's); and the falling
# platform's model with its collision (lll_geo_000B80, lll_seg7_collision_0701D21C) as a template platforms.lua takes.
# Starts data/extra_statics.lua (tools/ttm_statics.py, ttm_painting.py, thi_pipes.py and dorrie_low.py add to it).
# (The first one, 2026-10-19, was lost; written again 2026-11-01 for the installer: its output, the same.)
import os, sys, re, json
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import platx as P

textures, templates = {}, {}
keys = [P.template(BA.db, textures, templates, lambda s: s, 'lll_geo_000B80', 'lll_seg7_collision_0701D21C'),
        P.template(BA.db, textures, templates, lambda s: s, 'lll_geo_000AC0', '')]
OBJECTS = [('lll_geo_000AC0|', (-4607, 0, 3456), (0, 270, 0)), ('lll_geo_000AC0|', (-5119, 0, -511), (0, 0, 0))]


def fmt(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def lua(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k if re.match(r'^[A-Za-z_]\w*$', k) else '["%s"]' % k, lua(x)) for k, x in v.items()) + ' }'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, int): return str(v)
    if isinstance(v, float): return fmt(v)
    if v is None: return 'nil'
    return json.dumps(v)


out = ['-- Level pieces Mario 64 places as objects (bhvStaticObject) that the scene export left undrawn: drawn here, as',
       '-- static platforms with no collision of their own (their floors are in the level\'s). Made by lll_statics.py, '
       '2026-10-19 (TTM\'s mushroom towers:',
       '-- tools/ttm_statics.py, 2026-10-27).',
       'return {', '  lll = {', '    templates = {']
for k in keys:
    out.append('      ["%s"] = %s,' % (k, lua(templates[k])))
out += ['    },', '    objects = {']
for tpl, pos, ang in OBJECTS:
    out.append('      { kind = "platform", bhv = "static", tpl = "%s", pos = %s, ang = %s, bp = 0 },' % (tpl, lua(pos), lua(ang)))
out += ['    },', '  },', '}', '']
p = os.path.join(BA.DATA, 'extra_statics.lua')
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print('wrote', p, 'templates', keys)
