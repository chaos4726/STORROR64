# shadowsx.py: each geo layout's shadow as Mario 64 gives it (its GEO_SHADOW: type, solidity 0-255, size in units) -
# data/shadows.lua (the round shadows under things). Written again 2026-11-01 for the installer (the first was lost).
import os, re, glob, sys

D = os.environ.get('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
OUT = os.environ.get('SM64_OUT', '.')
found = {}
for p in sorted(glob.glob(os.path.join(D, 'actors', '**', 'geo.inc.c'), recursive=True)) + \
        sorted(glob.glob(os.path.join(D, 'levels', '**', 'geo.inc.c'), recursive=True)):
    t = open(p, encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'const\s+GeoLayout\s+(\w+)\s*\[\s*\]\s*=\s*\{(.*?)\n\};', t, re.S):
        s = re.search(r'GEO_SHADOW\(\s*(\w+)\s*,\s*(0x[0-9A-Fa-f]+|\d+)\s*,\s*(-?\d+)\s*\)', m.group(2))
        if s and m.group(1) not in found:
            found[m.group(1)] = (s.group(1), int(s.group(2), 0), int(s.group(3)))
out = ['-- generated from the Mario 64 decomp (GEO_SHADOW in each geo layout): type, solidity 0-255, size in units', 'return {']
for name in sorted(found):
    k, a, b = found[name]
    out.append('  %s = { "%s", %d, %d },' % (name, k, a, b))
out += ['}', '']
p = os.path.join(OUT, 'Scripts', 'data', 'shadows.lua')
os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print('wrote', p, len(found))
