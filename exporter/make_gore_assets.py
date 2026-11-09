"""Pictures for HUMAN MODE's gore (gore.lua): a drop of blood (gore_blood_drop), a wound on a cut (gore_blood_cut) and a
pool of blood on the floor (gore_blood_pool).

Usage: python make_gore_assets.py <mod textures dir>"""
import sys, os, math, random
import numpy as np
from PIL import Image, ImageFilter


def drop(size=64):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (size / 2.0)
    a = np.clip((1.0 - r) / 0.12, 0.0, 1.0)
    # (dark at its rim, a wet glint up and to the left)
    shade = np.clip(1.0 - r * 0.55, 0.0, 1.0)
    g = np.exp(-(((x - c * 0.7) ** 2 + (y - c * 0.65) ** 2) / (2 * (size * 0.08) ** 2)))
    R = 120 + 100 * shade + 60 * g
    G = 0 + 6 * shade + 60 * g
    B = 0 + 8 * shade + 60 * g
    img = np.dstack([R, G, B, a * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(img, 'RGBA')


def wound(size=64):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (size / 2.0)
    a = np.clip((1.0 - r) / 0.1, 0.0, 1.0)
    # (raw flesh round a dark middle, a pale ring of bone off centre)
    R = np.where(r < 0.45, 60 + 40 * r, 150 - 60 * r)
    G = np.where(r < 0.45, 0.0, 20 + 10 * r)
    B = np.where(r < 0.45, 0.0, 22 + 10 * r)
    bone = np.exp(-(((x - c * 1.15) ** 2 + (y - c * 0.9) ** 2) / (2 * (size * 0.07) ** 2)))
    R, G, B = R + 120 * bone, G + 110 * bone, B + 95 * bone
    img = np.dstack([R, G, B, a * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(img, 'RGBA')


def pool(size=256, seed=7):
    rnd = random.Random(seed)
    m = Image.new('L', (size, size), 0)
    arr = np.zeros((size, size), np.float32)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    arr = np.maximum(arr, (1.0 - np.sqrt((x - c) ** 2 + (y - c) ** 2) / (size * 0.30)))
    for _ in range(16):
        ang = rnd.random() * 2 * math.pi
        d = size * (0.12 + rnd.random() * 0.22)
        rr = size * (0.05 + rnd.random() * 0.12)
        cx, cy = c + math.cos(ang) * d, c + math.sin(ang) * d
        arr = np.maximum(arr, 1.0 - np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / rr)
    # (little splashes thrown round it)
    for _ in range(22):
        ang = rnd.random() * 2 * math.pi
        d = size * (0.36 + rnd.random() * 0.12)
        rr = size * (0.008 + rnd.random() * 0.02)
        cx, cy = c + math.cos(ang) * d, c + math.sin(ang) * d
        arr = np.maximum(arr, 1.0 - np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / rr)
    m = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(2))
    a = np.asarray(m).astype(np.float32) / 255.0
    a = np.clip((a - 0.02) / 0.12, 0.0, 1.0)
    # (deeper - darker - towards its middle, smoothly)
    depth = np.clip(np.asarray(m.filter(ImageFilter.GaussianBlur(14))).astype(np.float32) / 255.0, 0, 1)
    R = 175 - 60 * depth
    G = 4 + 0 * depth
    B = 8 + 0 * depth
    img = np.dstack([R, G, B, a * 235]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(img, 'RGBA')


def splat(size=128, seed=11):
    """a drop of blood landed: a blob, a little long, its spatter thrown on ahead of it (+x: the way it was going)"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx, cy = size * 0.40, size * 0.5
    arr = 1.0 - np.sqrt(((x - cx) / (size * 0.20)) ** 2 + ((y - cy) / (size * 0.15)) ** 2)
    for _ in range(7):
        ang = rnd.uniform(-1.2, 1.2)
        d = size * rnd.uniform(0.05, 0.14)
        rr = size * rnd.uniform(0.05, 0.09)
        bx, by = cx + math.cos(ang) * d, cy + math.sin(ang) * d
        arr = np.maximum(arr, 1.0 - np.sqrt((x - bx) ** 2 + (y - by) ** 2) / rr)
    for _ in range(12):
        ang = rnd.uniform(-0.7, 0.7)
        d = size * rnd.uniform(0.22, 0.48)
        rr = size * rnd.uniform(0.012, 0.035)
        bx, by = cx + math.cos(ang) * d, cy + math.sin(ang) * d
        arr = np.maximum(arr, 1.0 - np.sqrt((x - bx) ** 2 + (y - by) ** 2) / rr)
    m = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(1.2))
    a = np.clip((np.asarray(m).astype(np.float32) / 255.0 - 0.03) / 0.15, 0.0, 1.0)
    depth = np.clip(np.asarray(m.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0, 0, 1)
    R = 185 - 70 * depth
    G = 4 + 0 * depth
    B = 8 + 0 * depth
    img = np.dstack([R, G, B, a * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(img, 'RGBA')


def _paint(arr, blur, size):
    """a shape (0..1, 1 inside) made blood: crisp edged, darker where it is deep"""
    m = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(blur))
    a = np.clip((np.asarray(m).astype(np.float32) / 255.0 - 0.03) / 0.15, 0.0, 1.0)
    depth = np.clip(np.asarray(m.filter(ImageFilter.GaussianBlur(size / 24))).astype(np.float32) / 255.0, 0, 1)
    R = 185 - 75 * depth
    img = np.dstack([R, 4 + 0 * depth, 8 + 0 * depth, a * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(img, 'RGBA')


def _disc(x, y, cx, cy, r, sx=1.0, sy=1.0):
    return 1.0 - np.sqrt(((x - cx) / (r * sx)) ** 2 + ((y - cy) / (r * sy)) ** 2)


def splat_crown(size=256, seed=21):
    """straight down: a round splash, a crown of droplets thrown all round it"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    arr = _disc(x, y, c, c, size * 0.2)
    for _ in range(9):
        ang = rnd.uniform(0, 2 * math.pi)
        d = size * rnd.uniform(0.08, 0.16)
        arr = np.maximum(arr, _disc(x, y, c + math.cos(ang) * d, c + math.sin(ang) * d, size * rnd.uniform(0.05, 0.08)))
    for k in range(16):
        ang = 2 * math.pi * k / 16 + rnd.uniform(-0.15, 0.15)
        d = size * rnd.uniform(0.27, 0.40)
        r = size * rnd.uniform(0.012, 0.03)
        cx, cy = c + math.cos(ang) * d, c + math.sin(ang) * d
        # (each drawn out along its way from the middle)
        rx = x - cx; ry = y - cy
        along = (rx * math.cos(ang) + ry * math.sin(ang)) / (r * 1.8)
        across = (-rx * math.sin(ang) + ry * math.cos(ang)) / r
        arr = np.maximum(arr, 1.0 - np.sqrt(along ** 2 + across ** 2))
    return _paint(arr, 1.0, size)


def splat_streak(size=256, seed=31):
    """fast and low: a long smear tapering on ahead of where it hit (+x)"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cy = size / 2.0
    hx = size * 0.22
    arr = _disc(x, y, hx, cy, size * 0.12, 1.15, 1.0)
    t = np.clip((x - hx) / (size * 0.68), 0.0, 1.0)
    width = size * 0.10 * (1.0 - t) ** 1.3 + 0.5
    wob = np.sin(x / size * 9.0) * size * 0.012
    tail = 1.0 - np.abs(y - cy - wob) / width
    arr = np.maximum(arr, np.where((x >= hx) & (x <= size * 0.92), tail, 0.0))
    for _ in range(9):
        d = rnd.uniform(0.35, 0.95)
        arr = np.maximum(arr, _disc(x, y, size * d, cy + rnd.uniform(-1, 1) * size * 0.12, size * rnd.uniform(0.008, 0.022)))
    return _paint(arr, 0.8, size)


def splat_mist(size=256, seed=41):
    """a fine spray: specks, thick in the middle, thinning out"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    arr = np.zeros((size, size), np.float32)
    for _ in range(70):
        d = size * 0.42 * (rnd.random() ** 1.6)
        ang = rnd.uniform(0, 2 * math.pi)
        r = size * rnd.uniform(0.006, 0.03) * (1.0 - d / (size * 0.5))
        arr = np.maximum(arr, _disc(x, y, c + math.cos(ang) * d, c + math.sin(ang) * d, max(r, 1.2)))
    return _paint(arr, 0.6, size)


def splat_tiny(size=256, seed=51):
    """a super tiny drop: one round dot, a little out of round (drawn small)"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    arr = _disc(x, y, c, c, size * 0.32, 1.08, 0.94)
    for _ in range(3):
        ang = rnd.uniform(0, 2 * math.pi)
        arr = np.maximum(arr, _disc(x, y, c + math.cos(ang) * size * 0.16, c + math.sin(ang) * size * 0.16, size * 0.18))
    return _paint(arr, 1.5, size)


def splat_pool(size=256):
    """a pool: the round spread of blood that has run together"""
    im = pool(size, seed=13)
    a = np.asarray(im).astype(np.float32)
    # (a little darker and more solid than a fresh splat)
    a[:, :, 0] = a[:, :, 0] * 0.9
    a[:, :, 3] = np.clip(a[:, :, 3] * 1.1, 0, 255)
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def streak_var(size=256, seed=0, L=0.7, w=0.08, taper=1.3, head=0.11, amp=0.0, freq=1.0, strands=None, fork=None,
               beads=0, dots_from=None, spikes=0, smear=False, sats=6, extra=None):
    """a streak of blood, its own way: a head where it hit (x 0.2), a body drawn on ahead (+x) - `strands` (dy, angle)
    for more than one, `fork` (at, spread) to split, beads along it, dots past `dots_from`, spikes off it, a brush's
    stripes, satellite drops ahead"""
    rnd = random.Random(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cy, hx = size / 2.0, size * 0.2
    arr = _disc(x, y, hx, cy, size * head, 1.15, 1.0) if head > 0 else np.zeros((size, size), np.float32)
    path = []

    def body(y0, ang, u0=0.0, u1=1.0, ox=hx, oy=cy, scale=1.0):
        nonlocal arr
        n = 70
        for i in range(n + 1):
            u = u0 + (u1 - u0) * i / n
            px = ox + u * L * size * math.cos(ang)
            py = oy + y0 * size + u * L * size * math.sin(ang) + amp * size * math.sin(u * freq * 2 * math.pi) * min(1.0, u * 3)
            ww = (w * size * (1.0 - u) ** taper + 0.6) * scale
            if dots_from is not None and u > dots_from:
                if i % 6 == 0:
                    arr = np.maximum(arr, _disc(x, y, px, py, max(1.0, ww * 1.4)))
                continue
            arr = np.maximum(arr, _disc(x, y, px, py, max(0.8, ww)))
            path.append((px, py, ww, u))
        return path[-1] if path else (ox, oy, 1.0, 1.0)

    if fork:
        at, spread = fork
        ex, ey, _, _ = body(0.0, 0.0, 0.0, at)
        for sgn in (-1, 1):
            n = 40
            for i in range(n + 1):
                u = at + (1.0 - at) * i / n
                px = ex + (u - at) * L * size * math.cos(sgn * spread)
                py = ey + (u - at) * L * size * math.sin(sgn * spread)
                ww = w * size * 0.7 * (1.0 - u) ** taper + 0.6
                arr = np.maximum(arr, _disc(x, y, px, py, max(0.8, ww)))
    else:
        for dy, ang in (strands or [(0.0, 0.0)]):
            body(dy, ang)
    if smear:
        stripes = 0.55 + 0.45 * np.sin(y / size * 2 * math.pi * 9.0 + np.sin(x / size * 7.0) * 2.0)
        arr = np.where(x > hx * 0.6, arr * stripes + (arr - 0.5) * 0.2, arr)
    for _ in range(beads):
        px, py, ww, u = path[rnd.randrange(len(path))] if path else (hx, cy, 2.0, 0.5)
        arr = np.maximum(arr, _disc(x, y, px, py, max(2.0, ww * 1.9)))
    for _ in range(spikes):
        px, py, ww, u = path[rnd.randrange(len(path) // 2)] if path else (hx, cy, 2.0, 0.2)
        ang = rnd.choice((-1, 1)) * rnd.uniform(0.6, 1.2) + 0.3
        ln = size * rnd.uniform(0.05, 0.12)
        for k in range(12):
            t = k / 11.0
            arr = np.maximum(arr, _disc(x, y, px + math.cos(ang) * ln * t, py + math.sin(ang) * ln * t, max(0.8, ww * 0.5 * (1 - t) + 0.6)))
    for _ in range(sats):
        d = rnd.uniform(0.3, 0.95)
        arr = np.maximum(arr, _disc(x, y, size * d, cy + rnd.uniform(-1, 1) * size * 0.14, size * rnd.uniform(0.006, 0.02)))
    if extra:
        arr = extra(arr, x, y, size, rnd)
    return _paint(arr, 0.8, size)


# (the streaks: "make like 10 to 20 new ones", "like the streak", 2026-11-03)
def _tadpole_drip(arr, x, y, size, rnd):
    return np.maximum(arr, _disc(x, y, size * 0.86, size * 0.5, size * 0.035))


def _triple(arr, x, y, size, rnd):
    for dy, dx, ln in ((-0.15, 0.08, 0.28), (0.0, 0.0, 0.34), (0.16, 0.12, 0.25)):
        cy = size * (0.5 + dy)
        for k in range(40):
            t = k / 39.0
            px = size * (0.2 + dx) + t * ln * size
            arr = np.maximum(arr, _disc(x, y, px, cy, max(0.8, size * 0.045 * (1 - t) ** 1.2 + 0.6)))
        arr = np.maximum(arr, _disc(x, y, size * (0.2 + dx), cy, size * 0.06))
    return arr


STREAKS = [
    dict(seed=1, L=0.72, w=0.06, taper=1.0, head=0.09, sats=6),                                   # long and thin
    dict(seed=2, L=0.38, w=0.13, taper=1.6, head=0.15, sats=4),                                   # short and fat
    dict(seed=3, L=0.66, w=0.08, amp=0.10, freq=0.5, head=0.11),                                  # curved
    dict(seed=4, L=0.70, w=0.06, amp=0.035, freq=2.5, head=0.10),                                 # wavy
    dict(seed=5, L=0.62, w=0.06, head=0.0, strands=[(-0.06, 0.0), (0.06, 0.02)], sats=5,
         extra=lambda a, x, y, s, r: np.maximum(a, _disc(x, y, s * 0.2, s * 0.5, s * 0.11, 1.0, 1.4))),  # twin
    dict(seed=6, L=0.55, w=0.05, head=0.12, strands=[(0.0, -0.26), (0.0, 0.0), (0.0, 0.26)], sats=4),  # fan of three
    dict(seed=7, L=0.68, w=0.08, head=0.11, fork=(0.42, 0.2)),                                    # forked
    dict(seed=8, L=0.70, w=0.05, head=0.10, beads=6),                                             # beaded
    dict(seed=9, L=0.50, w=0.10, head=0.17, sats=14),                                             # big splashed head
    dict(seed=10, L=0.75, w=0.08, head=0.11, dots_from=0.55),                                     # breaks into dots
    dict(seed=11, L=0.65, w=0.07, head=0.11, spikes=6),                                           # side spikes
    dict(seed=12, L=0.78, w=0.025, taper=0.6, head=0.06, sats=3),                                 # hairline
    dict(seed=13, L=0.60, w=0.16, taper=0.8, head=0.0, smear=True, sats=2),                       # brush smear
    dict(seed=14, L=0.70, w=0.07, amp=0.07, freq=1.0, head=0.10),                                 # S-curve
    dict(seed=15, L=0.0, w=0.0, head=0.0, sats=3, extra=_triple),                                 # three short ones
    dict(seed=16, L=0.35, w=0.10, taper=1.8, head=0.14, sats=2, extra=_tadpole_drip),             # tadpole and drip
]


def splat_atlas(tex_dir):
    """the splats, four across, eight down (gore.lua M.SPLATS, in order): 1 impact, 2 pool, 3 streak, 4 super tiny, then
    the 16 other streaks (STREAKS) - "can you make 4 different types of blood spatter?", "like streak, and pool and super
    tiny", "make like 10 to 20 new ones", "like the streak", 2026-11-03"""
    cell = 256
    out = Image.new('RGBA', (cell * 4, cell * 8), (0, 0, 0, 0))
    imgs = [splat(128).resize((cell, cell), Image.LANCZOS), splat_pool(cell), splat_streak(cell), splat_tiny(cell)]
    imgs += [streak_var(cell, **kw) for kw in STREAKS]
    for i, im in enumerate(imgs):
        # (a margin round each, so they do not bleed into each other when drawn small)
        im = im.resize((int(cell * 0.92), int(cell * 0.92)), Image.LANCZOS)
        out.alpha_composite(im, ((i % 4) * cell + int(cell * 0.04), (i // 4) * cell + int(cell * 0.04)))
    out.save(os.path.join(tex_dir, 'gore_blood_splats.png'))
    print('splats:', len(imgs))


def main(tex_dir):
    drop().save(os.path.join(tex_dir, 'gore_blood_drop.png'))
    wound().save(os.path.join(tex_dir, 'gore_blood_cut.png'))
    pool().save(os.path.join(tex_dir, 'gore_blood_pool.png'))
    splat().save(os.path.join(tex_dir, 'gore_blood_splat.png'))
    splat_atlas(tex_dir)
    print('wrote gore_blood_drop, gore_blood_cut, gore_blood_pool, gore_blood_splat')


if __name__ == '__main__':
    main(sys.argv[1])
