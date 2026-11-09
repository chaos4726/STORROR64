# pokeyx.py: Pokey's body part (pokey_body_part_geo) into SM64_OUT, as build_all's enemy models are made
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
a = S.export_actor(BA.db, 'pokey_body_part_geo', [], BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_pokey_body_part_geo.lua'), a)
print('wrote actor pokey body part, parts', len(a['parts']))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
