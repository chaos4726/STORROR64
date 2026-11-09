#!/usr/bin/env python3
"""Mario 64's sounds and music for the STORROR x SM64 mod, rendered from the player's own ROM.

sm64audio.exe (the mod's own renderer, on libsm64's audio code) plays a recipe - "length <frames>" and lines of
"<frame> sound <SOUND_...>" or "<frame> music <0xPPSS>", 30 frames a second - through Mario 64's sound engine from the
ROM and writes the result (32 kHz, 16-bit stereo). Here:
  sound effects (audio/sfx/<name>.txt): their silence trimmed off both ends (-60 dB), at 48 kHz -> <mod>/sfx/<name>.wav
    (as sm64audio/one.sh made them; the timelines and loops below kept whole)
  music (audio/music/<name>.txt): cut to the tune's length (music.lua's LOOPS: a level tune runs 3 s past its loop
    point) -> <mod>/music/<name>.wav
  the ambience (audio/amb_<name>.txt) -> <mod>/ambience/<name>.wav
then the sounds made from those: the blue coin switch's ticking (tools/blue_ticks.py) and the ghost racer's voice
(tools/racer_voice.py); and the checkpoint pole's twang (tools/pole_twang.py: made, not from the ROM).

Usage: sm64audio_build.py <rom.z64> <mod dir> [--tools <dir>]   prints "STEP ..." lines, then DONE or FAILED.
"""
import os, subprocess, sys, tempfile, wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, 'sm64audio.exe')
REC = os.path.join(HERE, 'audio')

# how long each tune's file runs, seconds (the files the mod was made with)
MUSIC_LEN = {
    'event_boss': 108.392, 'event_credits': 202.0, 'event_cutscene_lakitu': 5.228375, 'event_ending': 75.0,
    'event_endless_stairs': 112.0, 'event_merry_go_round': 168.879, 'event_metal_cap': 39.176125,
    'event_piranha_plant': 107.812, 'event_powerup': 69.987875, 'event_victory': 26.0, 'intro_new_file': 50.0,
    'level_boss_koopa': 241.042, 'level_boss_koopa_final': 94.883, 'level_grass': 125.025, 'level_hot': 107.655,
    'level_inside_castle': 129.071, 'level_koopa_road': 221.867, 'level_slide': 148.329, 'level_snow': 169.85,
    'level_spooky': 354.404, 'level_underground': 208.875, 'level_water': 181.975, 'menu_game_over': 50.0,
    'menu_star_select': 60.0}
AMB_LEN = {'castle_grounds': 60.0, 'waterfall': 25.0}
# sound effects kept whole (a timeline, a loop): their length in seconds
WHOLE = {'intro_sfx': 50.0, 'loop_coin_count': 2.0, 'loop_coin_count_fast': 2.0}
# the looping sounds: from their first sound on, cut to their loop's length (seconds)
LOOP_LEN = {'loop_amp': 8.0, 'loop_big_platform': 12.0, 'loop_birds': 8.0, 'loop_blow_wind': 10.0, 'loop_bowser_fire': 12.0,
            'loop_chuckya': 8.0, 'loop_elevator1': 8.0, 'loop_elevator2': 8.0, 'loop_elevator3': 8.0, 'loop_elevator4': 8.0,
            'loop_env_water': 12.0, 'loop_fire': 8.0, 'loop_flying': 10.958, 'loop_fuse': 4.0, 'loop_heaveho': 8.0,
            'loop_lakitu': 8.0, 'loop_merry_creak': 12.0, 'loop_mri': 8.0, 'loop_outdoors': 8.0, 'loop_rough_slide': 8.0,
            'loop_sand': 8.0, 'loop_seesaw': 8.0, 'loop_sink_quicksand': 8.0, 'loop_slide_down_pole': 3.0,
            'loop_slide_down_tree': 3.0, 'loop_snow_roll': 12.0, 'loop_volcano': 8.0, 'loop_water_drain': 10.0,
            'loop_waterfall': 8.0, 'loop_wind': 10.0}
# sounds made louder or quieter by hand when the mod was made (dB)
GAIN = {'en_snufit_death': 1.0, 'haunted_chair': 12.1, 'koopa_message': -2.8, 'loop_amp': 1.6, 'loop_birds': -2.3,
        'loop_blow_wind': -0.9, 'loop_bowser_fire': -6.2, 'loop_chuckya': 1.0, 'loop_elevator1': 0.8, 'loop_elevator2': 1.0,
        'loop_elevator3': 1.0, 'loop_elevator4': 1.0, 'loop_fuse': 2.4, 'loop_heaveho': 1.1, 'loop_lakitu': 1.0,
        'loop_mri': 1.0, 'loop_outdoors': 1.1, 'loop_sand': 1.5, 'loop_seesaw': 1.0, 'loop_snow_roll': -1.5,
        'loop_volcano': 1.0, 'loop_waterfall': 1.0, 'purple_ticks': 1.1}
# quick sounds made before the padding, kept short (the game's few sound players take turns: a punch's voice padded
# out held a player through the next punch)
NOPAD = {'bbh_spin', 'body_hit_ground', 'bounce_off', 'door_insert_key', 'door_turn_key', 'heavy_landing', 'mario_doh',
         'mario_punch_hoo', 'mario_punch_wah', 'mario_punch_yah', 'mario_uh2', 'star_short', 'wiggler_attacked',
         'wiggler_jump', 'wiggler_step_high', 'wiggler_step_low'}
# cut to this length (seconds) after the trim
CUT = {'birds_fly_away': 4.654}
TRIM_DB = -60.0


def load(path):
    w = wave.open(path)
    rate, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).reshape(-1, ch)
    w.close()
    return rate, a


def save(path, rate, a):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, 'wb')
    w.setnchannels(a.shape[1])
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(np.ascontiguousarray(a, dtype=np.int16).tobytes())
    w.close()


def trim(a):
    lim = 32768.0 * 10 ** (TRIM_DB / 20.0)
    loud = np.nonzero(np.abs(a.astype(np.int32)).max(axis=1) > lim)[0]
    if len(loud) == 0:
        return a[:1]
    return a[loud[0]:loud[-1] + 1]


def resample(a, src, dst):
    if src == dst or len(a) < 2:
        return a
    n = int(round(len(a) * dst / src))
    t = np.arange(n) * (src / dst)
    out = np.empty((n, a.shape[1]), dtype=np.float64)
    for c in range(a.shape[1]):
        out[:, c] = np.interp(t, np.arange(len(a)), a[:, c].astype(np.float64))
    return np.clip(np.round(out), -32768, 32767).astype(np.int16)


def render(rom, recipe, tmp):
    out = os.path.join(tmp, os.path.basename(recipe) + '.wav')
    r = subprocess.run([EXE, rom, out, recipe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode != 0 or not os.path.exists(out):
        raise RuntimeError('sm64audio failed on ' + os.path.basename(recipe))
    return load(out)


def main():
    a = sys.argv[1:]
    tools = os.path.join(HERE, 'tools')
    if '--tools' in a:
        i = a.index('--tools')
        tools = a[i + 1]
        del a[i:i + 2]
    if len(a) != 2:
        sys.exit(__doc__)
    rom, mod = os.path.abspath(a[0]), os.path.abspath(a[1])
    tmp = tempfile.mkdtemp(prefix='sm64audio_')
    sfx = sorted(f[:-4] for f in os.listdir(os.path.join(REC, 'sfx')) if f.endswith('.txt'))
    music = sorted(f[:-4] for f in os.listdir(os.path.join(REC, 'music')) if f.endswith('.txt'))
    total = len(sfx) + len(music) + len(AMB_LEN) + 3
    step = 0

    def say(what):
        nonlocal step
        step += 1
        print('STEP %d/%d %s' % (step, total, what), flush=True)

    try:
        for name in sfx:
            say('sound ' + name)
            rate, s = render(rom, os.path.join(REC, 'sfx', name + '.txt'), tmp)
            if name in WHOLE:
                s = resample(s[:int(round(WHOLE[name] * rate))], rate, 48000)
            elif name in LOOP_LEN:
                s = resample(trim(s), rate, 48000)
                n = int(round(LOOP_LEN[name] * 48000))
                s = s[:n] if len(s) >= n else np.concatenate([s, np.zeros((n - len(s), s.shape[1]), dtype=np.int16)])
            else:
                # (0.3 s of silence after, and a second at least: the game's media player cut short ones off - as the
                # mod's sounds were made)
                s = resample(trim(s), rate, 48000)
                if name in CUT:
                    s = s[:int(round(CUT[name] * 48000))]
                if name not in NOPAD:
                    s = np.concatenate([s, np.zeros((int(0.3 * 48000), s.shape[1]), dtype=np.int16)])
                    if len(s) < 48000:
                        s = np.concatenate([s, np.zeros((48000 - len(s), s.shape[1]), dtype=np.int16)])
            if GAIN.get(name):
                s = np.clip(np.round(s.astype(np.float64) * 10 ** (GAIN[name] / 20.0)), -32768, 32767).astype(np.int16)
            save(os.path.join(mod, 'sfx', name + '.wav'), 48000, s)
        save(os.path.join(mod, 'sfx', 'silence.wav'), 48000, np.zeros((int(0.4 * 48000), 2), dtype=np.int16))
        for name in music:
            say('music ' + name)
            rate, s = render(rom, os.path.join(REC, 'music', name + '.txt'), tmp)
            s = s[:int(round(MUSIC_LEN.get(name, len(s) / rate) * rate))]
            save(os.path.join(mod, 'music', name + '.wav'), rate, s)
        for name, secs in AMB_LEN.items():
            say('ambience ' + name)
            rate, s = render(rom, os.path.join(REC, 'amb_%s.txt' % name), tmp)
            save(os.path.join(mod, 'ambience', name + '.wav'), rate, s[:int(round(secs * rate))])
        for script in ('blue_ticks.py', 'racer_voice.py', 'pole_twang.py'):
            say(script)
            r = subprocess.run([sys.executable, '-X', 'utf8', os.path.join(tools, script), mod],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if r.returncode != 0:
                raise RuntimeError('%s: %s' % (script, (r.stderr or '').strip().splitlines()[-1:]))
    except Exception as e:
        print('FAILED %s' % e, flush=True)
        sys.exit(1)
    print('DONE', flush=True)


if __name__ == '__main__':
    main()
