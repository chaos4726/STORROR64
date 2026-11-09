# The secrets' pictures (secrets.lua, caps.lua, charmenu.lua - "a secret unlock ... the ghost runner skin ... a crown ...
# a rainbow skin", 2026-11-04):
#   rainbow_skin.png   the RAINBOW skin's: the rainbow on the slant, repeating seamlessly (two rounds across, one down)
#   crown_gold.png     the crown's gold: a warm gold with a shine across it
#   crown_jewel.png    its jewels: a deep red, lit at the middle
#   skin_*_thumb.png, hat_*_thumb.png, skin_locked_thumb.png   the CHARACTER tab's photos for SKIN and HAT (512 x 512,
#                      as the others): a figure in each skin, the cap and the crown, and "?" for a secret not yet open
# Written as the game shows it: colour ** 2.2 where the engine reads it as linear (the skin's, the crown's).
# python -P tools/secrets_tex.py <mod dir>
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

mod = sys.argv[1]
T = os.path.join(mod, "textures")


def hsv(h, s, v):
    h6 = (h % 1.0) * 6.0
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = a[m], b[m], c[m]
    return out


def save_lin(a, name, mode="RGB"):
    a = np.clip(a, 0, 1) ** 2.2
    Image.fromarray((a * 255).astype(np.uint8), mode).save(os.path.join(T, name))


W = 512
y, x = np.mgrid[0:W, 0:W] / W
# the rainbow skin: hue round twice across and once down - seamless - softly banded
hue = (2.0 * x + 1.0 * y) % 1.0
rb = hsv(hue, np.full_like(hue, 0.8), np.full_like(hue, 0.95))
band = 0.9 + 0.1 * np.cos(2 * np.pi * (6 * x + 3 * y))
save_lin(rb * band[..., None], "rainbow_skin.png")
# the crown's gold and its jewel
g = np.zeros((128, 128, 3))
yy, xx = np.mgrid[0:128, 0:128] / 128.0
shine = np.exp(-((yy - 0.35) ** 2) / 0.02) * 0.45
base = 0.75 + 0.25 * np.cos(2 * np.pi * xx * 3)
g[..., 0], g[..., 1], g[..., 2] = (1.0 * base + shine), (0.72 * base + shine * 0.9), (0.18 * base + shine * 0.5)
save_lin(g, "crown_gold.png")
r = np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2)
j = np.zeros((128, 128, 3))
lit = np.clip(1.0 - r * 1.6, 0, 1)
j[..., 0], j[..., 1], j[..., 2] = 0.55 + 0.45 * lit, 0.05 + 0.5 * lit ** 3, 0.12 + 0.5 * lit ** 3
save_lin(j, "crown_jewel.png")

# the photos: a figure (head, body, arms, legs) filled with a look, on the dark of the tab
BG = (24, 24, 34)


def figure(fill, pack=False, cap=None, crown=False):
    im = Image.new("RGB", (W, W), BG)
    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((206, 70, 306, 170), fill=255)                                # head
    d.rounded_rectangle((180, 180, 332, 340), radius=40, fill=255)          # body
    d.rounded_rectangle((140, 190, 182, 330), radius=20, fill=255)          # arms
    d.rounded_rectangle((330, 190, 372, 330), radius=20, fill=255)
    d.rounded_rectangle((192, 330, 250, 460), radius=22, fill=255)          # legs
    d.rounded_rectangle((262, 330, 320, 460), radius=22, fill=255)
    if pack:
        d.rounded_rectangle((300, 200, 360, 300), radius=24, fill=255)      # backpack, to his side
    im.paste(fill, (0, 0), mask)
    dd = ImageDraw.Draw(im)
    if cap:
        dd.pieslice((196, 58, 316, 150), 180, 360, fill=cap)
        dd.rectangle((196, 102, 330, 114), fill=cap)
    if crown:
        pts = [(204, 108), (204, 60), (228, 84), (256, 44), (284, 84), (308, 60), (308, 108)]
        dd.polygon(pts, fill=(250, 196, 40), outline=(150, 100, 10))
        for cx in (230, 256, 282):
            dd.ellipse((cx - 8, 88, cx + 8, 104), fill=(200, 20, 40))
    return im


# (the ghost's chrome: cool silver, bright bands across it as the metal cap's picture lies on him)
ch = 0.55 + 0.25 * np.cos(2 * np.pi * (1.5 * y + 0.4 * x)) + 0.2 * np.exp(-((y - 0.3) ** 2) / 0.004)
metal = Image.fromarray((np.clip(np.dstack([ch * 0.92, ch * 0.95, ch * 1.05]), 0, 1) * 255).astype(np.uint8), "RGB")
rain = Image.fromarray((hsv(hue, np.full_like(hue, 0.8), np.full_like(hue, 0.95)) * 255).astype(np.uint8), "RGB")
plain = Image.new("RGB", (W, W), (200, 60, 50))
figure(plain, cap=(220, 30, 30)).save(os.path.join(T, "skin_normal_thumb.png"))
figure(metal, pack=True, cap=(190, 194, 205)).save(os.path.join(T, "skin_ghost_thumb.png"))
figure(rain, cap=(255, 120, 200)).save(os.path.join(T, "skin_rainbow_thumb.png"))
figure(plain, cap=(220, 30, 30)).save(os.path.join(T, "hat_cap_thumb.png"))
figure(plain, crown=True).save(os.path.join(T, "hat_crown_thumb.png"))
lk = Image.new("RGB", (W, W), BG)
dl = ImageDraw.Draw(lk)
dl.rounded_rectangle((96, 96, 416, 416), radius=48, outline=(120, 120, 150), width=10)
try:
    font = ImageFont.load_default(size=260)
except TypeError:
    font = ImageFont.load_default()
dl.text((W / 2, W / 2), "?", fill=(200, 200, 230), font=font, anchor="mm")
lk.save(os.path.join(T, "skin_locked_thumb.png"))
print("ok")
