"""Mario 64's ending credits and closing picture, read out of the player's own copy of the game.

After the Grand Star, Mario 64 rolls its credits: twenty shots of the courses (level_update.c's sCreditsSequence:
the level and area, the act, where Mario stands and which way he faces, which corner the picture shrinks to),
each with the camera flying its own path (camera.c's credits splines, followed here frame by frame as the game
follows them) and the names lettered beside the picture; then the cake. This writes:

  data/ending.lua                 the shots: scene, act, the athlete's place and facing, the corner, and the camera
                                  (position and target, the scene's centimetres) for each of the 200 frames of each
  textures/ending_credits_N.png   the names of shot N, as the game letters them on its 320x240 screen
  textures/ending_cake.png        the closing picture (levels/ending/cake: 48 tiles in the ROM, put together)

Usage: python endingx.py   (SM64_DECOMP, SM64_OUT and SM64_ROM as for build_all.py)"""
import os, re, sys, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json
import sm64x as X
from introx import splines, move, ue, D, K, Font, src
import sm64scenes as S
from PIL import Image

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
ROM = os.environ.get('SM64_ROM', os.path.join(os.path.dirname(D.rstrip('/\\')), 'rom_us.z64'))

SHOW, PROGRESS, WARP = 61, 90, 200          # (US: TIMER_CREDITS_SHOW, _PROGRESS, _WARP)

# (the US game's credits: level_update.c, the VERSION_US branches)
NAMES = {
    1: ["1GAME DIRECTOR", "SHIGERU MIYAMOTO"],
    2: ["2ASSISTANT DIRECTORS", "YOSHIAKI KOIZUMI", "TAKASHI TEZUKA"],
    3: ["2SYSTEM PROGRAMMERS", "YASUNARI NISHIDA", "YOSHINORI TANIMOTO"],
    4: ["3PROGRAMMERS", "HAJIME YAJIMA", "DAIKI IWAMOTO", "TOSHIO IWAWAKI"],
    5: ["4CAMERA PROGRAMMER", "MARIO FACE PROGRAMMER", "TAKUMI KAWAGOE", "GILES GODDARD"],
    6: ["2COURSE DIRECTORS", "YOICHI YAMADA", "YASUHISA YAMAMURA"],
    7: ["2COURSE DESIGNERS", "KENTA USUI", "NAOKI MORI"],
    8: ["3COURSE DESIGNERS", "YOSHIKI HARUHANA", "MAKOTO MIYANAGA", "KATSUHIKO KANNO"],
    9: ["1SOUND COMPOSER", "KOJI KONDO"],
    10: ["4SOUND EFFECTS", "SOUND PROGRAMMER", "YOJI INAGAKI", "HIDEAKI SHIMIZU"],
    11: ["23-D ANIMATORS", "YOSHIAKI KOIZUMI", "SATORU TAKIZAWA"],
    12: ["1ADDITIONAL GRAPHICS", "MASANAO ARIMOTO"],
    13: ["3TECHNICAL SUPPORT", "TAKAO SAWANO", "HIROHITO YOSHIMOTO", "HIROTO YADA"],
    14: ["1TECHNICAL SUPPORT", "SGI N64 PROJECT STAFF"],
    15: ["2PROGRESS MANAGEMENT", "KIMIYOSHI FUKUI", "KEIZO KATO"],
    16: ["5SCREEN TEXT WRITER", "TRANSLATION", "LESLIE SWAN", "MINA AKINO", "HIRO YAMADA"],
    17: ["4MARIO VOICE", "PEACH VOICE", "CHARLES MARTINET", "LESLIE SWAN"],
    18: ["3SPECIAL THANKS TO", "EAD STAFF", "ALL NINTENDO PERSONNEL", "MARIO CLUB STAFF"],
    19: ["1PRODUCER", "SHIGERU MIYAMOTO"],
    20: ["1EXECUTIVE PRODUCER", "HIROSHI YAMAUCHI"],
}

# sCreditsSequence (the shots between the first and last castle-grounds entries): scene, its flags (act in the low
# three bits, 0x10 the picture to the right, 0x20 the picture down), Mario's facing (<< 8), Mario's place, path
SHOTS = [
    ('bob', 1, 117, (713, 3918, -3889), 'BoB'),
    ('wf', 50, 46, (347, 5376, 326), 'WF'),
    ('jrb', 18, 22, (3800, -4840, 2727), 'JRB'),
    ('ccm_2', 34, 25, (-5464, 6656, -6575), 'CCMSlide'),
    ('bbh', 1, 60, (257, 1922, 2580), 'BBH'),
    ('hmc', -15, 123, (-6469, 1616, -6054), 'HMC'),
    ('thi_3', 17, -32, (508, 1024, 1942), 'THIWiggler'),
    ('lll_2', 33, 124, (-73, 82, -1467), 'Volcano'),
    ('ssl', 65, 98, (-5906, 1024, -2576), 'SSL'),
    ('ddd', 50, 47, (-4884, -4607, -272), 'DDD'),
    ('sl', 17, -34, (1925, 3328, 563), 'SL'),
    ('wdw', 33, 105, (-537, 1850, 1818), 'WDW'),
    ('ttm', 2, -33, (2613, 313, 1074), 'TTM'),
    ('thi', 51, 54, (-2609, 512, 856), 'THIHuge'),
    ('ttc', 17, -72, (-1304, -71, -967), 'TTC'),
    ('rr', 33, 64, (1565, 1024, -148), 'RR'),
    ('sa', 1, 24, (-1050, -1330, -1559), 'SA'),
    ('cotmc', 49, -16, (-254, 415, -6045), 'CotMC'),
    ('ddd_2', -111, -64, (3948, 1185, -104), 'DDDSub'),
    ('ccm', 33, 31, (3169, -4607, 5240), 'CCMOutside'),
]


def copy_segment(src):
    """copy_spline_segment: the first point twice, the points up to the end mark, then the end point three times more
    and a new end mark; the rest of the game's 32-point table stays marked -1"""
    dst = [src[0]]
    j = 0
    while True:
        dst.append(src[j])
        j += 1
        if src[j][0] == -1:
            break
    end = src[j]
    dst += [(0, end[1], end[2]), (0, 0.0, end[2]), (0, 0.0, end[2]), (-1, 0.0, end[2])]
    return dst + [(-1, 0.0, end[2])] * (40 - len(dst))


def shot_camera(sp, name):
    """cutscene_credits: one segment counter for both paths, moved on by each (so twice a frame)"""
    pos_sp, foc_sp = sp['s%sCreditsSplinePositions' % name], sp['s%sCreditsSplineFocus' % name]
    pos_sp, foc_sp = copy_segment(pos_sp), copy_segment(foc_sp)
    seg, prog = 0, 0.0
    pos, foc = list(pos_sp[0][2]), list(foc_sp[0][2])
    out = []
    for f in range(WARP + 1):
        pos, seg, prog, _ = move(pos, pos_sp, seg, prog)
        foc, seg, prog, _ = move(foc, foc_sp, seg, prog)
        out.append((list(pos), list(foc)))
    return out


# ------------------------------------------------------------------ the credits lettering (8x8 RGBA pictures)
class CreditsFont:
    def __init__(self):
        t = open(os.path.join(D, 'bin', 'segment2.c'), encoding='utf-8', errors='replace').read()
        files = dict(re.findall(r'Texture (texture_credits_char_\w+)\[\]\s*=\s*\{\s*#include "([^"]+)\.inc\.c"', t))
        self.glyph = {}
        for sym, path in files.items():
            ch = sym[len('texture_credits_char_'):]
            ch = '.' if ch == 'period' else ch
            self.glyph[ch] = Image.open(os.path.join(D, path + '.png')).convert('RGBA')

    def width(self, s):
        return sum(4 if c == ' ' else 7 for c in s)

    def draw(self, canvas, x, y, s):
        for c in s.upper():
            g = self.glyph.get(c)
            if c == ' ' or g is None:
                x += 4 if c == ' ' else 7
                continue
            big = g.resize((8 * K, 8 * K), Image.NEAREST)
            canvas.alpha_composite(big, (int(x * K), int(y * K)))
            x += 7


def credits_page(font, lines, flags):
    """print_displaying_credits_entry, on a 320x240 screen"""
    canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
    title, rest = lines[0], list(lines[1:])
    n = int(title[0])
    title = title[1:]
    left, right = 28, 320 - 28
    y = (28 if flags & 0x20 else 172) + (16 if n == 1 else 0)
    font.draw(canvas, left, y, title)
    step = 16
    if n == 4:
        font.draw(canvas, left, y + 24, rest.pop(0))
        n, step = 2, 24
    elif n == 5:
        font.draw(canvas, left, y + 16, rest.pop(0))
        n = 3
    for s in rest[:n]:
        font.draw(canvas, right - font.width(s), y, s)
        y += step
    return canvas


# ------------------------------------------------------------------ the cake
def mio0(rom, o):
    assert rom[o:o + 4] == b"MIO0", hex(o)
    size, co, uo = struct.unpack(">III", rom[o + 4:o + 16])
    out = bytearray(); lp = o + 16; cp = o + co; up = o + uo; bits = 0; n = 0
    while len(out) < size:
        if n == 0:
            bits = struct.unpack(">I", rom[lp:lp + 4])[0]; lp += 4; n = 32
        if bits & 0x80000000:
            out.append(rom[up]); up += 1
        else:
            v = (rom[cp] << 8) | rom[cp + 1]; cp += 2
            ln = (v >> 12) + 3; off = (v & 0xFFF) + 1
            for _ in range(ln): out.append(out[-off])
        bits = (bits << 1) & 0xFFFFFFFF; n -= 1
    return bytes(out[:size])


def cake_picture():
    assets = json.load(open(os.path.join(D, 'assets.json')))
    size, where = assets['levels/ending/cake.png']
    seg, pos = where['us']
    data = mio0(open(ROM, 'rb').read(), seg)[pos:pos + size]
    W, H, SW, SH = 4, 12, 80, 20                # (skyconv's cake: 4x12 tiles of 80x20, each with a seam row/column)
    img = Image.new('RGBA', ((SW - 1) * W, (SH - 1) * H))
    px = img.load()
    k = 0
    for i in range(H):
        for j in range(W):
            tile = data[k:k + SW * SH * 2]; k += SW * SH * 2
            for y in range(SH - 1):
                for x in range(SW - 1):
                    v = (tile[(y * SW + x) * 2] << 8) | tile[(y * SW + x) * 2 + 1]
                    px[j * (SW - 1) + x, i * (SH - 1) + y] = ((v >> 11 & 31) * 255 // 31, (v >> 6 & 31) * 255 // 31, (v >> 1 & 31) * 255 // 31, 255)
    # (the game draws it over its whole 320x240 screen)
    return img.resize((320 * K, 240 * K), Image.BICUBIC)


# ------------------------------------------------------------------ Peach's scene in front of the castle
SUBTITLES = ["Mario!", "The power of the Stars is restored to the castle...", "...and it's all thanks to you!",
             "Thank you, Mario!", "We have to do something special for you...", "Listen, everybody,",
             "let's bake a delicious cake...", "...for Mario...", "Mario!"]      # (gEndCutsceneStringsEn)


def subtitle(font, text):
    """do_cutscene_handler: white, centred on x 160, 227 from the top of the game's screen"""
    canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
    width = sum(font.widths[c] for c in font.encode(text))
    font.draw(canvas, 160 - width / 2.0, 240 - 13 - 16, text, (255, 255, 255))
    return canvas


def export_peach(textures):
    """Peach with all twelve of her animations (the opening's copy has only the first)"""
    db = X.DB()
    for sym, png in list(db.tex.items()):
        if not os.path.exists(os.path.join(D, png)):
            base, ext = png.split('.', 1)
            if os.path.exists(os.path.join(D, base + '_us.' + ext)):
                db.tex[sym] = base + '_us.' + ext
    peach = S.export_actor(db, 'peach_geo', S.anim_table(db, 'peach_seg5_anims_0501C41C'), textures)
    if peach.get('cum') == 1.0:
        # (as introx.py: her quarter size is not found on the way to her first part; her movement is put right)
        m = re.search(r'peach_geo\[\]\s*=\s*\{.*?GEO_SCALE\(\s*\w+\s*,\s*(\d+)\s*\)', src('actors', 'peach', 'geo.inc.c'), re.S)
        k = int(m.group(1)) / 65536.0 if m else 1.0
        for a in peach['anims']:
            a['trans'] = [round(v * k, 4) for v in a['trans']]
        peach['cum'] = k
    swap = {'actors__peach__peach_eye_open.rgba16': 'actors__peach__peach_eye_mostly_open.rgba16',
            'actors__peach__peach_lips_scrunched.rgba16': 'actors__peach__peach_lips.rgba16'}
    for part in peach['parts']:
        for sec in part['sections']:
            if sec.get('texture') in swap:
                sec['texture'] = swap[sec['texture']]
    for new in swap.values():
        textures[new] = 'actors/peach/' + new.split('__')[-1] + '.png'
    return peach


def main():
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(TEXD, exist_ok=True)
    sp = splines()
    font = CreditsFont()
    shots = []
    for n, (scene, flags, angle, pos, path) in enumerate(SHOTS, 1):
        fl = flags & 0xFF
        cam = []
        for p, f in shot_camera(sp, path):
            cam += [round(v, 1) for v in ue(p) + ue(f)]
        yaw = ((angle & 0xFF) << 8) & 0xFFFF
        if yaw >= 0x8000: yaw -= 0x10000
        shots.append({'scene': scene, 'act': fl & 7, 'right': bool(fl & 0x10), 'down': bool(fl & 0x20),
                      'at': [round(v, 1) for v in ue(pos)], 'yaw': round(180.0 - yaw * 360.0 / 65536.0, 2), 'cam': cam})
        credits_page(font, NAMES[n], fl).save(os.path.join(TEXD, 'ending_credits_%d.png' % n))
    cake_picture().save(os.path.join(TEXD, 'ending_cake.png'))
    dfont = Font()
    for n, text in enumerate(SUBTITLES):
        subtitle(dfont, text).save(os.path.join(TEXD, 'ending_sub_%d.png' % n))
    textures = {}
    peach = export_peach(textures)
    X.write_lua(os.path.join(DATA, 'actor_peach_end.lua'), peach)
    X.copy_textures(textures, TEXD)
    print('Peach: %d animations (%s frames)' % (len(peach['anims']), ', '.join(str(a['frames']) for a in peach['anims'])))
    data = {'fps': 30, 'show': SHOW, 'progress': PROGRESS, 'warp': WARP, 'fov': 45.0, 'shots': shots}
    X.write_lua(os.path.join(DATA, 'ending.lua'), data, header="-- (this file: Mario 64's credits shots and their camera paths, worked out by endingx.py)\n")
    print('%d shots, %d frames each; pages and cake written' % (len(shots), WARP))
    for s in shots[:3]:
        c = s['cam']
        print('  %s act %d at %s yaw %.0f; camera from (%.0f %.0f %.0f) to (%.0f %.0f %.0f)' % (s['scene'], s['act'], s['at'], s['yaw'], c[0], c[1], c[2], c[-6], c[-5], c[-4]))


if __name__ == '__main__':
    main()
