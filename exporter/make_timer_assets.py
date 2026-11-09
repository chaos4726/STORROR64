"""Pictures for the file select's TIMER button and the speedrun timer on the HUD.

The file select's labels are pictures of words in Mario 64's menu lettering (SCORE, COPY, MARIO A, ...).
There is none that says TIMER, so one is put together from the letters of the ones there are: every letter
sits in a cell 34 pixels wide (6 of the game's pixels), a space takes 4 of the game's pixels. The button
itself is the green block SCORE had. The HUD's letters and marks for TIME 0'00"00 are the game's own, from
the player's copy (the decompilation's extracted textures), as its digits already are.

Also measures the inside of the file select's frame (menu_bg16.png), which the start film is shown in.

Usage: python make_timer_assets.py <mod textures dir> <mod data dir> <decomp dir>"""
import sys, os, re, shutil
import numpy as np
from PIL import Image

CELL, SPACE = 34.0, 34.0 * 4.0 / 6.0
SOURCES = {'menu_t_score': 'SCORE', 'menu_t_stereo': 'STEREO', 'menu_t_mario_A': 'MARIO A',
           'menu_msg_na': 'NOT AVAILABLE YET', 'menu_msg_erase': 'SELECT A FILE TO ERASE'}
HUD = {'T': '03A00', 'I': '02400', 'M': '02C00', 'E': '01C00', 'apos': '04800', 'quote': '04A00'}


def letters(tex_dir):
    """every letter the labels have, cut out: {letter: picture}"""
    out = {}
    for name, text in SOURCES.items():
        im = Image.open(os.path.join(tex_dir, name + '.png')).convert('RGBA')
        x = 0.0
        for ch in text:
            if ch == ' ':
                x += SPACE
                continue
            if ch not in out:
                out[ch] = im.crop((int(round(x)), 0, int(round(x)) + int(CELL), im.size[1]))
            x += CELL
    return out


def word(glyphs, text, height=48):
    width = sum(SPACE if ch == ' ' else CELL for ch in text)
    im = Image.new('RGBA', (int(round(width)), height), (0, 0, 0, 0))
    x = 0.0
    for ch in text:
        if ch == ' ':
            x += SPACE
            continue
        im.alpha_composite(glyphs[ch], (int(round(x)), 0))
        x += CELL
    return im


def box(tex_dir):
    """the inside of the frame, in pixels of menu_bg16.png: left, top, right, bottom"""
    a = np.asarray(Image.open(os.path.join(tex_dir, 'menu_bg16.png')).convert('RGB')).astype(np.int32)
    h, w, _ = a.shape

    def edge(line):
        # the inside starts where the last big step in colour is, coming in from the edge (within the first sixth)
        d = np.abs(np.diff(line, axis=0)).sum(axis=1)
        n = len(line) // 6
        return int(np.where(d[:n] > 60)[0].max()) + 1

    rows = [a[int(h * f)] for f in (0.3, 0.5, 0.7)]
    cols = [a[:, int(w * f)] for f in (0.3, 0.5, 0.7)]
    left = max(edge(r) for r in rows)
    right = w - max(edge(r[::-1]) for r in rows)
    top = max(edge(c) for c in cols)
    bottom = h - max(edge(c[::-1]) for c in cols)
    return (left, top, right, bottom), (w, h)


def main(tex_dir, data_dir, decomp):
    g = letters(tex_dir)
    sizes = {}
    for name, text in (('menu_t_timer_on', 'TIMER ON'), ('menu_t_timer_off', 'TIMER OFF'), ('menu_t_timer', 'TIMER')):
        im = word(g, text)
        im.save(os.path.join(tex_dir, name + '.png'))
        sizes[name] = (im.size[0] / 1.5, im.size[1] / 1.5)
        print('wrote', name, im.size)
    shutil.copy(os.path.join(tex_dir, 'menu_btn_score.png'), os.path.join(tex_dir, 'menu_btn_timer.png'))
    sizes['menu_btn_timer'] = (150.67, 112.67)
    for key, off in HUD.items():
        src = os.path.join(decomp, 'textures', 'segment2', 'segment2.%s.rgba16.png' % off)
        Image.open(src).convert('RGBA').save(os.path.join(tex_dir, 'hud_%s.png' % key))
        print('wrote hud_%s from %s' % (key, os.path.basename(src)))
    # the sizes the menu lays its pictures out by
    p = os.path.join(data_dir, 'menu_sizes.lua')
    s = open(p, encoding='utf-8').read()
    for name, (w, h) in sizes.items():
        if name + ' =' not in s:
            s = re.sub(r'\}\s*$', '  %s = { %.2f, %.2f },\n}\n' % (name, w, h), s)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
    b, size = box(tex_dir)
    print('inside of the frame: left %d top %d right %d bottom %d of %dx%d' % (b + size))
    print('  as shares: %.4f %.4f %.4f %.4f; shape %.3f to 1' % (
        b[0] / size[0], b[1] / size[1], b[2] / size[0], b[3] / size[1], (b[2] - b[0]) / (b[3] - b[1])))


if __name__ == '__main__':
    main(*sys.argv[1:4])
