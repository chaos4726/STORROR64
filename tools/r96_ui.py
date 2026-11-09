# r96_ui.py : Render 96's HUD and menu pictures under the mod's own names. The mod's HUD pictures (hud_*, the power meter,
# ...) are Mario 64's own copied under names of the mod's (exporter/make_timer_assets.py, pausex.py, ...): each found again
# among the decomp's pictures by its pixels, and the Render 96 pack's picture of that name (r96_dl/pack: gfx/<path>)
# saved as textures_r96/<the mod's name>.png - lib.texture takes it with RENDER 96 on. ("and ui", 2026-10-31)
import os, hashlib
from PIL import Image
Image.MAX_IMAGE_PIXELS = 64_000_000

DECOMP = r"X:\mashup-work\sm64decomp"
PACK = r"X:\mashup-work\r96_dl\pack"
MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
TEX = os.path.join(MOD, "textures")
OUT = os.path.join(MOD, "textures_r96")
CAP = 256

def key(path):
    im = Image.open(path).convert("RGBA")
    return im.size, hashlib.sha1(im.tobytes()).hexdigest()

index = {}
for root in ("textures", "actors", "levels"):
    for dp, _, files in os.walk(os.path.join(DECOMP, root)):
        for f in files:
            if f.endswith(".png"):
                p = os.path.join(dp, f)
                try:
                    index.setdefault(key(p), os.path.relpath(p, DECOMP).replace("\\", "/"))
                except Exception:
                    pass
made, no_hd, unmatched = [], [], 0
for f in sorted(os.listdir(TEX)):
    name = f[:-4]
    if not f.endswith(".png") or "__" in name or name.startswith("sky_"):
        continue
    try:
        rel = index.get(key(os.path.join(TEX, f)))
    except Exception:
        continue
    if not rel:
        unmatched += 1
        continue
    hd = os.path.join(PACK, *rel.split("/"))
    if not os.path.exists(hd):
        no_hd.append(name)
        continue
    im = Image.open(hd).convert("RGBA")
    k = min(1.0, CAP / max(im.size))
    if k < 1.0:
        im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"))
    made.append("%s<-%s" % (name, rel))
print("made", len(made), "| matched but no Render 96 picture", len(no_hd), "| not Mario 64's own", unmatched)
print(" ".join(m.split("<-")[0] for m in made))
print("no HD:", " ".join(no_hd[:40]))
