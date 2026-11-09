# r96_water.py : the pictures for RENDER 96's water (water96.lua - "I just want more realisitic water", 2026-10-31):
#   water96_normal.png  a ripple normal map that tiles: many small waves of whole repeats across it, every way, longer
#                       ones stronger (a sea's spectrum, roughly), its slopes as a tangent-space normal (x, y in R, G)
#   water96_tint.png    the water's colour, a little lighter and darker in the same ripples (so it is not one flat tint)
# into textures_r96.
import math
import numpy as np
from PIL import Image

OUT = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\textures_r96"
S = 512
rng = np.random.default_rng(96)
y, x = np.mgrid[0:S, 0:S] / S
h = np.zeros((S, S))
dhx = np.zeros((S, S))
dhy = np.zeros((S, S))
for k in range(90):
    # (a wave of whole repeats across the picture, so it tiles: its count across, any way)
    f = int(rng.integers(2, 26))
    a = rng.uniform(0, 2 * math.pi)
    kx, ky = int(round(f * math.cos(a))), int(round(f * math.sin(a)))
    if kx == 0 and ky == 0:
        continue
    amp = 1.0 / (math.hypot(kx, ky) ** 1.15)
    ph = rng.uniform(0, 2 * math.pi)
    arg = 2 * math.pi * (kx * x + ky * y) + ph
    # (sharper crests than a sine: a little of its square)
    s = np.sin(arg)
    c = np.cos(arg)
    h += amp * (s + 0.25 * s * s)
    dhx += amp * (1 + 0.5 * s) * c * 2 * math.pi * kx
    dhy += amp * (1 + 0.5 * s) * c * 2 * math.pi * ky
strength = 0.011
nx, ny, nz = -dhx * strength, -dhy * strength, np.ones_like(dhx)
l = np.sqrt(nx * nx + ny * ny + nz * nz)
nx, ny, nz = nx / l, ny / l, nz / l
img = np.stack([(nx * 0.5 + 0.5), (ny * 0.5 + 0.5), (nz * 0.5 + 0.5)], axis=2)
Image.fromarray((img * 255).round().astype(np.uint8), "RGB").save(OUT + r"\water96_normal.png")
print("normal: slope spread %.2f, nz min %.2f" % (np.std(nx), nz.min()))

hn = (h - h.min()) / (h.max() - h.min())
deep = np.array([0.10, 0.34, 0.40])
light = np.array([0.26, 0.55, 0.58])
t = deep[None, None, :] * (1 - hn[..., None]) + light[None, None, :] * hn[..., None]
Image.fromarray((t * 255).round().astype(np.uint8), "RGB").save(OUT + r"\water96_tint.png")
print("made water96_normal.png, water96_tint.png")

# ---- lava: dark crust plates (cells) with glowing cracks between them - lava96_base.png (its colour, lit) and
# lava96_glow.png (its light, the cracks and the thin crust near them) - "also for lava", 2026-10-31
L = 512
rng2 = np.random.default_rng(1996)
P = rng2.random((70, 2)) * L
yy, xx = np.mgrid[0:L, 0:L].astype(float)
d1 = np.full((L, L), 1e9)
d2 = np.full((L, L), 1e9)
for px_, py_ in P:
    for ox in (-L, 0, L):
        for oy in (-L, 0, L):
            d = np.hypot(xx - (px_ + ox), yy - (py_ + oy))
            d2 = np.where(d < d1, d1, np.minimum(d2, d))
            d1 = np.minimum(d1, d)
edge = d2 - d1                                   # (0 on a crack)
# (wobble the cracks with a little tiling noise)
nz_ = np.zeros((L, L))
for k in range(30):
    f = int(rng2.integers(3, 24)); a = rng2.uniform(0, 2 * math.pi)
    kx, ky = int(round(f * math.cos(a))), int(round(f * math.sin(a)))
    nz_ += np.sin(2 * math.pi * (kx * xx + ky * yy) / L + rng2.uniform(0, 6.3)) / max(1, math.hypot(kx, ky))
nz_ = (nz_ - nz_.min()) / (nz_.max() - nz_.min())
crack = np.clip(1.0 - (edge + 6.0 * (nz_ - 0.5)) / 9.0, 0, 1) ** 2.2
heat = np.clip(crack + 0.25 * np.clip(1.0 - d1 / 40.0, 0, 1) * 0 + 0.18 * (1 - nz_), 0, 1)
def ramp(t, stops):
    out = np.zeros(t.shape + (3,))
    ps = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, ps, [s[1][c] for s in stops])
    return out
glow = ramp(heat, [(0.0, (0, 0, 0)), (0.2, (40, 4, 0)), (0.45, (190, 35, 0)), (0.7, (255, 120, 10)), (1.0, (255, 230, 120))])
crust = ramp(nz_, [(0.0, (22, 17, 15)), (0.5, (45, 33, 28)), (1.0, (70, 52, 42))])
base = crust * (1 - crack[..., None]) + glow * crack[..., None]
Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").save(OUT + r"\lava96_base.png")
Image.fromarray(np.clip(glow, 0, 255).astype(np.uint8), "RGB").save(OUT + r"\lava96_glow.png")
print("made lava96_base.png, lava96_glow.png")
