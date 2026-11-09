# The final fight's floor cracks (bowser_fight.lua pancake_crack): big fissures out from where Bowser came down - a
# black split with a glowing orange-red rim, so they show on the arena's dark cells and green veins ("the crack is still
# bad, its also very small", 2026-11-03). fissure_1..3: more fissures, longer, at each hit (drawn bigger each time).
# Written with gamma 2.2 as the game reads pictures as linear.
# python -P tools/boss_cracks.py <textures dir>
import sys, os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
W = 2048
S4 = 2                                   # drawn twice the size and brought down: smooth edges


def fissures(seed, n_main, reach, branchy):
    rnd = random.Random(seed)
    big = Image.new('L', (W * S4, W * S4), 0)
    d = ImageDraw.Draw(big)
    c = W * S4 / 2

    def run(x, y, ang, length, width, depth):
        left = length
        while left > 0:
            seg = rnd.uniform(40, 110) * S4
            ang += rnd.uniform(-0.28, 0.28)
            nx, ny = x + math.cos(ang) * seg, y + math.sin(ang) * seg
            r = math.hypot(nx - c, ny - c)
            if r > W * S4 * 0.48:
                return
            d.line((x, y, nx, ny), fill=255, width=max(S4 * 2, int(width)))
            d.ellipse((nx - width / 2, ny - width / 2, nx + width / 2, ny + width / 2), fill=255)
            x, y = nx, ny
            left -= seg
            width = max(S4 * 3.0, width * 0.94)
            if depth < 1 and rnd.random() < branchy:
                run(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(0.4, 0.8), left * rnd.uniform(0.45, 0.75),
                    width * 0.65, depth + 1)

    for i in range(n_main):
        a = i * 2 * math.pi / n_main + rnd.uniform(-0.25, 0.25)
        run(c, c, a, rnd.uniform(reach * 0.75, reach) * W * S4, rnd.uniform(26, 34) * S4, 0)
    # (the impact itself: a broken hole of a few jagged points)
    pts = []
    for k in range(9):
        a = k * 2 * math.pi / 9 + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(28, 60) * S4
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=255)
    return big.resize((W, W), Image.LANCZOS)


def save(name, line):
    L = np.asarray(line).astype(np.float64) / 255.0
    glow1 = np.asarray(line.filter(ImageFilter.GaussianBlur(7))).astype(np.float64) / 255.0
    glow2 = np.asarray(line.filter(ImageFilter.GaussianBlur(24))).astype(np.float64) / 255.0
    hot = np.clip(glow1 * 2.4, 0, 1) * (1 - L)               # (the rim: white-hot orange next to the split)
    warm = np.clip(glow2 * 3.0, 0, 1) * (1 - L)              # (and red further out)
    rgba = np.zeros((W, W, 4))
    for ch, (core, h, w) in enumerate([(0.03, 1.00, 0.85), (0.01, 0.62, 0.14), (0.01, 0.18, 0.04)]):
        col = w * warm + (h - w) * hot
        rgba[..., ch] = core * L + np.clip(col, 0, 1) * (1 - L)
    a = np.clip(np.maximum(L, np.maximum(hot * 1.0, warm * 0.75)), 0, 1)
    rgba[..., 3] = a
    rgba[..., :3] = np.clip(rgba[..., :3], 0, 1) ** 2.2
    Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, name + '.png'))


save('fissure_1', fissures(11, 5, 0.40, 0.10))
save('fissure_2', fissures(23, 7, 0.46, 0.14))
save('fissure_3', fissures(37, 9, 0.50, 0.18))
print('ok')
