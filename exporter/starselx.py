#!/usr/bin/env python3
"""Mario 64's star select screen (src/menu/star_select.c), for the mod: the see-through star the screen shows for an
act not yet won (actor_transparent_star.lua), the courses' and acts' names as the game's font draws them in black
(textures/starsel_course_<n>.png, starsel_act_<n>_<i>.png, starsel_myscore.png, starsel_num_<i>.png), the wooden
COURSE plaque (textures/menu_course_plaque.png) and data/starselect.lua: each course's number, scene and acts.
Usage: python starselx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
import build_all as B
import introx
import sm64x as X

TEXD, DATA, D, K = introx.TEXD, introx.DATA, introx.D, introx.K
os.makedirs(TEXD, exist_ok=True)
os.makedirs(DATA, exist_ok=True)

# the see-through star
act = B.S.export_actor(B.db, 'transparent_star_geo', [], B.textures)
X.write_lua(os.path.join(DATA, 'actor_transparent_star.lua'), act)
print('textures copied:', X.copy_textures(B.textures, TEXD))

font = introx.Font()


def text_picture(text, colour=(0, 0, 0)):
    """one line in the game's font, as tight as its letters (K pixels to one of the game's)"""
    w = 0
    for code in font.encode(text):
        w += font.widths[code]
    canvas = Image.new('RGBA', (max(1, w) * K, 16 * K), (0, 0, 0, 0))
    font.draw(canvas, 0, 0, text, colour)
    return canvas


# the course and act names (text/us/courses.h), courses 1 to 15
SCENES = ['bob', 'wf', 'jrb', 'ccm', 'bbh', 'hmc', 'lll', 'ssl', 'ddd', 'sl', 'wdw', 'ttm', 'thi', 'ttc', 'rr']
t = open(os.path.join(D, 'text', 'us', 'courses.h'), encoding='utf-8').read()
courses = {}
for n, m in enumerate(re.finditer(r'COURSE_ACTS\(\s*(\w+),\s*_\("(.*?)"\)\s*,(.*?)\)\s*\n', t, re.S)):
    if n >= len(SCENES):
        break
    name = m.group(2).strip()
    name = re.sub(r'^\d+\s+', '', name)            # (" 1 BOB-OMB BATTLEFIELD": the game prints it from its 4th letter)
    acts = re.findall(r'_\("(.*?)"\)', m.group(3))
    scene = SCENES[n]
    text_picture(name).save(os.path.join(TEXD, 'starsel_course_%d.png' % (n + 1)))
    for i, a in enumerate(acts[:6]):
        text_picture(a.strip()).save(os.path.join(TEXD, 'starsel_act_%d_%d.png' % (n + 1, i + 1)))
    courses[scene] = {'num': n + 1, 'name': name, 'acts': [a.strip() for a in acts[:6]]}
    print(n + 1, scene, name, len(acts))
text_picture('MY SCORE').save(os.path.join(TEXD, 'starsel_myscore.png'))
for i in range(1, 7):
    text_picture(str(i)).save(os.path.join(TEXD, 'starsel_num_%d.png' % i))

# the plaque: its two halves (levels/menu main_menu_seg7 0D1A8 upper, 0E1A8 lower, 64 x 32 each)
up = Image.open(os.path.join(D, 'levels', 'menu', 'main_menu_seg7.0D1A8.rgba16.png')).convert('RGBA')
lo = Image.open(os.path.join(D, 'levels', 'menu', 'main_menu_seg7.0E1A8.rgba16.png')).convert('RGBA')
plaque = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
plaque.paste(up, (0, 0))
plaque.paste(lo, (0, 32))
plaque.resize((256, 256), Image.BICUBIC).save(os.path.join(TEXD, 'menu_course_plaque.png'))

X.write_lua(os.path.join(DATA, 'starselect.lua'), {'courses': courses})
print('wrote', len(courses), 'courses')
