# The final fight's floors, rainbow liquid (bowser_fight.lua M.liquid_tick): the liquid's flow - its warped bands, a web
# of bright lines over them like light through water, the sky's stars in the dark - drawn without colour, for the
# material's colour to tint: each wedge of the arena its own colour of the rainbow, turning ("can you make the stage
# texture move like the water, also make it change colors like a rainbow", 2026-11-04). Repeats seamlessly.
# Written as the game shows it: c ** 2.2.
# python -P tools/final_liquid_rb_tex.py <textures dir>
import sys, os, math
import numpy as np
from PIL import Image

out = sys.argv[1]
W = 1024
rng = np.random.default_rng(11)
y, x = np.mgrid[0:W, 0:W] / W
T = 2.0 * math.pi


def wave(fx, fy, ph):
    return np.sin(T * (fx * x + fy * y) + ph)


# domain-warped flow, whole cycles across the picture so it repeats
wx = 0.35 * wave(1, 2, 0.3) + 0.25 * wave(-2, 1, 1.7) + 0.15 * wave(3, -2, 2.9)
wy = 0.35 * wave(2, -1, 0.8) + 0.25 * wave(1, 3, 2.2) + 0.15 * wave(-3, -1, 0.4)
u = x + 0.16 * wx
v = y + 0.16 * wy
f = (np.sin(T * (2 * u + 1 * v) + 0.5) + np.sin(T * (-1 * u + 3 * v) + 1.9) * 0.8
     + np.sin(T * (3 * u - 2 * v) + 2.7) * 0.5 + np.sin(T * (4 * u + 4 * v) + 0.2) * 0.25)
f = (f - f.min()) / (f.max() - f.min())

# light through water: thin bright ridges where two warped wave fields cross zero
g1 = np.sin(T * (3 * u + 2 * v) + 0.7 + 1.3 * wave(2, 3, 0.1)) + np.sin(T * (-2 * u + 4 * v) + 2.1)
g2 = np.sin(T * (4 * u - 1 * v) + 1.4 + 1.1 * wave(-1, 3, 1.2)) + np.sin(T * (1 * u + 5 * v) + 0.3)
web = np.exp(-(g1 / 0.22) ** 2) * 0.55 + np.exp(-(g2 / 0.18) ** 2) * 0.45


def band(level, width):
    return np.exp(-((f - level) / width) ** 2)


bands = band(0.30, 0.05) * 0.7 + band(0.50, 0.04) + band(0.70, 0.045) * 0.8
hot = band(0.50, 0.008) + band(0.70, 0.007) * 0.7 + band(0.30, 0.006) * 0.5

lum = 0.13 + 0.10 * f                                   # the depths: dark, a little lighter toward the bands
lum = lum + bands * 0.55
lum = lum + web * 0.35
lum = lum + hot * 0.5
c = np.repeat(np.clip(lum, 0, 1)[..., None], 3, axis=2)

# stars in the dark of it
n = 700
sx, sy = rng.integers(0, W, n), rng.integers(0, W, n)
br = rng.uniform(0.5, 1.0, n)
for i in range(n):
    if lum[sy[i], sx[i]] < 0.3:
        c[sy[i], sx[i]] = br[i]

c = np.clip(c, 0, 1) ** 2.2
Image.fromarray((c * 255).astype(np.uint8), 'RGB').save(os.path.join(out, 'final_liquid_rb.png'))
print('ok')
