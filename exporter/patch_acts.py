"""build_all.py: Mario 64's acts. Objects the level script places for some acts only carry `acts` (a bit mask of acts
1-6); the game builds them only in those acts. Scenery placed for some acts only (Whomp's Fortress's tower, which
stands only once the Whomp King is beaten) is no longer built into the level but made a standing platform with its
acts, so that it can be left out."""
p = r'X:/mashup-work/exporter/build_all.py'
s = open(p, encoding='utf-8').read()

start = s.index('    for o in entries:\n')
end = s.index('    # macro objects\n')
body = s[start:end]
lines = body.split('\n')
head = lines[0]
rest = lines[1:]
# the loop body, indented once more, inside try/finally that tags what this object added with its acts
new = [head,
       "        n0 = len(objects)",
       "        acts = o.get('acts', 0x3F) if isinstance(o, dict) else 0x3F",
       "        try:"]
for ln in rest:
    new.append(('    ' + ln) if ln.strip() else ln)
while new and not new[-1].strip():
    new.pop()
new += ["        finally:",
        "            if acts != 0x3F:",
        "                for ob in objects[n0:]:",
        "                    ob['acts'] = acts",
        "", ""]
s = s[:start] + '\n'.join(new) + s[end:]

# act-specific scenery: a standing platform, not part of the level's own shape
a = """                if b == 'bhvStaticObject' or solid:
                    S.walk_static(db, X.parse_geo(db, geo)['children'], S.rot_y_xf(o['ay'], pos), mesh, textures)"""
assert s.count(a) == 1, s.count(a)
s = s.replace(a, """                if (b == 'bhvStaticObject' or solid) and acts != 0x3F:
                    tpl = P.template(db, textures, templates, lambda secs: lift_decals(two_sided_alpha(tile_alpha(secs))), geo, solid)
                    if tpl:
                        objects.append({'kind': 'platform', 'bhv': 'static', 'tpl': tpl, 'pos': [o['x'], o['y'], o['z']],
                                        'ang': [o['ax'], o['ay'], o['az']], 'bp': 0})
                        continue
                if b == 'bhvStaticObject' or solid:
                    S.walk_static(db, X.parse_geo(db, geo)['children'], S.rot_y_xf(o['ay'], pos), mesh, textures)""")
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
