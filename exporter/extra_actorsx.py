# extra_actorsx.py: models exported one at a time the way build_all.py exports actors (dev's one_actor.py, made for
# the installer, 2026-11-01): the metal and wing caps, the vanish cap (the plain cap's model - caps.lua makes it
# see-through) and the Fire Sea's blue pole (the sinking cage's: poles.lua).
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S

MODELS = [('marios_metal_cap_geo', 'actor_cap_metal'), ('marios_wing_cap_geo', 'actor_cap_wing'),
          ('marios_cap_geo', 'actor_cap_vanish'), ('bitfs_geo_0006A8', 'actor_geo_bitfs_geo_0006A8')]
os.makedirs(BA.DATA, exist_ok=True)
for geo, name in MODELS:
    a = S.export_actor(BA.db, geo, [], BA.textures)
    X.write_lua(os.path.join(BA.DATA, name + '.lua'), a)
    print('wrote', name, 'parts', len(a['parts']))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
