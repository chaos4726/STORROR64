"""Mario 64's pause screen, read out of the player's own copy of the game.

Pausing in a course, Mario 64 shades the picture and shows the course's number and name, the star being
played for, MY SCORE (the course's stars and best coin count) and the choices CONTINUE, EXIT COURSE and SET
CAMERA ANGLE WITH R, with a white pointer. Pausing in the castle shows PAUSE in the counters' lettering and a
box with one course at a time: its name, its stars and its coin score. This writes the words as pictures in
the game's own lettering (white, as the pause screen draws them), the pointer, and where each word goes:

  textures/pause_t_*.png    each word or line: COURSE, MY SCORE, the choices, every course name, every star's
                            name, the digits, the star and coin signs. Four pixels to one of the game's.
  textures/pause_pointer.png, pause_arrow_up.png, pause_arrow_down.png, pause_white.png
  textures/hud_P/A/U/S.png  the counters' letters PAUSE needs (hud_E.png is there already)
  data/pause.lua            each picture's width in the game's pixels, and which course each scene belongs to

(the mod adds one choice of its own, SWITCH MENU, to go over to STORROR's pause menu: it is set in the same
lettering.)

Usage: python pausex.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, re, sys, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import introx
from PIL import Image, ImageDraw

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
D = introx.D
K = 4

FIXED = {
    'course': 'COURSE', 'my_score': 'MY SCORE', 'continue': 'CONTINUE', 'exit_course': 'EXIT COURSE',
    'camera_r': 'SET CAMERA ANGLE WITH R', 'switch_menu': 'SWITCH MENU',
    # (the mod's own: to the castle's entrance hall - EXIT COURSE puts him outside the course's painting)
    'exit_castle': 'EXIT TO CASTLE',
    'star': '★', 'star_open': '☆', 'coin_x': '$×', 'star_x': '★×',
    # (the mod's own: which pause menu Start opens, shown when the View button changes it)
    'start_storror': 'START: STORROR MENU', 'start_mario': 'START: MARIO 64 MENU',
    # (the course-complete screen's: a Bowser course's "<name> CLEAR")
    'clear': 'CLEAR',
}


def course_table():
    """names and star names from text/us/courses.h: ({course number: name}, {course number: [six star names]})"""
    t = open(os.path.join(D, 'text', 'us', 'courses.h'), encoding='utf-8').read()
    order = re.findall(r'DEFINE_(?:BONUS_)?COURSE\((COURSE_\w+)', open(os.path.join(D, 'levels', 'course_defines.h'), encoding='utf-8').read())
    number = {c: i for i, c in enumerate(order)}           # COURSE_NONE is 0, COURSE_BOB 1, ...
    names, acts = {}, {}
    for m in re.finditer(r'COURSE_ACTS\((COURSE_\w+),\s*_\("(.*?)"\),(.*?)\)\)\s*\n', t, re.S):
        n = number[m.group(1)]
        names[n] = m.group(2)
        acts[n] = re.findall(r'_\("(.*?)"', m.group(3))
    for m in re.finditer(r'SECRET_STAR\((COURSE_\w+),\s*_\("(.*?)"\)\)', t):
        names[number[m.group(1)]] = m.group(2)
    secret = re.search(r'CASTLE_SECRET_STARS\(_\("(.*?)"\)\)', t).group(1)
    return number, names, acts, secret


def level_courses(number):
    """the mod's scene names (level folder, with the mod's own names for the castle's parts) -> course number"""
    t = open(os.path.join(D, 'levels', 'level_defines.h'), encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'DEFINE_LEVEL\(\s*"[^"]*",\s*LEVEL_\w+,\s*(COURSE_\w+),\s*(\w+),', t):
        course, folder = m.group(1), m.group(2)
        if number.get(course, 0) > 0 and folder != 'ending':
            out[{'bowser_1': 'bowser'}.get(folder, folder)] = number[course]
    return out


def text_picture(font, text):
    """one line in white, its first letter's cell at the left edge: (picture, advance in the game's pixels)"""
    codes = font.encode(text)
    adv = sum(font.widths[c] for c in codes)
    width = max(adv, (adv - font.widths[codes[-1]] + 8) if codes else 1)
    canvas = Image.new('RGBA', (max(1, width) * K, 16 * K), (0, 0, 0, 0))
    font.draw(canvas, 0, 0, text, (255, 255, 255))
    return canvas, adv


def triangle(points, size):
    """a white triangle, `points` in the game's pixels within a `size` box, drawn smooth"""
    S = 4
    big = Image.new('L', (size[0] * K * S, size[1] * K * S), 0)
    ImageDraw.Draw(big).polygon([(x * K * S, y * K * S) for x, y in points], fill=255)
    a = big.resize((size[0] * K, size[1] * K), Image.LANCZOS)
    im = Image.new('RGBA', a.size, (255, 255, 255, 0))
    im.putalpha(a)
    return im


def main():
    os.makedirs(TEXD, exist_ok=True)
    os.makedirs(DATA, exist_ok=True)
    font = introx.Font()
    number, names, acts, secret = course_table()
    widths = {}

    def put(key, text):
        im, adv = text_picture(font, text)
        im.save(os.path.join(TEXD, 'pause_t_%s.png' % key))
        widths[key] = (adv, im.size[0] // K)

    for key, text in FIXED.items():
        put(key, text)
    for d in range(10):
        put('d_%d' % d, str(d))
    for n in range(1, 16):
        put('num_%d' % n, str(n))
    for n, name in names.items():
        if name.strip():
            put('cname_%d' % n, name[3:])           # (in a course: the name without its number)
            if n <= 15:
                put('cfull_%d' % n, name)           # (in the castle's box: with it)
    put('secret', secret)
    # (the course-complete screen's name for a castle secret star: the act table's first extra line)
    t = open(os.path.join(D, 'text', 'us', 'courses.h'), encoding='utf-8').read()
    put('secret_got', re.search(r'EXTRA_TEXT\(0,\s*_\("(.*?)"\)\)', t).group(1))
    for n, six in acts.items():
        for a, act in enumerate(six):
            put('act_%d_%d' % (n, a + 1), act)

    # the pointer (game/segment2's triangle: (0,0) (8,8) (0,16), y up) and the castle box's up and down arrows
    # (the same turned a quarter each way)
    triangle([(0, 16), (8, 8), (0, 0)], (8, 16)).save(os.path.join(TEXD, 'pause_pointer.png'))
    triangle([(0, 8), (8, 0), (16, 8)], (16, 8)).save(os.path.join(TEXD, 'pause_arrow_up.png'))
    triangle([(0, 0), (8, 8), (16, 0)], (16, 8)).save(os.path.join(TEXD, 'pause_arrow_down.png'))
    Image.new('RGBA', (4, 4), (255, 255, 255, 255)).save(os.path.join(TEXD, 'pause_white.png'))

    # PAUSE in the counters' lettering (and the course-complete screen's HI SCORE and CONGRATULATIONS)
    seg2 = open(os.path.join(D, 'bin', 'segment2.c'), encoding='utf-8', errors='replace').read()
    for ch in sorted(set('PAUSE' + 'HISCORE' + 'CONGRATULATIONS')):
        m = re.search(r'texture_hud_char_%s\[\]\s*=\s*\{\s*#include "([^"]+)\.inc\.c"' % ch, seg2)
        shutil.copy(os.path.join(D, m.group(1) + '.png'), os.path.join(TEXD, 'hud_%s.png' % ch))

    courses = level_courses(number)
    lines = ['-- Mario 64\'s pause screen (exporter/pausex.py). widths: the line\'s advance and its picture\'s width,',
             '-- in the game\'s pixels (the pictures are 4 pixels to one, 16 of the game\'s tall).',
             'return {', '  widths = {']
    for key in sorted(widths):
        lines.append('    %s = { %d, %d },' % (key, widths[key][0], widths[key][1]))
    lines.append('  },')
    lines.append('  space = %d,' % font.widths[font.encode(' ')[0]])
    lines.append('  courses = {')
    for scene in sorted(courses):
        lines.append('    %s = %d,' % (scene, courses[scene]))
    lines.append('  },')
    lines.append('}')
    open(os.path.join(DATA, 'pause.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    print('pause: %d pictures, %d scenes with a course' % (len(widths), len(courses)))


if __name__ == '__main__':
    main()
