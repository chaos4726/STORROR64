# r96_redmetal.py : red metal for RENDER 96's big star doors (tools/r96_stardoor.py) - "bowser door should be some sort of
# red metal", "kinda looks like wood or something", 2026-10-31. Render96's own metal door plate (door_metal: panels,
# rivets, wear) taken to its light and dark and laid in red: dark crimson in its shadows, bright red on its faces, its
# highest lights near white. stardoor_red_metal.png into textures_r96.
import numpy as np
from PIL import Image
SRC = r"X:\mashup-work\r96_dl\models\x\Render96\actors\door\door_metal.rgba32.png"
OUT = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\textures_r96\stardoor_red_metal.png"
a = np.asarray(Image.open(SRC).convert("RGB").resize((256, 512), Image.LANCZOS)).astype(float) / 255.0
l = 0.3 * a[:, :, 0] + 0.59 * a[:, :, 1] + 0.11 * a[:, :, 2]
l = (l - l.min()) / max(1e-6, l.max() - l.min())          # (its full range)
hi = np.clip((l - 0.75) / 0.25, 0.0, 1.0) ** 2              # (its highest lights)
r = np.clip(0.18 + 1.0 * l, 0, 1)
g = np.clip(0.02 + 0.22 * l ** 1.6 + 0.6 * hi, 0, 1)
b = np.clip(0.02 + 0.18 * l ** 1.6 + 0.55 * hi, 0, 1)
out = np.stack([r, g, b, np.ones_like(r)], axis=2)
Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(OUT)
print("made", OUT)
