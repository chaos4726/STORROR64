"""SUPER STORROR 64: the picture for the opening. See logox.py for where the letters come from.

Usage: python make_logo.py <wordmark.png> <out.png>"""
import os, sys, math
import numpy as np
from PIL import Image
import logox as L

W, H, SS = 1920, 1080, 2            # the screen, and how many times finer it is drawn before being scaled down
WORD_WIDTH = 1130                   # the wordmark's width on the screen: the full width of SUPER 64
DROP = 85                           # the whole logo sits this much lower than the game puts it, to centre the new shape
WORD_TOP = 505 + DROP               # where the wordmark's top edge sits
WORD_X = 6                          # nudge sideways from the logo's own middle
DEPTH = 30                          # how far its wooden sides run below the face, in screen pixels


def main(word_path, out_path):
    tris, info, tex, ymid = L.build(None, None)
    keep, dropped = [], []
    for p in info:
        if len(p['tris']) <= 2 or p['x1'] - p['x0'] > 3000:
            continue                                    # the sheet behind the logo
        (dropped if p['y1'] < 450 else keep).append(p)  # the bottom row is the word MARIO
    print('kept', len(keep), 'letters (SUPER and 64), left out', len(dropped), '(MARIO)')

    c = L.Canvas(W * SS, H * SS, shift=(0.0, DROP * SS))
    for p in keep:
        for i in p['tris']:
            c.triangle(tris[i], tex)
    logo = c.image()

    # where the logo's letters sit on the screen, to hang the wordmark under them
    xs = [c.project(v[0], v[1], v[2])[0] for p in keep for i in p['tris'] for v in tris[i][:3]]
    mid = (min(xs) + max(xs)) / 2.0 / SS

    mask = L.wordmark(word_path, WORD_WIDTH * SS)       # white where the wordmark is
    mw, mh = mask.size
    x0, y0 = round((mid + WORD_X) * SS - mw / 2), WORD_TOP * SS
    out = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 255))
    word_xy = (x0, y0)

    # its sides: brushed steel, running down from the face. Fine streaks along the length of the word,
    # slow bright and dark reflections across it, a cool tint, and one bright line where the light catches
    # the edge below the face.
    rng = np.random.default_rng(64)
    th, tw = mh + DEPTH * SS, mw
    streak = rng.normal(0.0, 1.0, (th, 1)).repeat(tw, axis=1)
    grain = rng.normal(0.0, 1.0, (th, tw))
    k = 48 * SS
    grain = np.cumsum(grain, axis=1)
    grain = (grain[:, k:] - grain[:, :-k]) / np.sqrt(k)                 # smeared sideways: brushing
    grain = np.pad(grain, ((0, 0), (0, tw - grain.shape[1])), mode='wrap')
    xs = np.arange(tw)[None, :] / tw
    sheen = 0.16 * np.sin(xs * 2 * np.pi * 2.5 + 0.6) + 0.07 * np.sin(xs * 2 * np.pi * 7.0 + 2.1)
    steel = 0.60 + 0.045 * streak + 0.05 * grain + sheen
    tile = np.stack([steel * 0.93, steel * 0.97, steel * 1.04], -1)     # (r, g, b): a little blue in it
    side = Image.new('L', (mw, mh + DEPTH * SS), 0)
    shade = Image.new('L', (mw, mh + DEPTH * SS), 0)
    steps = DEPTH * SS
    for kk in range(steps, 0, -1):
        f = kk / steps
        lit = 0.80 - 0.50 * f + 0.55 * np.exp(-((f - 0.22) / 0.09) ** 2)   # darker with depth, one bright line
        side.paste(255, (0, kk), mask)
        shade.paste(int(round(255 * min(1.0, max(0.0, lit / 1.4)))), (0, kk), mask)
    lit = np.asarray(shade, np.float32)[..., None] / 255.0 * 1.4
    sides = Image.fromarray((np.clip(tile * lit, 0.0, 1.0) * 255).astype(np.uint8), 'RGB')
    out.paste(sides, (x0, y0), side)
    # its face: the wordmark as it is, white
    out.paste(Image.new('RGB', (mw, mh), (255, 255, 255)), (x0, y0), mask)
    out.alpha_composite(logo)
    final = out.convert('RGB').resize((W, H), Image.LANCZOS).convert('RGBA')

    # the two small pictures the game lays over the logo, where the game puts them on its 320x240 screen
    # (here 4.5 screen pixels to one of its own, in the middle 4:3 of a 16:9 screen)
    def n64(x, y):
        return round(240 + x * 4.5), round(H - y * 4.5)
    layers = os.path.dirname(out_path)
    copy = Image.open(os.path.join(layers, 'title_copyright.png')).convert('RGBA')
    x0, y0 = n64(96, 58)
    final.alpha_composite(copy.resize((round(128 * 4.5), round(16 * 4.5)), Image.BILINEAR), (x0, y0))
    tm = Image.open(os.path.join(L.INTRO, '3_tm.rgba16.png')).convert('RGB')
    tm_a = tm.convert('L')
    tm = Image.merge('RGBA', (*tm.split(), tm_a))                    # black is nothing, as on the game's black screen
    tm.save(os.path.join(layers, 'title_tm.png'))
    x0, y0 = n64(268, 196)
    final.alpha_composite(tm.resize((72, 72), Image.BILINEAR), (x0, y0 + DROP))
    final.convert('RGB').save(out_path)
    print('wrote', out_path, final.size)

    # the logo by itself, see-through round the letters, for the game to zoom
    alone = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    alone.paste(sides, (word_xy[0], word_xy[1]), side)
    alone.paste(Image.new('RGB', (mw, mh), (255, 255, 255)), word_xy, mask)
    alone.alpha_composite(logo)
    alone.resize((W, H), Image.LANCZOS).save(os.path.join(layers, 'title_logo.png'))
    print('wrote title_logo.png, title_tm.png')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
