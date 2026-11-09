# The last fight's sky (bowser_fight.lua, G.chrome_sky_up with this picture): the run's chrome sky
# (textures/run_chrome_sky.png, tools/chrome_env.py) - its lower half black, under the lava in the run - with its
# upper half again below the horizon, mirrored and a little dimmer: stars and ribbons all round, for the floors hang in
# the open - "also the backround is half black", 2026-11-04. python -P tools/final_sky_tex.py <textures dir>
import sys, os
import numpy as np
from PIL import Image

d = sys.argv[1]
a = np.asarray(Image.open(os.path.join(d, 'run_chrome_sky.png')).convert('RGB')).astype(np.float64) / 255.0
h = a.shape[0] // 2
top = a[:h]
low = top[::-1] * 0.7                      # (as stored, c ** 2.2: 0.7 of it is about 0.85 as seen)
out = np.concatenate([top, low], axis=0)
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGB').save(os.path.join(d, 'final_sky.png'))
print('ok')
