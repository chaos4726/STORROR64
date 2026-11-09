import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_bitdw.lua')
for o in d['objects']:
    if 'pipe' in str(o.get('kind')) or 'pipe' in str(o.get('tpl', '')) or 'pipe' in str(o.get('actor', '')) or o.get('node') in (10, 11, 12):
        print({k: v for k, v in o.items() if k not in ('collision',)})
for n in d.get('nodes', []):
    print('node', n)
print([k for k in d.get('templates', {}).keys()][:20])
