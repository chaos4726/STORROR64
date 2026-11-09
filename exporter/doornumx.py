#!/usr/bin/env python3
"""The star doors' messages with their number in: DIALOG_025..028 say "You need [%] more Stars" - Mario 64 puts the
stars still wanting there (interaction.c interact_door: the dialog's variable). One picture per page per number,
textures/dlg_<n>_<page>_<k>.png, k from 1 to the door's stars (3, 8, 30, 50); dialog.lua shows the one for k.
Usage: python doornumx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
src = open(os.path.join(here, 'dialogx.py'), encoding='utf-8').read()
cut = src.index('introx.dialog_text = dialog_text')
g = {'__file__': os.path.join(here, 'dialogx.py'), '__name__': 'dialogx_defs'}
exec(compile(src[:cut], 'dialogx.py', 'exec'), g)          # (its text reading and font, not its run over every message)
introx, font, TEXD, dialog_text = g['introx'], g['font'], g['TEXD'], g['dialog_text']

NEED = {25: 3, 26: 8, 27: 30, 28: 50}
n_made = 0
for n, need in NEED.items():
    name = 'DIALOG_%03d' % n
    for k in range(1, need + 1):
        def with_number(nm, k=k):
            d = dialog_text(nm)
            d['lines'] = [ln.replace('[%]', str(k)) for ln in d['lines']]
            return d
        introx.dialog_text = with_number
        pages = introx.dialog_pages(font, name)
        for i, page in enumerate(pages):
            box = page.getbbox()
            if box:
                page = page.crop(box)
            page.save(os.path.join(TEXD, 'dlg_%d_%d_%d.png' % (n, i + 1, k)))
            n_made += 1
print('star door pages with their numbers:', n_made)
