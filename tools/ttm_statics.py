"""TTM's mushroom towers the scene export left undrawn (2026-10-27, "im standing on a missing shroom tower").

Tall Tall Mountain places its mushroom towers as special objects (special_level_geo_03..06 in its collision). The
scene export baked most of them into the level's mesh, but not the last copy of each kind (and the last two of
geo_05): their floors are in the level's collision, with nothing drawn. This adds those five to
data/extra_statics.lua as static platforms (drawn only: their floors stay the level's).

Run from anywhere: python tools/ttm_statics.py <path to Scripts/data/extra_statics.lua>
"""
import os, re, sys
os.environ.setdefault("SM64_DECOMP", "X:/mashup-work/sm64decomp")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exporter"))
import build_all as B
import platx as P
import sm64x as X

# (preset -> its model's geo layout: ttm/script.c LOAD_MODEL_FROM_GEO)
GEOS = {"03": "ttm_geo_000748", "04": "ttm_geo_000778", "05": "ttm_geo_0007A8", "06": "ttm_geo_0007D8"}
# the copies that are missing (SM64 position, yaw in 256ths), from ttm/areas/1/collision.inc.c
MISSING = [("03", (4938, -5568, 5115), 0), ("04", (3277, -4508, -4095), 0), ("05", (2509, -4489, -3378), 0),
           ("05", (534, -4490, -4176), 0), ("06", (2317, -4635, -3838), 0)]

path = sys.argv[1]
s = open(path, encoding="utf-8", newline="").read()
assert "\n  ttm = " not in s, "ttm already there"
templates, objects = {}, []
for g, pos, yaw in MISSING:
    key = P.template(B.db, B.textures, templates, lambda secs: B.lift_decals(B.two_sided_alpha(B.tile_alpha(secs))), GEOS[g], None)
    assert key, g
    objects.append({"kind": "platform", "bhv": "static", "tpl": key, "pos": list(pos), "ang": [0, yaw * 360.0 / 256, 0], "bp": 0})
for k, t in templates.items():
    print(k, len(t["sections"]), "sections", sum(c["ntris"] for c in t["sections"]), "tris")
print("textures used:", sorted(B.textures))
body = X.to_lua({"templates": templates, "objects": objects}, 1)
i = s.rstrip().rfind("}")
s = s[:i] + "  ttm = " + body + ",\n" + s[i:]
s = s.replace("Made by lll_statics.py, 2026-10-19.", "Made by lll_statics.py, 2026-10-19 (TTM's mushroom towers:\n-- tools/ttm_statics.py, 2026-10-27).", 1)
open(path, "w", encoding="utf-8", newline="").write(s)
print("written", path)
