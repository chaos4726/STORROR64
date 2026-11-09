# wigglerx.py: Wiggler's body segment (wiggler_body_geo, its walk wiggler_seg5_anims_0500C874) into SM64_OUT, as
# build_all's enemy models are made (data/actor_geo_wiggler_body_geo.lua)
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
tables = {n: S.anim_table(BA.db, n) for n in BA.db.src['animptrs']}
anims = tables.get('wiggler_seg5_anims_0500C874', [])
a = S.export_actor(BA.db, 'wiggler_body_geo', anims, BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_wiggler_body_geo.lua'), a)
print('wrote actor wiggler body, parts', len(a['parts']), 'anims', len(a.get('anims', [])))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
