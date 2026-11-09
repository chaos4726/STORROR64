import sys
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_castle.lua')
s = d['sections'][14]
print({k: v for k, v in s.items() if k not in ('pos', 'uv', 'col', 'nrm', 'idx')})
print('nrm', s.get('nrm'))
print('col', s.get('col'))
print('idx', s.get('idx'))
s0 = d['sections'][0]
print('sec0', {k: v for k, v in s0.items() if k not in ('pos', 'uv', 'col', 'nrm', 'idx')})
for v in (768, 769, 770, 771, 772, 773, 774, 775):
    print(v, s0['nrm'][3*v:3*v+3], s0['col'][4*v:4*v+4])
