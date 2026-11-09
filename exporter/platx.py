"""Mario 64's moving platforms. Each is exported as an object of kind "platform" that names a template
(the model and its collision, in the model's own coordinates) and carries what its behaviour needs,
in Mario 64's own units and angles; the mod runs the behaviour the way the game does.

The tables here are the ones in the game's behaviour code (src/game/behaviors/*.inc.c), which picks a
platform's collision model, speed and path from its behaviour parameters."""
import os, re, glob, math
import sm64x as X
import sm64scenes as S
from sm64x import SCALE, try_int

SEESAW_COL = ['bitdw_seg7_collision_0700F70C', 'bits_seg7_collision_0701ADD8', 'bits_seg7_collision_0701AE5C',
              'bob_seg7_collision_bridge', 'bitfs_seg7_collision_07015928', 'rr_seg7_collision_07029750',
              'rr_seg7_collision_07029858', 'vcutm_seg7_collision_0700AC44']
SLIDE2_COL = ['bits_seg7_collision_0701A9A0', 'bits_seg7_collision_0701AA0C', 'bitfs_seg7_collision_07015714',
              'bitfs_seg7_collision_07015768', 'rr_seg7_collision_070295F8', 'rr_seg7_collision_0702967C', None,
              'bitdw_seg7_collision_0700F688']
TRACK_COL = ['rr_seg7_collision_07029038', 'ccm_seg7_collision_070163F8',
             'checkerboard_platform_seg8_collision_0800D710', 'bitfs_seg7_collision_070157E0']
TRACK_PATHS = ['rr_seg7_trajectory_0702EC3C', 'rr_seg7_trajectory_0702ECC0', 'ccm_seg7_trajectory_0701669C',
               'bitfs_seg7_trajectory_070159AC', 'hmc_seg7_trajectory_0702B86C', 'lll_seg7_trajectory_0702856C',
               'lll_seg7_trajectory_07028660', 'rr_seg7_trajectory_0702ED9C', 'rr_seg7_trajectory_0702EEE0']
OCT_COL = ['bits_seg7_collision_0701AA84', 'rr_seg7_collision_07029508']
OCT_VEL = [300, -300, 600, -600]
ROT_PLAT = [(1.0, 'wf_seg7_collision_rotating_platform'), (1.5, 'wdw_seg7_collision_070186B4')]
FERRIS = [('bits_seg7_collision_0701ACAC', 'bits_seg7_collision_0701AC28', 'MODEL_BITS_BLUE_PLATFORM'),
          ('bitdw_seg7_collision_0700F7F0', 'bitdw_seg7_collision_0700F898', 'MODEL_BITDW_BLUE_PLATFORM')]
ELEVATOR_H = [(-51, 0, 0), (-461, 0, 0), (-512, 0, 0), (-2611, 0, 0), (-2360, 0, 0), (214, 0, 0), (-50, 1945, 1)]
# the stairs a purple switch brings out, as they stand once it has been pressed
STAIRS = [('bits_seg7_collision_0701B0D4', 'MODEL_BITS_STAIRCASE'),
          ('bitdw_seg7_collision_0700F91C', 'MODEL_BITDW_STAIRCASE_FRAME4'),
          ('rr_seg7_collision_07029924', 'MODEL_RR_TRICKY_TRIANGLES')]
# ... and as they stand before it (animated_floor_switch.inc.c D_80331A54, frame 0 of each)
STAIRS_IN = [('bits_seg7_collision_0701B734', 'MODEL_BITS_STAIRCASE_FRAME4'),
             ('bitdw_seg7_collision_0700FD9C', 'MODEL_BITDW_STAIRCASE'),
             ('rr_seg7_collision_0702A6B4', 'MODEL_RR_TRICKY_TRIANGLES_FRAME4')]
# the barred doors an openable grill puts either side of itself: half its width, model, collision
# (grill_door.inc.c gOpenableGrills: OPENABLE_GRILL_BP_BOB 0, OPENABLE_GRILL_BP_HMC 1)
GRILLS = [(320, 'MODEL_BOB_BARS_GRILLS', 'bob_seg7_collision_gate'),
          (410, 'MODEL_HMC_RED_GRILLS', 'hmc_seg7_collision_0702B65C')]
BF_COL = ['bits_seg7_collision_0701AD54', 'bitfs_seg7_collision_070157E0', 'bitfs_seg7_collision_07015124']
CHECKER_COL = 'checkerboard_platform_seg8_collision_0800D710'

HANDLED = {'bhvWaterBombCannon', 'bhvBowsersSub', 'bhvBowserSubDoor', 'bhvHiddenAt120Stars', 'bhvCannon', 'bhvCapSwitch', 'bhvSnowMoundSpawn', 'bhvSLWalkingPenguin', 'bhvJRBSlidingBox', 'bhvOpenableGrill', 'bhvFloorSwitchGrills', 'bhvFloorSwitchAnimatesObject', 'bhvPyramidTop', 'bhvTowerDoor', 'bhvKickableBoard', 'bhvWFBreakableWallRight', 'bhvWFBreakableWallLeft', 'bhvWaterLevelPillar', 'bhvMoatGrills', 'bhvControllablePlatform', 'bhvSeesawPlatform', 'bhvSquarishPathMoving', 'bhvSlidingPlatform2', 'bhvFerrisWheelAxle',
           'bhvOctagonalPlatformRotating', 'bhvRotatingPlatform', 'bhvWFRotatingWoodenPlatform', 'bhvPlatformOnTrack',
           'bhvCheckerboardElevatorGroup', 'bhvRRElevatorPlatform', 'bhvHMCElevatorPlatform', 'bhvMeshElevator',
           'bhvAnimatesOnFloorSwitchPress', 'bhvActivatedBackAndForthPlatform', 'bhvChainChompGate',
           'bhvThwomp', 'bhvThwomp2', 'bhvGrindel', 'bhvHorizontalGrindel', 'bhvSpindel',
           'bhvTTCRotatingSolid', 'bhvTTCPendulum', 'bhvTTCTreadmill', 'bhvTTCMovingBar', 'bhvTTCCog', 'bhvTTCPitBlock',
           'bhvTTCElevator', 'bhvTTC2DRotator', 'bhvTTCSpinner', 'bhvBlueCoinSwitch', 'bhvCannonClosed',
           'bhvMontyMoleHole', 'bhvWoodenPost', 'bhvHiddenObject', 'bhvFloorSwitchHiddenObjects', 'bhvPushableMetalBox',
           'bhvLLLTiltingInvertedPyramid', 'bhvBitFSTiltingInvertedPyramid', 'bhvLLLSinkingRectangularPlatform',
           'bhvLLLSinkingSquarePlatforms', 'bhvLLLSinkingRockBlock', 'bhvBitFSSinkingPlatforms', 'bhvBitFSSinkingCagePlatform',
           'bhvWDWSquareFloatingPlatform', 'bhvWDWRectangularFloatingPlatform', 'bhvArrowLift', 'bhvWFSlidingPlatform',
           'bhvSmallBomp', 'bhvLargeBomp', 'bhvSwingPlatform', 'bhvSSLMovingPyramidWall', 'bhvSquishablePlatform',
           'bhvLLLRotatingHexagonalPlatform', 'bhvLLLRotatingHexagonalRing', 'bhvLLLRollingLog', 'bhvTTMRollingLog',
           'bhvLLLVolcanoFallingTrap', 'bhvMerryGoRound', 'bhvPyramidElevator', 'bhvWDWExpressElevator',
           'bhvBBHTiltingTrapPlatform', 'bhvJRBFloatingPlatform', 'bhvLLLMovingOctagonalMeshPlatform',
           'bhvLLLRotatingBlockWithFireBars', 'bhvRRRotatingBridgePlatform', 'bhvTumblingBridge', 'bhvBBHTumblingBridge',
           'bhvCastleFloorTrap', 'bhvClockMinuteHand', 'bhvClockHourHand', 'bhvDecorativePendulum',
           'bhvTowerPlatformGroup', 'bhvDonutPlatformSpawner', 'bhvTreasureChestsJRB', 'bhvTreasureChestsShip',
           'bhvTreasureChestsDDD', 'bhvFallingBowserPlatform', 'bhvRRCruiserWing', 'bhvSunkenShipPart2', 'bhvShipPart3',
           'bhvHauntedBookshelf', 'bhvHauntedBookshelfManager', 'bhvCoffinSpawner',
           'bhvLLLBowserPuzzle', 'bhvLLLDrawbridgeSpawner', 'bhvLLLFloatingWoodBridge', 'bhvToxBox',
           'bhvWhirlpool', 'bhvDorrie', 'bhvUkikiCage', 'bhvTHIHugeIslandTop', 'bhvTHITinyIslandTop',
           'bhvTiltingBowserLavaPlatform',
           'bhvInSunkenShip', 'bhvInSunkenShip2', 'bhvInSunkenShip3'}
# bowser_falling_platform.inc.c: the final arena's ten outer pieces, by their second parameter byte
BOWSER3_COL = [None, 'bowser_3_seg7_collision_07004B94', 'bowser_3_seg7_collision_07004C18', 'bowser_3_seg7_collision_07004C9C',
               'bowser_3_seg7_collision_07004D20', 'bowser_3_seg7_collision_07004DA4', 'bowser_3_seg7_collision_07004E28',
               'bowser_3_seg7_collision_07004EAC', 'bowser_3_seg7_collision_07004F30', 'bowser_3_seg7_collision_07004FB4',
               'bowser_3_seg7_collision_07005038']
# treasure_chest.inc.c: (order, x, y, z, yaw) of each spawner's chests, and the star it leaves
CHESTS = {
    'bhvTreasureChestsJRB': ([(1, -1700, -2812, -1150, 0x7FFF), (2, -1150, -2812, -1550, 0x7FFF),
                              (3, -2400, -2812, -1800, 0x7FFF), (4, -1800, -2812, -2100, 0x7FFF)], (-1800, -2500, -1700), True),
    'bhvTreasureChestsShip': ([(1, 400, -350, -2700, 0), (2, 650, -350, -940, -0x6001),
                               (3, -550, -350, -770, 0x5FFF), (4, 100, -350, -1700, 0)], None, False),
    'bhvTreasureChestsDDD': ([(1, -4500, -5119, 1300, -0x6001), (2, -1800, -5119, 1050, 0x1FFF),
                              (3, -4500, -5119, -1100, 9102), (4, -2400, -4607, 125, 16019)], (-1900, -4000, -1400), False),
}
# donut_platform.inc.c sDonutPlatformPositions (s16)
DONUTS = [(0x0B4C, 0xF7D7, 0x19A4), (0xF794, 0x08A3, 0xFFA9), (0x069C, 0x09D8, 0xFFE0), (0x05CF, 0x09D8, 0xFFE0),
          (0x0502, 0x09D8, 0xFFE0), (0x054C, 0xF7D7, 0x19A4), (0x0A7F, 0xF7D7, 0x19A4), (0x09B2, 0xF7D7, 0x19A4),
          (0x06E6, 0xF7D7, 0x19A4), (0x0619, 0xF7D7, 0x19A4), (0xEFB5, 0xF7D7, 0x19A4), (0x00E6, 0xF7D7, 0x19A4),
          (0x0019, 0xF7D7, 0x19A4), (0xFF4D, 0xF7D7, 0x19A4), (0xF081, 0xF7D7, 0x19A4), (0xE34F, 0xF671, 0x197A),
          (0xEEE8, 0xF7D7, 0x19A4), (0xE74F, 0xF7D7, 0x197A), (0xE683, 0xF7D7, 0x197A), (0xE5B6, 0xF7D7, 0x197A),
          (0xEE83, 0xF4A4, 0x19A4), (0xE41C, 0xF671, 0x197A), (0xE4E9, 0xF671, 0x197A), (0xECE9, 0xF4A4, 0x19A4),
          (0xEDB6, 0xF4A4, 0x19A4), (0xFC3F, 0x0A66, 0xFF45), (0x00EF, 0x04CD, 0xFF53), (0x0022, 0x04CD, 0xFF53),
          (0xFF57, 0x04CD, 0xFF53), (0xFB73, 0x0A66, 0xFF45), (0xFD0C, 0x0A66, 0xFF45)]
# tumbling_bridge.inc.c sTumblingBridgeData: sections, first offset, spacing, plank model, plank collision
TUMBLING = {0: (9, -512, 128, 'MODEL_WF_TUMBLING_BRIDGE_PART', 'wf_seg7_collision_tumbling_bridge'),
            1: (9, -412, 103, 'MODEL_BBH_TUMBLING_PLATFORM_PART', 'bbh_seg7_collision_07026B1C'),
            3: (9, -512, 128, 'MODEL_BITFS_TUMBLING_PLATFORM_PART', 'bitfs_seg7_collision_07015288')}
# behaviour -> the platforms.lua behaviour that moves it, for the ones that need nothing more than their model
SIMPLE_MOVERS = {
    'bhvLLLTiltingInvertedPyramid': 'tilt_pyramid', 'bhvBitFSTiltingInvertedPyramid': 'tilt_pyramid',
    'bhvLLLSinkingRectangularPlatform': 'lll_rect', 'bhvLLLSinkingSquarePlatforms': 'lll_square',
    'bhvLLLSinkingRockBlock': 'sink_block', 'bhvBitFSSinkingPlatforms': 'bitfs_sink', 'bhvBitFSSinkingCagePlatform': 'bitfs_cage',
    'bhvWDWSquareFloatingPlatform': 'float_plat', 'bhvWDWRectangularFloatingPlatform': 'float_plat',
    'bhvArrowLift': 'arrow_lift', 'bhvWFSlidingPlatform': 'wf_slide', 'bhvSwingPlatform': 'swing',
    'bhvSSLMovingPyramidWall': 'pyramid_wall', 'bhvSquishablePlatform': 'squish',
    'bhvLLLRotatingHexagonalPlatform': 'spin_hex', 'bhvLLLRotatingHexagonalRing': 'hex_ring', 'bhvLLLRollingLog': 'roll_log',
    'bhvTTMRollingLog': 'roll_log', 'bhvLLLVolcanoFallingTrap': 'volcano_trap', 'bhvMerryGoRound': 'merry',
    'bhvPyramidElevator': 'pyr_elev', 'bhvWDWExpressElevator': 'express', 'bhvBBHTiltingTrapPlatform': 'tilt_trap',
    'bhvJRBFloatingPlatform': 'float_plat', 'bhvLLLMovingOctagonalMeshPlatform': 'oct_mesh',
    'bhvLLLRotatingBlockWithFireBars': 'fire_bars', 'bhvRRRotatingBridgePlatform': 'rr_bridge',
}
# the ones a level places as macro objects (build_all hands them over with their preset's model and parameter)
MACRO_PLATFORMS = {'bhvTTCRotatingSolid', 'bhvTTCPendulum', 'bhvTTCTreadmill', 'bhvTTCMovingBar', 'bhvTTCCog',
                   'bhvTTCPitBlock', 'bhvTTCElevator', 'bhvTTC2DRotator', 'bhvTTCSpinner', 'bhvBlueCoinSwitch',
                   'bhvCannonClosed', 'bhvCannon', 'bhvMontyMoleHole', 'bhvWoodenPost', 'bhvHiddenObject',
                   'bhvFloorSwitchHiddenObjects', 'bhvPushableMetalBox', 'bhvWaterBombCannon'}
# collision models Tick Tock Clock's pieces choose in code, by their second parameter byte
TTC_COL = {
    'bhvTTCRotatingSolid': ['ttc_seg7_collision_07014F70', 'ttc_seg7_collision_07015008'],
    'bhvTTCTreadmill': ['ttc_seg7_collision_070152B4', 'ttc_seg7_collision_070153E0'],
    'bhvTTCCog': ['ttc_seg7_collision_07015584', 'ttc_seg7_collision_07015650'],
    'bhvTTCPitBlock': ['ttc_seg7_collision_07015754', 'ttc_seg7_collision_070157D8'],
}

# ---------------------------------------------------------------- behaviour parameters as numbers
_defines = None


def _load_defines():
    global _defines
    _defines = {}
    for rel in ('include/object_constants.h', 'include/behavior_data.h', 'include/types.h'):
        p = os.path.join(X.D, rel)
        if not os.path.exists(p):
            continue
        t = X.strip_comments(open(p, encoding='utf-8', errors='replace').read()).replace('\\\n', ' ')
        for m in re.finditer(r'^[ \t]*#define[ \t]+(\w+)[ \t]+(.+?)[ \t]*$', t, re.M):
            _defines.setdefault(m.group(1), m.group(2))


class _Names(dict):
    """names in a behaviour parameter expression: #defines, and the few enums that matter"""
    def __missing__(self, k):
        if _defines is None:
            _load_defines()
        if k in _defines:
            try:
                v = _eval(_defines[k])
            except Exception:
                v = 0
            self[k] = v
            return v
        m = re.fullmatch(r'STAR_INDEX_ACT_(\d+)', k)
        if m:
            return int(m.group(1)) - 1
        m = re.fullmatch(r'WARP_NODE_([0-9A-Fa-f]{2})', k)
        if m:
            return int(m.group(1), 16)
        m = re.fullmatch(r'DIALOG_(\d+)', k)
        if m:
            return int(m.group(1))
        return 0


_names = _Names()
_names.update({'BPARAM1': lambda a: (a & 0xFF) << 24, 'BPARAM2': lambda a: (a & 0xFF) << 16,
               'BPARAM3': lambda a: (a & 0xFF) << 8, 'BPARAM4': lambda a: a & 0xFF})


def _eval(expr):
    expr = re.sub(r'\(\s*(?:[su](?:8|16|32)|f32)\s*\)', '', expr)        # casts
    expr = re.sub(r'\b(0[xX][0-9A-Fa-f]+|\d+)[uUlL]+\b', r'\1', expr)   # integer suffixes
    return int(eval(expr, {'__builtins__': {}}, _names))


def bp_value(expr):
    """a level script's behaviour parameter, as the 32-bit number the game sees"""
    try:
        return _eval(expr) & 0xFFFFFFFF
    except Exception as e:
        print('   !! behaviour parameter not understood:', expr, e)
        return 0


# ---------------------------------------------------------------- trajectories
_traj_text = None


def trajectory(name):
    """[[flag, x, y, z], ...] with the closing entry as flag -1"""
    global _traj_text
    if _traj_text is None:
        _traj_text = ''
        for f in glob.glob(os.path.join(X.D, 'levels', '*', '**', '*.c'), recursive=True):
            t = open(f, encoding='utf-8', errors='replace').read()
            if 'Trajectory' in t:
                _traj_text += X.strip_comments(t) + '\n'
    m = re.search(r'const\s+Trajectory\s+' + re.escape(name) + r'\s*\[\s*\]\s*=\s*\{(.*?)\};', _traj_text, re.S)
    if not m:
        return None
    out = []
    for w in re.finditer(r'TRAJECTORY_POS\(\s*(-?\w+)\s*,\s*(-?\w+)\s*,\s*(-?\w+)\s*,\s*(-?\w+)\s*\)|TRAJECTORY_END', m.group(1)):
        if w.group(1) is None:
            out.append([-1, 0, 0, 0])
            break
        out.append([try_int(w.group(1)) or 0, int(w.group(2), 0), int(w.group(3), 0), int(w.group(4), 0)])
    if not out or out[-1][0] != -1:
        out.append([-1, 0, 0, 0])
    return out


# ---------------------------------------------------------------- templates
_dl_maps = {}


def dl_model(level, model):
    """'dl:<display list>:<layer>' for a model the level (or the game) loads straight from a display list"""
    if level not in _dl_maps:
        m = {}
        for path in (os.path.join(X.D, 'levels', level, 'script.c'), os.path.join(X.D, 'levels', 'scripts.c')):
            if not os.path.exists(path):
                continue
            t = X.strip_comments(open(path, encoding='utf-8', errors='replace').read())
            for mm in re.finditer(r'LOAD_MODEL_FROM_DL\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)', t):
                m.setdefault(mm.group(1), 'dl:%s:%s' % (mm.group(2), mm.group(3)))
        _dl_maps[level] = m
    return _dl_maps[level].get(model)


def template(db, textures, templates, finish, geo, col):
    """model + collision in the model's own space; returns the key it is stored under, or None"""
    if not geo:
        return None
    if geo == 'none':
        nodes = []                              # (collision only: a model-less solid object)
    elif geo.startswith('dl:'):
        _, dl, layer = geo.split(':')
        nodes = [{'cmd': 'GEO_DISPLAY_LIST', 'args': [layer, dl], 'children': []}]
    elif geo.startswith('dls:'):
        # (several display lists drawn together: 'dls:dl1:layer1;dl2:layer2')
        nodes = []
        for part in geo[4:].split(';'):
            dl, layer = part.split(':')
            nodes.append({'cmd': 'GEO_DISPLAY_LIST', 'args': [layer, dl], 'children': []})
    elif db.has('geo', geo):
        nodes = None
    else:
        return None
    key = '%s|%s' % (geo, col or '')
    if key not in templates:
        mesh = X.Mesh()
        mesh.xf = None
        mesh.cum = 1.0
        S.walk_static(db, nodes if nodes is not None else X.parse_geo(db, geo)['children'], S.rot_y_xf(0, (0, 0, 0)), mesh, textures)
        t = {'sections': finish(X.finish_sections(mesh))}
        if col:
            try:
                c = X.export_collision(db, col)
                t['collision'] = {'source': col, 'ntris': c['ntris'], 'pos': c['pos'], 'idx': c['idx']}
            except Exception as e:
                print('   !! no collision', col, e)
        templates[key] = t
    return key


def s8(v):
    return v - 256 if v > 127 else v


# LLL's Bowser puzzle (bowser_puzzle_piece.inc.c): each piece's moves (2 wait, 3 left, 4 right, 5 up, 6 down) and
# where it lies in its frame
BOWSER_PUZZLE_LISTS = {1: [2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 2], 2: [2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 2, 2], 5: [2, 2, 2, 5, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 6, 2, 2, 2], 6: [2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2], 10: [2, 2, 2, 2, 2, 5, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 6, 2, 2, 2, 2, 2], 9: [2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2], 13: [2, 2, 2, 2, 2, 2, 2, 5, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 6, 2, 2, 2, 2, 2, 2, 2], 12: [2, 2, 2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2], 8: [2, 2, 2, 2, 2, 2, 2, 2, 2, 6, 2, 2, 2, 2, 2, 2, 5, 2, 2, 2, 2, 2, 2, 2, 2, 2], 7: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 3: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 6, 2, 2, 5, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 4: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 11: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 14: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]}
BOWSER_PUZZLE_OFFSETS = {1: (-5, -15), 2: (5, -15), 3: (-15, -5), 4: (-5, -5), 5: (5, -5), 6: (15, -5), 7: (-15, 5), 8: (-5, 5), 9: (5, 5), 10: (15, 5), 11: (-15, 15), 12: (-5, 15), 13: (5, 15), 14: (15, 15)}


def s16deg(a):
    """a Mario 64 angle (0..0xFFFF) in degrees, -180..180"""
    a &= 0xFFFF
    return (a - 0x10000 if a >= 0x8000 else a) * 360.0 / 65536.0


def make(db, level, o, mgmap, textures, templates, finish, bhv_collision):
    """The platform objects for one level-script object, or None when it is not a moving platform."""
    b = o['bhv']
    if b not in HANDLED:
        return None
    bp = bp_value(o.get('bparam', '0'))
    b1, b2, w = (bp >> 24) & 0xFF, (bp >> 16) & 0xFF, (bp >> 16) & 0xFFFF
    geo = mgmap.get(o['model']) or dl_model(level, o['model'])
    base = {'kind': 'platform', 'pos': [o['x'], o['y'], o['z']], 'ang': [o['ax'], o['ay'], o['az']], 'bp': bp}

    def T(g, c):
        return template(db, textures, templates, finish, g, c)

    def one(bhv, tpl, **extra):
        if not tpl:
            print('   !! platform without a model:', b, o['model'])
            return []
        return [dict(base, bhv=bhv, tpl=tpl, **extra)]

    if b == 'bhvCapSwitch':
        # capswitch.inc.c: the switch at half size 71 up, its colour by the second parameter byte (cap_switch_geo's
        # switch case: red, green, blue, yellow), on its own base at half size
        col = b2 if b2 < 4 else 0
        top = T('dls:cap_switch_exclamation_seg5_dl_05002E00:LAYER_TRANSPARENT_DECAL;capswitch_seg5_dl_050033%s:LAYER_OPAQUE'
                % ['50', '70', '90', 'B0'][col], 'capswitch_collision_050033D0')
        bottom = T('dl:cap_switch_base_seg5_dl_05003120:LAYER_OPAQUE', 'capswitch_collision_05003448')
        out = []
        if bottom:
            out.append(dict(base, bhv='static', tpl=bottom, scale=[0.5, 0.5, 0.5]))
        if top:
            out.append(dict(base, bhv='cap_switch', tpl=top, pos=[o['x'], o['y'] + 71, o['z']], scale=[0.5, 0.5, 0.5],
                            colour=col))
        return out
    if b == 'bhvControllablePlatform':
        # controllable_platform.inc.c: HMC's metal platform and its four arrows (bhv_controllable_platform_init: 204
        # out to each side and 51 up; arrow 1 on the +z side, 2 on -z, 3 on +x, 4 on -x)
        out = one('ctrl_platform', T(geo, bhv_collision.get(b)))
        arrow = T(mgmap.get('MODEL_HMC_METAL_ARROW_PLATFORM'), bhv_collision.get('bhvControllablePlatformSub'))
        if out and arrow:
            for d, (dx, dz, yaw) in ((1, (0, 204, 0)), (2, (0, -204, 180)), (3, (204, 0, 90)), (4, (-204, 0, -90))):
                out.append(dict(base, bhv='ctrl_arrow', tpl=arrow, pos=[o['x'] + dx, o['y'] + 51, o['z'] + dz],
                                ang=[0, yaw, 0], dir=d, off=[dx, 51, dz]))
        return out
    if b == 'bhvTowerDoor':
        # tower_door.inc.c: the door in WF's tower, broken by a punch or a kick (platforms.lua B.tower_door)
        return one('tower_door', T(geo, bhv_collision.get(b)))
    if b == 'bhvKickableBoard':
        # kickable_board.inc.c: WF's plank on end - hit, it rocks; jump-kicked from up high, it falls flat into a
        # bridge (platforms.lua B.kick_board)
        return one('kick_board', T(geo, bhv_collision.get(b)))
    if b in ('bhvWFBreakableWallRight', 'bhvWFBreakableWallLeft'):
        # breakable_wall.inc.c: WF's two walls that Mario breaks shot from the cannon (platforms.lua B.wf_wall)
        return one('wf_wall', T(geo, bhv_collision.get(b)), right=(b == 'bhvWFBreakableWallRight'))
    if b == 'bhvWaterLevelPillar':
        # water_pillar.inc.c: the basement lake's two pillars, pounded to drain the moat (platforms.lua B.water_pillar)
        return one('water_pillar', T(geo, bhv_collision.get(b)))
    if b == 'bhvMoatGrills':
        # moat_grill.inc.c: the grill across the way into Vanish Cap Under the Moat, gone once the moat is drained
        return one('moat_grills', T(geo, bhv_collision.get(b)))
    if b == 'bhvPyramidTop':
        # pyramid_top.inc.c: Shifting Sand Land's pyramid's top piece, the lid on the way down to Eyerok - it spins
        # and blows apart once Mario has stood on the four pillars (platforms.lua B.pyramid_top)
        return one('pyramid_top', T(geo, bhv_collision.get(b)))
    if b == 'bhvSeesawPlatform':
        return one('seesaw', T(geo, SEESAW_COL[b2] if b2 < len(SEESAW_COL) else None))
    if b == 'bhvSquarishPathMoving':
        return one('squarish', T(geo, bhv_collision.get(b)))
    if b == 'bhvSlidingPlatform2':
        return one('slide2', T(geo, SLIDE2_COL[(w & 0x0380) >> 7]))
    if b == 'bhvFerrisWheelAxle':
        f = FERRIS[b2 if b2 < len(FERRIS) else 0]
        t2 = T(mgmap.get(f[2]), f[1])
        return one('ferris', T(geo, f[0]), tpl2=t2) if t2 else []
    if b == 'bhvOctagonalPlatformRotating':
        return one('spin', T(geo, OCT_COL[b2 if b2 < len(OCT_COL) else 0]), avel=OCT_VEL[b1 & 3])
    if b == 'bhvRotatingPlatform':
        sc, col = ROT_PLAT[b2 if b2 < len(ROT_PLAT) else 0]
        return one('spin', T(geo, col), avel=s8(b1) << 4, scale=[sc, sc, sc])
    if b == 'bhvWFRotatingWoodenPlatform':
        return one('wf_wood', T(geo, bhv_collision.get(b)))
    if b == 'bhvPlatformOnTrack':
        ptype = (w & 0x70) >> 4
        path = trajectory(TRACK_PATHS[w & 0xF]) if (w & 0xF) < len(TRACK_PATHS) else None
        if not path:
            print('   !! no path for', b, hex(bp))
            return []
        extra = {'path': path, 'ptype': ptype}
        if ptype == 2:
            extra['scale'] = [1.0, 2.0, 1.0]
        return one('track', T(geo, TRACK_COL[ptype] if ptype < len(TRACK_COL) else None), **extra)
    if b == 'bhvCheckerboardElevatorGroup':
        return one('checker', T(mgmap.get('MODEL_CHECKERBOARD_PLATFORM'), CHECKER_COL))
    if b in ('bhvRRElevatorPlatform', 'bhvHMCElevatorPlatform', 'bhvMeshElevator'):
        h = ELEVATOR_H[b2 if b2 < len(ELEVATOR_H) else 0]
        return one('elevator', T(geo, bhv_collision.get(b)), low=h[0], high=h[1], fixed=h[2], rr=(b == 'bhvRRElevatorPlatform'))
    if b == 'bhvAnimatesOnFloorSwitchPress':
        # animated_floor_switch.inc.c: drawn folded away until the purple switch beside it is pressed, then out for good
        # (platforms.lua B.switch_stairs: both ends of its animation, one shown at a time)
        i = b2 if b2 < len(STAIRS) else 0
        col, model = STAIRS[i]
        col_in, model_in = STAIRS_IN[i]
        return (one('switch_stairs', T(mgmap.get(model) or geo, col), out=True) +
                one('switch_stairs', T(mgmap.get(model_in) or geo, col_in), out=False))
    if b == 'bhvFloorSwitchAnimatesObject':
        # the purple switch that brings those stairs out: once pressed it stays down (its second parameter byte 0)
        return one('purple_switch', T(geo, 'purple_switch_seg8_collision_0800C7A8'), scale=[1.5, 1.5, 1.5], stays=True)
    if b in ('bhvThwomp', 'bhvThwomp2', 'bhvGrindel'):
        # rising and slamming down, over and over (thwomp.inc.c); thwomps are drawn at 1.4
        if b == 'bhvGrindel':
            return one('thwomp', T(geo, bhv_collision.get(b)), grindel=True)
        return one('thwomp', T(geo, bhv_collision.get(b)), scale=[1.4, 1.4, 1.4])
    if b == 'bhvHorizontalGrindel':
        # the pyramid's hopping grindels (horizontal_grindel.inc.c), drawn at 0.9
        return one('hgrindel', T(geo, bhv_collision.get(b)), scale=[0.9, 0.9, 0.9])
    if b == 'bhvSpindel':
        # the pyramid's rolling spiked log (spindel.inc.c)
        return one('spindel', T(geo, bhv_collision.get(b)))
    if b in ('bhvSunkenShipPart2', 'bhvInSunkenShip', 'bhvInSunkenShip2'):
        # JRB's sunken ship (act 1): its halves to look at, and its collision; the wreck lies tilted
        # (bhvSunkenShipSetRotation: pitch 0xE958, yaw 0xEE6C, roll 0x0C80)
        tilt = [s16deg(0xE958), s16deg(0xEE6C), s16deg(0x0C80)]
        if b == 'bhvSunkenShipPart2':
            return one('static', T(geo, None), ang=tilt)
        return one('static', T('none', bhv_collision.get(b)), ang=tilt)
    if b == 'bhvShipPart3':
        # the risen ship's parts (acts 2-6), rocking on the water (jrb_ship.inc.c bhv_ship_part_3_loop)
        return one('ship_rock', T(geo, None))
    if b == 'bhvSnowMoundSpawn':
        # Snowman's Land's sliding snow mounds (snow_mound.inc.c): a spawner that sends them over the icy water
        return one('snow_mound', T(mgmap.get('MODEL_SL_SNOW_TRIANGLE'), 'sl_seg7_collision_sliding_snow_mound'))
    if b == 'bhvSLWalkingPenguin':
        # Snowman's Land's big penguin (sl_walking_penguin.inc.c), six times a penguin's size, walking the ice
        # bridge: his collision here (to stand on), his animated model drawn by the platform (B.walk_penguin)
        return one('walk_penguin', T('none', bhv_collision.get(b)), scale=[6.0, 6.0, 6.0])
    if b == 'bhvJRBSlidingBox':
        # the box on the risen ship's deck, sliding up and down it as the ship rocks (jrb_ship.inc.c)
        return one('slide_box', T(geo, bhv_collision.get(b)))
    if b == 'bhvInSunkenShip3':
        # the risen ship's deck and hull, rocking with its parts
        return one('ship_rock', T('none', bhv_collision.get(b)))
    if b == 'bhvTiltingBowserLavaPlatform':
        # (its script turns it back to yaw 0: SET_INT(oFaceAngleYaw, 0))
        return one('bowser_tilt', T(geo, bhv_collision.get(b)), ang=[0, 0, 0])
    if b in ('bhvTHIHugeIslandTop', 'bhvTHITinyIslandTop'):
        return one('thi_top', T(geo, bhv_collision.get(b)), tiny=(b == 'bhvTHITinyIslandTop'))
    if b == 'bhvUkikiCage':
        return one('ukiki_cage', T(geo, bhv_collision.get(b)), star_id=(bp >> 24) & 0xFF)
    if b == 'bhvDorrie':
        return one('dorrie', T(geo, bhv_collision.get(b)))
    if b == 'bhvWhirlpool':
        # DDD's whirlpool's swirl (a display list), spinning
        return one('whirlpool', T(geo, None))
    if b == 'bhvToxBox':
        return one('tox_box', T(geo, bhv_collision.get(b)))
    if b == 'bhvLLLDrawbridgeSpawner':
        # two halves 640 either side, the second turned round (bhv_lll_drawbridge_spawner_loop)
        tpl = T(geo, 'lll_seg7_collision_drawbridge')
        a = o['ay'] * math.pi / 180.0
        out = []
        for k in (1, -1):
            out += one('drawbridge', tpl, pos=[o['x'] + math.cos(a) * 640.0 * k, o['y'], o['z'] + math.sin(a) * 640.0 * k],
                       ang=[0, o['ay'] + (0 if k == 1 else 180), 0])
        return out
    if b == 'bhvLLLFloatingWoodBridge':
        # three planks 300 apart along it, 100 down, bobbing out of step (bhv_lll_floating_wood_bridge_loop)
        tpl = T(mgmap.get('MODEL_LLL_WOOD_BRIDGE'), 'lll_seg7_collision_wood_piece')
        a = o['ay'] * math.pi / 180.0
        out = []
        for i in (1, 2, 3):
            d = (i - 2) * 300.0
            out += one('wood_piece', tpl, pos=[o['x'] + d * math.cos(a), o['y'] - 100.0, o['z'] - d * math.sin(a)], phase=i * 0x1000)
        return out
    if b == 'bhvLLLBowserPuzzle':
        # the fourteen pieces (sBowserPuzzlePieces: offsets in tenths of a 480 cell, 50 up), each with its list of moves
        out = []
        for n in range(1, 15):
            tpl = T(mgmap.get('MODEL_LLL_BOWSER_PIECE_%d' % n), 'lll_seg7_collision_puzzle_piece')
            ox, oz = BOWSER_PUZZLE_OFFSETS[n]
            if tpl:
                out.append(dict(base, bhv='puzzle_piece', tpl=tpl, pos=[o['x'] + ox * 48.0, o['y'] + 50, o['z'] + oz * 48.0],
                                ang=[0, 0, 0], moves=BOWSER_PUZZLE_LISTS[n], piece=n, home=[o['x'], o['y'], o['z']]))
        return out
    if b == 'bhvCoffinSpawner':
        # six coffins in two rows (coffin.inc.c coffinRelativePos), the far row turned round; every other one stands up
        tpl = T(mgmap.get('MODEL_BBH_WOODEN_TOMB'), 'bbh_seg7_collision_coffin')
        out = []
        a = o['ay'] * math.pi / 180.0
        for i, (rx, rz) in enumerate([(412, -150), (762, -150), (1112, -150), (412, 150), (762, 150), (1112, 150)]):
            x = o['x'] + rx * math.cos(a) + rz * math.sin(a)
            z = o['z'] - rx * math.sin(a) + rz * math.cos(a)
            if tpl:
                out.append(dict(base, bhv='coffin', tpl=tpl, pos=[round(x, 2), o['y'], round(z, 2)],
                                ang=[0, o['ay'] + (180 if rz > 0 else 0), 0], scale=[1.0, 1.1, 1.0], order=i))
        return out
    if b == 'bhvHauntedBookshelf':
        # BBH's library shelf: slides back once the books are hit in order
        return one('bookshelf', T(geo, bhv_collision.get(b)))
    if b == 'bhvHauntedBookshelfManager':
        # the shelf's three books (bhvBookSwitch: D_80331B30, offsets turned by the manager's yaw), in the order to hit;
        # drawn 2 wide and 0.9 high
        book = T(mgmap.get('MODEL_BOOKEND') or 'bookend_geo', None)
        out = one('book_mgr', T('none', None))
        a = o['ay'] * math.pi / 180.0
        for i, (rx, ry) in enumerate([(52, 150), (135, 3), (-75, 78)]):
            x, z = o['x'] + rx * math.cos(a), o['z'] - rx * math.sin(a)
            if book:
                out.append(dict(base, bhv='book_switch', tpl=book, pos=[round(x, 2), o['y'] + ry, round(z, 2)],
                                ang=[0, o['ay'], 0], scale=[2.0, 0.9, 1.0], order=i))
        return out
    if b == 'bhvRRCruiserWing':
        return one('rr_wing', T(geo, None))
    if b == 'bhvFallingBowserPlatform':
        return one('bowser_plat', T(geo, BOWSER3_COL[b2] if 0 < b2 < len(BOWSER3_COL) else None))
    if b in CHESTS:
        chests, star, bubble = CHESTS[b]
        base_t = T(mgmap.get('MODEL_TREASURE_CHEST_BASE'), None)
        lid_t = T(mgmap.get('MODEL_TREASURE_CHEST_LID'), None)
        if not (base_t and lid_t):
            return []
        group = '%s,%d,%d' % (b, o['x'], o['z'])
        out = []
        for order, x, y, z, yaw in chests:
            a = yaw * math.pi / 32768.0
            # the lid: 102 up and 77 back from the chest's middle (bhv_treasure_chest_bottom_init)
            lx, lz = x + (-77) * math.sin(a), z + (-77) * math.cos(a)
            deg = yaw * 360.0 / 65536.0
            common = {'group': group, 'order': order, 'star': list(star) if star else None, 'star_id': (bp >> 24) & 0xFF,
                      'bubble': bubble}
            out.append(dict(base, bhv='chest', tpl=base_t, pos=[x, y, z], ang=[0, deg, 0], **common))
            out.append(dict(base, bhv='chest_lid', tpl=lid_t, pos=[lx, y + 102, lz], ang=[0, deg, 0], **common))
        return out
    if b == 'bhvTowerPlatformGroup':
        # eight round the tower, 704 out, 45 degrees and 100 up apart (spawn_wf_platform_group)
        sq = T(mgmap.get('MODEL_WF_TOWER_SQUARE_PLATORM'), 'wf_seg7_collision_platform')
        lift = T(mgmap.get('MODEL_WF_TOWER_SQUARE_PLATORM_ELEVATOR'), 'wf_seg7_collision_platform')
        out = []
        for i, kind in enumerate(('static', 'tower_slide', 'static', 'tower_slide', 'static', 'tower_slide', 'static', 'tower_elev')):
            yaw = i * 0x2000
            a = yaw * math.pi / 32768.0
            tpl = lift if kind == 'tower_elev' else sq
            if tpl:
                out.append(dict(base, bhv=kind, tpl=tpl, pos=[o['x'] + 704.0 * math.sin(a), o['y'] + 100.0 * i, o['z'] + 704.0 * math.cos(a)],
                                ang=[0, yaw * 360.0 / 65536.0, 0]))
        return out
    if b == 'bhvDonutPlatformSpawner':
        tpl = T(mgmap.get('MODEL_RR_DONUT_PLATFORM'), 'rr_seg7_collision_donut_platform')
        s16 = lambda v: v - 0x10000 if v >= 0x8000 else v
        return [dict(base, bhv='donut', tpl=tpl, pos=[o['x'] + s16(dx), o['y'] + s16(dy), o['z'] + s16(dz)])
                for dx, dy, dz in DONUTS] if tpl else []
    if b == 'bhvOpenableGrill':
        # grill_door.inc.c: two barred doors half its width either side, the first turned round, which the purple
        # switch beside it (bhvFloorSwitchGrills) swings open, 0x100 a frame for 64 frames, opposite ways
        half, model, col = GRILLS[b2 if b2 < len(GRILLS) else 0]
        tpl = T(mgmap.get(model), col)
        if not tpl:
            return []
        ya = math.radians(o['ay'])
        out = []
        for rel, turn, sign in ((half, 180, 1), (-half, 0, -1)):
            dx, dz = rel * math.cos(ya), -rel * math.sin(ya)
            out.append(dict(base, bhv='grill_door', tpl=tpl, pos=[o['x'] + dx, o['y'], o['z'] + dz],
                            ang=[o['ax'], o['ay'] + turn, o['az']], turn=sign, jingle=(b2 == 1)))
        return out
    if b == 'bhvFloorSwitchGrills':
        # the purple switch that opens them: stays down once pressed
        return one('purple_switch', T(geo, 'purple_switch_seg8_collision_0800C7A8'), scale=[1.5, 1.5, 1.5], stays=True)
    if b == 'bhvCastleFloorTrap':
        # two panels 358 either side, the second turned round (bhv_castle_floor_trap_init)
        tpl = T(mgmap.get('MODEL_CASTLE_BOWSER_TRAP'), 'inside_castle_seg7_collision_floor_trap')
        if not tpl:
            return []
        ya = math.radians(o['ay'])
        out = []
        for rel, turn in ((-358, 0), (358, 180)):
            dx, dz = rel * math.cos(ya), -rel * math.sin(ya)
            out.append(dict(base, bhv='floor_trap', tpl=tpl, pos=[o['x'] + dx, o['y'], o['z'] + dz],
                            ang=[o['ax'], o['ay'] + turn, o['az']], group='%d,%d' % (o['x'], o['z'])))
        return out
    if b in ('bhvClockMinuteHand', 'bhvClockHourHand'):
        return one('spin_roll', T(geo, None), av=(-0x180 if b == 'bhvClockMinuteHand' else -0x20))
    if b == 'bhvDecorativePendulum':
        return one('deco_pendulum', T(geo, None))
    if b in ('bhvTumblingBridge', 'bhvBBHTumblingBridge'):
        n, first, step, model, col = TUMBLING.get(1 if b == 'bhvBBHTumblingBridge' else b2, TUMBLING[0])
        tpl = T(mgmap.get(model), col)
        if not tpl:
            print('   !! tumbling bridge without its plank:', model)
            return []
        out = []
        for i in range(n):
            d = first + step * i
            dx, dz = (d, 0) if b2 == 3 else (0, d)
            out.append(dict(base, bhv='tumble_plank', tpl=tpl, pos=[o['x'] + dx, o['y'], o['z'] + dz]))
        return out
    if b in SIMPLE_MOVERS:
        return one(SIMPLE_MOVERS[b], T(geo, bhv_collision.get(b)), ttm=(b == 'bhvTTMRollingLog'))
    if b in ('bhvSmallBomp', 'bhvLargeBomp'):
        return one('bomp', T(geo, bhv_collision.get(b)), big=(b == 'bhvLargeBomp'))
    if b == 'bhvPushableMetalBox':
        return one('metal_box', T(geo, bhv_collision.get(b) or 'metal_box_seg8_collision_08024C28'))
    if b == 'bhvHiddenObject':
        # (the game shows a hidden box as the small cork box model)
        if b2 == 0:
            return one('hidden', T(mgmap.get('MODEL_BREAKABLE_BOX_SMALL') or geo, 'breakable_box_seg8_collision_08012D70'), box=True)
        return one('hidden', T(geo, 'wdw_seg7_collision_07018528'))
    if b == 'bhvFloorSwitchHiddenObjects':
        return one('purple_switch', T(geo, 'purple_switch_seg8_collision_0800C7A8'), scale=[1.5, 1.5, 1.5])
    if b == 'bhvWaterBombCannon':
        # water_bomb_cannon.inc.c: BoB's act-1 cannon, standing in the start's cannon hole where the lid is in the other
        # acts (platforms.lua B.wbomb_cannon adds its barrel). Its model is the cannon's base; it has no collision of
        # its own (it pushes Mario off a cylinder).
        return one('wbomb_cannon', T(geo, None))
    if b == 'bhvCannonClosed':
        # the lid over a cannon's hole: a Bob-omb Buddy opens it (platforms.lua B.cannon)
        return one('cannon', T(geo, bhv_collision.get(b)))
    if b == 'bhvCannon':
        # a cannon with no lid (macro_cannon_open: the castle grounds' one, by the moat): open from the start - the lid
        # model only stands in for it and is never shown (B.cannon, o.open). Under the grill until 120 stars.
        return one('cannon', T(mgmap.get('MODEL_DL_CANNON_LID') or dl_model(level, 'MODEL_DL_CANNON_LID'),
                               bhv_collision.get('bhvCannonClosed')), open=True)
    if b in ('bhvBowsersSub', 'bhvBowserSubDoor'):
        # ddd_sub.inc.c: Bowser's sub in DDD and the door by it, gone once the second key is had (B.gone_key2) - DDD's
        # poles come in its place (poles.lua). Both were baked into DDD for good.
        return one('gone_key2', T(geo, bhv_collision.get(b)))
    if b == 'bhvHiddenAt120Stars':
        # castle_cannon_grate.inc.c: the grill over the castle grounds' cannon, gone once the file has 120 stars
        # (B.hidden_120). It was baked into the grounds for good.
        return one('hidden_120', T(geo, bhv_collision.get(b)))
    if b == 'bhvMontyMoleHole':
        return one('static', T(geo, None))
    if b == 'bhvWoodenPost':
        # (bhvWoodenPost: SCALE(0, 50) - every post at half the model's size, its collision too; it was built whole, twice
        # as big as Mario 64's: "why are these posts huge?", 2026-10-16)
        return one('wpost', T(geo, bhv_collision.get(b) or 'poundable_pole_collision_06002490'), scale=[0.5, 0.5, 0.5])
    if b == 'bhvBlueCoinSwitch':
        # (drawn three times its size: the game scales it so every frame)
        return one('blue_switch', T(geo, bhv_collision.get(b)), scale=[3.0, 3.0, 3.0])
    if b.startswith('bhvTTC'):
        # Tick Tock Clock (ttc_*.inc.c)
        if b == 'bhvTTCRotatingSolid':
            return one('ttc_solid', T(geo, TTC_COL[b][b2 & 1]))
        if b == 'bhvTTCTreadmill':
            return one('ttc_treadmill', T(geo, TTC_COL[b][b2 & 1]))
        if b == 'bhvTTCCog':
            return one('ttc_cog', T(geo, TTC_COL[b][(b2 & 2) >> 1]))
        if b == 'bhvTTCPitBlock':
            return one('ttc_pit', T(geo, TTC_COL[b][b2 & 1]))
        if b == 'bhvTTC2DRotator':
            # the hands are solid; the gears only turn
            return one('ttc_rotator', T(geo, bhv_collision.get(b) if b2 == 0 else None))
        kind = {'bhvTTCPendulum': 'ttc_pendulum', 'bhvTTCMovingBar': 'ttc_bar', 'bhvTTCElevator': 'ttc_elevator',
                'bhvTTCSpinner': 'ttc_spinner'}[b]
        return one(kind, T(geo, bhv_collision.get(b)))
    if b == 'bhvChainChompGate':
        # Bob-omb Battlefield's gate: standing still, but a piece of its own, so that the chain chomp can break it
        return one('static', T(geo, 'bob_seg7_collision_chain_chomp_gate'), gate='chomp')
    if b == 'bhvActivatedBackAndForthPlatform':
        ptype = (w & 0x0300) >> 8
        return one('bf', T(geo, BF_COL[ptype] if ptype < len(BF_COL) else None), ptype=ptype)
    return None
