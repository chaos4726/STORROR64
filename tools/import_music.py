"""import_music.py <folder>: remixes of Mario 64's tunes put where the mod plays them (Settings > Audio, REMIX MUSIC -
music.lua). Each audio file in <folder> (any format ffmpeg reads: mp3, m4a, webm, opus, wav, flac, ogg...) is matched
to a tune by words in its name - "Bob-Omb Battlefield" -> level_grass, "Koopa's Road" -> level_koopa_road - made the
same loudness as the rest (EBU R128, -16 LUFS) and written as music_remix/<tune>.mp3. Then: which tunes have a remix,
which don't, and any file that matched nothing (rename it to the tune's name, or with words from its title, and run again).
A file named exactly as a tune (level_slide.mp3) always goes there.
python tools/import_music.py "C:/path/to/songs"   (from X:/mashup-work)"""
import os
import re
import subprocess
import sys

MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
OUT = os.path.join(MOD, "music_remix")
AUDIO = (".mp3", ".m4a", ".mp4", ".webm", ".opus", ".ogg", ".wav", ".flac", ".aac", ".wma")

# the tunes the mod plays (music.lua's names, Mario 64's sequences), with words that pick each out of a song's title -
# the first to match wins, so the narrow ones come first
TUNES = [
    ("menu_file_select", ["file select"]),
    ("menu_title_screen", ["title theme", "title screen"]),
    ("menu_star_select", ["star select"]),
    ("menu_game_over", ["game over"]),
    ("intro_new_file", ["opening", "dear mario", "peach's message", "intro"]),
    ("level_boss_koopa_final", ["ultimate koopa", "final bowser", "ultimate bowser"]),
    ("level_koopa_road", ["road to koopa", "koopa's road", "koopas road", "koopa road", "bowser's road"]),
    ("level_boss_koopa", ["koopa's theme", "koopas theme", "koopa theme", "bowser's theme", "bowser battle"]),
    ("event_endless_stairs", ["endless stairs", "endless staircase"]),
    ("event_piranha_plant", ["piranha plant", "lullaby"]),
    ("event_merry_go_round", ["merry go round", "merry-go-round"]),
    ("event_powerup", ["powerful mario", "wing cap", "power up", "powerup"]),
    ("event_metal_cap", ["metallic mario", "metal mario", "metal cap"]),
    ("event_credits", ["staff roll", "credits"]),
    ("event_ending", ["ending", "peach's theme"]),
    ("event_boss", ["boss battle", "boss theme", "king bob-omb", "big bob-omb"]),
    ("level_slide", ["slider", "slide"]),
    ("level_inside_castle", ["inside the castle", "castle walls", "inside castle", "peach's castle"]),
    ("level_grass", ["bob-omb battlefield", "bob omb battlefield", "bob-omb", "main theme", "field"]),
    ("level_water", ["dire, dire docks", "dire dire docks", "dire docks", "jolly roger", "water"]),
    ("level_hot", ["shifting sand", "lethal lava", "desert"]),
    ("level_snow", ["cool cool mountain", "cool, cool mountain", "snowman", "snow"]),
    ("level_spooky", ["boo's haunt", "boos haunt", "big boo", "haunt"]),
    ("level_underground", ["hazy maze", "cave dungeon", "cave"]),
]
NAMES = [t for t, _ in TUNES]
# (where each plays, to say what a missing one leaves on Mario 64's own)
WHERE = {
    "level_grass": "Bob-omb Battlefield, Whomp's Fortress, Tall Tall Mountain, Tiny-Huge Island",
    "level_slide": "the slides, Rainbow Ride, Tick Tock Clock, Wing Mario Over the Rainbow",
    "level_inside_castle": "inside the castle", "level_water": "Jolly Roger Bay, Dire Dire Docks, the aquarium",
    "level_hot": "Shifting Sand Land, Lethal Lava Land", "level_snow": "Cool Cool Mountain, Snowman's Land",
    "level_spooky": "Big Boo's Haunt", "level_underground": "Hazy Maze Cave and the caps' caves",
    "level_koopa_road": "the Bowser courses", "level_boss_koopa": "the first two Bowser fights",
    "level_boss_koopa_final": "the last Bowser fight", "event_boss": "the boss fights (King Bob-omb, Whomp King, ...)",
    "event_powerup": "the wing cap", "event_metal_cap": "the metal cap", "event_piranha_plant": "a sleeping Piranha Plant",
    "event_merry_go_round": "the merry-go-round in Big Boo's Haunt", "event_endless_stairs": "the endless stairs",
    "intro_new_file": "a new file's opening", "menu_file_select": "the file select", "menu_title_screen": "the title",
    "menu_star_select": "the star select", "menu_game_over": "game over", "event_credits": "the staff roll",
    "event_ending": "the ending",
}


def tune_for(fname):
    stem = os.path.splitext(os.path.basename(fname))[0]
    if stem in NAMES:
        return stem
    t = stem.lower().replace("_", " ")
    t = re.sub(r"\s+", " ", t)
    for name, words in TUNES:
        for w in words:
            if w in t:
                return name
    return None


def main():
    # (song titles carry music notes and the like: printed as UTF-8, not the console's own code page)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if len(sys.argv) < 2 or not os.path.isdir(sys.argv[1]):
        print(__doc__)
        return
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    done, unmatched, clash = {}, [], []
    for f in sorted(os.listdir(src)):
        if not f.lower().endswith(AUDIO):
            continue
        tune = tune_for(f)
        if not tune:
            unmatched.append(f)
            continue
        if tune in done:
            clash.append((f, tune, done[tune]))
            continue
        dst = os.path.join(OUT, tune + ".mp3")
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(src, f), "-vn",
               "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000", "-ac", "2", "-b:a", "256k", dst]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("could not convert %s: %s" % (f, r.stderr.strip()[:200]))
            continue
        done[tune] = f
        print("%-24s <- %s" % (tune, f))
    have = {os.path.splitext(x)[0] for x in os.listdir(OUT)}
    print("\nremixes in place: %d of %d tunes" % (len([n for n in NAMES if n in have]), len(NAMES)))
    for n in NAMES:
        if n not in have:
            print("  no remix: %-24s (%s keeps Mario 64's own)" % (n, WHERE.get(n, "")))
    for f in unmatched:
        print("matched no tune: %s - rename it to a tune's name above and run again" % f)
    for f, tune, first in clash:
        print("two for %s: %s and %s - the first kept" % (tune, first, f))


main()
