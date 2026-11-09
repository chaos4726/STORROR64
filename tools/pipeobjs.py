import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_%s.lua' % sys.argv[1])
px, py = [o for o in d['objects'] if o.get('kind') == 'pipe'][0]['pos'][:2]
for o in d['objects']:
    pos = o.get('pos')
    if pos and math.hypot(pos[0] - px, pos[1] - py) < 900:
        print({k: v for k, v in o.items() if k in ('kind', 'bhv', 'tpl', 'pos', 'type', 'actor', 'node')})
