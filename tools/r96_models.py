# r96_models.py : the Render96 model pack's models (tools/r96_overlay.py's decomp) exported by the mod's own exporter
# (exporter/build_all.py export_actors, sm64scenes walk_static) into r96_build/out: data_r96/actor_<name>.lua for every
# actor of the mod whose model is Render96's, data_r96/trees.lua (the trees, as models: { [geo] = sections }), and the
# pictures they use (textures/). The enemy models the mod has (data/actor_geo_<geo>.lua) are asked for again by name,
# with the animation table that holds their animations - the decomp's: the skeletons are Mario 64's.
import os, sys, shutil, json
os.environ['SM64_DECOMP'] = r'X:\mashup-work\r96_build\decomp'
OUT = r'X:\mashup-work\r96_build\out'
os.environ['SM64_OUT'] = OUT
os.environ['SM64_TEXGEN_SPHERE'] = '1'      # (shine maps laid on by the normals: exporter/sm64x.py SPHERE)
os.environ['SM64_HD_TILE'] = '1'            # (HD pictures in smaller materials laid on at the material's size: HD_TILE)
sys.path.insert(0, r'X:\mashup-work\exporter')
import lupa
import build_all as BA
import sm64x as X
import sm64scenes as S

MODDATA = r'E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\Scripts\data'
R96 = os.path.join(X.D, 'actors')
R96_NAMES = set(os.listdir(r'X:\mashup-work\r96_dl\models\x\Render96\actors'))
DATA = os.path.join(OUT, 'data_r96')
TEXD = os.path.join(OUT, 'textures')
os.makedirs(DATA, exist_ok=True)
db = BA.db

def is_r96(geo):
    """the geo is defined in one of the Render96 actors' files"""
    if not db.has('geo', geo):
        return False
    path = db.src['geo'][geo][0]
    rel = os.path.relpath(path, R96).replace('\\', '/').split('/')
    return len(rel) >= 2 and rel[0] in R96_NAMES

# the enemy models the mod has, and the animation table that holds each one's animations
L = lupa.LuaRuntime(unpack_returned_tuples=True)
anim_tables = {n: S.anim_table(db, n) for n in db.src['animptrs']}
for f in sorted(os.listdir(MODDATA)):
    if f.startswith('actor_geo_') and f.endswith('.lua'):
        geo = f[len('actor_geo_'):-4]
        d = L.eval('loadfile')(os.path.join(MODDATA, f))()
        first = None
        if d['anims'] is not None and len(d['anims']) > 0:
            first = d['anims'][1]['name']
        table = None
        if first:
            for tn, lst in anim_tables.items():
                if first in lst:
                    table = tn; break
        BA.enemy_geos[geo] = table

# which geo each exported actor came from
geo_of = {}
_real = S.export_actor
def export_actor(db_, geo_name, *a, **k):
    r = _real(db_, geo_name, *a, **k)
    geo_of[id(r)] = geo_name
    return r
S.export_actor = export_actor

actors = BA.export_actors()
# (made outside export_actors in the mod: the star already collected - its own name - and the Amp, its arcs on
# (exporter/ampx.py: switch case 1) - Render96's is amp_geo, the decomp's dAmpGeo)
EXTRA = [('transparent_star', 'transparent_star_geo', None, 0), ('geo_dAmpGeo', 'amp_geo', 'dAmpAnimsList', 1),
         # (Render96's coins are models, turned by the game: the mod's are four pictures in turn - game.lua uses these
         # with RENDER 96 on, by these names of their own)
         ('coin3d_yellow', 'yellow_coin_no_shadow_geo', None, 0), ('coin3d_red', 'red_coin_no_shadow_geo', None, 0),
         ('coin3d_blue', 'blue_coin_no_shadow_geo', None, 0)]
for name, geo, anim_sym, sw in EXTRA:
    if db.has('geo', geo):
        an = S.anim_table(db, anim_sym) if anim_sym and anim_sym in db.src['animptrs'] else []
        try:
            actors[name] = S.export_actor(db, geo, an, BA.textures, switch=sw)
        except Exception as e:
            print('   !! failed', name, geo, e)
wrote = []
for name, v in actors.items():
    geo = geo_of.get(id(v))
    if not geo or not is_r96(geo):
        continue
    nsec = sum(len(p['sections']) for p in v['parts'])
    if nsec == 0:
        print('   !! no picture in', name, geo)
        continue
    X.write_lua(os.path.join(DATA, 'actor_%s.lua' % name), v)
    wrote.append('%s(%s:%d parts %d sections %d anims)' % (name, geo, len(v['parts']), nsec, len(v['anims'])))

# the trees, as models
trees = {}
for g in ('bubbly_tree_geo', 'spiky_tree_geo', 'snow_tree_geo', 'palm_tree_geo', 'spiky_tree1_geo'):
    if is_r96(g):
        tm = X.Mesh(); tm.xf = None; tm.cum = 1.0
        S.walk_static(db, X.parse_geo(db, g)['children'], S.rot_y_xf(0, (0, 0, 0)), tm, BA.textures)
        secs = X.finish_sections(tm)
        if secs:
            trees[g] = secs
X.write_lua(os.path.join(DATA, 'trees.lua'), trees)

n = X.copy_textures(BA.textures, TEXD)
print('wrote', len(wrote), 'Render96 actors:')
for w in sorted(wrote): print('  ', w)
print('trees:', sorted(trees))
print('pictures copied', n)
