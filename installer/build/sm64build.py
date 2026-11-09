#!/usr/bin/env python3
"""sm64build: every Super Mario 64 file the STORROR x SM64 mod needs, made on the player's own PC from their own ROM.

The mod ships with none of the game's content ("there can be absolutely nothing from sm64 in the mod folder until the
game is received from the user", 2026-11-01). The installer checks the player's ROM, downloads the public SM64
decompilation's source (which holds no game pictures or sounds), and runs this, which runs the mod's exporter scripts
in order: the ROM's pictures pulled out into the decomp tree, then the levels, actors, dialog, menus and the rest
written into the mod folder.

Usage: sm64build.py <rom.z64> <decomp dir> <mod dir> [--exporter <dir>] [--tools <dir>] [--from <step>] [--only <step>]
Prints one line a step ("STEP n/N name"), then "DONE" or "FAILED <step>: <why>".
"""
import os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def args():
    a = sys.argv[1:]
    opt = {'exporter': os.path.join(HERE, 'exporter'), 'tools': os.path.join(HERE, 'tools'), 'from': None, 'only': None}
    pos = []
    i = 0
    while i < len(a):
        if a[i].startswith('--'):
            opt[a[i][2:]] = a[i + 1]
            i += 2
        else:
            pos.append(a[i])
            i += 1
    if len(pos) != 3:
        sys.exit(__doc__)
    return pos[0], pos[1], pos[2], opt


ROM, DECOMP, MOD, OPT = args()
ROM, DECOMP, MOD = (os.path.abspath(p) for p in (ROM, DECOMP, MOD))
EXP, TOOLS = os.path.abspath(OPT['exporter']), os.path.abspath(OPT['tools'])
ROOT = os.path.abspath(OPT.get('root') or os.path.join(EXP, '..'))   # (the few generators kept at the top of the work folder)
OLD_EXP = os.path.abspath(OPT.get('old') or os.path.join(EXP, '..', 'exporter_old'))
TRACKS = os.path.abspath(OPT.get('tracks') or os.path.join(EXP, '..', 'tracks'))
TEX = os.path.join(MOD, 'textures')
DATA = os.path.join(MOD, 'Scripts', 'data')
ENV = dict(os.environ, SM64_DECOMP=DECOMP, SM64_OUT=MOD, SM64_ROM=ROM, SM64_MOD=MOD, PYTHONIOENCODING='utf-8')


def py(script, *a, where=None):
    """a script of the exporter (or tools), run as it was run when the mod was made: from its own folder"""
    path = os.path.join(where or EXP, script)
    return [sys.executable, '-X', 'utf8', path] + [str(x) for x in a]


# the steps, in order: (name, command)
STEPS = [
    ('textures from the ROM', py('extract_textures.py', ROM, DECOMP)),
    ('levels and actors', py('build_all.py')),
]
for s in ('ampx', 'bubbax', 'cannonx', 'capx', 'dorriex', 'flagx', 'heartx', 'keyunlockx', 'koopax', 'leafx', 'mistx',
          'pokeyx', 'shellx', 'snowx', 'wigglerx', 'butterflyx', 'groundsx', 'starselx', 'introx', 'endingx'):
    STEPS.append((s, py(s + '.py')))
# data/extra_statics.lua: begun by lll_statics, added to by the others
STATICS = os.path.join(DATA, 'extra_statics.lua')
STEPS += [
    ('lll_statics', py('lll_statics.py')),
    ('dorrie_low', py('dorrie_low.py')),          # (hmc's, second in the file, as the mod has it)
    ('ttm_statics', py('ttm_statics.py', STATICS, where=TOOLS)),
    ('ttm_painting', py('ttm_painting.py', MOD, where=TOOLS)),
    ('thi_pipes', py('thi_pipes.py', STATICS, where=TOOLS)),
]
for s in ('icex', 'movtexx', 'slidex', 'slide_patches', 'spawnx', 'talkx', 'dialogx', 'doornumx',
          'bowserintrox', 'pausex', 'headx'):
    STEPS.append((s, py(s + '.py')))
STEPS += [
    ('extra actors', py('extra_actorsx.py')),
    ('camera bounds', py('cambounds.py')),
    ('shadow sizes', py('shadowsx.py')),
    ('paintings', py('paintx.py', where=ROOT) + ['>', os.path.join(DATA, 'paint_ripples.lua')]),
    ('rooms bbh', py('roomgeo.py', 'bbh', 1, 'bbh')),
    ('rooms hmc', py('roomgeo.py', 'hmc', 1, 'hmc')),
    ('rooms', py('roomx.py', where=TOOLS)),
    ('lamp floors', py('lampfloors.py', where=TOOLS)),
    ('floor sounds', py('surfx.py', where=TOOLS)),
    ('race dialogs', py('race_dialogs.py', MOD, where=TOOLS)),
    ('skies', py('envx.py', ROM, TEX)),
    ('sky caps', py('skycapx.py', TEX)),
    ('transitions', py('irisx.py', DECOMP, TEX)),
    ('title logo timing', py('make_logo_data.py', MOD)),
    ('texture tiles', py('tile_textures.py', where=TOOLS)),
    ('smooth classic', py('smooth_classic.py', where=TOOLS)),
    ('baked shadows bob', py('shadowbake.py', 'bob', where=TOOLS)),
    ('tiny island', py('thi_tiny_scale.py', DATA, where=TOOLS)),
    ('pictures by rule', py('texvariants.py', DECOMP, MOD, where=HERE)),
]
# Scenes the mod still has from the exporter as it was on 2026-10-15 (Bowser's first and last arenas, the Wing Cap's tower,
# the Dark World): that exporter run into a folder of its own, those scenes taken from it, the Dark World's third track
# added to it as it was by hand.
OLD_OUT = os.path.join(MOD, '_old_export')
OLD_SCENES = ('scene_bowser.lua', 'scene_bowser_3.lua', 'scene_totwc.lua', 'scene_bitdw.lua')
STEPS += [
    ('old scenes', [sys.executable, '-X', 'utf8', os.path.join(OLD_EXP, 'build_all.py'), '@env', 'SM64_OUT=' + OLD_OUT]),
    ('take old scenes', ['@copy', os.path.join(OLD_OUT, 'Scripts', 'data'), DATA] + list(OLD_SCENES) + ['@rmtree', OLD_OUT]),
    ('dark world track', py('add_track3.py', os.path.join(DATA, 'scene_bitdw.lua'), where=TRACKS)),
    # the files the mod had fixed by hand or from earlier runs: their patches (copies of the fresh file's own tokens)
    ('as the mod has them', py('reconcile.py', 'apply', DATA, os.path.join(HERE, 'patches'), where=HERE)),
]
# (after the menu's pictures, still to come: make_timer_assets.py TEX DATA DECOMP, make_copy_fp_assets.py TEX DATA)


def main():
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(TEX, exist_ok=True)
    names = [n for n, _ in STEPS]
    start = names.index(OPT['from']) if OPT['from'] else 0
    todo = [STEPS[names.index(OPT['only'])]] if OPT['only'] else STEPS[start:]
    log = open(os.path.join(MOD, 'sm64build.log'), 'a', encoding='utf-8')
    for i, (name, cmd) in enumerate(todo, 1):
        print('STEP %d/%d %s' % (i, len(todo), name), flush=True)
        t0 = time.time()
        log.write('== %s: %s\n' % (name, ' '.join(cmd)))
        log.flush()
        if cmd[0] == '@copy':                           # (files copied from one folder to another, then a folder removed)
            src, dst = cmd[1], cmd[2]
            rest = cmd[3:]
            gone = None
            if '@rmtree' in rest:
                gone = rest[rest.index('@rmtree') + 1]
                rest = rest[:rest.index('@rmtree')]
            for f in rest:
                shutil.copyfile(os.path.join(src, f), os.path.join(dst, f))
            if gone:
                shutil.rmtree(gone, ignore_errors=True)
            continue
        env = ENV
        if '@env' in cmd:                               # (a step with settings of its own: NAME=value after @env)
            i2 = cmd.index('@env')
            env = dict(ENV)
            for kv in cmd[i2 + 1:]:
                k, v = kv.split('=', 1)
                env[k] = v
            cmd = cmd[:i2]
        out = log
        if '>' in cmd:                                  # (a script that prints its file: its output to that file)
            i = cmd.index('>')
            cmd, out = cmd[:i], open(cmd[i + 1], 'w', encoding='utf-8', newline='\n')
        r = subprocess.run(cmd, cwd=os.path.dirname(cmd[3]), env=env, stdout=out, stderr=log if out is not log else subprocess.STDOUT)
        if out is not log:
            out.close()
        log.write('== %s: exit %d in %.1f s\n' % (name, r.returncode, time.time() - t0))
        log.flush()
        if r.returncode != 0:
            print('FAILED %s: exit %d (see sm64build.log)' % (name, r.returncode), flush=True)
            sys.exit(1)
    print('DONE', flush=True)


if __name__ == '__main__':
    main()
