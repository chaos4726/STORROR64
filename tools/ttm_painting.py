"""TTM's slide painting (2026-10-27, "fix the slide image" / "missing texture actually").

The scene export takes paintings only from the castle's painting.inc.c, so Tall Tall Mountain's own - ttm_slide_painting,
the way into its slide, camouflaged in the mountain's rock - was never drawn: its opening in the wall showed nothing.
This makes its picture (textures/painting_ttm_slide.png: its two images, listed bottom first, the last on top - as
sm64scenes.export_paintings stacks them) and adds it to data/extra_statics.lua's ttm entry (G.add_extra_statics), at
its place in the scene as export_paintings would put it. Its three strips' warps (paint:0-2) are the scene's already.

python tools/ttm_painting.py <SM64Map mod dir>
"""
import math, os, sys
from PIL import Image

MOD = sys.argv[1]
D = os.environ.get("SM64_DECOMP", "X:/mashup-work/sm64decomp")
SCALE = 0.75
# ttm/areas/1/painting.inc.c: textures { ttm_seg7_texture_07004000 (7), ttm_seg7_texture_07003000 (6) }
imgs = [Image.open(os.path.join(D, "levels/ttm/7.rgba16.png")).convert("RGBA"),
        Image.open(os.path.join(D, "levels/ttm/6.rgba16.png")).convert("RGBA")]
canvas = Image.new("RGBA", (imgs[0].width, sum(i.height for i in imgs)))
y = 0
for im in reversed(imgs):
    canvas.paste(im, (0, y))
    y += im.height
canvas.save(os.path.join(MOD, "textures", "painting_ttm_slide.png"))

# its place: pos (3072, 921.6, -819.2), pitch 0, yaw 90, size 460.8 - turned as export_paintings turns them
pos, yaw, size = (3072.0, 921.6, -819.2), 90.0, 460.8
c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
turn = lambda v: (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)
right, up, normal = turn((1, 0, 0)), turn((0, 1, 0)), turn((0, 0, 1))
corner = lambda a, b: tuple(pos[k] + right[k] * a + up[k] * b for k in range(3))
ue = lambda p: [-p[2] * SCALE, p[0] * SCALE, p[1] * SCALE]
corners = [round(v, 2) for q in [corner(0, 0), corner(size, 0), corner(size, size), corner(0, size)] for v in ue(q)]
nrm = [round(-normal[2], 4), round(normal[0], 4), round(normal[1], 4)]
entry = ('    paintings = {\n      { name = "ttm_slide", id = 0, target = "ttm_2", node = 10, texture = "painting_ttm_slide",\n'
         '        corners = {%s}, normal = {%s}, size = %s },\n    },\n'
         % (",".join("%g" % v for v in corners), ",".join("%g" % v for v in nrm), "%g" % (size * SCALE)))

p = os.path.join(MOD, "Scripts", "data", "extra_statics.lua")
t = open(p, encoding="utf-8", newline="").read()
assert "painting_ttm_slide" not in t, "already there"
a = t.index("\n  ttm = {")
b = t.index("    templates = {", a)
t = t[:b] + entry + t[b:]
open(p, "w", encoding="utf-8", newline="").write(t)
print("painting", corners, nrm)
