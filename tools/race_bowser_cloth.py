"""The Bowser checkpoint flag's cloth, after the user's picture (2026-10-27: "the bowser flag doesnt look like the image I
sent you", then a black flag with Bowser's red emblem): a black cloth, its loose edge cut in three points (the checkpoint
flag's), Bowser's emblem on it in red - horns curving up either side, a crest of three points between them, angry
slanted eyes, cheeks bulging out, a wide open mouth with fangs down from its top and up from its jaw, a round chin.
Drawn four times over and shrunk, for smooth edges. Writes textures/race_cloth_bowser3.png.

python tools/race_bowser_cloth.py <SM64Map mod dir> [preview.png]
"""
import os, sys
from PIL import Image, ImageDraw

MOD = sys.argv[1]
W, H = 256, 166            # the cloth's picture: as long as race.lua's cloth (175 x 114 cm) - "also flags not long enough"
S = 4
im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)

BLACK = (22, 22, 24, 255)
RED = (238, 238, 238, 255)   # (the emblem white: "this is a flat image of bowser I still want it in white tho")
cloth = [(0, 0), (256, 0), (216, 42), (256, 83), (216, 124), (256, 166), (0, 166)]
d.polygon([(x * S, y * S) for x, y in cloth], fill=BLACK)

# the emblem in its own measure: u across (-1 .. 1, half its width), v down (0 its top .. 1 its foot)
CX, TOP, HW, HT = 106.0, 12.0, 56.0, 142.0


def P(pts):
    return [((CX + u * HW) * S, (TOP + v * HT) * S) for u, v in pts]


def mirror(pts):
    return [(-u, v) for u, v in reversed(pts)]


# its outline, the left half from the crest's top round to the chin's middle, then the right the same
left = [(0.0, 0.0), (-0.10, 0.10), (-0.22, 0.05), (-0.26, 0.16), (-0.36, 0.20),
        (-0.50, 0.24), (-0.56, 0.12), (-0.64, 0.02), (-0.70, 0.08), (-0.76, 0.22), (-0.80, 0.34),
        (-0.82, 0.46), (-0.92, 0.54), (-1.00, 0.64), (-0.98, 0.76), (-0.88, 0.84),
        (-0.74, 0.88), (-0.60, 0.95), (-0.42, 1.00), (-0.20, 0.98), (-0.08, 0.93), (0.0, 0.92)]
outline = left[:-1] + mirror(left)[1:]
d.polygon(P(outline), fill=RED)
# the mouth, open, black
mouth_l = [(0.0, 0.54), (-0.30, 0.57), (-0.62, 0.50), (-0.56, 0.66), (-0.44, 0.78), (-0.24, 0.84), (0.0, 0.85)]
d.polygon(P(mouth_l[:-1] + mirror(mouth_l)[1:]), fill=BLACK)
# its fangs: long ones down from the top at its corners, short ones up from the jaw
for s in (-1, 1):
    d.polygon(P([(s * 0.52, 0.52), (s * 0.30, 0.56), (s * 0.38, 0.76)]), fill=RED)
    d.polygon(P([(s * 0.26, 0.84), (s * 0.10, 0.85), (s * 0.17, 0.69)]), fill=RED)
# the eyes: dark slits slanting down to the middle
for s in (-1, 1):
    d.polygon(P([(s * 0.54, 0.30), (s * 0.12, 0.42), (s * 0.14, 0.48), (s * 0.44, 0.43)]), fill=BLACK)
# the brow's notch over the nose
d.polygon(P([(-0.06, 0.40), (0.06, 0.40), (0.0, 0.46)]), fill=BLACK)

mask = Image.new("L", im.size, 0)
ImageDraw.Draw(mask).polygon([(x * S, y * S) for x, y in cloth], fill=255)
out = Image.new("RGBA", im.size, (0, 0, 0, 0))
out.paste(im, (0, 0), mask)
out = out.resize((W, H), Image.LANCZOS)
out.save(os.path.join(MOD, "textures", "race_cloth_bowser4.png"))

# and his own, as long: red, the white round with his red M
mim = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
md = ImageDraw.Draw(mim)
md.polygon([(x * S, y * S) for x, y in cloth], fill=(222, 24, 32, 255))
mx, my, mr = 106.0, 83.0, 62.0
md.ellipse(((mx - mr) * S, (my - mr) * S, (mx + mr) * S, (my + mr) * S), fill=(248, 244, 236, 255))
k, t2 = 1.05, 15
m_pts = [(-40, 36), (-26, -34), (-26 + t2, -34), (0, 4), (26 - t2, -34), (26, -34), (40, 36), (40 - t2, 36),
         (26 - t2 / 2, -4), (0, 30), (-26 + t2 / 2, -4), (-40 + t2, 36)]
md.polygon([((mx + x * k) * S, (my + y * k) * S) for x, y in m_pts], fill=(222, 24, 32, 255))
mm = Image.new("RGBA", mim.size, (0, 0, 0, 0))
mm.paste(mim, (0, 0), mask)
mm.resize((W, H), Image.LANCZOS).save(os.path.join(MOD, "textures", "race_cloth_mario2.png"))
if len(sys.argv) > 2:
    bg = Image.new("RGBA", (W * 2 + 20, H * 2 + 20), (110, 170, 230, 255))
    bg.alpha_composite(out.resize((W * 2, H * 2), Image.LANCZOS), (10, 10))
    bg.convert("RGB").save(sys.argv[2])
print("drawn race_cloth_bowser4.png, race_cloth_mario2.png")
