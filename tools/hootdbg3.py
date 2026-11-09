import os, sys
sys.path.insert(0, 'X:/mashup-work/exporter')
import sm64x as X
orig = X.interp_dl
db = X.DB()
real_vtx = db.vtx
def vtx(nm):
    a = real_vtx(nm)
    return a
import traceback
class St: pass
def wrapped(db_, name, st, mesh, layer, textures, depth=0):
    for cmd, a in db_.commands('gfx', name, 'gs'):
        if cmd == 'gsSPVertex':
            nm, off = X.parse_vtx_ref(a[0])
            n = X.to_int(a[1]); v0 = X.to_int(a[2])
            arr = db_.vtx(nm)
            if off + n > len(arr):
                print('BAD', name, a, 'len', len(arr))
    return orig(db_, name, st, mesh, layer, textures, depth)
X.interp_dl = wrapped
import sm64scenes as S
try:
    S.export_actor(db, 'hoot_geo', [], {})
except Exception as e:
    print('err', e)
