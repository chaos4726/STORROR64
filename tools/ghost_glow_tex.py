# The purple on the floor where Bowser's shadow will stand (bowser_fight.lua M.glow_at: "also add a purple hue around
# the area that the ghost bowser spawns", 2026-11-04): a soft violet glow, brightest in a ring near its edge, a faint
# swirl in it, fading out to nothing at its rim. RGBA; its colour written as the game shows it (c ** 2.2), its alpha as is.
# python -P tools/ghost_glow_tex.py <textures dir>
import sys, os, math
import numpy as np
from PIL import Image

out = sys.argv[1]
W = 512
y, x = (np.mgrid[0:W, 0:W] + 0.5) / W * 2.0 - 1.0
r = np.hypot(x, y)
a = np.arctan2(y, x)

disc = np.clip(1.0 - r, 0, 1) ** 0.8 * 0.45                      # the soft middle
ring = np.exp(-((r - 0.78) / 0.07) ** 2)                          # the ring near the edge
inner = np.exp(-((r - 0.55) / 0.03) ** 2) * 0.35                  # a thin one inside it
swirl = (0.5 + 0.5 * np.sin(5.0 * a + 9.0 * r)) * np.clip(1.0 - r, 0, 1) * 0.25
alpha = np.clip(disc + ring * 0.9 + inner + swirl, 0, 1) * np.clip((1.0 - r) / 0.12, 0, 1)

VIOLET = np.array([0.62, 0.22, 1.0])
PINK = np.array([0.95, 0.55, 1.0])
t = np.clip(ring + inner, 0, 1)[..., None]
c = VIOLET * (1 - t) + PINK * t
c = np.clip(c, 0, 1) ** 2.2
img = np.dstack([c, alpha])
Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, 'ghost_glow.png'))
print('ok')
