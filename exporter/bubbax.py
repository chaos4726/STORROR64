# bubbax.py: Bubba with its mouth open (bubba_geo, switch case 1: oAnimState 1) into SM64_OUT as actor_geo_bubba_open
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
a = S.export_actor(BA.db, 'bubba_geo', [], BA.textures, switch=1)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_bubba_open.lua'), a)
print('wrote actor bubba open, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
