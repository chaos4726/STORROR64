"""Which textures Mario 64 draws clamped (G_TX_CLAMP on the render tile) where the clamp shows - texture coordinates
past the picture's edge - against lib's CLAMP list. Prints one line per texture: name, clamp s/t, uv range."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
db = X.DB()
seen = {}   # sym -> {'cs': set, 'ct': set, 'umin'.., 'clamped_uv': [...]}

def interp(name, st, depth=0):
    if depth > 24 or not db.has('gfx', name):
        return
    for cmd, a in db.commands('gfx', name, 'gs'):
        if cmd == 'gsSPEndDisplayList':
            return
        if cmd in ('gsSPDisplayList', 'gsSPBranchList'):
            interp(a[0].lstrip('&').strip(), st, depth + 1)
            if cmd == 'gsSPBranchList':
                return
        elif cmd == 'gsDPSetTextureImage':
            st['tex'] = a[3].lstrip('&').strip()
        elif cmd in ('gsDPLoadTextureBlock', 'gsDPLoadTextureBlock_4b'):
            st['tex'] = a[0].lstrip('&').strip()
            k = 5 if cmd == 'gsDPLoadTextureBlock' else 4
            st['cs'] = 'CLAMP' in a[k + 1]; st['ct'] = 'CLAMP' in a[k + 2]
        elif cmd == 'gsDPSetTile':
            if 'G_TX_RENDERTILE' in a[4] or a[4].strip() == '0':
                st['ct'] = 'CLAMP' in a[6]; st['cs'] = 'CLAMP' in a[9]
        elif cmd == 'gsSPVertex':
            nm, off = X.parse_vtx_ref(a[0])
            n = X.to_int(a[1]); v0 = X.to_int(a[2])
            arr = db.vtx(nm)
            for i in range(min(n, len(arr) - off)):
                st['vbuf'][v0 + i] = arr[off + i]
        elif cmd in ('gsSP1Triangle', 'gsSP2Triangles'):
            tris = [(a[0], a[1], a[2])] + ([(a[4], a[5], a[6])] if cmd == 'gsSP2Triangles' else [])
            sym = st.get('tex')
            if not sym:
                continue
            r = seen.setdefault(sym, {'cs': set(), 'ct': set(), 'u': [1e9, -1e9], 'v': [1e9, -1e9], 'cu': [1e9, -1e9], 'cv': [1e9, -1e9]})
            r['cs'].add(st.get('cs', False)); r['ct'].add(st.get('ct', False))
            for t in tris:
                for idx in t:
                    v = st['vbuf'].get(X.to_int(idx))
                    if not v:
                        continue
                    u, w = v[3] / 32.0, v[4] / 32.0
                    r['u'][0] = min(r['u'][0], u); r['u'][1] = max(r['u'][1], u)
                    r['v'][0] = min(r['v'][0], w); r['v'][1] = max(r['v'][1], w)
                    if st.get('cs') or st.get('ct'):
                        r['cu'][0] = min(r['cu'][0], u); r['cu'][1] = max(r['cu'][1], u)
                        r['cv'][0] = min(r['cv'][0], w); r['cv'][1] = max(r['cv'][1], w)

for name in list(db.src['gfx'].keys()):
    interp(name, {'vbuf': {}})

lib = open(r'X:\mashup-work\lib_cur.lua', encoding='utf-8').read()
have = set(re.findall(r'\["([^"]+)"\]\s*=\s*true', lib))
rows = []
for sym, r in seen.items():
    if True not in r['cs'] and True not in r['ct']:
        continue
    png = db.tex.get(sym)
    if not png:
        continue
    key = X.png_key(png)
    dims = db.tex_dims(sym)
    if not dims:
        continue
    w, h = dims
    cu = (r['cu'][0] / w, r['cu'][1] / w); cv = (r['cv'][0] / h, r['cv'][1] / h)
    out_s = cu[0] < -0.01 or cu[1] > 1.01
    out_t = cv[0] < -0.01 or cv[1] > 1.01
    shows = (True in r['cs'] and out_s) or (True in r['ct'] and out_t)
    mixed = (False in r['cs'] and True in r['cs']) or (False in r['ct'] and True in r['ct'])
    rows.append((key, shows, key in have, sorted(r['cs']), sorted(r['ct']), cu, cv, mixed))
rows.sort(key=lambda x: (not x[1], x[2], x[0]))
for key, shows, inlib, cs, ct, cu, cv, mixed in rows:
    if shows:
        print('%-62s %s cs=%s ct=%s u %.2f..%.2f v %.2f..%.2f%s' % (key, 'IN-LIB ' if inlib else 'MISSING', cs, ct, cu[0], cu[1], cv[0], cv[1], ' MIXED' if mixed else ''))
print('textures drawn clamped:', len(rows), '| where the clamp shows:', sum(1 for r in rows if r[1]), '| of those already in lib:', sum(1 for r in rows if r[1] and r[2]))
