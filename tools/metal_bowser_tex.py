# Metal Bowser (bowser_fight.lua M.metal_on: "when bowser lands on the final floor stage 3 turn bowser into metal bowser
# kinda like metal mario cap does", "also give him purple eyes", 2026-11-04).
#  metal_bowser.png: polished chrome that repeats seamlessly - silver, a bright band of sky and a dark one of the
#    ground in it as a chrome ball shows them, wavering, with Mario 64's metal picture's pink and blue in the bright -
#    to lie on his own faces' layout (Mario 64's own metal picture is a chrome ball, laid on by facing: on a layout it
#    showed as patches and black corners). bowser_fight slides it as the camera turns, for the shine to move.
#  bowser_eye_metal_0/1.png: his eye pictures - each the eye and the green skin round it - the skin that chrome, the
#    red of the eye purple, the white and the pupil kept. Classic (64x32, textures/) and RENDER 96 (512x256,
#    textures_r96/) alike.
# Pictures are read and written as the game shows them: c ** 2.2.  python -P tools/metal_bowser_tex.py <mod dir>
import sys, os, math
import numpy as np
from PIL import Image

mod = sys.argv[1]
T = 2.0 * math.pi


def load(path):
    a = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64) / 255.0
    return a[..., :3] ** (1 / 2.2), a[..., 3]


def save(path, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1) ** 2.2
    if alpha is None:
        Image.fromarray((rgb * 255).astype(np.uint8), 'RGB').save(path)
    else:
        Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), 'RGBA').save(path)


def chrome(W, H):
    y, x = np.mgrid[0:H, 0:W]
    u, v = x / W, y / H
    # the bands' height wavers gently across (a whole cycle: it repeats)
    ph = (v + 0.05 * np.sin(T * u) + 0.02 * np.sin(T * (2 * u + v) + 0.8)) % 1.0

    def bump(c, width):
        d = np.minimum(np.abs(ph - c), 1.0 - np.abs(ph - c))
        return np.exp(-(d / width) ** 2)
    # a chrome ball's run, top to bottom: bright sky, a darker line at the horizon, the ground a little darker, light again
    lum = 0.56 + 0.30 * bump(0.20, 0.16) - 0.24 * bump(0.48, 0.07) - 0.10 * bump(0.64, 0.14) + 0.14 * bump(0.86, 0.10)
    lum = np.clip(lum + 0.012 * np.sin(T * (u * 7 + v * 2)), 0.05, 1.0)
    base = np.stack([lum * 0.96, lum * 0.98, lum * 1.03], axis=2)
    # Mario 64's metal picture's colours in the light: a little pink in the sky band, a little blue lower down
    pink = bump(0.14, 0.07)[..., None] * np.array([0.12, -0.02, 0.07])
    blue = bump(0.80, 0.08)[..., None] * np.array([-0.05, 0.02, 0.12])
    hot = bump(0.21, 0.03)[..., None] * 0.15
    return np.clip(base + pink + blue + hot, 0, 1)


metal = chrome(256, 256)
save(os.path.join(mod, 'textures', 'metal_bowser.png'), metal)


def metal_eye(src, dst):
    rgb, alpha = load(src)
    h, w = rgb.shape[:2]
    m = chrome(w, h)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb.mean(axis=2)
    skin = np.clip((g - np.maximum(r, b)) * 4.0, 0, 1)
    red = np.clip((r - np.maximum(g, b)) * 3.0, 0, 1)
    ref = lum[skin > 0.5].mean() if (skin > 0.5).any() else 0.5
    shade = np.clip(lum / max(ref, 1e-3), 0.45, 1.3)[..., None]
    out = rgb * (1 - skin[..., None]) + (m * shade) * skin[..., None]
    purple = np.stack([r * 0.68, r * 0.18, np.clip(r * 1.15, 0, 1)], axis=2)
    out = out * (1 - red[..., None]) + purple * red[..., None]
    save(dst, out, alpha)


# his eyes purple the whole fight, the skin as it is ("also make his eye purple through the fight"); and the glow of
# them on the last floor: the purple alone, the rest black, for the material's emission ("on stage 3 make his eyes
# glow", 2026-11-04)
def purple_eye(src, dst, glow_dst):
    rgb, alpha = load(src)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    red = np.clip((r - np.maximum(g, b)) * 3.0, 0, 1)
    purple = np.stack([r * 0.68, r * 0.18, np.clip(r * 1.15, 0, 1)], axis=2)
    save(dst, rgb * (1 - red[..., None]) + purple * red[..., None], alpha)
    save(glow_dst, np.stack([red * 0.75, red * 0.25, red * 1.0], axis=2), alpha)


for k in (0, 1):
    name = 'actors__bowser__bowser_eye_left_%d.rgba16.png' % k
    for folder in ('textures', 'textures_r96'):
        src = os.path.join(mod, folder, name)
        if os.path.exists(src):
            metal_eye(src, os.path.join(mod, folder, 'bowser_eye_metal_%d.png' % k))
            purple_eye(src, os.path.join(mod, folder, 'bowser_eye_purple_%d.png' % k),
                       os.path.join(mod, folder, 'bowser_eye_glow_%d.png' % k))
# RENDER 96's Bowser has an eye of its own (actors__bowser__bowser_eye_left.rgba32, an eyeball - no skin round it): its
# iris purple, the veins a deeper purple; and the glow, the iris alone (a disc in the middle). As bowser_eye_r96_purple
# and _glow, in textures/ (the RENDER 96 model's metal eye is the purple one: chrome is on the face round it).
def r96_eye(src, dst, glow_dst):
    rgb, alpha = load(src)
    h, w = rgb.shape[:2]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    red = np.clip((r - np.maximum(g, b)) * 3.0, 0, 1)
    yy, xx = np.mgrid[0:h, 0:w]
    rr = np.hypot(xx - w / 2.0, yy - h / 2.0) / w
    iris = red * (rr < 0.14)
    vein = red * (rr >= 0.14)
    purple = np.stack([r * 0.68, r * 0.18, np.clip(r * 1.15, 0, 1)], axis=2)
    deep = np.stack([r * 0.45, r * 0.10, r * 0.80], axis=2)
    out = rgb * (1 - red[..., None]) + purple * iris[..., None] + deep * vein[..., None]
    save(dst, out, alpha)
    save(glow_dst, np.stack([iris * 0.75, iris * 0.25, iris * 1.0], axis=2), alpha)


src = os.path.join(mod, 'textures_r96', 'actors__bowser__bowser_eye_left.rgba32.png')
if os.path.exists(src):
    r96_eye(src, os.path.join(mod, 'textures', 'bowser_eye_r96_purple.png'),
            os.path.join(mod, 'textures', 'bowser_eye_r96_glow.png'))
print('ok')
