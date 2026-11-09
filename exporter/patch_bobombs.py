"""build_all.py: bob-ombs, bob-omb buddies and King Bob-omb (asked 2026-10-14: "also bombombs", "aswell as king
bombomb"), their models, and the explosion's pictures."""
p = r'X:/mashup-work/exporter/build_all.py'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:60])
    s = s.replace(a, b)


# level-script objects
rep("""        elif b == 'bhvMessagePanel':""", """        elif b in ('bhvBobombBuddy', 'bhvBobombBuddyOpensCannon'):
            # (one per spot: the level has a buddy per act at the same place)
            if not any(q.get('kind') == 'bobomb_buddy' and q.get('sm64') == [o['x'], o['y'], o['z']] for q in objects):
                objects.append({'kind': 'bobomb_buddy', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay']})
        elif b == 'bhvKingBobomb':
            objects.append({'kind': 'king_bobomb', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay'],
                            'star': star_id(o.get('bparam', '0'))})
        elif b == 'bhvMessagePanel':""")

# macro objects
rep("""            if pr == 'macro_chain_chomp':""", """            if pr in ('macro_bobomb', 'macro_bobomb_stationary'):
                objects.append({'kind': 'bobomb', 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],
                                'yaw': -mo['yaw'], 'stationary': pr == 'macro_bobomb_stationary'})
            if pr == 'macro_chain_chomp':""")

# models
rep("""    print('== actor chain chomp')""", """    print('== actor bob-ombs')
    actors['bobomb'] = S.export_actor(db, 'black_bobomb_geo', table_for('bobomb_seg8_anims'), textures)
    actors['bobomb_buddy'] = S.export_actor(db, 'bobomb_buddy_geo', table_for('bobomb_seg8_anims'), textures)
    actors['king_bobomb'] = S.export_actor(db, 'king_bobomb_geo', table_for('king_bobomb_seg5_anims'), textures)
    # the explosion: seven pictures, shown in turn on a quad (its geo switches between them)
    for i in range(7):
        src = os.path.join(X.D, 'actors', 'explosion', 'explosion_%d.rgba16.png' % i)
        if os.path.exists(src):
            os.makedirs(TEXD, exist_ok=True)
            shutil.copy(src, os.path.join(TEXD, 'actors__explosion__explosion_%d.rgba16.png' % i))
    print('== actor chain chomp')""")

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
