#!/usr/bin/env python3
"""Makes the STORROR x Super Mario 64 release from the installed mod: X:/mashup-work/release/<version>/.

The release is the game folder's files to add (STORRORParkourPRO/Binaries/Win64/...): UE4SS and the Lua mods the mod
needs, and SM64Map itself - its code, Render 96's pictures, the remixes, the multiplayer DLL, the installer
(SM64Setup.exe) and sm64_assets.pak: every Super Mario 64 file of the mod, locked with the Super Mario 64 (USA) ROM
(ChaCha20, its key made from the ROM: the player's own copy unlocks it, nothing else does). Left out: the maker's saves
and settings, dev files, backups, caches the game remakes.

python installer/make_release.py [version]      (the ROM: X:/mashup-work/rom_us.z64)
To update a release: run it again; the players run the new SM64Setup.exe over their install."""
import json, os, shutil, subprocess, sys, zipfile

WORK = 'X:/mashup-work'
GAME_BIN = 'E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64'
MOD = GAME_BIN + '/ue4ss/Mods/SM64Map'
ROM = WORK + '/rom_us.z64'
SETUP = WORK + '/installer/setup/SM64Setup.exe'
VERSION = sys.argv[1] if len(sys.argv) > 1 else '1.0'
OUT = WORK + '/release/STORROR64-' + VERSION
BIN_OUT = OUT + '/STORRORParkourPRO/Binaries/Win64'
MOD_OUT = BIN_OUT + '/ue4ss/Mods/SM64Map'

# Super Mario 64's files: locked in the pack
LOCKED_DIRS = ['Scripts/data', 'Scripts/data_r96', 'textures', 'textures_tiles_orig', 'sfx', 'music', 'ambience']
# the mod's own, open
OPEN_DIRS = ['textures_r96', 'textures_r96_paint_orig', 'textures_r96_seams_orig', 'music_remix', 'sfx_remix', 'ambience_remix']
OPEN_FILES = ['enabled.txt', 'swim_base.lua', 'bin/sm64net.dll']
# never: the maker's own play and settings, and what the game remakes
SKIP_SCRIPTS = {'level_data.lua', 'collision_data.lua'}          # (unused, made from the ROM)
UE4SS_MODS = ['shared', 'BPModLoaderMod', 'BPML_GenericFunctions', 'ConsoleEnablerMod', 'ConsoleCommandsMod',
              'CheatManagerEnablerMod', 'Keybinds']


def junk(name):
    n = name.lower()
    # (.keep_: a race time kept aside - "save my time" - not the level's ghost itself)
    return '.bak' in n or '.keep_' in n or n.endswith(('.off', '.tmp', '.orig')) or '.before_' in n or n.startswith('.')


def walk(base, rel):
    out = []
    root = os.path.join(base, rel)
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if not junk(x)]
        for f in files:
            if junk(f):
                continue
            out.append(os.path.relpath(os.path.join(d, f), base).replace('\\', '/'))
    return sorted(out)


def copy(src_base, rel, dst_base):
    d = os.path.join(dst_base, rel)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    shutil.copy2(os.path.join(src_base, rel), d)


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(MOD_OUT)
    # UE4SS and its mods
    for f in ('dwmapi.dll',):
        copy(GAME_BIN, f, BIN_OUT)
    for f in os.listdir(GAME_BIN + '/ue4ss'):
        p = GAME_BIN + '/ue4ss/' + f
        if os.path.isfile(p) and not junk(f) and not f.endswith(('.log', '.dmp')) and f != 'imgui.ini':
            copy(GAME_BIN, 'ue4ss/' + f, BIN_OUT)
    for m in UE4SS_MODS:
        for rel in walk(GAME_BIN + '/ue4ss/Mods', m):
            copy(GAME_BIN + '/ue4ss/Mods', rel, BIN_OUT + '/ue4ss/Mods')
    with open(BIN_OUT + '/ue4ss/Mods/mods.txt', 'w', encoding='utf-8', newline='\r\n') as f:
        for m in UE4SS_MODS[1:-1]:
            f.write('%s : 1\n' % m)
        f.write('SM64Map : 1\n\n; Built-in keybinds, do not move up!\nKeybinds : 1\n')
    mj = GAME_BIN + '/ue4ss/Mods/mods.json'
    if os.path.exists(mj):
        keep = set(UE4SS_MODS) | {'SM64Map'}
        try:
            data = [e for e in json.load(open(mj, encoding='utf-8')) if e.get('mod_name') in keep]
            json.dump(data, open(BIN_OUT + '/ue4ss/Mods/mods.json', 'w', encoding='utf-8'), indent=4)
        except Exception as e:
            print('mods.json left out:', e)
    # the mod: code and its own files open
    n_open = 0
    for f in sorted(os.listdir(MOD + '/Scripts')):
        if f.endswith('.lua') and not junk(f) and f not in SKIP_SCRIPTS:
            copy(MOD, 'Scripts/' + f, MOD_OUT)
            n_open += 1
    for d in OPEN_DIRS:
        for rel in walk(MOD, d):
            copy(MOD, rel, MOD_OUT)
            n_open += 1
    for rel in OPEN_FILES:
        copy(MOD, rel, MOD_OUT)
        n_open += 1
    shutil.copy2(SETUP, MOD_OUT + '/SM64Setup.exe')
    shutil.copy2(WORK + '/installer/README.txt', OUT + '/README.txt')
    shutil.copy2(WORK + '/installer/MUSIC_CREDITS.md', OUT + '/MUSIC_CREDITS.md')     # (the README points to it)
    # Super Mario 64's files: locked
    # (and a file named for this version, unlocked with the rest: Melty's install recipe waits for it after its unlock,
    # so a newer release's pack is unlocked again over an older one - installed.txt alone would say "done" for good)
    for f in os.listdir(MOD + '/Scripts/data'):
        if f.startswith('unlocked_') and f.endswith('.txt'):
            os.remove(MOD + '/Scripts/data/' + f)
    marker = 'Scripts/data/unlocked_%s.txt' % VERSION
    open(MOD + '/' + marker, 'w', encoding='utf-8', newline='\n').write('STORROR64 %s: the Super Mario 64 files are unlocked\n' % VERSION)
    locked = []
    for d in LOCKED_DIRS:
        locked += walk(MOD, d)
    lst = WORK + '/release/locked_list.txt'
    open(lst, 'w', encoding='utf-8', newline='\n').write('\n'.join(locked) + '\n')
    r = subprocess.run([SETUP, '--pack', ROM, lst, MOD.replace('/', '\\'), (MOD_OUT + '/sm64_assets.pak').replace('/', '\\')],
                       capture_output=True, text=True)
    os.remove(MOD + '/' + marker)
    print(r.stdout.strip(), r.stderr.strip())
    if r.returncode != 0 or not os.path.exists(MOD_OUT + '/sm64_assets.pak'):
        sys.exit('packing failed')
    print('open files', n_open, '| locked', len(locked))
    # the zip players download
    z = WORK + '/release/STORROR64-%s.zip' % VERSION
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for d, dirs, files in os.walk(OUT):
            for f in files:
                p = os.path.join(d, f)
                zf.write(p, os.path.relpath(p, OUT))
    print('wrote', z, '%.0f MB' % (os.path.getsize(z) / 1048576.0))


if __name__ == '__main__':
    main()
