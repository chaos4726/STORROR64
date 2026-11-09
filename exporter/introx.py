"""Mario 64's opening for a new file, read out of the player's own copy of the game.

When a brand new file is picked, Mario 64 plays a scene: Peach's letter fades in over the sky, the camera
flies down and round the castle behind Lakitu, a pipe rises from the ground, Mario jumps out of it, and a
message explains the controls. This writes what the mod needs to play the same scene:

  data/intro.lua            where the camera is and what it looks at on each of the game's frames (30 a
                            second), its zoom, where Lakitu is and how he is turned, and when things happen
  textures/intro_letter.png the letter: the game's paper, its text in the game's own lettering, the signature
  textures/intro_dialog_N.png  the pages of the message at the pipe, as the game's dialog box shows them
  data/actor_pipe.lua, actor_lakitu.lua   the pipe and Lakitu (with his flying animation)

The camera and Lakitu are not copied from a recording: the game's own routines (src/game/camera.c,
behaviors/intro_lakitu.inc.c) are followed here step by step with the game's own path tables.

Usage: python introx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, re, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
from sm64x import SCALE
from PIL import Image

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
D = X.D
K = 4                               # pixels of the pictures to one of the game's 320x240


def src(*parts):
    return X.strip_comments(open(os.path.join(D, *parts), encoding='utf-8', errors='replace').read())


# ------------------------------------------------------------------ the path tables
def splines():
    t = src('src', 'game', 'camera.c')
    # (where the EU game's table differs, the US one comes second in the file and is the one kept)
    out = {}
    for m in re.finditer(r'struct CutsceneSplinePoint (\w+)\[\]\s*=\s*\{(.*?)\};', t, re.S):
        pts = [(int(a), float(b), (float(x), float(y), float(z)))
               for a, b, x, y, z in re.findall(r'\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}\s*\}', m.group(2))]
        out[m.group(1)] = pts
    return out


def cubic(u, a0, a1, a2, a3):
    """evaluate_cubic_spline"""
    u = min(u, 1.0)
    b0 = (1.0 - u) ** 3 / 6.0
    b1 = u * u * u / 2.0 - u * u + 0.6666667
    b2 = -u * u * u / 2.0 + u * u / 2.0 + u / 2.0 + 0.16666667
    b3 = u * u * u / 6.0
    return [b0 * a0[k] + b1 * a1[k] + b2 * a2[k] + b3 * a3[k] for k in range(3)]


def move(p, spline, seg, prog):
    """move_point_along_spline: -> (point, segment, progress, finished). `p` is what the point was."""
    segment, u = seg, prog
    if seg < 0:
        segment, u = 0, 0.0
    if spline[segment][0] == -1 or spline[segment + 1][0] == -1 or spline[segment + 2][0] == -1:
        return p, seg, prog, True
    p = cubic(u, *(spline[segment + i][2] for i in range(4)))
    first = 1.0 / spline[seg + 1][1] if spline[seg + 1][1] != 0 else 0.0
    second = 1.0 / spline[seg + 2][1] if spline[seg + 2][1] != 0 else 0.0
    prog += (second - first) * prog + first
    finished = False
    if prog >= 1.0:
        seg += 1
        if spline[seg + 3][0] == -1:
            seg, finished = 0, True
        prog -= 1.0
    return p, seg, prog, finished


def dist_and_angle(a, b):
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    return math.sqrt(dx * dx + dy * dy + dz * dz), math.atan2(dy, math.sqrt(dx * dx + dz * dz)), math.atan2(dx, dz)


def at_dist_and_angle(a, dist, pitch, yaw):
    return [a[0] + dist * math.cos(pitch) * math.sin(yaw), a[1] + dist * math.sin(pitch), a[2] + dist * math.cos(pitch) * math.cos(yaw)]


def clamp_pitch(pos, focus, limit=math.radians(0x3B00 * 360.0 / 65536.0)):
    dist, pitch, yaw = dist_and_angle(pos, focus)
    return at_dist_and_angle(pos, dist, max(-limit, min(limit, pitch)), yaw)


def unit(a):
    return a * 2.0 * math.pi / 65536.0


# ------------------------------------------------------------------ the scene, frame by frame
LETTER_AT, LETTER_HOLD, LETTER_FADE = 65, 250, 20       # the letter: when it starts, its timer, its fades
START = (-1328.0, 260.0, 4664.0)                        # where Mario starts: the pipe


def simulate():
    sp = splines()
    pos_s, focus_s = sp['sIntroStartToPipePosition'], sp['sIntroStartToPipeFocus']
    pipe_pos_s, pipe_focus_s = sp['sIntroPipeToDialogPosition'], sp['sIntroPipeToDialogFocus']
    # (in the game's own code the two Lakitu tables are handed over in each other's place: the one called
    # Focus is where he is, from the camera; the one called OffsetFromCamera is which way he faces)
    lak_where, lak_facing = sp['gIntroLakituStartToPipeFocus'], sp['gIntroLakituStartToPipeOffsetFromCamera']
    cam = {'pos': [0.0, 0.0, 0.0], 'focus': [0.0, 0.0, 0.0], 'seg': 0, 'prog': 0.0, 'fov': 45.0}
    frames, lakitu = [], []

    def start_to_pipe():
        cam['pos'], _, _, _ = move(cam['pos'], pos_s, cam['seg'], cam['prog'])          # (its speeds are all 0: no progress)
        cam['focus'], cam['seg'], cam['prog'], _ = move(cam['focus'], focus_s, cam['seg'], cam['prog'])
        # "the two splines are reflected in the horizontal plane for some reason, so they are rotated every frame"
        for key in ('pos', 'focus'):
            p = cam[key]
            cam[key] = [-p[0] + START[0], p[1] + START[1], -p[2] + START[2]]

    def keep(zoom_to, rate):
        cam['fov'] += (zoom_to - cam['fov']) / rate
        frames.append((list(cam['pos']), list(cam['focus']), cam['fov']))

    # the letter: the camera looks up into the sky, zoomed right in, and eases out
    letter = LETTER_AT + LETTER_HOLD + LETTER_FADE + 2
    for t in range(letter):
        if t == 0:
            cam['fov'] = 8.0
            start_to_pipe()
        cam['focus'] = clamp_pitch(cam['pos'], cam['focus'])
        keep(30.0, 60.0)
    for t in range(35):
        keep(45.0, 30.0)

    # the flight to the pipe, Lakitu in front of the camera
    fly0 = len(frames)
    lak = {'action': -1, 'timer': 0, 'seg': 0, 'prog': 0.0, 'pos': None, 'pitch': 0.0, 'yaw': 0.0}
    for t in range(820):
        # (the game moves its objects before its camera: Lakitu goes by where the camera was a frame ago)
        if t == 2:
            lak['action'] = 0
        elif t > 2:
            if lak['action'] == 0:
                lak['action'], lak['timer'] = 1, 0
            if lak['action'] == 1:
                facing, _, _, f1 = move([0, 0, 0], lak_facing, lak['seg'], lak['prog'])
                where, lak['seg'], lak['prog'], f2 = move([0, 0, 0], lak_where, lak['seg'], lak['prog'])
                if not (f1 and where == [0, 0, 0]):
                    # his place: the offset, turned to sit relative to where the camera looks
                    world = [where[k] + cam['pos'][k] for k in range(3)]
                    _, fp, fy = dist_and_angle(cam['pos'], cam['focus'])
                    dist, op, oy = dist_and_angle(cam['pos'], world)
                    lak['pos'] = at_dist_and_angle(cam['pos'], dist, fp + op, fy + oy)
                    _, lak['pitch'], lak['yaw'] = dist_and_angle([0, 0, 0], facing)
                if f1 or f2:
                    lak['action'], lak['timer'] = 2, -1
            elif lak['action'] == 2:
                if t > 720:
                    lak.update(action=3, timer=-1, r=1400.0, bob=-4096.0, bob_v=2048.0, dx=-200.0, move=0x8000)
                    lak['yaw'] = unit(0x8000 + 0x4000)
            elif lak['action'] == 3:
                lak['move'] += 0x200
                lak['r'] += (100.0 - lak['r']) * 0.03
                lak['pitch'] = math.atan2(lak['pos'][1] - 400.0, 200.0)
                want = unit(lak['move'] + 0x8000)
                diff = (want - lak['yaw'] + math.pi) % (2 * math.pi) - math.pi
                lak['yaw'] += diff / 4.0
                p = at_dist_and_angle([-1128.0, 560.0, 4664.0], lak['r'], 0.0, unit(lak['move']))
                p[1] += 150.0 * math.cos(unit(lak['bob']))
                lak['bob'] += lak['bob_v']
                lak['bob_v'] += (512.0 - lak['bob_v']) * 0.05
                p[0] += lak['dx']
                lak['dx'] += (0.0 - lak['dx']) * 0.05
                lak['pos'] = p
                if lak['timer'] == 98:
                    lak['action'] = 4
            lak['timer'] += 1
        shown = lak['action'] in (1, 2, 3) and lak['pos'] is not None
        lakitu.append((list(lak['pos']) if shown else None, lak['pitch'], lak['yaw']))
        start_to_pipe()
        cam['focus'] = clamp_pitch(cam['pos'], cam['focus'])
        keep(45.0, 30.0)

    # at the pipe: the camera is Lakitu's now, circling as Mario comes out
    pipe0 = len(frames)
    for t in range(270):
        if t == 0:
            cam['seg'], cam['prog'] = 0, 0.1
        cam['pos'], _, _, _ = move(cam['pos'], pipe_pos_s, cam['seg'], cam['prog'])
        cam['focus'], cam['seg'], cam['prog'], _ = move(cam['focus'], pipe_focus_s, cam['seg'], cam['prog'])
        keep(45.0, 30.0)
    return frames, lakitu, {'letter': letter, 'fly': fly0, 'pipe': pipe0}


def ue(p):
    return [-p[2] * SCALE, p[0] * SCALE, p[1] * SCALE]


def ue_rotation(pitch, yaw, roll=0.0):
    """the game's (pitch, yaw, roll) of an object -> Unreal's pitch, yaw, roll for the same pose, in degrees"""
    sx, cx, sy, cy, sz, cz = math.sin(pitch), math.cos(pitch), math.sin(yaw), math.cos(yaw), math.sin(roll), math.cos(roll)
    # (mtxf_rotate_zxy_and_translate: where the object's own x, y and z axes point)
    x_img = (cy * cz + sx * sy * sz, cx * sz, -sy * cz + sx * cy * sz)
    y_img = (-cy * sz + sx * sy * cz, cx * cz, sy * sz + sx * cy * cz)
    z_img = (cx * sy, -sx, cx * cy)

    def c(v):
        return (-v[2], v[0], v[1])
    xu, yu, zu = c([-k for k in z_img]), c(x_img), c(y_img)
    return [math.degrees(math.asin(max(-1.0, min(1.0, xu[2])))), math.degrees(math.atan2(xu[1], xu[0])),
            math.degrees(math.atan2(-yu[2], zu[2]))]


# ------------------------------------------------------------------ the game's dialog lettering
class Font:
    def __init__(self):
        t = open(os.path.join(D, 'bin', 'segment2.c'), encoding='utf-8', errors='replace').read()
        files = dict(re.findall(r'Texture (\w+)\[\]\s*=\s*\{\s*#include "([^"]+)\.inc\.c"', t))
        lut = t[t.index('const Texture *const main_font_lut[]'):]
        lut = lut[lut.index('// US Font Table'):]
        lut = lut[:lut.index('};')]
        lut = re.sub(r'#if defined\(VERSION_CN\)(.*?)#else(.*?)#endif', lambda m: m.group(2), lut, flags=re.S)
        end = re.search(r'#else|#elif|#endif', lut)
        if end:
            lut = lut[:end.start()]
        self.lut = [e.strip() for e in lut.split('\n', 1)[1].replace('\n', ' ').split(',') if e.strip()]
        self.files = files
        w = src('src', 'game', 'ingame_menu.c')
        w = w[w.index('gDialogCharWidths[256]'):]
        w = w[w.index('{') + 1:w.index('};')]
        w = re.sub(r'#ifdef VERSION_EU\b(.*?)#else(.*?)#endif', lambda m: m.group(2), w, flags=re.S)
        self.widths = [int(v) for v in re.findall(r'\d+', w)]
        self.codes = {}
        for line in open(os.path.join(D, 'charmap.txt'), encoding='utf-8'):
            m = re.match(r"\s*'(.+)'\s*=\s*(?:CN_ZERO\s+|CN_FF\s+)?(0x[0-9A-Fa-f]+)\s*$", line.rstrip())
            if m:
                key = m.group(1).replace('\\n', '\n').replace("\\'", "'")
                self.codes.setdefault(key, int(m.group(2), 16))
        # (the game has single codes for the words "the" and "you", which it then spells out letter by
        # letter anyway: here they are simply spelled)
        self.keys = sorted((k for k in self.codes if len(k) == 1 or not k.isalpha()), key=len, reverse=True)
        self.glyphs = {}

    def glyph(self, code):
        """a letter as it stands on the screen: 8 wide, 16 tall, each pixel its coverage 0..255"""
        if code in self.glyphs:
            return self.glyphs[code]
        g = None
        sym = self.lut[code] if code < len(self.lut) else '0x0'
        if sym in self.files:
            im = Image.open(os.path.join(D, self.files[sym] + '.png')).convert('LA')
            tex = im.load()
            # the game keeps each letter lying on its side, 16 wide and 8 tall, and turns it as it draws
            g = Image.new('L', (8, 16), 0)
            px = g.load()
            for y in range(16):
                for x in range(8):
                    px[x, y] = tex[15 - y, 7 - x][1] if tex[15 - y, 7 - x][0] > 0 else 0
        self.glyphs[code] = g
        return g

    def encode(self, text):
        out, i = [], 0
        while i < len(text):
            for key in self.keys:
                if text.startswith(key, i):
                    out.append(self.codes[key])
                    i += len(key)
                    break
            else:
                raise KeyError('no code for %r' % text[i])
        return out

    def draw(self, canvas, x, top, text, colour):
        """one line, its letters' cells starting at (x, top) in the game's pixels"""
        for code in self.encode(text):
            if code == 0xD0:
                # DIALOG_CHAR_SLASH: no letter, two spaces (a choice's room for its arrow: "//Go!////Don't Go")
                x += 2 * self.widths[self.codes[' ']]
                continue
            g = self.glyph(code)
            if g is not None:
                big = g.resize((8 * K, 16 * K), Image.NEAREST)
                ink = Image.new('RGBA', big.size, tuple(colour) + (255,))
                canvas.paste(ink, (int(round(x * K)), int(round(top * K))), big)
            x += self.widths[code]
        return x


def dialog_text(name):
    t = open(os.path.join(D, 'text', 'us', 'dialogs.h'), encoding='utf-8').read()
    m = re.search(r'DEFINE_DIALOG\(%s,\s*\d+,\s*(\d+),\s*(\d+),\s*(\d+),\s*_\("(.*?)"\)\)' % name, t, re.S)
    lines = m.group(4).replace('\\\n', '').split('\\n')
    return {'per_page': int(m.group(1)), 'left': int(m.group(2)), 'top': int(m.group(3)), 'lines': lines}


def letter_picture(font):
    """Peach's letter on the game's 320x240 screen (print_peach_letter_message)"""
    canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
    # the paper: two halves, each a 32x64 picture, drawn 71 and 72 wide and 163 high about (97, 118)
    left = Image.open(os.path.join(D, 'levels', 'castle_grounds', '3.rgba16.png')).convert('RGB')
    right = Image.open(os.path.join(D, 'levels', 'castle_grounds', '4.rgba16.png')).convert('RGB')
    top = 240 - (118 + 82)
    canvas.paste(left.resize((71 * K, 163 * K), Image.BILINEAR), ((97 - 71) * K, top * K))
    canvas.paste(right.resize((72 * K, 163 * K), Image.BILINEAR), (97 * K, top * K))
    d = dialog_text('DIALOG_020')
    for n, line in enumerate(d['lines']):
        font.draw(canvas, 38, 240 - (142 - 16 * n) - 16, line, (20, 20, 20))
    # the signature, in pink
    sig = Image.open(os.path.join(D, 'levels', 'castle_grounds', '5.ia8.png')).convert('LA')
    alpha = sig.split()[1].resize((64 * K, 32 * K), Image.NEAREST)
    canvas.paste(Image.new('RGBA', alpha.size, (200, 80, 120, 255)), (116 * K, 166 * K), alpha)
    return canvas


def dialog_pages(font, name):
    """a message as the game's dialog box shows it, one picture for each page"""
    d = dialog_text(name)
    per = d['per_page']
    pages = []
    lines = d['lines']
    for first in range(0, len(lines), per):
        canvas = Image.new('RGBA', (320 * K, 240 * K), (0, 0, 0, 0))
        # the box: black, see-through, a little bigger than the lines
        x0, y0 = d['left'] - 7, 240 - (d['top'] + 5)
        w, h = 130 * 1.1, 80 * (per / 5.0 + 0.1)
        box = Image.new('RGBA', (int(w * K), int(h * K)), (0, 0, 0, 150))
        canvas.alpha_composite(box, (int(x0 * K), int(y0 * K)))
        for n, line in enumerate(lines[first:first + per]):
            font.draw(canvas, d['left'], 240 - (d['top'] - 2 - 16 * n), line, (255, 255, 255))
        pages.append(canvas)
    return pages


def main():
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(TEXD, exist_ok=True)
    frames, lakitu, marks = simulate()
    fly, pipe = marks['fly'], marks['pipe']
    cam = []
    for pos, focus, fov in frames:
        cam += [round(v, 2) for v in ue(pos) + ue(focus)] + [round(fov, 3)]
    lak, lak_from = [], None
    for i, (pos, pitch, yaw) in enumerate(lakitu):
        if pos is None:
            if lak_from is not None and 'until' not in marks:
                marks['until'] = fly + i
            continue
        if lak_from is None:
            lak_from = fly + i
        lak += [round(v, 2) for v in ue(pos)] + [round(v, 2) for v in ue_rotation(pitch, yaw)]
    # when things happen, in frames from the start (Mario's side of it: act_intro_cutscene)
    pipe_at = fly + 717 + 38
    jump_at = pipe_at + 39 + 118
    data = {
        'fps': 30, 'frames': len(frames), 'cam': cam,
        'lakitu': lak, 'lakitu_from': lak_from, 'lakitu_until': marks.get('until', pipe),
        'letter': {'at': LETTER_AT, 'fade': LETTER_FADE, 'hold': LETTER_HOLD, 'alpha': 200.0 / 255.0},
        'fly_at': fly, 'pipe_shot_at': pipe,
        'pipe': {'at': pipe_at, 'pos': ue((START[0], 60.0, START[2])), 'rise': 200.0 * SCALE, 'rise_frames': 20,
                 'sink_per_frame': 5.0 * SCALE, 'yaw': -180.0},
        'jump_at': jump_at, 'jump': {'up': 60.0 * SCALE * 30.0, 'forward': 10.0 * SCALE * 30.0, 'gravity': 4.0 * SCALE * 900.0},
        'hud_at': pipe_at + 39 + 25,
        'dialog_at': pipe + 250, 'start': ue(START),
    }
    # Peach, in the sky while her letter is read (behaviors/intro_peach.inc.c): a fixed place in front of the
    # camera, a fixed turn, her first animation from its 100th frame; she fades away when the letter has gone
    pos0, focus0, _ = frames[0]
    _, fp, fy = dist_and_angle(pos0, focus0)
    peach_at = at_dist_and_angle(pos0, 186.0, fp + unit(-9984.0), fy + unit(-768.0))
    data['peach'] = {'pos': [round(v, 2) for v in ue(peach_at)],
                     'rot': [round(v, 3) for v in ue_rotation(unit(0x400), unit(0x7500), unit(-0x3700))],
                     'anim_from': 100, 'fade_at': marks['letter'], 'fade_frames': 32}
    font = Font()
    letter_picture(font).save(os.path.join(TEXD, 'intro_letter.png'))
    pages = dialog_pages(font, 'DIALOG_033')
    for n, page in enumerate(pages):
        page.save(os.path.join(TEXD, 'intro_dialog_%d.png' % (n + 1)))
    data['dialog_pages'] = len(pages)
    X.write_lua(os.path.join(DATA, 'intro.lua'), data, header="-- (this file: the camera, Lakitu and timings of the new-file opening, worked out by introx.py)\n")
    print('frames %d (letter to %d, flight from %d, pipe from %d); Lakitu %d..%d; pipe at %d, jump at %d, message at %d; %d pages' % (
        len(frames), marks['letter'], fly, pipe, lak_from, data['lakitu_until'], pipe_at, jump_at, data['dialog_at'], len(pages)))
    for i in (0, 200, fly, fly + 200, fly + 500, fly + 700, fly + 819, pipe, pipe + 100, pipe + 269):
        pos, focus, fov = frames[i]
        print('  frame %4d: camera (%6.0f %6.0f %6.0f) looks at (%6.0f %6.0f %6.0f) fov %.1f' % ((i,) + tuple(pos) + tuple(focus) + (fov,)))

    # the pipe and Lakitu
    db = X.DB()
    for sym, png in list(db.tex.items()):
        if not os.path.exists(os.path.join(D, png)):
            base, ext = png.split('.', 1)
            if os.path.exists(os.path.join(D, base + '_us.' + ext)):
                db.tex[sym] = base + '_us.' + ext
    textures = {}
    pipe_actor = S.export_actor(db, 'warp_pipe_geo', [], textures)
    X.write_lua(os.path.join(DATA, 'actor_pipe.lua'), pipe_actor)
    anims = S.anim_table(db, 'lakitu_seg6_anims_060058F8')
    lak_actor = S.export_actor(db, 'lakitu_geo', anims, textures)
    X.write_lua(os.path.join(DATA, 'actor_lakitu.lua'), lak_actor)
    peach_actor = S.export_actor(db, 'peach_geo', S.anim_table(db, 'peach_seg5_anims_0501C41C')[:1], textures)
    if peach_actor.get('cum') == 1.0:
        # Her model is a quarter size (a scale at the very top of her layout, before it branches to her
        # body). The exporter scales her parts by it but, not finding it on the way to the first of them,
        # leaves how far her animation moves her at full size: four times too far. Put right here.
        m = re.search(r'peach_geo\[\]\s*=\s*\{.*?GEO_SCALE\(\s*\w+\s*,\s*(\d+)\s*\)', src('actors', 'peach', 'geo.inc.c'), re.S)
        k = int(m.group(1)) / 65536.0 if m else 1.0
        for a in peach_actor['anims']:
            a['trans'] = [round(v * k, 4) for v in a['trans']]
        peach_actor['cum'] = k
        print('Peach: the movement of her animation scaled by %.2f' % k)
    # Her face: the game picks her eyes and mouth as she is drawn (geo_switch_peach_eyes); the exporter takes the
    # first choice, wide-open eyes and a pursed mouth, which looks startled. She is given the eyes the game shows
    # her with between blinks (half open) and her smile.
    swap = {'actors__peach__peach_eye_open.rgba16': 'actors__peach__peach_eye_mostly_open.rgba16',
            'actors__peach__peach_lips_scrunched.rgba16': 'actors__peach__peach_lips.rgba16'}
    for part in peach_actor['parts']:
        for sec in part['sections']:
            if sec.get('texture') in swap:
                sec['texture'] = swap[sec['texture']]
    for new in swap.values():
        textures[new] = 'actors/peach/' + new.split('__')[-1] + '.png'
    X.write_lua(os.path.join(DATA, 'actor_peach.lua'), peach_actor)
    print('Peach: %d parts, %d sections, animation of %s frames' % (len(peach_actor['parts']),
          sum(len(p['sections']) for p in peach_actor['parts']), ', '.join(str(a.get('frames')) for a in peach_actor['anims'])))
    n = X.copy_textures(textures, TEXD)
    print('pipe: %d parts; Lakitu: %d parts, %d animations (%s frames); textures copied: %d' % (
        len(pipe_actor['parts']), len(lak_actor['parts']), len(lak_actor['anims']),
        ', '.join(str(a.get('frames')) for a in lak_actor['anims']), n))


if __name__ == '__main__':
    main()
