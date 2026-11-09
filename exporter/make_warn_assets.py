"""Pictures for the file select's warning about the game modes (menu.lua M.confirm): its lines, in Mario 64's own menu
font (the decomp's main_menu_seg7_us font letters, each font pixel 6 across, white, as the file select's labels are), a
YES and a NO, and a dark panel for behind them - "we have to put a warning at the main menu for when a player has
different gamemodes selected on an already made file", 2026-11-03.

Usage: python make_warn_assets.py <mod textures dir> <mod data dir>"""
import sys, os, re
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

DECOMP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'r96_build', 'decomp', 'levels', 'menu')
SCALE = 6
GAP = 2 * 1
SPACE = 24

LINES = {
    # (the modes on, every mix of h HUMAN, i IRONMAN, f FIRST PERSON - "also firts person", 2026-11-03)
    'menu_w_on_h': "GORE MODE IS ON.",
    'menu_w_on_i': "IRONMAN MODE IS ON.",
    'menu_w_on_f': "FIRST PERSON IS ON.",
    'menu_w_on_hi': "GORE AND IRONMAN MODE ARE ON.",
    'menu_w_on_hf': "GORE MODE AND FIRST PERSON ARE ON.",
    'menu_w_on_if': "IRONMAN MODE AND FIRST PERSON ARE ON.",
    'menu_w_on_hif': "GORE, IRONMAN AND FIRST PERSON ARE ON.",
    'menu_w_later': "YOU CAN'T CHANGE THIS LATER.",
    'menu_w_match': "YOUR GAME MODES DON'T MATCH YOUR SAVE.",
    'menu_w_some': "SOME WILL NOT ACTIVATE.",
    'menu_w_sure': "ARE YOU SURE?",
    'menu_w_yes': "YES",
    'menu_w_no': "NO",
}
SYMBOL = {"'": 'apostrophe', '?': 'question', '.': 'period', ',': 'comma', '!': 'exclamation', '-': 'dash', ':': 'colon'}


def font_files():
    """char name -> its picture (the US one where the decomp has a US and an EU)"""
    src = open(os.path.join(DECOMP, 'leveldata.c'), encoding='utf-8', errors='replace').read()
    out = {}
    for m in re.finditer(r'texture_menu_font_char_(\w+)\[\]\s*=\s*\{(.*?)\};', src, re.S):
        name, body = m.group(1), m.group(2)
        incs = re.findall(r'"levels/menu/(main_menu_seg7[\w.]*?)\.inc\.c"', body)
        if not incs:
            continue
        us = [i for i in incs if '_us.' in i]
        pick = (us or incs)[0]
        if name not in out or '_us.' in pick:
            out[name] = os.path.join(DECOMP, pick + '.png')
    return out


def glyph(path, height=48):
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    ink = ((a[:, :, 3] > 128) & (a[:, :, 0] > 128)).astype(np.uint8) * 255
    mask = Image.fromarray(ink, 'L').resize((ink.shape[1] * SCALE, ink.shape[0] * SCALE), Image.NEAREST)
    mask = mask.filter(ImageFilter.BoxBlur(1))
    out = Image.new('RGBA', mask.size, (255, 255, 255, 0))
    out.putalpha(mask)
    bbox = mask.getbbox()
    if not bbox:
        return None
    return out.crop((bbox[0], 0, bbox[2], mask.size[1]))


def word(files, text):
    gl = []
    w = 0
    for ch in text:
        if ch == ' ':
            gl.append(None)
            w += SPACE
            continue
        key = SYMBOL.get(ch, ch)
        g = glyph(files[key]) if key in files else None
        if g is None:
            raise SystemExit('no letter for %r' % ch)
        gl.append(g)
        w += g.size[0] + GAP
    im = Image.new('RGBA', (w + 2, 48), (0, 0, 0, 0))
    x = 0
    for g in gl:
        if g is None:
            x += SPACE
            continue
        im.alpha_composite(g, (x, 0))
        x += g.size[0] + GAP
    return im


def panel(w=1024, h=384):
    """a dark panel, its corners rounded, a thin light edge"""
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((4, 4, w - 5, h - 5), radius=40, fill=(10, 12, 40, 235), outline=(230, 230, 255, 255), width=6)
    return im


def main(tex_dir, data_dir):
    files = font_files()
    sizes = {}
    for name, text in LINES.items():
        im = word(files, text)
        im.save(os.path.join(tex_dir, name + '.png'))
        sizes[name] = (im.size[0] / 1.5, im.size[1] / 1.5)
        print('wrote', name, im.size)
    pn = panel()
    pn.save(os.path.join(tex_dir, 'menu_w_panel.png'))
    sizes['menu_w_panel'] = (pn.size[0] / 1.0, pn.size[1] / 1.0)
    p = os.path.join(data_dir, 'menu_sizes.lua')
    s = open(p, encoding='utf-8').read()
    for name, (w, hh) in sizes.items():
        line = '  %s = { %.2f, %.2f },' % (name, w, hh)
        if re.search(r'^\s*%s\s*=' % re.escape(name), s, re.M):
            s = re.sub(r'^\s*%s\s*=.*$' % re.escape(name), line, s, flags=re.M)
        else:
            s = re.sub(r'\}\s*$', line + '\n}\n', s)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
    print('sizes written')


if __name__ == '__main__':
    main(*sys.argv[1:3])
