# r96_build.py : the Render 96 HD texture pack (github.com/pokeheadroom/RENDER96-HD-TEXTURE-PACK, GPL-3.0 - credit the
# Render96 team) made into the mod's own pictures, for Settings > Graphics, RENDER 96 (lib.lua M.R96): textures_r96/,
# beside textures/, the same names. The pack's gfx/<a>/<b>/<c>.png is the mod's <a>__<b>__<c>. Made from it:
#   <name>.png        the HD picture at the original's shape, at most UP times the original and BASE_CAP on its long side
#                     (the pictures load without mipmaps: much larger and they shimmer off in the distance)
#   (no tiled copies: lib.lua draws the HD picture itself repeated - at its size the seam they hide is a hair; within
#   1024 the biggest surfaces' 16 and 32 repeats left no room for anything finer than Mario 64's)
#   <name>.clamp.png  the clamped copy (lib.lua M.CLAMP): the picture in the middle third of one three times its size, its
#                     edges drawn out over the rest
#   sky_<n>.png       the sky's band from the pack's skyboxes/<n>.rgba16.png (the same layout as the mod's), SKY_SIZE
# Run: python -P tools/r96_build.py <pack gfx folder>
import os, sys, re
from PIL import Image

PACK = sys.argv[1] if len(sys.argv) > 1 else r"X:\mashup-work\r96_dl\pack"
MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
TEX = os.path.join(MOD, "textures")
OUT = os.path.join(MOD, "textures_r96")
UP, BASE_CAP, TILE_CAP, SKY_SIZE = 8, 512, 1024, 2048
SKIES = {"bbh": "bbh", "bitdw": "bidw", "bitfs": "bitfs", "bits": "bits", "ccm": "ccm", "clouds": "clouds", "ssl": "ssl",
         "water": "water", "wdw": "wdw"}           # (cloud_floor: the pack's is another shape - left as it is)
Image.MAX_IMAGE_PIXELS = 64_000_000
os.makedirs(OUT, exist_ok=True)

pack = {}
for root, _, files in os.walk(PACK):
    for f in files:
        if f.lower().endswith(".png"):
            rel = os.path.relpath(os.path.join(root, f), PACK).replace("\\", "/")[:-4]
            pack[rel.replace("/", "__")] = os.path.join(root, f)

mod = [f[:-4] for f in os.listdir(TEX) if f.lower().endswith(".png")]
modset = set(mod)
tiles = {}
for name in mod:
    m = re.match(r"^(.*)\.x(\d+)$", name)
    if m:
        tiles[m.group(1)] = int(m.group(2))

def hd_at(name, w0, h0, cap):
    """the HD picture of `name` at the original's shape (w0 x h0), as large as UP and `cap` allow - or None"""
    src = Image.open(pack[name])
    src = src.convert("RGBA")
    k = min(UP, cap / max(w0, h0), src.size[0] / w0, src.size[1] / h0)
    if k <= 1.0:
        return None
    w, h = max(1, int(round(w0 * k))), max(1, int(round(h0 * k)))
    return src.resize((w, h), Image.LANCZOS)

def save(im, name):
    im.save(os.path.join(OUT, name + ".png"), optimize=False)

made = {"base": 0, "tiles": 0, "clamp": 0, "sky": 0}
for name in sorted(modset):
    if name not in pack:
        continue
    try:
        orig = Image.open(os.path.join(TEX, name + ".png"))
        w0, h0 = orig.size
        im = hd_at(name, w0, h0, BASE_CAP)
        if im is None:
            continue
        save(im, name)
        made["base"] += 1
        if name + ".clamp" in modset:
            w, h = im.size
            c = Image.new("RGBA", (w * 3, h * 3))
            c.paste(im, (w, h))
            # (its edges drawn out: rows up and down, then the columns - corners and all - out to the sides)
            top, bot = im.crop((0, 0, w, 1)), im.crop((0, h - 1, w, h))
            for y in range(h):
                c.paste(top, (w, y)); c.paste(bot, (w, 2 * h + y))
            left, right = c.crop((w, 0, w + 1, 3 * h)), c.crop((2 * w - 1, 0, 2 * w, 3 * h))
            for x in range(w):
                c.paste(left, (x, 0)); c.paste(right, (2 * w + x, 0))
            save(c, name + ".clamp")
            made["clamp"] += 1
    except Exception as e:
        print("skipped", name, e)

for pn, mn in SKIES.items():
    key = "textures__skyboxes__%s.rgba16" % pn
    if key in pack and ("sky_" + mn) in modset:
        im = Image.open(pack[key]).convert("RGB").resize((SKY_SIZE, SKY_SIZE), Image.LANCZOS)
        save(im, "sky_" + mn)
        made["sky"] += 1

size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
print("made", made, "in", OUT, "%.0f MB" % (size / 1e6))
