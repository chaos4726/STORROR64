"""Writes a line of text in Mario 64's HUD font (the mod's hud_*.png letters, from the ROM) to a PNG with a see-through
background. Letters advance 12 pixels as Mario 64's print_text does, a space 8; '!' is made from the 'I' (the HUD font
has none). Usage: python -P tools/sm64_text.py "15 MAIN COURSES!" out.png [scale]"""
import sys
from PIL import Image

TEX = "E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/textures/"
NAMES = {"'": "apos", '"': "quote", "/": "slash", "*": "star", "x": "x", "X": "x"}
ADV, SPACE = 12, 8


def pinch(img, rows, most):
    """each row in `rows` its left half moved right and its right half left, more toward the last row (up to `most`)"""
    out = img.copy()
    a, b = rows[0], rows[-1]
    for y in rows:
        k = int(round(most * (y - a) / max(1, b - a)))
        if k == 0:
            continue
        line = [img.getpixel((x, y)) for x in range(16)]
        for x in range(16):
            out.putpixel((x, y), (0, 0, 0, 0))
        for x in range(16):
            p = line[x]
            if p[3] == 0:
                continue
            nx = x + k if x <= 7 else x - k
            if 0 <= nx < 16:
                q = out.getpixel((nx, y))
                if q[3] == 0 or x <= 7:
                    out.putpixel((nx, y), p)
    return out


def glyph(c):
    # (letters the HUD font has none of, made from its own: V the U pinched in toward its foot; J the U without its left
    # arm; Y the U's arms over the T's stem)
    if c in "VJY":
        u = Image.open(TEX + "hud_U.png").convert("RGBA")
        if c == "V":
            return pinch(u, list(range(3, 16)), 3)
        if c == "J":
            out = u.copy()
            for y in range(3, 10):
                for x in range(0, 7):
                    out.putpixel((x, y), (0, 0, 0, 0))
            return out
        t = Image.open(TEX + "hud_T.png").convert("RGBA")
        out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        out.paste(pinch(u, list(range(3, 13)), 2).crop((0, 3, 16, 12)), (0, 3))
        stem = t.crop((0, 11, 16, 16))
        # (the stem in the U's own colours: its pixels from the U's foot)
        for y in range(stem.height):
            for x in range(16):
                p = stem.getpixel((x, y))
                if p[3] > 0:
                    q = u.getpixel((min(15, max(0, x + 1)), 13))
                    if q[3] == 0:
                        q = u.getpixel((6, 13))
                    stem.putpixel((x, y), q[:3] + (p[3],))
        out.alpha_composite(stem, (1, 11))
        return out
    # (D: the B - its straight back - with its two bumps made one round side, and its two holes one)
    if c == "D":
        b = Image.open(TEX + "hud_B.png").convert("RGBA")
        out = b.copy()
        for y in range(4, 12):
            xs = [x for x in range(16) if b.getpixel((x, y))[3] > 0]
            if not xs:
                continue
            right = b.getpixel((xs[-1], y))
            want = 11 if y == 4 else 12
            for x in range(xs[-1] + 1, want + 1):
                out.putpixel((x, y), right)
            for x in range(5, 8):
                out.putpixel((x, y), (0, 0, 0, 0))
        return out
    # (-: a short piece of the E's top bar, half way up)
    if c == "-":
        e = Image.open(TEX + "hud_E.png").convert("RGBA")
        out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        out.paste(e.crop((0, 3, 9, 6)), (1, 7))
        return out
    if c == "!":
        i = Image.open(TEX + "hud_I.png").convert("RGBA")
        out = Image.new("RGBA", i.size, (0, 0, 0, 0))
        out.paste(i.crop((0, 0, 16, 10)), (0, 0))         # the bar
        out.paste(i.crop((0, 12, 16, 15)), (0, 12))       # the dot
        return out
    name = NAMES.get(c, c.upper())
    return Image.open(TEX + "hud_%s.png" % name).convert("RGBA")


def main():
    text = sys.argv[1]
    out_path = sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    w = 0
    for c in text:
        w += SPACE if c == " " else ADV
    w += 16 - ADV
    img = Image.new("RGBA", (w, 16), (0, 0, 0, 0))
    x = 0
    for c in text:
        if c == " ":
            x += SPACE
            continue
        g = glyph(c)
        img.alpha_composite(g, (x, 0))
        x += ADV
    # (trimmed to the letters, a pixel's margin, then scaled up pixel for pixel)
    box = img.getbbox()
    if box:
        img = img.crop((max(0, box[0] - 1), max(0, box[1] - 1), min(img.width, box[2] + 1), min(img.height, box[3] + 1)))
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(out_path)
    print(out_path, img.size)


if __name__ == "__main__":
    main()
