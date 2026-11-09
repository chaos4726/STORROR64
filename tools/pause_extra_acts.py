"""The courses' extra stars' names on Mario 64's pause screen (exporter/pausex.py draws the acts'): textures/
pause_t_act_<course>_<act>.png, in the pause screen's own white lettering, and each one's width put into
data/pause.lua's widths. The names are game.lua's G.EXTRA_STARS ones (the race against each course's ghost): "in mario
64 menu the 7th star name doesnt show correclty please fix for all levels", 2026-11-05.

python -P tools/pause_extra_acts.py <SM64Map mod dir>    (SM64_DECOMP set, as for the exporter)
"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exporter"))
import introx
from PIL import Image

MOD = sys.argv[1]
TEXD, DATA = os.path.join(MOD, "textures"), os.path.join(MOD, "Scripts", "data")
K = 4
font = introx.Font()

# the courses' numbers, as data/pause.lua has them
pause_src = open(os.path.join(DATA, "pause.lua"), encoding="utf-8").read()
courses = dict((m.group(1), int(m.group(2))) for m in re.finditer(r"^\s+([a-z0-9_]+) = (\d+),$", pause_src, re.M))
# the extra stars, as game.lua has them
game_src = open(os.path.join(MOD, "Scripts", "game.lua"), encoding="utf-8").read()
extra = re.findall(r'^\s+([a-z]+)\s*=\s*\{ act = (\d+), as = \d+, star = \d+, name = "([^"]+)" \},?$', game_src, re.M)


def text_picture(text):
    """one line in white, its first letter's cell at the left edge - pausex.py's"""
    codes = font.encode(text)
    adv = sum(font.widths[c] for c in codes)
    width = max(adv, (adv - font.widths[codes[-1]] + 8) if codes else 1)
    canvas = Image.new("RGBA", (max(1, width) * K, 16 * K), (0, 0, 0, 0))
    font.draw(canvas, 0, 0, text, (255, 255, 255))
    return canvas, adv


lines = []
for scene, act, name in extra:
    n = courses.get(scene)
    if not n:
        print("no course number for", scene)
        continue
    key = "act_%d_%s" % (n, act)
    im, adv = text_picture(name)
    im.save(os.path.join(TEXD, "pause_t_%s.png" % key))
    lines.append((key, adv, im.size[0] // K))
    print(key, adv, repr(name))

# into the widths table: each one's line replaced, or put in after the course's own acts
src = pause_src
for key, adv, w in lines:
    entry = "    %s = { %d, %d }," % (key, adv, w)
    pat = re.compile(r"^    %s = \{ \d+, \d+ \},$" % re.escape(key), re.M)
    if pat.search(src):
        src = pat.sub(entry, src)
    else:
        n = key.split("_")[1]
        last = None
        for m in re.finditer(r"^    act_%s_\d+ = \{ \d+, \d+ \},$" % n, src, re.M):
            last = m
        if not last:
            print("no acts of course", n, "in the widths")
            continue
        src = src[:last.end()] + "\n" + entry + src[last.end():]
open(os.path.join(DATA, "pause.lua"), "w", encoding="utf-8", newline="").write(src)
print("pause.lua: %d extra star names" % len(lines))
