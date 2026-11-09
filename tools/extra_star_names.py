"""The extra stars' names on the star select (2026-10-27: "you didn't add a new star, also we have to name these
stars"), drawn in the game's font as exporter/starselx.py draws the acts': textures/starsel_act_<course>_<act>.png, and
the number over the star, starsel_num_<act>.png.

python tools/extra_star_names.py <SM64Map mod dir> <course number> <act> "<NAME>"
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exporter"))
import introx
from PIL import Image

MOD, course, act, name = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4].upper()
TEXD = os.path.join(MOD, "textures")
font, K = introx.Font(), introx.K


def text_picture(text, colour=(0, 0, 0)):
    """one line in the game's font, as tight as its letters (K pixels to one of the game's) - starselx.py's"""
    w = 0
    for code in font.encode(text):
        w += font.widths[code]
    canvas = Image.new("RGBA", (max(1, w) * K, 16 * K), (0, 0, 0, 0))
    font.draw(canvas, 0, 0, text, colour)
    return canvas


text_picture(name).save(os.path.join(TEXD, "starsel_act_%d_%d.png" % (course, act)))
text_picture(str(act)).save(os.path.join(TEXD, "starsel_num_%d.png" % act))
print("drawn:", "starsel_act_%d_%d.png" % (course, act), "starsel_num_%d.png" % act, repr(name))
