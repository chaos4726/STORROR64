# ending_peach_cam.py : Mario 64's ending on the castle grounds (US version), run frame by frame as the game runs it -
# camera.c sCutsceneEnding (its shots, splines and fov), Mario's fall (end_peach_cutscene_mario_falling: the wing cap's
# flutter), Peach's descent (end_peach_cutscene_descend_peach) and the birds (intro_scene.inc.c, end_birds_1/2.inc.c) -
# written to the mod's data/ending_peach.lua for ending.lua: the camera's place, focus and fov every frame, Mario's
# height through his fall, and each bird's way. Mario 64's units throughout.
#   python -P tools/ending_peach_cam.py
import math, random, os

OUT = r'E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\Scripts\data\ending_peach.lua'

# ---------------------------------------------------------------- angles as the game has them
def s16(v):
    v = int(v) & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v

def sins(a): return math.sin(s16(a) * math.pi / 32768.0)
def coss(a): return math.cos(s16(a) * math.pi / 32768.0)

def atan2s(y, x):
    """the game's atan2s(y, x): the angle whose sins is x/d and coss is y/d"""
    return s16(round(math.atan2(x, y) * 32768.0 / math.pi))

def get_dist_and_angle(frm, to):
    dx, dy, dz = to[0] - frm[0], to[1] - frm[1], to[2] - frm[2]
    d = math.sqrt(dx * dx + dy * dy + dz * dz)
    return d, atan2s(math.sqrt(dx * dx + dz * dz), dy), atan2s(dz, dx)

def set_dist_and_angle(frm, d, pitch, yaw):
    return [frm[0] + d * coss(pitch) * sins(yaw), frm[1] + d * sins(pitch), frm[2] + d * coss(pitch) * coss(yaw)]

def approach_s16_asymptotic(cur, target, div):
    if div == 0:
        return s16(target)
    t = s16(cur - target)
    t = s16(t - int(t / div))          # (C's division: toward zero)
    return s16(t + target)

def approach_asym(cur, target, mul):
    mul = min(mul, 1.0)
    return cur + (target - cur) * mul

def approach_sym(cur, target, inc):
    inc = abs(inc)
    d = target - cur
    if d > 0:
        d -= inc
        return target - d if d > 0 else target
    d += inc
    return target - d if d < 0 else target

# ---------------------------------------------------------------- the splines (camera.c)
FLY_POS = [(0, 0, (-86, 876, 640)), (1, 0, (-86, 876, 610)), (2, 0, (-66, 945, 393)), (3, 0, (-80, 976, 272)),
           (4, 0, (-66, 1306, -36)), (5, 0, (-70, 1869, -149)), (6, 0, (-10, 2093, -146)), (7, 0, (-10, 2530, -248)),
           (8, 0, (-10, 2530, -263)), (9, 0, (-10, 2530, -273))]
FLY_FOCUS = [(0, 50, (-33, 889, -7)), (1, 35, (-33, 889, -7)), (2, 31, (-17, 1070, -193)), (3, 25, (-65, 1182, -272)),
             (4, 20, (-64, 1559, -542)), (5, 25, (-68, 2029, -677)), (6, 25, (-9, 2204, -673)), (7, 25, (-8, 2529, -772)),
             (8, 0, (-8, 2529, -772)), (9, 0, (-8, 2529, -772)), (-1, 0, (-8, 2529, -772))]
# (FLY_POS has no end mark: the game reads on into FLY_FOCUS, laid out after it)
FLY_POS_MEM = FLY_POS + FLY_FOCUS
DESCENT = [(0, 50, (1, 120, -1150)), (1, 50, (1, 120, -1150)), (2, 40, (118, 121, -1199)), (3, 40, (147, 74, -1306)),
           (4, 40, (162, 95, -1416)), (5, 40, (25, 111, -1555)), (6, 40, (-188, 154, -1439)), (7, 40, (-203, 181, -1242)),
           (8, 40, (7, 191, -1057)), (9, 40, (262, 273, -1326)), (0, 40, (-4, 272, -1627)), (1, 35, (-331, 206, -1287)),
           (2, 30, (-65, 219, -877)), (3, 25, (6, 216, -569)), (4, 25, (-8, 157, 40)), (5, 25, (-4, 106, 200)),
           (6, 25, (-6, 72, 574)), (7, 0, (-6, 72, 574)), (8, 0, (-6, 72, 574)), (-1, 0, (-6, 72, 574))]
TO_PEACH_POS = [(0, 0, (-130, 1111, -1815)), (1, 0, (-131, 1052, -1820)), (2, 0, (-271, 1008, -1651)),
                (3, 0, (-439, 1043, -1398)), (4, 0, (-433, 1040, -1120)), (5, 0, (-417, 1040, -1076)),
                (6, 0, (-417, 1040, -1076)), (7, 0, (-417, 1040, -1076)), (-1, 0, (-417, 1040, -1076))]
TO_PEACH_FOCUS = [(0, 50, (-37, 1020, -1332)), (1, 20, (-36, 1012, -1330)), (2, 20, (-24, 1006, -1215)),
                  (3, 20, (28, 1002, -1224)), (4, 24, (45, 1013, -1262)), (5, 35, (34, 1000, -1287)),
                  (6, 0, (34, 1000, -1287)), (7, 0, (34, 1000, -1287)), (-1, 0, (34, 1000, -1287))]
LOOK_UP_CASTLE = [(0, 50, (200, 1066, -1414)), (0, 50, (200, 1066, -1414)), (0, 30, (198, 1078, -1412)),
                  (0, 33, (15, 1231, -1474)), (0, 39, (-94, 1381, -1368)), (0, 0, (-92, 1374, -1379)),
                  (0, 0, (-92, 1374, -1379)), (-1, 0, (-92, 1374, -1379))]
LOOK_AT_SKY = [(0, 50, (484, 1368, -888)), (0, 72, (479, 1372, -892)), (0, 50, (351, 1817, -918)),
               (0, 50, (351, 1922, -598)), (0, 0, (636, 2027, -415)), (0, 0, (636, 2027, -415)), (-1, 0, (636, 2027, -415))]

class Spline:
    seg = 0
    prog = 0.0

SP = Spline()

def reset_spline():
    SP.seg, SP.prog = 0, 0.0

def cubic(u, a0, a1, a2, a3):
    u = min(u, 1.0)
    B0 = (1 - u) ** 3 / 6.0
    B1 = u ** 3 / 2.0 - u * u + 0.6666667
    B2 = -u ** 3 / 2.0 + u * u / 2.0 + u / 2.0 + 0.16666667
    B3 = u ** 3 / 6.0
    return [B0 * a0[k] + B1 * a1[k] + B2 * a2[k] + B3 * a3[k] for k in range(3)]

def move_along(p, spline):
    """move_point_along_spline: p (a list) set from the spline at the shared segment and progress, which go on"""
    seg, u = SP.seg, SP.prog
    if seg < 0:
        seg, u = 0, 0.0
    if spline[seg][0] == -1 or spline[seg + 1][0] == -1 or spline[seg + 2][0] == -1:
        return 1
    q = cubic(u, spline[seg][2], spline[seg + 1][2], spline[seg + 2][2], spline[seg + 3][2])
    p[0], p[1], p[2] = q
    s1 = 1.0 / spline[SP.seg + 1][1] if spline[SP.seg + 1][1] != 0 else 0.0
    s2 = 1.0 / spline[SP.seg + 2][1] if spline[SP.seg + 2][1] != 0 else 0.0
    SP.prog += (s2 - s1) * SP.prog + s1
    fin = 0
    if SP.prog >= 1.0:
        SP.seg += 1
        if spline[SP.seg + 3][0] == -1:
            SP.seg = 0
            fin = 1
        SP.prog -= 1.0
    return fin

# ---------------------------------------------------------------- Mario's fall, Peach's descent
FLOOR0 = 809.0                       # (the ground where he lands: the mod's scene, 607 cm)
def mario_fall():
    y, v, ys = 8000.0, 0.0, []
    g = 0
    while True:
        ys.append(y)
        # perform_air_step: down by his speed, landed at the floor
        if y + v <= FLOOR0:
            y = FLOOR0
            ys[-1] = y
            return ys, g
        y += v
        # apply_gravity: the wing cap's flutter (A held, falling) - else plain gravity
        if v < 0.0:
            v -= 2.0
            if v < -37.5:
                v += 4.0
                if v > -37.5:
                    v = -37.5
        else:
            v -= 4.0
            if v < -75.0:
                v = -75.0
        g += 1

FALL, L = mario_fall()
# (ending.lua's frames F: F 1 is his landing step's first; the camera's frame c = F + L - 1 (its cutscene began at his
# fall's second frame))
P_PEACH, P_DESCEND = 315, 631          # (spawn_peach's frame 40; descend_peach's first)
DESCEND_FRAMES = 584

def peach_ys(nF):
    ys = {}
    y, st = 2428.0, 0
    for F in range(P_PEACH, nF):
        if P_DESCEND <= F < P_DESCEND + DESCEND_FRAMES:
            if y >= 1300.0:
                if st < 60: st += 5
            else:
                if st >= 27: st -= 2
            y -= int(st / 10)
            if y <= 907.0: y = 906.0
        ys[F] = y
    return ys

F_DIALOG3 = 2235                      # (its first frame 2236)
F_RUN_CASTLE = F_DIALOG3 + 350        # (run_to_castle's first frame 2586)
F_FADE = F_RUN_CASTLE + 389           # (fade_out: the warp to the credits, 60 frames to black)
F_DONE = F_FADE + 60
NF = F_DONE + 2
PEACH_Y = peach_ys(NF)
PEACH_X, PEACH_Z = 0.0, -1300.0

# ---------------------------------------------------------------- the camera
SHOTS = [('mario_fall', 170), ('mario_land', 70), ('land_closeup', 75), ('stars_free_peach', 386),
         ('peach_appears', 139), ('peach_descends', 590), ('mario_to_peach', 95), ('peach_wakeup', 425),
         ('dialog', 236), ('kiss', 245), ('cake_for_mario', 1 << 20)]

def run():
    pos, foc = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
    fov, fov_fn = 45.0, 'default'
    cvar2y, cvar3y = 0.0, 0.0
    shot, t = 0, 0
    track, starts = [], []
    spawns = []                       # (cam frame, kind 7/8/9)
    ncam = F_DONE + L                 # (to the end of the fade)
    starts.append(0)
    for c in range(ncam):
        F = c - L + 1
        g = c + 1
        my = FALL[min(g, L)] if g <= L else FLOOR0
        py = PEACH_Y.get(F, 2428.0)
        name = SHOTS[shot][0]
        if name == 'mario_fall':
            if t == 0:
                foc[:] = [-26.0, 0.0, -137.0]
                pos[:] = [165.0, 4725.0, 324.0]
            zoff = abs(my - pos[1]) * -0.1
            if zoff > -100.0: zoff = -100.0
            to = (0.0, 80.0, zoff)
            pitch, yaw = 0, 0x8000      # (his face: -128 << 8)
            pr2 = -(to[2] * coss(pitch) - to[1] * sins(pitch))
            pr1 = to[2] * sins(pitch) + to[1] * coss(pitch)
            pr0 = to[0]
            foc[:] = [0.0 + pr2 * sins(yaw) + pr0 * coss(yaw), my + pr1, 0.0 + pr2 * coss(yaw) - pr0 * sins(yaw)]
        elif name == 'mario_land':
            foc[:] = [FLY_FOCUS[0][2][0], FLY_FOCUS[0][2][1] + 80.0, FLY_FOCUS[0][2][2]]
            pos[:] = [FLY_POS[0][2][0], FLY_POS[0][2][1], FLY_POS[0][2][2] + 150.0]
        elif name == 'land_closeup':
            foc[:] = [85.0, 826.0, 250.0]
            pos[:] = [-51.0, 988.0, -202.0]
        elif name == 'stars_free_peach':
            if t == 0: reset_spline()
            move_along(pos, FLY_POS_MEM)
            move_along(foc, FLY_FOCUS)
        elif name == 'peach_appears':
            if t == 0:
                pos[:] = [179.0, py + 35.0, -1216.0]
                foc[:] = [PEACH_X, py + 125.0, PEACH_Z]
            pos[1] = approach_asym(pos[1], py + 35.0, 0.02)
            foc[1] = approach_asym(foc[1], py + 125.0, 0.15)
        elif name == 'peach_descends':
            if t == 0:
                reset_spline()
                cvar2y = 150.0
            if t <= 299:
                move_along(pos, DESCENT)
                pos[1] += py + cvar3y
            else:
                p = [0.0, 0.0, 0.0]
                move_along(p, DESCENT)
                pos[0], pos[2] = p[0], p[2]
                pos[1] = approach_asym(pos[1], p[1] + py, 0.07)
                cvar2y = approach_sym(cvar2y, 90.0, 0.5)
            foc[:] = [PEACH_X, cvar2y + py, PEACH_Z]
        elif name == 'mario_to_peach':
            if t == 0: reset_spline()
            move_along(pos, TO_PEACH_POS)
            move_along(foc, TO_PEACH_FOCUS)
        elif name == 'peach_wakeup':
            if t == 0:
                reset_spline()
                move_along(foc, LOOK_UP_CASTLE)
            if t >= 250:
                move_along(foc, LOOK_UP_CASTLE)
            if t == 300: spawns.append((c, 7, t))
            if t == 340: spawns.append((c, 9, t))
            pos[:] = [-163.0, 978.0, -1082.0]
        elif name == 'dialog':
            foc[:] = [11.0, 983.0, -1273.0]
            pos[:] = [-473.0, 970.0, -1152.0]
        elif name == 'kiss':
            if t == 0:
                fov_fn = 'set29'
                foc[:] = [350.0, 1034.0, -1216.0]
                pos[:] = [-149.0, 1021.0, -1216.0]
            if t >= 155:
                fov_fn = 'default'
                pos[0] = approach_asym(pos[0], -250.0, 0.2); pos[1] = approach_asym(pos[1], 966.0, 0.1)
                pos[2] = approach_asym(pos[2], -1111.0, 0.2)
                foc[0] = approach_asym(foc[0], 233.0, 0.2); foc[1] = approach_asym(foc[1], 1068.0, 0.1)
                foc[2] = approach_asym(foc[2], -1298.0, 0.2)
        elif name == 'cake_for_mario':
            if t == 0:
                reset_spline()
                move_along(foc, LOOK_AT_SKY)
                pos[:] = [699.0, 1680.0, -703.0]
            if t <= 499:
                fov = 37.0
            if t >= 500:
                move_along(foc, LOOK_AT_SKY)
                pos[:] = [699.0, 1680.0, -703.0]
            if t in (600, 608, 624, 710): spawns.append((c, 8, t))
        # the fov, after the cutscene's own
        if fov_fn == 'set29':
            fov = 29.0
        else:
            fov = approach_sym(fov, 45.0, (45.0 - fov) / 30.0)
        track.append((pos[0], pos[1], pos[2], foc[0], foc[1], foc[2], fov))
        t += 1
        if t == SHOTS[shot][1]:
            shot += 1
            t = 0
            starts.append(c + 1)
    return track, starts, spawns

TRACK, STARTS, SPAWNS = run()

# ---------------------------------------------------------------- the birds
random.seed(64)
BIRDS1 = {7: [(0, 205, 500, 0x1000, 0x6000, -0x1E00, 25), (0, 205, 800, 0x1800, 0x6000, -0x1400, 35),
              (-100, 300, 500, 0x800, 0x6000, 0, 25), (100, -200, 800, 0, 0x4000, 0x1400, 45),
              (-80, 300, 350, 0x1800, 0x5000, 0xA00, 35), (-300, 300, 500, 0x800, 0x6000, 0x2800, 25),
              (-400, -200, 800, 0, 0x4000, -0x1400, 45)],
          9: [(50, 205, 500, 0x1000, 0x6000, 0, 35), (0, 285, 800, 0x1800, 0x6000, 0, 35)],
          8: [(-100, -100, -700, 0, 0, -0xF00, 25), (-250, 255, -200, 0, 0, -0x1400, 25), (-100, 155, -600, 0, 0, -0x500, 35),
              (250, 200, -1200, 0, 0, -0x700, 25), (-250, 255, -700, 0, 0, 0, 25)]}
DIALOG_START = STARTS[8]              # (the birds of the window go as the next shot starts: gCutsceneTimer 0)

birds = []
for c0, kind, st in SPAWNS:
    cam = TRACK[c0]
    for (ox, oy, oz, pi, ya, ro, fv) in BIRDS1[kind]:
        b = {'c0': c0, 'kind': kind, 'f0': int(random.random() * 6.0), 'x': cam[0] + ox, 'y': cam[1] + oy, 'z': cam[2] + oz,
             'pitch': s16(pi), 'yaw': s16(ya), 'roll': s16(ro), 'fv': float(fv), 'way': [], 't': 0, 'act': 0}
        if st > 700:                    # (spawn_child_obj_relative: past the shot's frame 700, 150 lower)
            b['y'] -= 150.0
        birds.append(b)
for b in birds:
    end = DIALOG_START if b['kind'] != 8 else len(TRACK)
    for c in range(b['c0'], end):
        cam = TRACK[c]
        if b['kind'] == 8:
            b['fv'] = random.random() * 10.0 + 25.0
        if b['act'] == 0:
            b['act'] = 1                # (its first frame: its size; then it flies)
        else:
            if b['kind'] != 8:
                if b['t'] < 100:
                    _, p, y = get_dist_and_angle((b['x'], b['y'], b['z']), (-554.0, 3044.0, -1314.0))
                    b['pitch'] = approach_s16_asymptotic(b['pitch'], s16(0 - p), 0x20)
                    b['yaw'] = approach_s16_asymptotic(b['yaw'], s16(y + 0), 0x20)
            else:
                _, p, y = get_dist_and_angle((cam[0], cam[1], cam[2]), (cam[3], cam[4], cam[5]))
                tgt = set_dist_and_angle((cam[0], cam[1], cam[2]), 14000.0, p, s16(y + 0x1000))
                _, p2, y2 = get_dist_and_angle((b['x'], b['y'], b['z']), tgt)
                b['pitch'] = approach_s16_asymptotic(b['pitch'], s16(0 - p2), 8)
                b['yaw'] = approach_s16_asymptotic(b['yaw'], s16(y2), 8)
        # cur_obj_set_pos_via_transform: forward along its pitch and yaw
        sx, cx = sins(b['pitch']), coss(b['pitch'])
        sy, cy = sins(b['yaw']), coss(b['yaw'])
        b['x'] += b['fv'] * cx * sy
        b['y'] += b['fv'] * -sx
        b['z'] += b['fv'] * cx * cy
        b['way'].append((b['x'], b['y'], b['z'], b['pitch'], b['yaw'], b['roll']))
        b['t'] += 1

# ---------------------------------------------------------------- the end: all of them waving (act_end_waving_cutscene)
# The camera's cutscene_end_waving (gEndWavingPos/Focus: from in front of them, back and up over the bridge), and the
# Lakitu that comes at its frame 120 (intro_lakitu.inc.c, actions 100-102). 300 frames, then 60 to black.
END_WAVING_POS = [(0, 0, (-5, 975, -917)), (0, 0, (-5, 975, -917)), (0, 0, (-5, 975, -917)), (0, 0, (-76, 1067, 742)),
                  (0, 0, (-105, 1576, 3240)), (0, 0, (-177, 1709, 5586)), (0, 0, (-177, 1709, 5586)),
                  (0, 0, (-177, 1709, 5586)), (0, 0, (-177, 1709, 5586))]
END_WAVING_FOCUS = [(0, 50, (18, 1013, -1415)), (0, 100, (17, 1037, -1412)), (0, 100, (16, 1061, -1408)),
                    (0, 100, (-54, 1053, 243)), (0, 100, (-84, 1575, 2740)), (0, 50, (-156, 1718, 5086)),
                    (0, 0, (-156, 1718, 5086)), (0, 0, (-156, 1718, 5086)), (0, 0, (-156, 1718, 5086))]
WAVE_FRAMES = 360

def approach_s16_sym(cur, target, inc):
    inc = abs(inc)
    d = s16(target - cur)
    if d > 0:
        d -= inc
        cur = target - d if d >= 0 else target
    else:
        d += inc
        cur = target - d if d <= 0 else target
    return s16(cur)

def run_wave():
    reset_spline()
    pos, foc = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
    cam, lak = [], []
    L_ = None
    for t in range(WAVE_FRAMES):
        move_along(pos, END_WAVING_POS)
        move_along(foc, END_WAVING_FOCUS)
        cam.append((pos[0], pos[1], pos[2], foc[0], foc[1], foc[2], 45.0))
        # Lakitu: made at 120 (unseen its first frame), placed by the camera the next, then flying
        if t == 120:
            L_ = {'act': 0, 'timer': 0, 'fv': 0.0}
        elif L_ is not None:
            o = L_
            if o['act'] == 0:
                # action 100: behind the camera as Mario faces (offset_rotated by his yaw 0x8000), then on
                yaw = 0x8000
                to = (-100.0, 100.0, 300.0)
                pr2, pr1, pr0 = -(to[2]), to[1], to[0]
                o['x'] = pos[0] + pr2 * sins(yaw) + pr0 * coss(yaw)
                o['y'] = pos[1] + pr1
                o['z'] = pos[2] + pr2 * coss(yaw) - pr0 * sins(yaw)
                o['mp'], o['my'] = 0x1000, s16(0x9000)
                o['fp'], o['fy'] = 0x800, s16(0x9000)
                o['act'], o['timer'] = 101, 0
                lak.append((t, o['x'], o['y'], o['z'], o['fp'], o['fy']))
                continue
            if o['act'] == 101:
                if o['timer'] > 60:
                    o['fv'] = o['fv'] + (-10.0 - o['fv']) * 0.05
                    o['my'] = s16(o['my'] + 0x78)
                    o['mp'] = s16(o['mp'] + 0x40)
                    o['fy'] = approach_s16_sym(o['fy'], atan2s(pos[2] - o['z'], pos[0] - o['x']), 0x200)
                nxt = None
                if o['timer'] > 105:
                    nxt = 102
                    o['mp'] = 0xE00
                o['fp'] = 0
            else:
                o['fv'] = o['fv'] + (60.0 - o['fv']) * 0.05
                o['fy'] = approach_s16_sym(o['fy'], atan2s(pos[2] - o['z'], pos[0] - o['x']), 0x200)
                if o['timer'] < 62:
                    o['my'] = approach_s16_asymptotic(o['my'], 0x1800, 0x1E)
                o['mp'] = approach_s16_sym(o['mp'], -0x2000, 0x5A)
                o['fp'] = 0
                nxt = None
            sx, cx = sins(o['mp']), coss(o['mp'])
            sy, cy = sins(o['my']), coss(o['my'])
            o['x'] += o['fv'] * cx * sy
            o['y'] += o['fv'] * -sx
            o['z'] += o['fv'] * cx * cy
            lak.append((t, o['x'], o['y'], o['z'], o['fp'], o['fy']))
            o['timer'] += 1
            if nxt:
                o['act'], o['timer'] = nxt, 0
    return cam, lak

WAVE_CAM, WAVE_LAK = run_wave()

# ---------------------------------------------------------------- written out
def num(v):
    r = round(v, 1)
    return str(int(r)) if r == int(r) else repr(r)

with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- generated by tools/ending_peach_cam.py from the decomp (camera.c sCutsceneEnding, mario_actions_cutscene.c, the\n')
    f.write('-- birds\' behaviours): Mario 64\'s ending on the castle grounds, frame by frame, in its own units. Do not edit.\n')
    f.write('return {\n')
    f.write('  land = %d,          -- the frame of his fall he lands on (the camera\'s frame c = F + land - 1)\n' % L)
    f.write('  floor = %s,\n' % num(FLOOR0))
    f.write('  fade = %d, done = %d,  -- (F: the warp to the credits\' black starts, and is black)\n' % (F_FADE, F_DONE))
    f.write('  shots = {%s},\n' % ', '.join(str(s) for s in STARTS))
    f.write('  fall = {%s},\n' % ', '.join(num(y) for y in FALL))
    f.write('  peach0 = %d,       -- (F of her first height below: her heights, appearing and coming down)\n' % P_PEACH)
    f.write('  peach = {%s},\n' % ', '.join(num(PEACH_Y[F]) for F in range(P_PEACH, P_DESCEND + DESCEND_FRAMES + 1)))
    f.write('  -- per camera frame: its place, its focus, its fov (top to bottom, of the game\'s 4:3 picture)\n')
    f.write('  cam = {\n')
    for i in range(0, len(TRACK), 4):
        f.write('    ' + ', '.join(', '.join(num(v) for v in fr) for fr in TRACK[i:i + 4]) + ',\n')
    f.write('  },\n')
    f.write('  -- each bird: the camera frame it comes, its first frame of flapping, and its way (x, y, z, pitch, yaw, roll) each frame\n')
    f.write('  birds = {\n')
    for b in birds:
        f.write('    { c0 = %d, f0 = %d, sound = %s, way = {' % (b['c0'], b['f0'], 'true' if b is birds[0] or (b['kind'] == 8 and b is [x for x in birds if x['kind'] == 8][0]) else 'false'))
        f.write(', '.join(', '.join(num(v) for v in w) for w in b['way']))
        f.write('} },\n')
    f.write('  },\n')
    # the end, all of them waving: the camera each frame (place, focus, fov), then Lakitu's way (frame, x, y, z, his
    # face's pitch and yaw) from where he comes
    f.write('  wave = {\n')
    f.write('    frames = %d, fade = 300,\n' % WAVE_FRAMES)
    f.write('    cam = {\n')
    for i in range(0, len(WAVE_CAM), 4):
        f.write('      ' + ', '.join(', '.join(num(v) for v in fr) for fr in WAVE_CAM[i:i + 4]) + ',\n')
    f.write('    },\n')
    f.write('    lakitu0 = %d,\n' % (WAVE_LAK[0][0] if WAVE_LAK else -1))
    f.write('    lakitu = {%s},\n' % ', '.join(', '.join(num(v) for v in w[1:]) for w in WAVE_LAK))
    f.write('  },\n')
    f.write('}\n')

print('wave: camera frames', len(WAVE_CAM), 'lakitu from', WAVE_LAK[0][0] if WAVE_LAK else None, 'frames', len(WAVE_LAK))
for t in (0, 60, 120, 200, 299, 359):
    print('  wave', t, [round(v) for v in WAVE_CAM[t]])
for k in (0, 30, 60, 100, 150, 200, len(WAVE_LAK) - 1):
    if k < len(WAVE_LAK):
        print('  lakitu', [round(v) for v in WAVE_LAK[k]])
print('landed at frame', L, 'of his fall; camera frames', len(TRACK))
print('shots start at camera frames', STARTS)
print('in F:', [s - L + 1 for s in STARTS])
print('bird spawns (cam frame, kind, shot frame):', SPAWNS, '-> F', [(c - L + 1, k) for c, k, _ in SPAWNS])
print('birds', len(birds), 'frames', sum(len(b['way']) for b in birds))
print('size', os.path.getsize(OUT))
