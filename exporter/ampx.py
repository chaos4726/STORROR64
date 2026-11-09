# ampx.py: the Amp with its electricity on (dAmpGeo, switch case 1: oAnimState 1 - the four arcs; case 0 is nothing, and
# the Amps were drawn without them: "the amp is missing its electric textures as well", 2026-10-17)
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
anims = S.anim_table(BA.db, 'dAmpAnimsList') if 'dAmpAnimsList' in BA.db.src['animptrs'] else []
a = S.export_actor(BA.db, 'dAmpGeo', anims, BA.textures, switch=1)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_dAmpGeo.lua'), a)
print('wrote actor amp, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']), 'anims', len(anims))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
