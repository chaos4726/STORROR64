# cannonx.py: only the cannon's two models (base, barrel) into SM64_OUT, as build_all's actor export makes them
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
for name in ('cannon_base', 'cannon_barrel'):
    a = S.export_actor(BA.db, BA.PROP_GEOS[name], [], BA.textures)
    X.write_lua(os.path.join(BA.DATA, 'actor_%s.lua' % name), a)
    print('wrote actor', name, 'parts', len(a['parts']))
    for p in a['parts']:
        pos = [v for sec in p.get('sections', []) for v in sec.get('pos', [])]
        if pos:
            zs, xs, ys = pos[2::3], pos[0::3], pos[1::3]
            print('   part', p.get('name'), 'x %.0f..%.0f y %.0f..%.0f z %.0f..%.0f' % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)), 'off', p.get('off'))
os.makedirs(BA.TEXD, exist_ok=True)
print('textures copied:', X.copy_textures(BA.textures, BA.TEXD), 'of', len(BA.textures))
