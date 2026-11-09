import os, sys, traceback
sys.path.insert(0, 'X:/mashup-work/exporter')
os.environ.setdefault('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
import sm64x as X, sm64scenes as S
db = X.DB()
t = S.anim_table(db, 'hoot_seg5_anims_05005768')
print('table', t)
try:
    a = S.export_actor(db, 'hoot_geo', t, {})
    print(len(a['parts']), a['nbones'], len(a['anims']))
except Exception:
    traceback.print_exc()
