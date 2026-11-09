"""The ghost race's beacon pictures (race.lua), 2026-10-27: the checkpoint flags - Bowser's before he passes it, his own
after (Mario 3D World's, as the user showed them) - and the beams of light over the next ones.

python tools/race_art.py <SM64Map mod dir> [bowser.png mario.png]

Given the user's own flag pictures, they are used (cut to the flag, made 256 x 384, the pole at 27% across); else
stand-ins are drawn here in their likeness."""
import math, os, sys
from PIL import Image, ImageDraw

MOD = sys.argv[1]
OUT = os.path.join(MOD, "textures")
W, H = 256, 384
POLE_X = int(W * 0.27)
GOLD, GOLD_HI, GOLD_LO = (250, 196, 20, 255), (255, 232, 120, 255), (205, 150, 10, 255)


def fit(path):
    """The user's picture: its white or empty surround cleared, set on a 256 x 384 canvas, its pole at POLE_X."""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0 and r > 245 and g > 245 and b > 245:
                px[x, y] = (255, 255, 255, 0)
    im = im.crop(im.getbbox())
    k = min(W / im.width, H / im.height)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(im, ((W - im.width) // 2, H - im.height), im)
    return out


def pole(d):
    # the base: a gold disc, a white ring on it
    d.ellipse((POLE_X - 58, H - 30, POLE_X + 58, H - 4), fill=GOLD_LO)
    d.ellipse((POLE_X - 58, H - 36, POLE_X + 58, H - 12), fill=GOLD)
    d.ellipse((POLE_X - 38, H - 46, POLE_X + 38, H - 28), fill=(235, 235, 235, 255))
    d.rectangle((POLE_X - 30, H - 52, POLE_X + 30, H - 37), fill=(235, 235, 235, 255))
    d.ellipse((POLE_X - 30, H - 58, POLE_X + 30, H - 46), fill=(250, 250, 250, 255))
    # the pole and its ball
    d.rectangle((POLE_X - 9, 40, POLE_X + 9, H - 52), fill=GOLD)
    d.rectangle((POLE_X - 4, 40, POLE_X - 1, H - 52), fill=GOLD_HI)
    d.ellipse((POLE_X - 20, 6, POLE_X + 20, 46), fill=GOLD)
    d.ellipse((POLE_X - 12, 12, POLE_X + 2, 26), fill=GOLD_HI)


def cloth(d, colour):
    x0, x1, xn = POLE_X + 9, W - 6, W - 44
    top, bot = 54, 236
    step = (bot - top) / 4.0
    pts = [(x0, top), (x1, top), (xn, top + step), (x1, top + 2 * step), (xn, top + 3 * step), (x1, bot), (x0, bot)]
    d.polygon(pts, fill=colour)
    return (x0 + xn) / 2.0 + 4, (top + bot) / 2.0


def bowser():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pole(d)
    cx, cy = cloth(d, (45, 45, 48, 255))
    wht, blk = (232, 232, 232, 255), (45, 45, 48, 255)
    # Bowser's face, his emblem: horns, brow, the face, eyes and a fanged grin
    d.polygon([(cx - 44, cy - 30), (cx - 52, cy - 70), (cx - 26, cy - 44)], fill=wht)
    d.polygon([(cx + 44, cy - 30), (cx + 52, cy - 70), (cx + 26, cy - 44)], fill=wht)
    d.polygon([(cx - 20, cy - 46), (cx - 10, cy - 64), (cx, cy - 50), (cx + 10, cy - 64), (cx + 20, cy - 46)], fill=wht)
    d.ellipse((cx - 46, cy - 50, cx + 46, cy + 54), fill=wht)
    d.polygon([(cx - 32, cy - 22), (cx - 6, cy - 8), (cx - 12, cy + 4), (cx - 30, cy - 6)], fill=blk)
    d.polygon([(cx + 32, cy - 22), (cx + 6, cy - 8), (cx + 12, cy + 4), (cx + 30, cy - 6)], fill=blk)
    d.polygon([(cx - 34, cy + 14), (cx + 34, cy + 14), (cx + 22, cy + 42), (cx - 22, cy + 42)], fill=blk)
    for fx in (-22, 22):
        d.polygon([(cx + fx - 7, cy + 14), (cx + fx + 7, cy + 14), (cx + fx, cy + 34)], fill=wht)
    for fx in (-10, 10):
        d.polygon([(cx + fx - 6, cy + 42), (cx + fx + 6, cy + 42), (cx + fx, cy + 28)], fill=wht)
    return im


def mario():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pole(d)
    cx, cy = cloth(d, (222, 24, 32, 255))
    red = (222, 24, 32, 255)
    d.ellipse((cx - 58, cy - 58, cx + 58, cy + 58), fill=(248, 244, 236, 255))
    # the M
    t = 15
    d.polygon([(cx - 40, cy + 36), (cx - 26, cy - 34), (cx - 26 + t, cy - 34), (cx, cy + 4), (cx + 26 - t, cy - 34),
               (cx + 26, cy - 34), (cx + 40, cy + 36), (cx + 40 - t, cy + 36), (cx + 26 - t / 2, cy - 4), (cx, cy + 30),
               (cx - 26 + t / 2, cy - 4), (cx - 40 + t, cy + 36)], fill=red)
    return im


def beam(colour, strength, core=(255, 252, 225)):
    # (a pillar of light, as Call of Duty's mystery box's: a white-hot core in a yellow glow, strong at its foot - the
    # picture's bottom - and dying away slowly up it)
    w, h = 64, 1024
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        f = min(1.0, (h - 1 - y) / (0.07 * h))
        up = (y / (h - 1)) ** 0.55 * (f * f * (3.0 - 2.0 * f))   # (and fading in smoothly over its foot, ~8 m: "make the beam fade at the bottom")
        for x in range(w):
            d = abs(x - (w - 1) / 2.0) / (w / 2.0)
            glow = max(0.0, 1.0 - d) ** 1.4
            hot = max(0.0, 1.0 - d / 0.3) ** 1.2
            c = tuple(int(colour[k] + (core[k] - colour[k]) * hot) for k in range(3))
            px[x, y] = c + (min(255, int(255 * strength * up * (0.95 * glow + 0.6 * hot))),)
    return im


if len(sys.argv) >= 4:
    fit(sys.argv[2]).save(os.path.join(OUT, "race_flag_bowser.png"))
    fit(sys.argv[3]).save(os.path.join(OUT, "race_flag_mario.png"))
    print("flags from the user's pictures")
else:
    bowser().save(os.path.join(OUT, "race_flag_bowser.png"))
    mario().save(os.path.join(OUT, "race_flag_mario.png"))
    print("stand-in flags drawn")
# the 3D flag's parts (race.lua): its cloths, cut from the flags' pictures - the cloth alone, its zigzag edge see-through
# - and the gold of the pole, ball and base, the white of the base's ring
CLOTH = (POLE_X + 9, 54, W - 6, 236)
for who in ("bowser", "mario"):
    Image.open(os.path.join(OUT, "race_flag_%s.png" % who)).crop(CLOTH).save(os.path.join(OUT, "race_cloth_%s.png" % who))
Image.new("RGBA", (8, 8), GOLD).save(os.path.join(OUT, "race_gold.png"))
Image.new("RGBA", (8, 8), (240, 240, 240, 255)).save(os.path.join(OUT, "race_white.png"))
print("cloths and parts cut")
beam((255, 205, 25), 1.0).save(os.path.join(OUT, "race_glow.png"))
beam((255, 236, 150), 0.45).save(os.path.join(OUT, "race_glow_dim.png"))
print("beams drawn")
