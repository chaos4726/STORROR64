#!/usr/bin/env python3
"""The mod's pictures that are Mario 64's own under another name, or made from them by a rule - from the player's ROM.

  copies (texcopies.json): <mod name> <- <the decomp's extracted picture>, as they are
  the penguin's eye over his blue (G_CC_BLENDRGBA: "_blend"), the Snufit's eye over white
  the angry Wiggler's red segments (the yellow ones turned: hue -24/255, saturation x1.067), the Skeeter's teal eye
  "<name>.base.png": the Boos' eyes and mouths over white (enemies.lua: the base under the see-through face)
  "<name>.clamp.png": every texture lib.lua's M.CLAMP names, in the middle third of one three times the size, its edges
     drawn out (make_clamp.py) - and its ".clamp.base.png" where the base has one

Usage: texvariants.py <decomp dir> <mod dir>"""
import json, os, re, sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
D, MOD = sys.argv[1], sys.argv[2]
TEX = os.path.join(MOD, 'textures')
os.makedirs(TEX, exist_ok=True)


def rgba(path):
    return np.asarray(Image.open(path).convert('RGBA'))


def save(name, a):
    Image.fromarray(np.ascontiguousarray(a, dtype=np.uint8), 'RGBA').save(os.path.join(TEX, name))


def over(a, color):
    al = a[..., 3:4].astype(np.float64) / 255.0
    rgb = a[..., :3] * al + np.array(color, np.float64) * (1 - al)
    out = np.empty_like(a)
    out[..., :3] = np.clip(np.round(rgb), 0, 255)
    out[..., 3] = 255
    return out


def hsv_turn(a, dh=None, s_mul=None, hue=None, sat=None):
    im = Image.fromarray(np.ascontiguousarray(a[..., :3])).convert('HSV')
    h = np.asarray(im, np.float64).copy()
    if dh is not None:
        h[..., 0] = (h[..., 0] + dh) % 256
    if hue is not None:
        h[..., 0] = hue
    if s_mul is not None:
        h[..., 1] = np.clip(np.round(h[..., 1] * s_mul), 0, 255)
    if sat is not None:
        h[..., 1] = sat
    rgb = np.asarray(Image.fromarray(h.astype(np.uint8), 'HSV').convert('RGB'))
    out = a.copy()
    out[..., :3] = rgb
    return out


def clamp(a):
    h, w = a.shape[:2]
    return np.pad(a, ((h, h), (w, w), (0, 0)), mode='edge')


n = 0
for name, src in json.load(open(os.path.join(HERE, 'texcopies.json'), encoding='utf-8')).items():
    save(name, rgba(os.path.join(D, src)))
    n += 1
print('copies', n)

A = lambda p: rgba(os.path.join(D, p))
save('actors__penguin__penguin_eye_open_blend.rgba16.png', over(A('actors/penguin/penguin_eye_open.rgba16.png'), (9, 32, 137)))
save('actors__snufit__snufit_eye_blend.rgba16.png', over(A('actors/snufit/snufit_eye.rgba16.png'), (255, 255, 255)))
for side in ('left', 'right'):
    save('actors__wiggler__wiggler_segment_%s_side_red.rgba16.png' % side,
         hsv_turn(A('actors/wiggler/wiggler_segment_%s_side.rgba16.png' % side), dh=-24, s_mul=1.067))
save('actors__skeeter__skeeter_eye_body.rgba16.png', hsv_turn(A('actors/skeeter/skeeter_eye.rgba16.png'), hue=119, sat=255))
# the coins (actors/coin: intensity and alpha) in the colours the game draws them: yellow, red, blue
for pre, tint in (('', (1.0, 1.0, 0.0)), ('red_', (1.0, 0.0, 0.0)), ('blue_', (120 / 255.0, 120 / 255.0, 1.0))):
    for part in ('front', 'side', 'tilt_left', 'tilt_right'):
        la = np.asarray(Image.open(os.path.join(D, 'actors', 'coin', 'coin_%s.ia16.png' % part)).convert('LA'), np.float64)
        out = np.zeros(la.shape[:2] + (4,), np.uint8)
        for c in range(3):
            out[..., c] = np.clip(np.round(la[..., 0] * tint[c]), 0, 255)
        out[..., 3] = la[..., 1]
        save('coin_%s%s.png' % (pre, part), out)
# the metal cap's picture for the engine (caps.lua METAL_TEX): Mario 64's metal, toned by this curve (5-bit levels)
METAL = {0: 0, 8: 2, 16: 8, 24: 14, 32: 22, 41: 32, 49: 42, 57: 53, 65: 65, 74: 79, 82: 92, 90: 106, 98: 121, 106: 136,
         115: 154, 123: 170, 131: 187, 139: 205, 148: 225, 156: 244}
m = A('actors/mario/mario_metal.rgba16.png').copy()
lut = np.array([METAL.get(v, 255 if v > 156 else v) for v in range(256)], np.uint8)
m[..., :3] = lut[m[..., :3]]
save('metal_body_sm64.png', m)
# Mario 64's flame (actors/flame, eight frames of intensity and alpha) in one colour: flame_sm64_red/blue_<n> as the game
# tints it (burn.lua, bowser_fight.lua), and flame_orig_red/blue_<n> four times bigger and smooth (enemies.lua)
for k in range(8):
    la = np.asarray(Image.open(os.path.join(D, 'actors', 'flame', 'flame_%d.ia16.png' % k)).convert('LA'))
    big = np.asarray(Image.open(os.path.join(D, 'actors', 'flame', 'flame_%d.ia16.png' % k)).convert('LA')
                     .resize((la.shape[1] * 4, la.shape[0] * 4), Image.BICUBIC))
    for col, rgb, af in (('red', (255, 50, 0), 200 / 255.0), ('blue', (100, 100, 255), 1.0)):
        for name, src in (('flame_sm64_%s_%d.png', la), ('flame_orig_%s_%d.png', big)):
            out = np.zeros(src.shape[:2] + (4,), np.uint8)
            out[..., :3] = rgb
            out[..., 3] = np.clip(np.round(src[..., 1] * af), 0, 255)
            save(name % (col, k), out)
# (the Bullet Bill's eye and mouth over his dark blue, as the mod draws them - full-bright, its colours 1: the eye and
# mouth's own see-through parts were black holes in his face)
for part, color in (('eye', (19, 21, 62)), ('mouth', (15, 17, 51))):
    t = 'actors__bullet_bill__bullet_bill_%s.rgba16.png' % part
    save(t, over(rgba(os.path.join(TEX, t)), color))
BASE = ['actors__boo__boo_eyes.rgba16', 'actors__boo__boo_mouth.rgba16', 'actors__boo_castle__bbh_boo_eyes.rgba16',
        'actors__boo_castle__bbh_boo_mouth.rgba16']
for b in BASE:
    save(b + '.base.png', over(rgba(os.path.join(TEX, b + '.png')), (255, 255, 255)))

# the clamped ones: lib.lua's own list
lib = open(os.path.join(MOD, 'Scripts', 'lib.lua'), encoding='utf-8').read()
body = re.search(r'\nM\.CLAMP = \{(.*?)\n\}', lib, re.S).group(1)
names = re.findall(r'\["([^"]+)"\]\s*=\s*true', body)
# (and those other scripts add to it: lib.CLAMP["..."] = true - intro.lua's Peach)
for f in sorted(os.listdir(os.path.join(MOD, 'Scripts'))):
    if f.endswith('.lua'):
        t = open(os.path.join(MOD, 'Scripts', f), encoding='utf-8', errors='replace').read()
        for n in re.findall(r'lib\.CLAMP\["([^"]+)"\]\s*=\s*true', t):
            if n not in names:
                names.append(n)
made = 0
for t in names:
    p = os.path.join(TEX, t + '.png')
    if not os.path.exists(p):
        print('no', t)
        continue
    c = clamp(rgba(p))
    save(t + '.clamp.png', c)
    if t in BASE:
        save(t + '.clamp.base.png', over(c, (255, 255, 255)))
    made += 1
print('clamped', made, 'of', len(names))
