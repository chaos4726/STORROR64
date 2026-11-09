# keyunlockx.py: the Bowser key as it unlocks a key door (bowser_key_cutscene_geo, bhvBowserKeyUnlockDoor) with its
# animations - 0 the door's, 1 the course's exit - into SM64_OUT as actor_geo_bowser_key_cutscene_geo (game.lua's key
# door unlocking: "we need a animation for unlocking new doors as well as keydoors", 2026-10-20)
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
anims = S.anim_table(BA.db, 'bowser_key_seg3_anims_list')
a = S.export_actor(BA.db, 'bowser_key_cutscene_geo', anims, BA.textures)
X.write_lua(os.path.join(BA.DATA, 'actor_geo_bowser_key_cutscene_geo.lua'), a)
print('wrote key cutscene, parts', len(a['parts']), 'anims', [(an.get('name'), an.get('frames')) for an in a.get('anims') or []])
for i, p in enumerate(a['parts']):
    print(' part', i, p['name'], 'parent', p['parent'], 'bone', p.get('bone'), 'off', p['off'], 'sections', len(p['sections']))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
