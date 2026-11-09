# Peach's three new lines for the Final Bowser story (ending.lua LINES) cut from the user's one recording of them -
# "use this for peaches audio instead of the 3 I gave you ... all 3 lines are in this one audio", 2026-11-04
# (Downloads/music/peach.mp3, decoded to a mono 48 kHz wav first). Already her voice and pitch: only cut at its two
# pauses, a gentle top cut at 9 kHz like her other lines from the game, her loudness (the loud parts' rms ~0.10, as
# sfx/peach_*.wav), and the 0.33 s of silence at the front that ending.lua plays them early for.
# python -P tools/peach_lines_split.py <peach_all.wav> <sfx dir>
import sys, os, wave
import numpy as np

CUTS = (("peach_saved_again", 0.08, 1.55), ("peach_another_cake", 1.55, 3.00), ("peach_for_you_mario", 3.00, None))
SR = 48000

w = wave.open(sys.argv[1])
assert w.getframerate() == SR and w.getnchannels() == 1
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
out_dir = sys.argv[2]


def loud_rms(z):
    fr = 2400
    rr = np.array([np.sqrt(np.mean(z[i:i + fr] ** 2)) for i in range(0, len(z) - fr, fr)])
    return np.sqrt(np.mean(rr[rr > 0.3 * rr.max()] ** 2))


for name, t0, t1 in CUTS:
    y = x[int(t0 * SR):(int(t1 * SR) if t1 else len(x))].copy()
    # (its silence off both ends, 50 ms kept)
    fr = 240
    r = np.array([np.sqrt(np.mean(y[i:i + fr] ** 2)) for i in range(0, len(y) - fr, fr)])
    on = np.where(r > 0.02 * r.max())[0]
    y = y[max(0, (on[0] - 10) * fr):min(len(y), (on[-1] + 11) * fr)]
    y = y - np.mean(y)
    Y = np.fft.rfft(y)
    f = np.fft.rfftfreq(len(y), 1.0 / SR)
    Y *= np.clip((10000.0 - f) / 1500.0, 0.0, 1.0)
    y = np.fft.irfft(Y, len(y))
    y *= 0.10 / max(1e-9, loud_rms(y))
    if np.max(np.abs(y)) > 0.95:
        y = np.tanh(y / 0.95 * 1.2) * 0.95 / np.tanh(1.2)
    nf = int(0.015 * SR)
    y[:nf] *= np.linspace(0, 1, nf)
    y[-nf:] *= np.linspace(1, 0, nf)
    y = np.concatenate([np.zeros(int(0.33 * SR)), y, np.zeros(int(0.25 * SR))])
    s = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    o = wave.open(os.path.join(out_dir, name + ".wav"), "wb")
    o.setnchannels(2)
    o.setsampwidth(2)
    o.setframerate(SR)
    o.writeframes(np.repeat(s[:, None], 2, axis=1).tobytes())
    o.close()
    print("%s: %.2f s" % (name, len(y) / SR))
