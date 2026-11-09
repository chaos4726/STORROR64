# Bowser's mega star (bowser_fight.lua M.mega_star: "after talking to him he gets turned in to a mega star made of rainbow
# material", 2026-11-04): the whole rainbow running across it - two rounds of it on the slant - with the floors' liquid
# lines bright in it (textures/final_liquid_rb.png, tools/final_liquid_rb_tex.py) and a glow; repeats seamlessly, for
# bowser_fight to slide it so the colours run over the star. Written as the game shows it: c ** 2.2.
# python -P tools/rainbow_star_tex.py <textures dir>
import sys, os, colorsys
import numpy as np
from PIL import Image

d = sys.argv[1]
liq = np.asarray(Image.open(os.path.join(d, 'final_liquid_rb.png')).convert('RGB').resize((512, 512))).astype(np.float64) / 255.0
lum = liq.mean(axis=2) ** (1 / 2.2)                     # (as shown)
W = 512
y, x = np.mgrid[0:W, 0:W] / W
hue = (2.0 * x + 1.0 * y + 0.08 * np.sin(2 * np.pi * (3 * y + x))) % 1.0
hsv = np.dstack([hue, np.full_like(hue, 0.85), np.ones_like(hue)])
rgb = np.zeros((W, W, 3))
# hsv -> rgb, vectorised
h6 = hsv[..., 0] * 6.0
i = np.floor(h6).astype(int) % 6
f = h6 - np.floor(h6)
s, v = hsv[..., 1], hsv[..., 2]
p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
for k, (a, b, c) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
    m = i == k
    rgb[m, 0], rgb[m, 1], rgb[m, 2] = a[m], b[m], c[m]
# the colour everywhere, deeper in the dark of the liquid, near white in its lines
shade = 0.55 + 0.45 * np.clip(lum * 1.6, 0, 1)
out = rgb * shade[..., None] + np.clip(lum - 0.6, 0, 1)[..., None] * 1.2
out = np.clip(out, 0, 1) ** 2.2
Image.fromarray((out * 255).astype(np.uint8), 'RGB').save(os.path.join(d, 'rainbow_star.png'))
print('ok')
