"""Mario 64's screen transitions as masks for the mod (segment2's transition textures, from the ROM): black where the
picture is opaque, see-through where it is not, 512 x 512. The star, circle and Bowser pictures are half shapes that
the game mirrors (render_textured_transition); Mario's head is whole. python irisx.py <decomp> <mod textures dir>"""
import os
import sys
from PIL import Image

d, out = sys.argv[1], sys.argv[2]
SRC = {'star': ('0F458', True), 'circle': ('0FC58', True), 'mario': ('10458', False), 'bowser': ('11458', True)}
for name, (off, half) in SRC.items():
    im = Image.open(os.path.join(d, 'textures', 'segment2', 'segment2.%s.ia8.png' % off)).convert('RGBA')
    if half:
        w, h = im.size
        full = Image.new('RGBA', (w * 2, h))
        full.paste(im.transpose(Image.FLIP_LEFT_RIGHT), (0, 0))
        full.paste(im, (w, 0))
        im = full
    w, h = im.size
    side = max(w, h)
    sq = Image.new('RGBA', (side, side), (255, 255, 255, 255))
    sq.paste(im, ((side - w) // 2, (side - h) // 2))
    a = sq.split()[3].resize((512, 512), Image.BICUBIC)
    mask = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    mask.putalpha(a)
    mask.save(os.path.join(out, 'iris_%s.png' % name))
    print('iris_%s.png' % name)
