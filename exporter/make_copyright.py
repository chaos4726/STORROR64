"""The line under the logo, redone: the game's "(c)1996 Nintendo" is a 128x16 picture whose letters are
shaded in bands from top to bottom. This writes "(c)2026 Claude" the same size, shaded with the very
bands of the original (read from the player's copy), so it sits on the screen the way the original does.

Usage: python make_copyright.py <out.png>"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

D = os.environ.get('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
SRC = os.path.join(D, 'levels', 'intro', '2_copyright.rgba16.png')
W, H, UP = 128, 16, 8               # the picture's size, and how much finer the letters are drawn before scaling down
FONTS = 'C:/Windows/Fonts/'


def bands():
    """the colour of the lettering on each of the 16 rows of the original"""
    a = np.asarray(Image.open(SRC).convert('RGB'), np.float32)
    out = []
    for y in range(H):
        row = a[y]
        lum = row.max(axis=1)
        lit = row[lum >= max(40.0, lum.max() * 0.6)]
        out.append(lit.mean(axis=0) if len(lit) else np.zeros(3))
    return np.array(out)


def lettering():
    """coverage (0..1) of the text on the 128x16 grid"""
    big = Image.new('L', (W * UP, H * UP), 0)
    d = ImageDraw.Draw(big)
    size = round(18.6 * UP)
    thin, bold = ImageFont.truetype(FONTS + 'arial.ttf', size), ImageFont.truetype(FONTS + 'arialbd.ttf', size)
    parts = [('\u00a92026', thin), (' ', thin), ('Claude', bold)]
    total = sum(d.textlength(t, font=f) for t, f in parts)
    squeeze = min(1.0, (W - 3) * UP / total)             # narrow the letters a little if the line is too long
    layer = Image.new('L', (int(total) + 4 * UP, H * UP), 0)
    ld = ImageDraw.Draw(layer)
    x = 0.0
    for t, f in parts:
        # capitals and digits stand from row 1 to row 14, as the original's do
        ld.text((x, 14.6 * UP), t, font=f, fill=255, anchor='ls')
        x += ld.textlength(t, font=f)
    layer = layer.crop((0, 0, int(x) + UP, H * UP)).resize((int((x + UP) * squeeze), H * UP), Image.LANCZOS)
    big.paste(layer, ((W * UP - layer.width) // 2, 0))
    return np.asarray(big.resize((W, H), Image.LANCZOS), np.float32) / 255.0


def main(out_path):
    cov = lettering()
    col = bands()
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., :3] = col[:, None, :]
    rgba[..., 3] = np.clip(cov * 1.15, 0, 1) * 255.0
    Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(out_path)
    print('wrote', out_path)


if __name__ == '__main__':
    main(sys.argv[1])
