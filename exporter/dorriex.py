# dorriex.py: HMC's Dorrie (dorrie_geo, bhvDorrie) with her animations into SM64_OUT as actor_geo_dorrie_geo
# (the user, 2026-10-19: "next dori needs fixed" - she was a still model; platforms.lua B.dorrie draws this)
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
anims = S.anim_table(BA.db, 'dorrie_seg6_anims_0600F638')
a = S.export_actor(BA.db, 'dorrie_geo', anims, BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_dorrie_geo.lua'), a)
print('wrote dorrie, parts', len(a['parts']), 'sections', sum(len(p['sections']) for p in a['parts']), 'anims', len(a.get('anims') or []))
for i, an in enumerate(a.get('anims') or []):
    print(' anim', i, {k: (v if not isinstance(v, (list, dict)) else len(v)) for k, v in an.items()} if isinstance(an, dict) else type(an))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
