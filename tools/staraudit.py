"""Every course star Mario 64 places (script objects and macro objects that carry a star index), and whether the
mod's exported scenes have something for it. python tools/staraudit.py   (from X:/mashup-work)"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luadata

MOD = 'E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data'
COURSES = ['bob', 'wf', 'jrb', 'ccm', 'bbh', 'hmc', 'lll', 'ssl', 'ddd', 'sl', 'wdw', 'ttm', 'thi', 'ttc', 'rr',
           'bitdw', 'bitfs', 'bits', 'pss', 'cotmc', 'totwc', 'vcutm', 'wmotr', 'sa']
STAR_BHV = re.compile(r'Star|Koopa$|KingBobomb|WhompKing|BigBully|ChillBully|Eyerok|Wiggler|Klepto|MrI|BigBoo|'
                      r'MerryGoRound|BalconyBigBoo|TuxiesMother|RacingPenguin|SnowmansHead|MantaRay|JetStreamRing|'
                      r'TreasureChests|Unagi|UkikiCage|FirePiranha|ExclamationBox|Ukiki|BigBoulder|Snufit|Bowser')

src = ''
for f in glob.glob('*.lua'):
    if '.before' not in f:
        src += open(f, encoding='utf-8', errors='ignore').read()


def star_of(bp):
    m = re.search(r'STAR_INDEX_ACT_(\d)', bp)
    if m:
        return int(m.group(1)) - 1
    m = re.search(r'EXCLAMATION_BOX_BP_STAR_ACT_(\d)', bp)
    if m:
        return int(m.group(1)) - 1
    try:
        v = int(bp, 0)
        return (v >> 24) & 0xFF
    except ValueError:
        return None


for lvl in COURSES:
    places = []
    for f in [f'sm64decomp/levels/{lvl}/script.c'] + glob.glob(f'sm64decomp/levels/{lvl}/areas/*/script.c'):
        if not os.path.exists(f):
            continue
        for line in open(f):
            m = re.search(r'/\*bhvParam\*/\s*(.*?),\s*/\*bhv\*/\s*(bhv\w+)', line)
            if m and STAR_BHV.search(m.group(2)):
                places.append((m.group(2), m.group(1).strip()))
    have = {}
    for f in glob.glob(f'{MOD}/scene_{lvl}.lua') + glob.glob(f'{MOD}/scene_{lvl}_*.lua'):
        d = luadata.load(f)
        for o in d.get('objects', []):
            k = o.get('kind')
            if k in ('star', 'red_coin_star', 'secret_star', 'slide_star'):
                have.setdefault(int(o.get('id', 0)), []).append(k)
            elif k == 'enemy' and o.get('type'):
                bp = int(o.get('bp', 0) or 0)
                have.setdefault(('en', o['type']), []).append((bp >> 24) & 0xFF)
            elif k == 'platform' and o.get('bhv'):
                have.setdefault(('pl', o['bhv']), []).append(o.get('star_id'))
            elif k == 'box':
                have.setdefault(('box',), []).append(o.get('content'))
    print('==', lvl)
    for b, bp in places:
        s = star_of(bp)
        got = have.get(s) if b in ('bhvStar', 'bhvHiddenRedCoinStar', 'bhvHiddenStar', 'bhvCCMTouchedStarSpawn',
                                   'bhvBowserCourseRedCoinStar') else None
        en = have.get(('en', b))
        named = bool(re.search(r'\b' + b + r'\b', src))
        print('   %-28s star %-4s %-20s scene:%s enemy:%s code:%s' % (b, s, bp[:20], got, en, named))
