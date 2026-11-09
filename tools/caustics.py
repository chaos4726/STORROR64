"""caustics.py: RENDER 96's caustics picture (water96.lua - the net of light the water's ripples throw on the seabed,
"make it behave like real water", 2026-10-31). caustic96.png, 512 x 512, tiling: white, its alpha the light.
Made as real caustics are: light straight down through a rippled surface (a tiling height field - waves of whole
repeats across the picture), each ray bent by the slope where it crosses, and where the bent rays bunch up on the floor
the light is bright. (Thousands of rays per pixel thrown, wrapped round the edges, counted.)
python tools/caustics.py   (from X:/mashup-work)"""
import math
import numpy as np
from PIL import Image

OUT = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\textures_r96\caustic96.png"
S = 512                 # the picture
G = 2048                # rays a side
rng = np.random.default_rng(1996)

y, x = np.mgrid[0:G, 0:G] / G
gx = np.zeros((G, G))
gy = np.zeros((G, G))
for k in range(40):
    f = int(rng.integers(2, 9))
    a = rng.uniform(0, 2 * math.pi)
    kx, ky = int(round(f * math.cos(a))), int(round(f * math.sin(a)))
    if kx == 0 and ky == 0:
        continue
    amp = 1.0 / (math.hypot(kx, ky) ** 1.6)
    ph = rng.uniform(0, 2 * math.pi)
    c = np.cos(2 * math.pi * (kx * x + ky * y) + ph)
    gx += amp * c * 2 * math.pi * kx
    gy += amp * c * 2 * math.pi * ky
# (how far the rays bend: enough that they cross into sharp bright lines, not so far it is noise)
spread = 0.022 / np.std(np.hypot(gx, gy))
px = (x - spread * gx) % 1.0
py = (y - spread * gy) % 1.0
ix = np.floor(px * S).astype(np.int64) % S
iy = np.floor(py * S).astype(np.int64) % S
cnt = np.bincount((iy * S + ix).ravel(), minlength=S * S).reshape(S, S).astype(np.float64)
# (a little soft, wrapped)
f = np.fft.fftfreq(S) * S
fx, fy = np.meshgrid(f, f)
cnt = np.real(np.fft.ifft2(np.fft.fft2(cnt) * np.exp(-(fx * fx + fy * fy) / (2 * 42.0 ** 2))))
light = cnt / cnt.mean()
# (the evenly lit floor no light added: only the bunching over it, its brightest lines full)
light = np.clip((light - 1.0) / (np.percentile(light, 99.7) - 1.0), 0.0, 1.0) ** 0.8
rgba = np.zeros((S, S, 4))
rgba[..., 0:3] = 1.0
rgba[..., 3] = light
Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA").save(OUT)
print("caustic96: lit share %.2f, mean alpha %.3f" % ((light > 0.05).mean(), light.mean()))
prev = (np.stack([light, light, light], axis=2) * 255).astype(np.uint8)
Image.fromarray(np.tile(prev, (2, 2, 1))).resize((512, 512)).save(r"caustic_preview.png")
