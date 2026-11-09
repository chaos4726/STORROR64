"""Pictures for the file select's COPY steps and its FIRST PERSON button (and the TIMER labels again).

The words are put together from the letters of the file select's own labels (Mario 64's menu lettering), the COPY
label and MARIO D giving the P, Y and D the others lack. Mario 64's menu letters are not all one width (M and N are
wider), so each letter is cut out where the empty columns between letters are, and the words are set with the
labels' own letter and word spacing. (make_timer_assets.py cut them in fixed 34-pixel cells, which clipped M and N
in TIMER ON; those labels are made again here.) The FIRST PERSON button is the block Mario 64's sound-mode switch
had. Mario 64's copy messages ("COPY IT TO WHERE?", "COPYING COMPLETED") need letters no label has, so they are
said with the ones there are.

Usage: python make_copy_fp_assets.py <mod textures dir> <mod data dir>"""
import sys, os, re, shutil
import numpy as np
from PIL import Image

SOURCES = {'menu_t_score': 'SCORE', 'menu_t_stereo': 'STEREO', 'menu_t_mario_A': 'MARIO A', 'menu_t_mario_D': 'MARIO D',
           'menu_msg_na': 'NOT AVAILABLE YET', 'menu_msg_erase': 'SELECT A FILE TO ERASE', 'menu_t_copy': 'COPY',
           'menu_t_erase': 'ERASE'}
WORDS = (('menu_t_fp', 'FIRST PERSON'), ('menu_t_fp_on', 'ON'), ('menu_t_fp_off', 'OFF'),
         ('menu_msg_copy', 'SELECT A FILE TO COPY'), ('menu_msg_copy_to', 'SELECT AN EMPTY FILE'),
         ('menu_msg_copied', 'FILE COPIED'),
         ('menu_t_timer_on', 'TIMER ON'), ('menu_t_timer_off', 'TIMER OFF'), ('menu_t_timer', 'TIMER'))


def runs(alpha):
    """(start, end) of each run of columns with any ink"""
    ink = alpha.max(axis=0) > 40
    out, start = [], None
    for x, on in enumerate(ink):
        if on and start is None:
            start = x
        elif not on and start is not None:
            out.append((start, x))
            start = None
    if start is not None:
        out.append((start, len(ink)))
    return out


def letters(tex_dir):
    """every letter the labels have, cut at the gaps: {letter: picture}, plus the gap between letters and a space"""
    glyphs, gaps, spaces, split_from = {}, [], [], set()
    for name, text in SOURCES.items():
        im = Image.open(os.path.join(tex_dir, name + '.png')).convert('RGBA')
        a = np.asarray(im)[:, :, 3]
        boxes = runs(a)
        chars = [c for c in text if c != ' ']
        # letters that touch (M and A in MARIO A) come out as one: the widest piece is split at its thinnest
        # column, near its middle, until the count is right
        ink = (a > 40).sum(axis=0)
        whole = set(boxes)
        while 0 < len(boxes) < len(chars):
            i = max(range(len(boxes)), key=lambda j: boxes[j][1] - boxes[j][0])
            x0, x1 = boxes[i]
            # (the pairs that touch are a wide letter, M or N at 34 columns, before a 32-column one: the cut
            # leaves the second letter its 32)
            cut = x1 - 32
            boxes[i:i + 1] = [(x0, cut), (cut, x1)]
        if len(boxes) != len(chars):
            print('  (%s: %d letters seen for %d, not used)' % (name, len(boxes), len(chars)))
            continue
        k = 0
        for i, ch in enumerate(text):
            if ch == ' ':
                continue
            x0, x1 = boxes[k]
            # (a letter cut out of a touching pair is only kept until a whole one turns up)
            if ch not in glyphs or (boxes[k] in whole and ch in split_from):
                glyphs[ch] = im.crop((x0, 0, x1, im.size[1]))
                if boxes[k] in whole:
                    split_from.discard(ch)
                else:
                    split_from.add(ch)
            if k > 0:
                gap = x0 - boxes[k - 1][1]
                (spaces if text[i - 1] == ' ' else gaps).append(gap)
            k += 1
    gap = int(np.median(gaps)) if gaps else 6
    space = int(np.median(spaces)) if spaces else 20
    print('letters:', ''.join(sorted(glyphs)), '| gap', gap, 'space', space)
    return glyphs, gap, space


def word(glyphs, gap, space, text, height=48):
    width = 0
    for i, ch in enumerate(text):
        if ch == ' ':
            continue
        if i > 0:
            width += space if text[i - 1] == ' ' else gap
        width += glyphs[ch].size[0]
    im = Image.new('RGBA', (width + 2, height), (0, 0, 0, 0))
    x = 1
    for i, ch in enumerate(text):
        if ch == ' ':
            continue
        if i > 0:
            x += space if text[i - 1] == ' ' else gap
        im.alpha_composite(glyphs[ch], (x, 0))
        x += glyphs[ch].size[0]
    return im


def main(tex_dir, data_dir):
    glyphs, gap, space = letters(tex_dir)
    sizes = {}
    for name, text in WORDS:
        im = word(glyphs, gap, space, text)
        im.save(os.path.join(tex_dir, name + '.png'))
        sizes[name] = (im.size[0] / 1.5, im.size[1] / 1.5)
        print('wrote', name, im.size)
    shutil.copy(os.path.join(tex_dir, 'menu_btn_stereo.png'), os.path.join(tex_dir, 'menu_btn_fp.png'))
    sizes['menu_btn_fp'] = (150.67, 112.67)
    p = os.path.join(data_dir, 'menu_sizes.lua')
    s = open(p, encoding='utf-8').read()
    for name, (w, h) in sizes.items():
        line = '  %s = { %.2f, %.2f },' % (name, w, h)
        if re.search(r'^\s*%s\s*=' % re.escape(name), s, re.M):
            s = re.sub(r'^\s*%s\s*=.*$' % re.escape(name), line, s, flags=re.M)
        else:
            s = re.sub(r'\}\s*$', line + '\n}\n', s)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
    print('sizes written')


if __name__ == '__main__':
    main(*sys.argv[1:3])
