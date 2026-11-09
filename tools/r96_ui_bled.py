# r96_ui_bled.py : Render 96 pictures for the mod's copies of Mario 64's whose see-through pixels were given their edge's
# colour (numtex.py and the like: the blended edge of a see-through picture went dark otherwise) - matched by what shows
# (the see-through pixels' colour left out), the Render 96 pack's picture bled the same way. And the numbers over a coin
# (envfx_num_N) made again from the Render 96 HUD digits as numtex.py makes them. ("some textures still missing",
# 2026-10-31)
import os, hashlib
from PIL import Image
import numpy as np
Image.MAX_IMAGE_PIXELS = 64_000_000

DECOMP = r"X:\mashup-work\sm64decomp"
PACK = r"X:\mashup-work\r96_dl\pack"
MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
TEX = os.path.join(MOD, "textures")
OUT = os.path.join(MOD, "textures_r96")
CAP = 256

def shown_key(im):
    a = np.array(im.convert("RGBA"))
    a[a[:, :, 3] == 0, :3] = 0
    return im.size, hashlib.sha1(a.tobytes()).hexdigest()

def bleed(im, rounds=8):
    """the see-through pixels given the colour of the shown ones beside them"""
    a = np.array(im.convert("RGBA")).astype(np.float32)
    known = a[:, :, 3] > 0
    for _ in range(rounds):
        if known.all():
            break
        acc = np.zeros(a.shape[:2] + (3,), np.float32)
        cnt = np.zeros(a.shape[:2], np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sk = np.roll(known, (dy, dx), (0, 1))
            sc = np.roll(a[:, :, :3], (dy, dx), (0, 1))
            acc += sc * sk[:, :, None]
            cnt += sk
        new = (~known) & (cnt > 0)
        a[new, :3] = acc[new] / cnt[new][:, None]
        known = known | new
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")

index = {}
for root in ("textures", "actors", "levels"):
    for dp, _, files in os.walk(os.path.join(DECOMP, root)):
        for f in files:
            if f.endswith(".png"):
                p = os.path.join(dp, f)
                try:
                    index.setdefault(shown_key(Image.open(p)), os.path.relpath(p, DECOMP).replace("\\", "/"))
                except Exception:
                    pass
have = set(f[:-4] for f in os.listdir(OUT))
made = []
for f in sorted(os.listdir(TEX)):
    name = f[:-4]
    if not f.endswith(".png") or name in have or "__" in name or name.startswith("envfx_num_"):
        continue
    try:
        im = Image.open(os.path.join(TEX, f))
    except Exception:
        continue
    rel = index.get(shown_key(im))
    if not rel:
        continue
    hd = os.path.join(PACK, *rel.split("/"))
    if not os.path.exists(hd):
        continue
    out = Image.open(hd).convert("RGBA")
    s = min(1.0, CAP / max(out.size))
    if s < 1.0:
        out = out.resize((max(1, int(out.size[0] * s)), max(1, int(out.size[1] * s))), Image.LANCZOS)
    bleed(out).save(os.path.join(OUT, name + ".png"))
    made.append(name)
# the numbers over a coin: the Render 96 HUD digit, bled (numtex.py)
for n in range(10):
    src = os.path.join(OUT, "hud_%d.png" % n)
    if os.path.exists(src):
        bleed(Image.open(src).convert("RGBA").resize((128, 128), Image.LANCZOS)).save(os.path.join(OUT, "envfx_num_%d.png" % n))
        made.append("envfx_num_%d" % n)
print("made", len(made), ":", " ".join(made))
