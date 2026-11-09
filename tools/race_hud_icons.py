"""The race's HUD pictures, in the style of Mario 64's own (textures/hud_*.png, read from the ROM): 16x16, hard pixels,
lit from the top left. hud_slash - the "/" between the checkpoints taken and their count, silver as the "x" and the
time's marks; hud_flag - the checkpoint counter's picture, a gold pole and its ball with a black Bowser pennant, as the
race's flags. ("also add a checkpoint number counter", 2026-10-27.)

python tools/race_hud_icons.py <SM64Map mod dir>
"""
import os, sys
from PIL import Image

TEX = os.path.join(sys.argv[1], "textures")


def ramp(img):
    """The picture's colours, darkest to lightest (alpha > 0)."""
    cols = sorted({c for c in img.convert("RGBA").getdata() if c[3] > 0}, key=lambda c: c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11)
    return cols


silver = ramp(Image.open(os.path.join(TEX, "hud_x.png")))
gold = ramp(Image.open(os.path.join(TEX, "hud_star.png")))
S = lambda k: silver[min(len(silver) - 1, int(k * (len(silver) - 1)))]
Gd = lambda k: gold[min(len(gold) - 1, int(k * (len(gold) - 1)))]
BLACK, EDGE, WHITE = (24, 24, 32, 255), (8, 8, 12, 255), (250, 250, 250, 255)

# the slash: a stroke three pixels thick from the bottom left to the top right, dark edged, lit along its top
sl = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
for y in range(1, 15):
    x = 4 + (14 - y) * 8 // 13           # (its middle: x 4 at the bottom, 12 at the top)
    for dx in (-2, -1, 0, 1, 2):
        px = x + dx
        if not 0 <= px < 16:
            continue
        if dx in (-2, 2):
            c = S(0.0)                    # (its edge)
        else:
            k = 1.0 - (y / 15.0) * 0.6 - (0.15 if dx == 1 else 0.0)
            c = S(max(0.2, min(1.0, k)))
        sl.putpixel((px, y), c)
sl.save(os.path.join(TEX, "hud_slash.png"))

# the flag: the pole (x 3-4), its ball on top, the pennant (x 5-14, y 2-9) with a notch in its end and a white mark
fl = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
for y in range(3, 16):
    fl.putpixel((2, y), Gd(0.0))
    fl.putpixel((3, y), Gd(0.95 - y / 30.0))
    fl.putpixel((4, y), Gd(0.55 - y / 40.0))
    fl.putpixel((5, y), Gd(0.0))
for (x, y, k) in [(3, 0, 0.6), (4, 0, 0.5), (2, 1, 0.5), (3, 1, 1.0), (4, 1, 0.9), (5, 1, 0.3), (2, 2, 0.4), (3, 2, 0.8),
                  (4, 2, 0.6), (5, 2, 0.2)]:
    fl.putpixel((x, y), Gd(k))           # (the ball: lit top left, as the star's points)
for y in range(3, 11):
    for x in range(6, 16):
        notch = (x >= 13 and abs(y - 6.5) < (x - 12) * 0.9)
        if notch:
            continue
        edge = y in (3, 10) or x == 15 or (x >= 12 and abs(y - 6.5) < (x - 11) * 0.9 + 0.6)
        fl.putpixel((x, y), EDGE if edge else BLACK)
# (Bowser's mark, as small as it gets: a white face - two eyes over a jaw)
for (x, y) in [(8, 5), (10, 5), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7), (8, 8), (10, 8)]:
    fl.putpixel((x, y), WHITE)
fl.save(os.path.join(TEX, "hud_flag.png"))

# a look at both, big
look = Image.new("RGBA", (16 * 12 * 2 + 12, 16 * 12), (60, 120, 200, 255))
for i, im in enumerate((fl, sl)):
    big = im.resize((16 * 12, 16 * 12), Image.NEAREST)
    look.paste(big, (i * (16 * 12 + 12), 0), big)
look.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "devtmp", "race_hud_icons_look.png"))
print("written hud_slash.png, hud_flag.png")
