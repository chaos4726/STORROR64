"""The tops and bottoms of the skies. The sky is a sphere about the level: around it each sky picture
(textures/sky_<name>.png) twice, its rows from the top of the view to the bottom - Mario 64 scrolls its sky picture
the same way, its top rows overhead and its bottom rows underfoot (skybox.c: two pictures to a turn). From CAP degrees
up (and down) the sphere is a cap of its own, its picture drawn here from the sky picture as seen looking straight up
(down): each pixel the sky picture at that direction, averaged across the turn as the circles get small, so that the
very top is the mean of its row and there is no pinch. Writes textures/sky_<name>_top.png and _bottom.png.
Usage: python skycapx.py <textures dir>"""
import math
import os
import sys

import numpy as np
from PIL import Image

REPEATS = 2          # pictures to a turn, as sky.lua's sphere has them
CAP = 50.0           # degrees up (down) where the caps begin, as menu.lua builds it
SIZE = 512           # the cap pictures, pixels across
BLEND = 30.0         # degrees from the pole within which the cap blends into its row's mean


def v_of(e):
    """the sky picture's row (0 top .. 1 bottom) at elevation e degrees"""
    return 0.5 - e / 180.0


def cap(img, top):
    h, w, _ = img.shape
    # each row's running sum along the turn, twice round, for a box average over any span of it
    wrap = np.concatenate([img, img], axis=1).astype(np.float64)
    csum = np.concatenate([np.zeros((h, 1, 3)), np.cumsum(wrap, axis=1)], axis=1)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    dx = (xs + 0.5 - SIZE / 2) / (SIZE / 2)
    dy = (ys + 0.5 - SIZE / 2) / (SIZE / 2)
    r = np.minimum(np.sqrt(dx * dx + dy * dy), 1.0)
    a = np.arctan2(dy, dx)
    span = 90.0 - CAP
    e = (90.0 - r * span) if top else (-90.0 + r * span)
    v = np.clip(v_of(e), 0.0, 1.0) * (h - 1)
    u = (REPEATS * a / (2 * math.pi)) % 1.0 * w
    # the span of the turn one pixel covers at this radius (in the picture's pixels), widened near the pole
    per_px = REPEATS * w / (2 * math.pi * np.maximum(r, 1e-6) * (SIZE / 2))
    near = np.clip(1.0 - (90.0 - np.abs(e)) / BLEND, 0.0, 1.0)
    width = np.minimum(np.maximum(per_px, 1.0) + near * near * REPEATS * w, w)
    u0 = u - width / 2
    u0 = np.mod(u0, w)
    u1 = u0 + width
    out = np.zeros((SIZE, SIZE, 3))
    v0 = np.floor(v).astype(int)
    v1 = np.minimum(v0 + 1, h - 1)
    fv = (v - v0)[..., None]
    # (the running sum read between pixels too, so the average slides smoothly as the span widens: whole-pixel
    # steps drew rings round the pole)
    def run(rows, x):
        x = np.clip(x, 0.0, 2 * w - 1e-6)
        i = np.floor(x).astype(int)
        f = (x - i)[..., None]
        return csum[rows, i] + f * (csum[rows, i + 1] - csum[rows, i])
    for rows, k in ((v0, 1.0 - fv), (v1, fv)):
        out += k * (run(rows, u1) - run(rows, u0)) / width[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGB')


def main():
    texd = sys.argv[1]
    n = 0
    for f in sorted(os.listdir(texd)):
        if not (f.startswith('sky_') and f.endswith('.png')) or f.endswith('_top.png') or f.endswith('_bottom.png'):
            continue
        name = f[:-4]
        img = np.asarray(Image.open(os.path.join(texd, f)).convert('RGB'))
        cap(img, True).save(os.path.join(texd, name + '_top.png'))
        cap(img, False).save(os.path.join(texd, name + '_bottom.png'))
        n += 1
    print('sky caps written:', n)


if __name__ == '__main__':
    main()
