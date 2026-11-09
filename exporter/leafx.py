# leafx.py: a falling leaf (leaves_geo: what a tree sheds as Mario climbs it) into SM64_OUT
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
a = S.export_actor(BA.db, 'leaves_geo', [], BA.textures, switch=0)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_leaves_geo.lua'), a)
print('wrote actor leaves, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
