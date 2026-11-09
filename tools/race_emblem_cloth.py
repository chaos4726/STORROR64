"""The Bowser checkpoint flag's cloth from the user's own picture of the emblem (2026-10-27: "this but white" - art/
bowser_emblem_source.png, Bowser's emblem in red on black): the emblem cut out of it - each pixel as much of it as it is
red, for soft edges - made white and set on the checkpoint flag's black cloth (its loose edge in three points), as long
as race.lua's cloth. Writes textures/race_cloth_bowser5.png.

python tools/race_emblem_cloth.py <SM64Map mod dir> <the picture> [preview.png]
"""
import os, sys
from PIL import Image, ImageDraw

MOD, SRC = sys.argv[1], sys.argv[2]
W, H = 256, 166                     # the cloth's picture (race.lua's cloth: 175 x 114 cm)
S = 4                               # (drawn this much bigger, then shrunk)
BLACK = (22, 22, 24, 255)
WHITE = (238, 238, 238)
cloth = [(0, 0), (256, 0), (216, 42), (256, 83), (216, 124), (256, 166), (0, 166)]
CX, HT = 106.0, 142.0               # where the emblem's middle goes across, and its height

# the emblem: how red each pixel is, as its cover
src = Image.open(SRC).convert("RGB")
a = Image.new("L", src.size, 0)
sp, ap = src.load(), a.load()
for y in range(src.height):
    for x in range(src.width):
        r, g, b = sp[x, y]
        red = r - max(g, b)
        ap[x, y] = max(0, min(255, int((red - 40) * 255 / 110)))
box = a.getbbox()
a = a.crop(box)
k = HT * S / a.height
a = a.resize((max(1, round(a.width * k)), max(1, round(a.height * k))), Image.LANCZOS)

im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
ImageDraw.Draw(im).polygon([(x * S, y * S) for x, y in cloth], fill=BLACK)
ox, oy = round(CX * S - a.width / 2), round((H * S - a.height) / 2)
white = Image.new("RGBA", a.size, WHITE + (255,))
white.putalpha(a)
im.alpha_composite(white, (ox, oy))
mask = Image.new("L", im.size, 0)
ImageDraw.Draw(mask).polygon([(x * S, y * S) for x, y in cloth], fill=255)
out = Image.new("RGBA", im.size, (0, 0, 0, 0))
out.paste(im, (0, 0), mask)
out = out.resize((W, H), Image.LANCZOS)
out.save(os.path.join(MOD, "textures", "race_cloth_bowser5.png"))
if len(sys.argv) > 3:
    bg = Image.new("RGBA", (W * 2 + 20, H * 2 + 20), (110, 170, 230, 255))
    bg.alpha_composite(out.resize((W * 2, H * 2), Image.LANCZOS), (10, 10))
    bg.convert("RGB").save(sys.argv[3])
print("cut from", SRC, "box", box, "-> race_cloth_bowser5.png")
