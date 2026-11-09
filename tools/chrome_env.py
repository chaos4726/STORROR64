# The Bowser run's custom chrome world: one environment, made here, painted twice -
#   run_chrome_sky.png   a panorama for the sky sphere (u round, v from straight up to straight down)
#   run_chrome_ball.png  the same seen in a chrome ball (sphere map, straight up its middle, straight down its rim) for the
#                        lava to reflect
# Under a sky going from `zen` overhead through `mid` to `low` near the horizon, a `hot` glow at the horizon, two side
# glows, ribbons of light, faint stars, a crisp horizon line and dark ground. Palettes below; the one asked for is
# written to the mod's textures/ and textures_r96/.
#   python chrome_env.py <mod folder> <palette>            write it
#   python chrome_env.py <mod folder> preview <out.png>    every palette side by side, nothing written
import sys, os
import numpy as np
from PIL import Image

PALETTES = {
    # (zen, mid, low, hot, warm glow, cool glow, ribbons x4, ground, ground sheen)
    "synthwave": dict(zen=(0.05, 0.04, 0.16), mid=(0.28, 0.14, 0.52), low=(0.78, 0.22, 0.62), hot=(1.00, 0.55, 0.45),
                      warm=(0.45, 0.18, 0.05), cool=(0.05, 0.25, 0.55),
                      ribbons=((0.55, 0.85, 1.0), (1.0, 0.75, 0.95), (0.9, 0.95, 1.0), (0.7, 0.6, 1.0)),
                      ground=(0.06, 0.04, 0.10), sheen=(0.45, 0.20, 0.50)),
    # (the same, darker: "make it darker", 2026-11-03)
    "synthwave_dark": dict(zen=(0.004, 0.004, 0.015), mid=(0.05, 0.02, 0.11), low=(0.22, 0.04, 0.17), hot=(0.42, 0.16, 0.16),
                           warm=(0.10, 0.03, 0.01), cool=(0.01, 0.04, 0.12),
                           ribbons=((0.22, 0.34, 0.48), (0.42, 0.26, 0.40), (0.32, 0.36, 0.46), (0.28, 0.22, 0.44)),
                           ground=(0.012, 0.008, 0.022), sheen=(0.12, 0.05, 0.15), line=0.55),
    "bowser_fire": dict(zen=(0.04, 0.01, 0.01), mid=(0.30, 0.04, 0.02), low=(0.85, 0.22, 0.03), hot=(1.00, 0.80, 0.35),
                        warm=(0.55, 0.25, 0.02), cool=(0.35, 0.05, 0.10),
                        ribbons=((1.0, 0.55, 0.15), (1.0, 0.85, 0.40), (1.0, 0.35, 0.10), (0.95, 0.70, 0.30)),
                        ground=(0.07, 0.02, 0.01), sheen=(0.60, 0.20, 0.05)),
    "classic_chrome": dict(zen=(0.20, 0.26, 0.36), mid=(0.52, 0.62, 0.76), low=(0.86, 0.90, 0.96), hot=(1.00, 1.00, 1.00),
                           warm=(0.20, 0.18, 0.14), cool=(0.10, 0.18, 0.30),
                           ribbons=((1.0, 1.0, 1.0), (0.85, 0.92, 1.0), (1.0, 1.0, 1.0), (0.80, 0.88, 1.0)),
                           ground=(0.10, 0.10, 0.12), sheen=(0.35, 0.38, 0.45)),
    "metal_mario": dict(zen=(0.03, 0.05, 0.16), mid=(0.12, 0.30, 0.72), low=(0.92, 0.35, 0.62), hot=(1.00, 0.92, 0.95),
                        warm=(0.50, 0.12, 0.30), cool=(0.05, 0.30, 0.70),
                        ribbons=((1.0, 1.0, 1.0), (1.0, 0.60, 0.85), (0.70, 0.90, 1.0), (1.0, 0.95, 0.60)),
                        ground=(0.04, 0.05, 0.12), sheen=(0.40, 0.30, 0.60)),
    "dark_world": dict(zen=(0.01, 0.05, 0.03), mid=(0.03, 0.30, 0.18), low=(0.15, 0.75, 0.45), hot=(0.80, 1.00, 0.85),
                       warm=(0.10, 0.35, 0.10), cool=(0.02, 0.25, 0.30),
                       ribbons=((0.60, 1.0, 0.80), (0.40, 0.95, 0.70), (0.85, 1.0, 0.90), (0.30, 0.80, 0.90)),
                       ground=(0.02, 0.05, 0.03), sheen=(0.15, 0.45, 0.25)),
}


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def env(dx, dy, dz, P):
    """Colour (r, g, b in 0..1) of directions (arrays), palette P."""
    el = np.arcsin(np.clip(dz, -1.0, 1.0))
    az = np.arctan2(dy, dx)
    e = np.degrees(el)
    up = smooth(-0.6, 0.8, e)
    k = np.clip(e / 90.0, 0.0, 1.0)
    C = lambda c: np.array(c)[None, None, :]
    zen, mid, low, hot = C(P["zen"]), C(P["mid"]), C(P["low"]), C(P["hot"])
    t = k[..., None]
    sky = np.where(t > 0.35, mid + (zen - mid) * smooth(0.35, 1.0, t), low + (mid - low) * smooth(0.04, 0.35, t))
    sky = sky + (hot - sky) * np.exp(-((e - 0.0) / 5.0) ** 2)[..., None] * 0.85
    w = 0.5 + 0.5 * np.cos(az - np.radians(40))
    lowg = np.exp(-((e - 3.0) / 9.0) ** 2)[..., None]
    sky = sky + lowg * (w[..., None] * C(P["warm"]) + (1 - w[..., None]) * C(P["cool"]))
    for (amp, freq, ph, el0, wid), col in zip(((9, 2, 0.3, 30, 1.6), (6, 3, 1.9, 46, 1.1), (12, 1, 4.0, 20, 2.2),
                                               (5, 4, 2.6, 62, 0.9)), P["ribbons"]):
        centre = el0 + amp * np.sin(freq * az + ph)
        band = np.exp(-((e - centre) / wid) ** 2) * (0.55 + 0.45 * np.sin(3 * az + ph * 2))
        sky = sky + band[..., None] * C(col) * 0.8
    rng = np.random.default_rng(7)
    st = rng.random(e.shape)
    stars = ((st > 0.9985) & (e > 25)).astype(float) * 0.9
    sky = sky + stars[..., None] * C((1.0, 1.0, 1.0))
    sky = sky + np.exp(-((e - 0.35) / 0.35) ** 2)[..., None] * C((1.0, 0.97, 0.95)) * P.get("line", 1.2)
    g = np.clip(-e / 90.0, 0.0, 1.0)[..., None]
    ground = C(P["ground"]) * (1 - g) ** 2 + C((0.008, 0.008, 0.012))
    ground = ground + np.exp(-((e + 2.0) / 2.5) ** 2)[..., None] * C(P["sheen"])
    col = sky * up[..., None] + ground * (1 - up[..., None])
    return np.clip(col, 0.0, 1.0)


def panorama(P, W=2048, H=1024):
    u = (np.arange(W) + 0.5) / W
    v = (np.arange(H) + 0.5) / H
    U, V = np.meshgrid(u, v)
    az = U * 2 * np.pi
    el = (0.5 - V) * np.pi
    return env(np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el), P)


def ball(P, N=1024):
    s = (np.arange(N) + 0.5) / N
    X, Y = np.meshgrid(s * 2 - 1, (0.5 - s) * 2)
    r2 = X * X + Y * Y
    nz = np.sqrt(np.clip(1 - r2, 0.0, 1.0))
    Rx, Ry, Rz = 2 * nz * X, 2 * nz * Y, 2 * nz * nz - 1
    L = np.sqrt(Rx * Rx + Ry * Ry + Rz * Rz) + 1e-9
    img = env(Rx / L, Ry / L, Rz / L, P)
    img[r2 > 1.0] = env(np.zeros(1)[None], np.zeros(1)[None], -np.ones(1)[None], P)[0, 0]
    return img


def to_img(a, linear=False):
    # (the game reads a picture loaded from a file as linear: written as such - its colours to the power 2.2 - it shows
    # as made; written as they are, every dark tone came out pale, "make it darker", 2026-11-03)
    if linear:
        a = np.power(np.clip(a, 0.0, 1.0), 2.2)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGB')


mod = sys.argv[1]
if sys.argv[2] == "preview":
    rows = []
    for name, P in PALETTES.items():
        rows.append((name, to_img(panorama(P, 768, 256)).crop((0, 0, 768, 160)), to_img(ball(P, 160))))
    out = Image.new('RGB', (768 + 170, 170 * len(rows)), (30, 30, 30))
    for i, (name, pano, b) in enumerate(rows):
        out.paste(pano, (0, i * 170))
        out.paste(b, (778, i * 170))
    out.save(sys.argv[3])
    print('preview', list(PALETTES))
else:
    P = PALETTES[sys.argv[2]]
    for d in ('textures', 'textures_r96'):
        to_img(panorama(P), True).save(os.path.join(mod, d, 'run_chrome_sky.png'))
        to_img(ball(P), True).save(os.path.join(mod, d, 'run_chrome_ball.png'))
    print('written', sys.argv[2])
