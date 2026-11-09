"""Pictures for the file select's HUMAN and IRONMAN buttons: their blocks (one of Mario 64's file-select blocks, its
colour taken out and given its own - deep red, and steel grey - with the mode's icon on it: menu_icon_human, a heart,
menu_icon_ironman, a skull) and their labels, set in the file select's lettering as make_copy_fp_assets.py sets FIRST
PERSON. The labels have no H or U: those two come straight from Mario 64's menu font in the decomp (the letters the
labels were cut from), grown the same 6 times.

Usage: python make_mode_assets.py <mod textures dir> <mod data dir>"""
import sys, os, re
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_copy_fp_assets as CF


# Mario 64's own file-select letters (the menu font, 8x8) the labels' letters were cut from, for the two they lack
FONT = {'H': '0B080', 'U': '0B3C0', 'G': '0B040'}
FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'r96_build', 'decomp', 'levels', 'menu')


def font_letter(ch, height):
    """Mario 64's menu-font letter `ch` as the cut letters are: white, each font pixel 6 across, edges softened by a
    pixel, cropped to its ink"""
    im = Image.open(os.path.join(FONT_DIR, 'main_menu_seg7_us.%s.ia8.png' % FONT[ch])).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    ink = ((a[:, :, 3] > 128) & (a[:, :, 0] > 128)).astype(np.uint8) * 255
    k = height // ink.shape[0]
    mask = Image.fromarray(ink, 'L').resize((ink.shape[1] * k, ink.shape[0] * k), Image.NEAREST)
    mask = mask.filter(ImageFilter.BoxBlur(1))
    out = Image.new('RGBA', mask.size, (255, 255, 255, 0))
    out.putalpha(mask)
    bbox = mask.getbbox()
    return out.crop((bbox[0], 0, bbox[2], mask.size[1]))


def block(tex_dir, src, tint, icon):
    """a file-select block in its own colour, the mode's icon on its face"""
    im = Image.open(os.path.join(tex_dir, src + '.png')).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    lum = (0.3 * a[:, :, 0] + 0.59 * a[:, :, 1] + 0.11 * a[:, :, 2]) / 255.0
    out = a.copy()
    for c in range(3):
        out[:, :, c] = np.clip(lum * tint[c] * 1.35, 0, 255)
    im = Image.fromarray(out.astype(np.uint8), 'RGBA')
    ic = Image.open(os.path.join(tex_dir, icon + '.png')).convert('RGBA')
    s = int(im.size[1] * 0.55)
    ic = ic.resize((s, s), Image.NEAREST)
    im.alpha_composite(ic, ((im.size[0] - s) // 2 + 4, (im.size[1] - s) // 2 - 6))
    return im


def main(tex_dir, data_dir):
    glyphs, gap, space = CF.letters(tex_dir)
    h = next(iter(glyphs.values())).size[1]
    for ch in ('H', 'U', 'G'):
        if ch not in glyphs:
            glyphs[ch] = font_letter(ch, h)
    sizes = {}
    for name, text in (('menu_t_human', 'GORE'), ('menu_t_ironman', 'IRONMAN')):   # (HUMAN MODE named GORE MODE: "rename human mode to gore mode", 2026-11-07)
        im = CF.word(glyphs, gap, space, text, height=h)
        im.save(os.path.join(tex_dir, name + '.png'))
        sizes[name] = (im.size[0] / 1.5, im.size[1] / 1.5)
        print('wrote', name, im.size)
    for name, tint, icon in (('menu_btn_human', (190, 30, 40), 'menu_icon_human'),
                             ('menu_btn_ironman', (150, 158, 172), 'menu_icon_ironman')):
        im = block(tex_dir, 'menu_btn_timer', tint, icon)
        im.save(os.path.join(tex_dir, name + '.png'))
        sizes[name] = (150.67, 112.67)
        print('wrote', name, im.size)
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
