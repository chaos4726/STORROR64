def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

patch(r'X:/mashup-work/exporter/enemyx.py', [
("""                'bowser_key_geo': None}""", """                'bowser_key_geo': None, 'hoot_geo': 'hoot_seg5_anims_05005768'}"""),
])
patch(r'X:/mashup-work/exporter/build_all.py', [
("""            elif b == 'bhvHiddenRedCoinStar':""", """            elif b == 'bhvHoot':
                # Hoot, WF's owl (hoot.inc.c): asleep in his tree, he carries the athlete about (Scripts/hoot.lua)
                objects.append({'kind': 'hoot', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']]})
            elif b == 'bhvHiddenRedCoinStar':"""),
])
print('ok')
