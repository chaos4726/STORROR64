"""The ghost racer's voice (race.lua's DIALOG 9001-9003): Metal Mario talking as if under water - "next can you give the
charater a voice when you talk to him, maybe like a sound of someone talking in water", 2026-10-27.

Mario's own voice (the ROM's clips in sfx/: "mama mia", "here we go", "hoo hoo", "hrmm"...) cut into syllables, each
pitched a little up or down, and strung into gibberish words; then put under water - its pitch wobbling as sound does
through water, its top cut away (muffled) with a boom low down, a gurgle of low noise under it, bubbles popping up
through it (rising chirps), and a short watery echo. Three takes, one a box: sfx/talk_racer_1..3.wav (48 kHz, 16-bit,
mono).

python tools/racer_voice.py <SM64Map mod dir>
"""
import os, sys, wave
import numpy as np

MOD = sys.argv[1]
SFX = os.path.join(MOD, "sfx")
RATE = 48000
SRC = ["mario_mama_mia", "mario_here_we_go", "mario_hoohoo", "mario_hrmm", "mario_uh", "mario_yah", "mario_wah",
       "mario_hoo", "mario_whoa", "mario_eeuh"]


def load(name):
    w = wave.open(os.path.join(SFX, name + ".wav"))
    n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
    w.close()
    if ch == 2:
        a = a.reshape(-1, 2).mean(axis=1)
    if sr != RATE:
        a = np.interp(np.arange(0, len(a), sr / RATE), np.arange(len(a)), a)
    return a


def envelope(a, secs=0.02):
    win = max(1, int(secs * RATE))
    return np.sqrt(np.convolve(a * a, np.ones(win) / win, "same"))


# the voiced stretches of each clip: where a syllable can be cut from
CLIPS = []
for name in SRC:
    p = os.path.join(SFX, name + ".wav")
    if not os.path.exists(p):
        continue
    a = load(name)
    e = envelope(a)
    on = e > 0.30 * e.max()
    CLIPS.append((name, a, on))


def syllable(rng, length):
    """a slice `length` s long out of a voiced stretch of one of the clips, faded in and out"""
    for _ in range(200):
        name, a, on = CLIPS[rng.integers(len(CLIPS))]
        n = int(length * RATE)
        if len(a) <= n + 1:
            continue
        s = int(rng.integers(0, len(a) - n))
        if on[s:s + n].mean() > 0.9:
            seg = a[s:s + n].copy()
            break
    else:
        name, a, on = CLIPS[0]
        seg = a[:int(length * RATE)].copy()
    # (a little up or down in pitch: read faster or slower)
    k = rng.uniform(0.86, 1.18)
    seg = np.interp(np.arange(0, len(seg) - 1, k), np.arange(len(seg)), seg)
    att, rel = int(0.012 * RATE), int(0.035 * RATE)
    env = np.ones(len(seg))
    env[:att] = np.linspace(0.0, 1.0, att)
    env[-rel:] = np.linspace(1.0, 0.0, rel)
    return seg * env / (np.abs(seg).max() + 1e-9)


def babble(rng, total=1.25):
    """gibberish: words of 1-3 syllables, a short gap between words"""
    out = np.zeros(int((total + 0.5) * RATE))
    t = 0.02
    while t < total - 0.12:
        for _ in range(int(rng.integers(1, 4))):
            seg = syllable(rng, rng.uniform(0.09, 0.16)) * rng.uniform(0.7, 1.0)
            i = int(t * RATE)
            out[i:i + len(seg)] += seg[:len(out) - i]
            t += len(seg) / RATE - 0.015
        t += rng.uniform(0.04, 0.09)
    return out[:int((t + 0.1) * RATE)]


def wobble(x, rng, rate_hz=5.5, depth_ms=3.5):
    """pitch wobbling, as heard through water: read through a delay swinging to and fro"""
    n = np.arange(len(x))
    ph = rng.uniform(0, 2 * np.pi)
    t = n / RATE
    d = (depth_ms / 1000.0 * RATE) * (1.0 + np.sin(2 * np.pi * rate_hz * t + ph) * 0.8
                                       + 0.25 * np.sin(2 * np.pi * rate_hz * 2.3 * t))
    return np.interp(n - d, n, x, left=0.0, right=0.0)


def under_water(x):
    """the top cut away - muffled - and a boom low down, as through water"""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    h = 1.0 / (1.0 + (f / 850.0) ** 4) + 0.55 * np.exp(-((f - 330.0) / 140.0) ** 2)
    h[f < 70.0] *= (f[f < 70.0] / 70.0)
    return np.fft.irfft(spec * h, len(x))


def lowpass(x, fc):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec / (1.0 + (f / fc) ** 2), len(x))


def gurgle(rng, n):
    """low noise welling under it, coming and going"""
    noise = lowpass(rng.standard_normal(n), 220.0)
    swell = lowpass(np.abs(rng.standard_normal(n)), 6.0)
    g = noise * (swell / (swell.max() + 1e-9))
    return g / (np.abs(g).max() + 1e-9)


def bubbles(rng, n, count):
    """bubbles coming up through it: each a little rising chirp, dying fast"""
    out = np.zeros(n)
    for _ in range(count):
        dur = rng.uniform(0.02, 0.055)
        m = int(dur * RATE)
        start = int(rng.integers(0, max(1, n - m)))
        t = np.arange(m) / RATE
        f0 = rng.uniform(380.0, 900.0)
        f = f0 * (1.0 + 1.6 * t / dur)                    # (rising as the bubble shrinks to the top)
        ph = 2 * np.pi * np.cumsum(f) / RATE
        env = (1.0 - np.exp(-t / 0.002)) * np.exp(-t / (dur * 0.35))
        out[start:start + m] += np.sin(ph) * env * rng.uniform(0.5, 1.0)
    return out


def echo(x):
    """a short watery echo: a few late copies, darker each time"""
    y = x.copy()
    for ms, g in ((23, 0.32), (41, 0.22), (67, 0.14), (97, 0.08)):
        d = int(ms / 1000.0 * RATE)
        y[d:] += lowpass(x, 1200.0)[:-d] * g
    return y


def take(seed):
    rng = np.random.default_rng(seed)
    v = babble(rng)
    v = wobble(v, rng)
    v = under_water(v)
    v = v / (np.abs(v).max() + 1e-9)
    n = len(v)
    mix = v + 0.16 * gurgle(rng, n) + 0.30 * bubbles(rng, n, int(rng.integers(6, 11)))
    mix = echo(mix)
    # (a slow swell in loudness, as if bobbing)
    t = np.arange(n) / RATE
    mix *= 0.88 + 0.12 * np.sin(2 * np.pi * 2.1 * t + rng.uniform(0, 6.28))
    fade = int(0.06 * RATE)
    mix[:int(0.005 * RATE)] *= np.linspace(0.0, 1.0, int(0.005 * RATE))
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)
    return mix / (np.abs(mix).max() + 1e-9) * 0.85


def save(path, x):
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes((np.clip(x, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes())
    w.close()


print("syllables from", len(CLIPS), "of Mario's clips")
for i, seed in enumerate((101, 202, 303), 1):
    x = take(seed)
    p = os.path.join(SFX, "talk_racer_%d.wav" % i)
    save(p, x)
    print("written", os.path.basename(p), "%.2f s" % (len(x) / RATE))
