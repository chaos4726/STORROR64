"""The checkpoint pole's sound as it is walked into (2026-10-27: "can you make a metal bending noise when walking into
the pole", then "thats a bad metal bending sound" - the merry-go-round's creak): a springy metal pole's twang, a door
stop's - a struck rod's partials (1, 2.76, 5.40, 8.93 times its note), wobbling as it swings, dying away - made here.
Three, a little apart in pitch: sfx/pole_twang_1..3.wav (22050 Hz, 16-bit, mono).

python tools/pole_twang.py <SM64Map mod dir>
"""
import math, os, struct, sys, wave, random

MOD = sys.argv[1]
RATE = 22050
random.seed(7)


def twang(f0, length=0.9):
    n = int(RATE * length)
    out = []
    partials = [(1.0, 1.0, 0.42), (2.76, 0.45, 0.22), (5.40, 0.22, 0.12), (8.93, 0.10, 0.07)]   # (ratio, level, decay s)
    for i in range(n):
        t = i / RATE
        # (the note bent down a little as it is struck, then steady; the swing's wobble in its loudness)
        f = f0 * (1.0 + 0.06 * math.exp(-t / 0.03))
        wob = 1.0 - 0.45 * (0.5 + 0.5 * math.cos(2.0 * math.pi * 9.0 * t)) * math.exp(-t / 0.5)
        s = 0.0
        for ratio, level, decay in partials:
            s += level * math.exp(-t / decay) * math.sin(2.0 * math.pi * f * ratio * t + ratio)
        # (the knock of the hit)
        click = (random.random() * 2.0 - 1.0) * math.exp(-t / 0.004) * 0.5
        attack = min(1.0, t / 0.002)
        out.append((s * wob + click) * attack)
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak * 0.85 for v in out]


for k, f0 in enumerate((440.0, 495.0, 400.0), start=1):   # ("increase the pitch of the metal": twice the first)
    path = os.path.join(MOD, "sfx", "pole_ting_%d.wav" % k)   # (new names: the first ones are held by the running game)
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in twang(f0)))
    w.close()
    print("written", path)
