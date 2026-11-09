# The final fight's floors in the run's chrome sky's colours (game.lua G.pancakes): the Sky arena's own Render 96
# pictures recoloured - their shapes kept - to the sky's synthwave: the cells' glowing veins magenta and violet over deep
# navy, the sides' stripes violet to pink, the plate a cool chrome ("make it match our backround", 2026-11-04).
# Written as the game shows them: c ** 2.2 (it reads pictures as linear).
# python -P tools/final_stage_tex.py <mod dir>
import sys, os
import numpy as np
from PIL import Image

mod = sys.argv[1]
src = os.path.join(mod, 'textures_r96')
out = os.path.join(mod, 'textures')


def load(name):
    a = np.asarray(Image.open(os.path.join(src, name)).convert('RGB')).astype(np.float64) / 255.0
    return a ** (1 / 2.2)                       # (as the game shows it)


def save(name, c):
    c = np.clip(c, 0, 1) ** 2.2
    Image.fromarray((c * 255).astype(np.uint8), 'RGB').save(os.path.join(out, name + '.png'))


def mix(a, b, t):
    t = t[..., None]
    return a * (1 - t) + b * t


NAVY = np.array([0.04, 0.02, 0.10])
VIOLET = np.array([0.42, 0.22, 0.95])
MAGENTA = np.array([0.98, 0.25, 0.80])
PINK = np.array([1.00, 0.55, 0.75])

# the cells: their green veins glow
a = load('levels__bowser_3__1.rgba16.png')
green = np.clip(a[..., 1] - np.maximum(a[..., 0], a[..., 2]) * 0.6, 0, 1)
lum = a.mean(axis=2)
glow = np.clip(green * 1.6, 0, 1)
hot = np.clip((glow - 0.55) / 0.45, 0, 1)
c = mix(NAVY + lum[..., None] * np.array([0.10, 0.06, 0.20]), VIOLET, glow)
c = mix(c, MAGENTA, hot * 0.85)
save('final_stage_1', c)

# the sides: the stripes violet, their brightest pink
a = load('levels__bowser_3__2.rgba16.png')
g = np.clip(a[..., 1], 0, 1)
c = mix(NAVY, VIOLET, np.clip(g * 1.3, 0, 1))
c = mix(c, PINK, np.clip((g - 0.75) / 0.25, 0, 1) * 0.8)
save('final_stage_2', c)

# the plate: chrome, cooled toward the sky's blue-violet
a = load('levels__bowser_3__0.rgba16.png')
lum = a.mean(axis=2)
c = lum[..., None] * np.array([0.78, 0.74, 1.00]) * 0.85 + np.array([0.03, 0.01, 0.06])
save('final_stage_0', c)
print('ok')
