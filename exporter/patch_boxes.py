"""build_all.py: boxes (! boxes, cork boxes, small cork boxes, jumping boxes) as kind="box" objects, and their models."""
p = r'X:/mashup-work/exporter/build_all.py'
s = open(p, encoding='utf-8').read()
BOXES = "('bhvExclamationBox', 'bhvBreakableBox', 'bhvBreakableBoxSmall', 'bhvJumpingBox')"
# level-script boxes (inside the try: block, 12 spaces)
a = "            if b in EN.ENEMY_BHVS and b not in BHV_COLLISION:\n"
assert s.count(a) == 1, s.count(a)
s = s.replace(a, "            if b in " + BOXES + ":\n"
              "                objects.append({'kind': 'box', 'type': b, 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay'],\n"
              "                                'content': W.bparam_byte(o.get('bparam', '0'), 2)})\n"
              "                continue\n" + a)
# macro boxes (after mp is known)
a = "            mp = EN.macro_presets().get(pr)\n"
assert s.count(a) == 1
s = s.replace(a, a + "            if mp and mp[0] in " + BOXES + ":\n"
              "                objects.append({'kind': 'box', 'type': mp[0], 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],\n"
              "                                'yaw': -mo['yaw'], 'content': P.bp_value(mp[2]) if mp[2] not in ('', '0') else 0, 'preset': pr})\n")
a = "    print('== actor chain chomp')\n"
assert s.count(a) == 1
s = s.replace(a, "    print('== actor boxes')\n"
              "    for i in range(4):          # the ! box's four colours: red (wing cap), green (metal), blue (vanish), yellow\n"
              "        actors['exbox_%d' % i] = S.export_actor(db, 'exclamation_box_geo', [], textures, switch=i)\n"
              "    actors['cork_box'] = S.export_actor(db, 'breakable_box_geo', [], textures)\n" + a)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
