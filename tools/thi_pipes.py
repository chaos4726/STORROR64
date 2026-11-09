"""Tiny-Huge Island's six warp pipes (bhvWarpPipe, MODEL_THI_WARP_PIPE), 2026-10-29: the scene export drew two of each
island's three (the first two: their pictures baked into the level's) with nothing solid, and left out the third - there
walking over the spot took him to the other island. Added to data/extra_statics.lua as static platforms: the pipe's
collision for all three (warp_pipe_seg3_collision_03009AC8: 154 round, 205 tall, a floor inside at its foot), its model
too for the third.

Run: python tools/thi_pipes.py <path to Scripts/data/extra_statics.lua>
"""
import os, sys
os.environ.setdefault("SM64_DECOMP", "X:/mashup-work/sm64decomp")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exporter"))
import build_all as B
import platx as P
import sm64x as X

PIPES = {"thi": [(6656, -1536, -5632), (-5888, -2048, -5888), (-3072, 512, -3840)],
         "thi_2": [(1997, -461, -1690), (-1766, -614, -1766), (-922, 154, -1152)]}
path = sys.argv[1]
s = open(path, encoding="utf-8", newline="").read()
for sc in PIPES:
    assert ("\n  %s = " % sc) not in s, sc + " already there"
for sc, ps in PIPES.items():
    templates, objects = {}, []
    key = P.template(B.db, B.textures, templates, lambda secs: secs, "warp_pipe_geo", "warp_pipe_seg3_collision_03009AC8")
    solid = P.template(B.db, B.textures, templates, lambda secs: secs, "none", "warp_pipe_seg3_collision_03009AC8")
    assert key and solid
    for i, pos in enumerate(ps):
        objects.append({"kind": "platform", "bhv": "static", "tpl": key if i == 2 else solid, "pos": list(pos), "ang": [0, 0, 0], "bp": 0})
    for k, t in templates.items():
        print(sc, k, len(t["sections"]), "sections", sum(c["ntris"] for c in t["sections"]), "tris", t.get("collision", {}).get("ntris"), "solid")
    body = X.to_lua({"templates": templates, "objects": objects}, 1)
    i = s.rstrip().rfind("}")
    s = s[:i] + "  %s = " % sc + body + ",\n" + s[i:]
print("textures used:", sorted(B.textures))
open(path, "w", encoding="utf-8", newline="").write(s)
print("written", path)
