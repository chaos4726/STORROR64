# r96_fire.py : the picture for RENDER 96's 3D fire (burn.lua fire3d - Render96 has no fire model: "need to also make a
# new fire 3d model, that ties to mario getting burned or running", 2026-10-31). Laid up each flame tongue: v 1 its foot,
# v 0 its tip - white-yellow at the foot, orange, red, and clear at the tip, with licks of flame running up it (u round
# it) so its edge flickers as the tongues turn. fire3d.png and its blue one (a burn by ice) into textures_r96.
import os, math
import numpy as np
from PIL import Image

OUT = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\textures_r96"
W, H = 64, 256
rng = np.random.default_rng(64)

def make(stops):
    v = np.linspace(0.0, 1.0, H)[:, None]                 # 0 tip .. 1 foot
    u = np.linspace(0.0, 1.0, W, endpoint=False)[None, :]
    # (licks: the clear part reaches down further between them)
    licks = 0.5 + 0.5 * np.sin(u * 2 * math.pi * 3 + 1.3 * np.sin(u * 2 * math.pi * 2))
    noise = np.repeat(rng.random((H // 8, W)), 8, axis=0)
    noise = (noise + np.roll(noise, 1, 1) + np.roll(noise, -1, 1)) / 3.0
    d = v + 0.18 * (licks - 0.5) + 0.08 * (noise - 0.5)
    d = np.clip(d, 0.0, 1.0)
    img = np.zeros((H, W, 4))
    ps = [s[0] for s in stops]
    for c in range(4):
        img[:, :, c] = np.interp(d, ps, [s[1][c] for s in stops])
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")

red = make([(0.0, (200, 20, 0, 0)), (0.18, (230, 50, 5, 40)), (0.38, (255, 100, 10, 170)), (0.6, (255, 165, 30, 225)),
            (0.82, (255, 220, 90, 245)), (1.0, (255, 250, 200, 255))])
blue = make([(0.0, (10, 40, 200, 0)), (0.18, (20, 70, 230, 40)), (0.38, (40, 120, 255, 170)), (0.6, (80, 170, 255, 225)),
             (0.82, (150, 215, 255, 245)), (1.0, (225, 245, 255, 255))])
red.save(os.path.join(OUT, "fire3d.png"))
blue.save(os.path.join(OUT, "fire3d_blue.png"))
print("made fire3d.png, fire3d_blue.png")
