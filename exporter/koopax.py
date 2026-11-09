# koopax.py: the Koopa without his shell (koopa_without_shell_geo, the Koopa's own anims koopa_seg6_anims_06011364) into
# SM64_OUT, as build_all's enemy models are made (data/actor_geo_koopa_without_shell_geo.lua) - knocked out of his shell
# ("when squishing a turtle they dont come out of they're shell", 2026-10-29)
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
tables = {n: S.anim_table(BA.db, n) for n in BA.db.src['animptrs']}
anims = tables.get('koopa_seg6_anims_06011364', [])
a = S.export_actor(BA.db, 'koopa_without_shell_geo', anims, BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_koopa_without_shell_geo.lua'), a)
print('wrote actor koopa without shell, parts', len(a['parts']), 'anims', len(a.get('anims', [])))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
