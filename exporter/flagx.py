# flagx.py: Koopa the Quick's finish flag (koopa_flag_geo, bhvKoopaRaceEndpoint) with its waving animation into SM64_OUT
# as actor_geo_koopa_flag_geo (the user, 2026-10-16: "add ... the flag at the end of the level")
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
anims = S.anim_table(BA.db, 'koopa_flag_seg6_anims_06001028')
a = S.export_actor(BA.db, 'koopa_flag_geo', anims, BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_koopa_flag_geo.lua'), a)
print('wrote koopa flag, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']), 'anims', len(a.get('anims') or []))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
