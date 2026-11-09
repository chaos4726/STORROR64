# capx.py: Mario's plain red cap (marios_cap_geo: the M on its front) into SM64_OUT as actor_cap_red - the Mario look's
# cap (the user, 2026-10-16: "I want his hat to be a baseball cap thats red with the M on the front")
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
a = S.export_actor(BA.db, 'marios_cap_geo', [], BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_cap_red.lua'), a)
print('wrote red cap, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']),
      [s.get('texture') for p in a['parts'] for s in p['sections']])
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
