# r96_ui_stacked.py : Render 96 pictures for the mod's pictures stacked from several of Mario 64's - the castle's
# paintings (sm64scenes.py: a painting's pictures one over the other, its last on top). Each picture of the mod's not yet
# in textures_r96/: cut into 2, 3 or 4 strips across, each strip found among the decomp's pictures by its pixels, and the
# Render 96 pack's pictures of those names stacked the same way. ("some textures still missing", 2026-10-31)
import os, hashlib
from PIL import Image
Image.MAX_IMAGE_PIXELS = 64_000_000

DECOMP = r"X:\mashup-work\sm64decomp"
PACK = r"X:\mashup-work\r96_dl\pack"
MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
TEX = os.path.join(MOD, "textures")
OUT = os.path.join(MOD, "textures_r96")
CAP = 512

def key(im):
    im = im.convert("RGBA")
    return im.size, hashlib.sha1(im.tobytes()).hexdigest()

index = {}
for root in ("textures", "actors", "levels"):
    for dp, _, files in os.walk(os.path.join(DECOMP, root)):
        for f in files:
            if f.endswith(".png"):
                p = os.path.join(dp, f)
                try:
                    index.setdefault(key(Image.open(p)), os.path.relpath(p, DECOMP).replace("\\", "/"))
                except Exception:
                    pass
have = set(f[:-4] for f in os.listdir(OUT))
made = []
for f in sorted(os.listdir(TEX)):
    name = f[:-4]
    if not f.endswith(".png") or name in have or "__" in name:
        continue
    try:
        im = Image.open(os.path.join(TEX, f)).convert("RGBA")
    except Exception:
        continue
    w, h = im.size
    for k in (2, 3, 4):
        if h % k:
            continue
        sh = h // k
        rels = [index.get(key(im.crop((0, i * sh, w, (i + 1) * sh)))) for i in range(k)]
        if not all(rels):
            continue
        hds = [os.path.join(PACK, *r.split("/")) for r in rels]
        if not all(os.path.exists(p) for p in hds):
            continue
        parts = [Image.open(p).convert("RGBA") for p in hds]
        pw = parts[0].size[0]
        parts = [p.resize((pw, int(round(p.size[1] * pw / p.size[0]))), Image.LANCZOS) if p.size[0] != pw else p for p in parts]
        canvas = Image.new("RGBA", (pw, sum(p.size[1] for p in parts)))
        y = 0
        for p in parts:
            canvas.paste(p, (0, y)); y += p.size[1]
        s = min(1.0, CAP / max(canvas.size))
        if s < 1.0:
            canvas = canvas.resize((max(1, int(canvas.size[0] * s)), max(1, int(canvas.size[1] * s))), Image.LANCZOS)
        canvas.save(os.path.join(OUT, name + ".png"))
        made.append("%s (%d strips)" % (name, k))
        break
print("made", len(made), ":", ", ".join(made))
