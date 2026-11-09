"""The logo's arrival and departure, as the game plays them: its width and height on each frame
(30 a second), read from the intro level's tables. Usage: python make_logo_data.py <out dir>"""
import os, re, sys
import sm64x as X

t = open(os.path.join(X.D, 'levels', 'intro', 'leveldata.c'), encoding='utf-8', errors='replace').read()


def table(name):
    m = re.search(r'const\s+f32\s+' + name + r'\s*\[\s*\]\s*=\s*\{(.*?)\};', t, re.S)
    v = [float(x.rstrip('f')) for x in re.findall(r'-?\d+\.\d+f?', m.group(1))]
    return [[v[i], v[i + 1]] for i in range(0, len(v), 3)]


data = {'zoom_in': table('intro_seg7_table_0700C790'), 'zoom_out': table('intro_seg7_table_0700C880'),
        'fade_from': 19, 'fade_step': 26, 'hold_until': 75}
X.write_lua(os.path.join(sys.argv[1], 'Scripts', 'data', 'title_logo.lua'), data)
print('wrote title_logo.lua:', len(data['zoom_in']), 'frames in,', len(data['zoom_out']), 'out')
