def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

patch(r'X:/mashup-work/exporter/enemyx.py', [
("""                'bowser_key_geo': None, 'hoot_geo': 'hoot_seg5_anims_05005768'}""",
 """                'bowser_key_geo': None, 'hoot_geo': 'hoot_seg5_anims_05005768',
                'wf_geo_000AE0': None, 'ddd_geo_000450': None, 'yellow_sphere_geo': None}     # (poles: Scripts/poles.lua)"""),
])
patch(r'X:/mashup-work/exporter/build_all.py', [
("""            elif b == 'bhvHoot':""", """            elif b in ('bhvPoleGrabbing', 'bhvGiantPole', 'bhvDDDPole'):
                # poles Mario climbs (pole.inc.c, ddd_pole.inc.c; Scripts/poles.lua): their hitbox's height - a plain
                # one's from its second parameter byte (tenths), WF's giant pole 2100 with a yellow ball on top, DDD's
                # 800 (100 of it below its foot) sliding to and fro along its heading by 100 x its second byte
                bp2 = (P.bp_value(o.get('bparam', '0')) >> 16) & 0xFF
                pole = {'kind': 'pole', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': o['ay'],
                        'height': {'bhvGiantPole': 2100, 'bhvDDDPole': 800}.get(b, bp2 * 10), 'type': b}
                if b == 'bhvGiantPole':
                    pole['model'], pole['ball'] = 'geo_wf_geo_000AE0', 'geo_yellow_sphere_geo'
                elif b == 'bhvDDDPole':
                    pole['model'], pole['down'], pole['travel'] = 'geo_ddd_geo_000450', 100, 100 * bp2
                objects.append(pole)
            elif b == 'bhvHoot':"""),
("""            elif pr in ('macro_hidden_1up_trigger', 'macro_hidden_star_trigger'):""",
 """            elif pr == 'macro_hidden_1up_in_pole':
                # mushroom_1up.inc.c: a 1-up hidden at the top of a pole, out once both its marks on the pole (there and
                # 200 below) are passed - climbing it (Scripts/poles.lua)
                objects.append({'kind': 'oneup', 'lurk': 'oneup', 'need': 2, 'pos': ue(mo['x'], mo['y'] + 50, mo['z'])})
                for dy in (0, -200):
                    objects.append({'kind': 'secret_trigger', 'what': 'oneup', 'pos': ue(mo['x'], mo['y'] + dy, mo['z'])})
            elif pr in ('macro_hidden_1up_trigger', 'macro_hidden_star_trigger'):"""),
])
print('ok')
