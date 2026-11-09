#!/usr/bin/env python3
"""Every one of Mario 64's messages (text/us/dialogs.h), as the game's dialog box shows them, one picture per page:
textures/dlg_<n>_<page>.png (n the dialog's number, the picture cropped to the box), and data/dialogs.lua:
{ pages = { [n] = count }, boxes = { [n] = { x0, y0, x1, y1 } } } (the box on Mario 64's 320 x 240 screen).
Usage: python dialogx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import introx
from PIL import Image, ImageDraw
import sm64x as X

TEXD, DATA, D = introx.TEXD, introx.DATA, introx.D
os.makedirs(TEXD, exist_ok=True)
os.makedirs(DATA, exist_ok=True)
font = introx.Font()
t = open(os.path.join(D, 'text', 'us', 'dialogs.h'), encoding='utf-8').read()
# (the US text's own words are #defined (the #else side of VERSION_EU) and joined into the strings:
# _("... his " COMRADES " in ...") - read as C would)
plain = re.sub(r'#ifdef VERSION_EU.*?#else(.*?)#endif', lambda m: m.group(1), t, flags=re.S)
BS = '\\'
CONT = BS + '\n'                     # a backslash at a line's end: the string goes on


def c_strings(src):
    """the C string literals and macro names in `src`, joined as the compiler joins them"""
    out, i = '', 0
    src = src.replace(CONT, '')
    while i < len(src):
        ch = src[i]
        if ch == '"':
            j = i + 1
            while src[j] != '"':
                j += 2 if src[j] == BS else 1
            out += src[i + 1:j]
            i = j + 1
        elif ch.isalpha() or ch == '_':
            j = i
            while j < len(src) and (src[j].isalnum() or src[j] == '_'):
                j += 1
            out += MACROS.get(src[i:j], '')
            i = j
        else:
            i += 1
    return out


MACROS = {}
for m in re.finditer(r'#define (\w+) ("(?:.|' + re.escape(CONT) + r')*?")\s*\n', plain):
    MACROS[m.group(1)] = c_strings(m.group(2))


from dialog_overrides import OVERRIDES     # (messages reworded for the mashup, the user's asking)


def dialog_text(name):
    m = re.search(r'DEFINE_DIALOG\(%s,\s*\d+,\s*(\d+),\s*(\d+),\s*(\d+),\s*_\((.*?)\)\)' % name, plain, re.S)
    text = c_strings(m.group(4))
    lines = text.split(BS + 'n')
    lines = [ln.replace(BS + "'", "'").replace(BS + '"', '"') for ln in lines]
    n = int(name.split('_')[1])
    per = int(m.group(1))
    if n in OVERRIDES:
        o = OVERRIDES[n]
        lines = wrap_pages(o['pages'], per) if isinstance(o, dict) else list(o)
    return {'per_page': per, 'left': int(m.group(2)), 'top': int(m.group(3)), 'lines': lines}


LINE_MAX = 132          # (Mario 64 units: the box's inside, from the line's left)


def line_width(text):
    """how wide a line draws, Mario 64 units (drawn and measured: the font's own spacing)"""
    c = Image.new('RGBA', (400 * introx.K, 40 * introx.K), (0, 0, 0, 0))
    font.draw(c, 0, 20, text, (255, 255, 255))
    b = c.getbbox()
    return (b[2] / introx.K) if b else 0.0


def wrap_pages(pages, per):
    """a page of text each, wrapped into lines that fit the box and each page made up to the message's lines a page
    (a long one runs on over more pages)"""
    out = []
    for text in pages:
        lines = []
        for para in text.split(chr(10)):
            cur = ''
            for w in para.split():
                t = (cur + ' ' + w).strip()
                if cur and line_width(t) > LINE_MAX:
                    lines.append(cur)
                    cur = w
                else:
                    cur = t
            lines.append(cur)
        while len(lines) % per:
            lines.append('')
        out += lines
    return out


introx.dialog_text = dialog_text
out, skipped = {'pages': {}, 'boxes': {}, 'choices': {}}, []
# a choice's arrow (dl_draw_triangle: 8 by 8, pointing right), white as on the black box
tri = Image.new('RGBA', (8 * introx.K, 8 * introx.K), (0, 0, 0, 0))
ImageDraw.Draw(tri).polygon([(0, 0), (8 * introx.K - 1, 4 * introx.K), (0, 8 * introx.K - 1)], fill=(255, 255, 255, 255))
tri.save(os.path.join(TEXD, 'dlg_triangle.png'))
for m in re.finditer(r'DEFINE_DIALOG\((DIALOG_(\d+)),', plain):
    name, n = m.group(1), int(m.group(2))
    try:
        pages = introx.dialog_pages(font, name)
    except Exception as e:
        skipped.append((n, str(e)[:60]))
        continue
    for i, page in enumerate(pages):
        # (only the box: the rest of the 320 x 240 screen is see-through, and big)
        box = page.getbbox()
        if box:
            page = page.crop(box)
        page.save(os.path.join(TEXD, 'dlg_%d_%d.png' % (n, i + 1)))
        if i == 0:
            out['boxes'][n] = [b / introx.K for b in box] if box else [0, 0, 320, 240]
    out['pages'][n] = len(pages)
    if n in OVERRIDES:
        for ln in dialog_text(name)['lines']:
            if line_width(ln) > LINE_MAX + 4:
                print('!! too wide in', n, repr(ln), round(line_width(ln)))
    d = dialog_text(name)
    if '/' in d['lines'][-1]:
        # a question (create_dialog_box_with_response): on its last page the arrow by the first answer or the
        # second (render_dialog_triangle_choice, US: 9 and 9 + 56 from the box's left, on the last line), on Mario
        # 64's 320 x 240 screen; its top as dialog_pages sets the lines (4 lower than the game's own, as there)
        last = len(d['lines']) - (len(pages) - 1) * d['per_page']
        o = d['top'] + 2 - 16 * last
        out['choices'][n] = [d['left'] + 9, d['left'] + 9 + 56, 240 - (o + 8) + 4]
X.write_lua(os.path.join(DATA, 'dialogs.lua'), out)
print('dialogs:', len(out['pages']), 'skipped:', skipped)
print('DIALOG_000 first lines:', dialog_text('DIALOG_000')['lines'][9:12])
