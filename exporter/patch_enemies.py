"""build_all.py: Mario 64's enemies as `kind="enemy"` scene objects, and their models (enemyx.py)."""
p = r'X:/mashup-work/exporter/build_all.py'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:60])
    s = s.replace(a, b)


rep("""import envx as E""", """import envx as E
import enemyx as EN""")

rep("""level_props = {}        # prop actor name -> geo, for models that only one level has (star doors and the like)""",
    """level_props = {}        # prop actor name -> geo, for models that only one level has (star doors and the like)
enemy_geos = {}         # enemy model geo -> its animation table (enemyx.py), exported as actor "geo_<geo>\"""")

# level-script objects: enemies first (before the scenery branch; the ones with a collision model of their own,
# thwomps and whomps, stay built into the level until they move)
rep("""        # pieces of the level that the game places as objects: plain scenery, and solid things with a
        # collision model of their own (towers, platforms, gates). They are built in where they start.""",
    """        if b in EN.ENEMY_BHVS and b not in BHV_COLLISION:
            eo = EN.enemy_object(db, b, o.get('model'), o['x'], o['y'], o['z'], o['ay'],
                                 P.bp_value(o.get('bparam', '0')), parse_model_geo_map(level), ue, enemy_geos)
            if eo:
                objects.append(eo)
            continue
        # pieces of the level that the game places as objects: plain scenery, and solid things with a
        # collision model of their own (towers, platforms, gates). They are built in where they start.""")

# macro objects
rep("""            if pr in ('macro_bobomb', 'macro_bobomb_stationary'):""", """            mp = EN.macro_presets().get(pr)
            if mp and mp[0] in EN.ENEMY_BHVS and mp[0] not in BHV_COLLISION:
                bp = P.bp_value(mo.get('bparam', '0')) if mo.get('bparam', '0') not in ('0', '') else 0
                eo = EN.enemy_object(db, mp[0], mp[1], mo['x'], mo['y'], mo['z'], mo['yaw'], bp, mgmap, ue, enemy_geos)
                if eo:
                    eo['preset'] = pr
                    objects.append(eo)
            if pr in ('macro_bobomb', 'macro_bobomb_stationary'):""")

# models: every enemy model the scenes used
rep("""    print('== actor bowser')""", """    for geo, anim_sym in sorted(enemy_geos.items()):
        if db.has('geo', geo):
            print('== enemy model', geo, anim_sym)
            try:
                actors['geo_' + geo] = S.export_actor(db, geo, anim_tables.get(anim_sym, []) if anim_sym else [], textures)
            except Exception as e:
                print('   !! enemy model failed', geo, e)
    print('== actor bowser')""")

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
