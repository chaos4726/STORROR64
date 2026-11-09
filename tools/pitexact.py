import sys
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_castle.lua')
s = d['sections'][14]
for v in range(20):
    print(v, s['pos'][3*v:3*v+3])
s0 = d['sections'][0]
for v in (768, 769, 770, 771, 772, 773, 774, 775):
    print('rim', v, s0['pos'][3*v:3*v+3], s0['uv'][2*v:2*v+2])
