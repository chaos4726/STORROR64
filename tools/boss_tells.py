# The final fight's own pictures (bowser_fight.lua): cracks for its floors (crack_1..3, cut-out: dark split stone with a
# faint glow in it), the fire snipe's warning strip (tell_strip) and the meteors' landing marks (tell_ring) - see-through
# red. Written with gamma 2.2 as the game reads pictures as linear.
# python -P tools/boss_tells.py <textures dir>
import sys, os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]

def save(name, rgba):
    a = np.asarray(rgba).astype(np.float64) / 255.0
    a[..., :3] = a[..., :3] ** 2.2
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, name + '.png'))

def crack(seed, n_main, size=1024):
    # jagged cracks: straight runs that break off at sharp angles, tapering, branching; near black, a hair of shadow
    # either side for depth; smooth-edged (drawn see-through), no glow
    rnd = random.Random(seed)
    W = size
    S4 = 4                                   # drawn 4x and brought down: smooth edges
    big = Image.new('L', (W * S4, W * S4), 0)
    d = ImageDraw.Draw(big)
    c = W * S4 / 2
    def run(x, y, ang, length, width, depth):
        left = length
        while left > 0:
            seg = rnd.uniform(14, 34) * S4
            ang += rnd.uniform(-0.55, 0.55)
            nx, ny = x + math.cos(ang) * seg, y + math.sin(ang) * seg
            if not (S4 * 6 < nx < W * S4 - S4 * 6 and S4 * 6 < ny < W * S4 - S4 * 6):
                return
            d.line((x, y, nx, ny), fill=255, width=max(S4, int(width)))
            d.ellipse((nx - width / 2, ny - width / 2, nx + width / 2, ny + width / 2), fill=255)
            x, y = nx, ny
            left -= seg
            width = max(S4 * 0.8, width * 0.93)
            if depth < 3 and rnd.random() < 0.22:
                run(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(0.5, 1.2), left * rnd.uniform(0.35, 0.6), width * 0.6, depth + 1)
    for i in range(n_main):
        a = i * 2 * math.pi / n_main + rnd.uniform(-0.35, 0.35)
        run(c, c, a, rnd.uniform(W * 0.30, W * 0.47) * S4, rnd.uniform(4.5, 6.5) * S4, 0)
    line = big.resize((W, W), Image.LANCZOS)
    L = np.asarray(line).astype(np.float64) / 255.0
    # (the broken stone's lip round the split: pale, as stone shows inside - a dark crack alone was lost on the dark floor)
    lip = np.asarray(line.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float64) / 255.0
    lip = np.clip(lip - L, 0, 1)
    rgba = np.zeros((W, W, 4))
    k = np.clip(L * 1.3, 0, 1)
    for ch, (dark, pale) in enumerate([(0.04, 0.80), (0.03, 0.86), (0.03, 0.78)]):
        rgba[..., ch] = dark * k + pale * (1 - k)
    rgba[..., 3] = np.clip(np.maximum(L, lip * 0.85), 0, 1)
    return (rgba * 255).astype(np.uint8)

for i, (seed, n) in enumerate([(11, 5), (23, 7), (37, 9)], 1):
    save('crack_%d' % i, crack(seed, n))

# the snipe's strip: hot red down its middle, soft at its sides, chevrons pointing along it (u runs along it)
W, H = 512, 128
u = np.linspace(0, 1, W)[None, :]
v = np.linspace(-1, 1, H)[:, None]
side = np.clip(1.0 - np.abs(v) ** 3, 0, 1)
chev = ((u * 8.0 + np.abs(v) * 0.5) % 1.0) < 0.5
rgba = np.zeros((H, W, 4))
rgba[..., 0] = 1.0
rgba[..., 1] = np.where(chev, 0.18, 0.05)
rgba[..., 2] = 0.03
rgba[..., 3] = side * np.where(chev, 0.85, 0.55)
edge = (np.abs(v) > 0.82) & (np.abs(v) < 0.95)
rgba[..., 3] = np.maximum(rgba[..., 3], edge * 0.95)
save('tell_strip', (rgba * 255).astype(np.uint8))

# the meteors' marks: a red disc, a bright ring round it and a smaller one in it
W = 256
y, x = np.mgrid[0:W, 0:W]
r = np.sqrt((x - W / 2 + 0.5) ** 2 + (y - W / 2 + 0.5) ** 2) / (W / 2)
rgba = np.zeros((W, W, 4))
rgba[..., 0] = 1.0
rgba[..., 1] = 0.08
rgba[..., 2] = 0.04
a = np.where(r < 0.88, 0.35, 0.0)
a = np.maximum(a, np.exp(-((r - 0.92) / 0.035) ** 2) * 0.95)
a = np.maximum(a, np.exp(-((r - 0.45) / 0.03) ** 2) * 0.8)
a = np.maximum(a, np.where(r < 0.12, 0.85, 0.0))
rgba[..., 3] = np.clip(a, 0, 1) * (r < 1.0)
save('tell_ring', (rgba * 255).astype(np.uint8))
print('ok')
