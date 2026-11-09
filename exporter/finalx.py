"""The Final Bowser story's own words, drawn as the game draws its dialog box and its ending's lines
(bowser_fight.lua, ending.lua), in the game's own font:
  textures/bowser_dialog_final_<n>.png  his words as the final fight opens
  textures/bowser_beaten_final_<n>.png  his words beaten, floating in the wind under the last floor
  textures/ending_sub_story_<n>.png     Peach's lines changed for the story (ending.lua STORY_SUBS)
("also his beginning text needs to be ... you may have peach and your puny power star ...", "ending quote something like
The things I've done to acquire this star all for NOTHING ...", "peach say you saved me again and I baked another cake
for you mario", 2026-11-04.) Prints how many pages each has.
Usage: SM64_DECOMP=X:/mashup-work/sm64decomp SM64_OUT=<mod dir> python finalx.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import introx
from PIL import Image

K = introx.K
os.makedirs(introx.TEXD, exist_ok=True)
font = introx.Font()

# (a page each, wrapped to the box: the pages break where the sentences do)
INTRO = ["You may have Peach and your puny Power Star...",
         "...but I have found something MUCH greater in power than a pathetic Power Star!",
         "And there's nothing you can do to stop me now!",
         "I will take Peach back, and this will be your end..."]
BEATEN = ["The things I've done to acquire this star... all for NOTHING!",
          "And even after 30 years, I still can't beat you, Mario.",
          "I don't know when, but I WILL get you! Bwah ah ah ah!"]
SUBS = {1: "You saved me again!", 4: "And I baked another cake...", 7: "...for you, Mario!"}


def width(text):
    return sum(font.widths[c] for c in font.encode(text))


def wrap(text, limit):
    lines, cur = [], ""
    for word in text.split():
        t = word if not cur else cur + " " + word
        if width(t) <= limit:
            cur = t
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def box_pages(lines, per=5, left=30, top=200):
    """as introx.dialog_pages: the black see-through box, the lines in white, `per` to a page"""
    pages = []
    for first in range(0, len(lines), per):
        canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
        x0, y0 = left - 7, 240 - (top + 5)
        w, h = 130 * 1.1, 80 * (per / 5.0 + 0.1)
        box = Image.new('RGBA', (int(w * K), int(h * K)), (0, 0, 0, 150))
        canvas.alpha_composite(box, (int(x0 * K), int(y0 * K)))
        for n, line in enumerate(lines[first:first + per]):
            font.draw(canvas, left, 240 - (top - 2 - 16 * n), line, (255, 255, 255))
        pages.append(canvas)
    return pages


def subtitle(text):
    """as endingx.subtitle: white, centred on x 160, 227 from the top of the game's screen"""
    canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
    font.draw(canvas, 160 - width(text) / 2.0, 240 - 13 - 16, text, (255, 255, 255))
    return canvas


# the widest the game's own Sky dialog runs (DIALOG_093)
limit = max(width(l) for l in introx.dialog_text('DIALOG_093')['lines'])
for name, texts in (("bowser_dialog_final", INTRO), ("bowser_beaten_final", BEATEN)):
    for n, text in enumerate(texts):
        lines = wrap(text, limit)
        assert len(lines) <= 5, (text, lines)
        box_pages(lines)[0].save(os.path.join(introx.TEXD, "%s_%d.png" % (name, n + 1)))
        print(name, n + 1, " / ".join(lines))
    print(name, len(texts), "pages")
for n, text in SUBS.items():
    subtitle(text).save(os.path.join(introx.TEXD, "ending_sub_story_%d.png" % n))
print("ending_sub_story", sorted(SUBS))
