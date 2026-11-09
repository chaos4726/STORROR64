# The final fight's floors as the run's liquid chrome (game.lua G.pancakes, bowser_fight.lua's drift): the liquid's own
# look - near-black depths with the sky's stars in them, and flowing bands of the synthwave sky's violet and pink where
# the surface turns toward the horizon - as a picture that repeats seamlessly ("can you make the stage look like the
# liquid?", 2026-11-04). Written as the game shows it: c ** 2.2.
# python -P tools/final_liquid_tex.py <textures dir>
import sys, os, math
import numpy as np
from PIL import Image

out = sys.argv[1]
W = 1024
rng = np.random.default_rng(7)
y, x = np.mgrid[0:W, 0:W] / W                    # 0..1, the picture repeats at 1
T = 2.0 * math.pi


def wave(fx, fy, ph):
    return np.sin(T * (fx * x + fy * y) + ph)


# domain-warped flow, every term whole cycles across the picture so it repeats seamlessly
wx = 0.35 * wave(1, 2, 0.3) + 0.25 * wave(-2, 1, 1.7) + 0.15 * wave(3, -2, 2.9)
wy = 0.35 * wave(2, -1, 0.8) + 0.25 * wave(1, 3, 2.2) + 0.15 * wave(-3, -1, 0.4)
u = x + 0.18 * wx
v = y + 0.18 * wy
f = (np.sin(T * (2 * u + 1 * v) + 0.5) + np.sin(T * (-1 * u + 3 * v) + 1.9) * 0.8
     + np.sin(T * (3 * u - 2 * v) + 2.7) * 0.5 + np.sin(T * (4 * u + 4 * v) + 0.2) * 0.25)
f = (f - f.min()) / (f.max() - f.min())

# bands where the flow crosses a few levels: soft-edged, violet ones and pink ones, a hot thin line in each
def band(level, width):
    return np.exp(-((f - level) / width) ** 2)

violet = band(0.30, 0.035) + band(0.70, 0.03)
pink = band(0.50, 0.025)
hot = band(0.50, 0.007) + band(0.70, 0.006) * 0.6
glow = band(0.5, 0.12) * 0.25 + band(0.7, 0.12) * 0.2

NAVY = np.array([0.012, 0.008, 0.035])
VIOLET = np.array([0.45, 0.25, 0.95])
PINK = np.array([0.98, 0.38, 0.72])
WHITE = np.array([1.0, 0.85, 0.95])

c = np.zeros((W, W, 3)) + NAVY
c += glow[..., None] * np.array([0.20, 0.08, 0.30])
c = c * (1 - np.clip(violet, 0, 1)[..., None]) + VIOLET * np.clip(violet, 0, 1)[..., None]
c = c * (1 - np.clip(pink, 0, 1)[..., None]) + PINK * np.clip(pink, 0, 1)[..., None]
c += WHITE * np.clip(hot, 0, 1)[..., None] * 0.6

# the sky's stars in the dark of it, few and small
n = 900
sx, sy = rng.integers(0, W, n), rng.integers(0, W, n)
br = rng.uniform(0.3, 1.0, n)
for i in range(n):
    if f[sy[i], sx[i]] < 0.22 or 0.36 < f[sy[i], sx[i]] < 0.44 or f[sy[i], sx[i]] > 0.82:
        c[sy[i], sx[i]] = np.maximum(c[sy[i], sx[i]], br[i] * np.array([0.9, 0.9, 1.0]))

c = np.clip(c, 0, 1) ** 2.2
Image.fromarray((c * 255).astype(np.uint8), 'RGB').save(os.path.join(out, 'final_liquid.png'))
print('ok')
