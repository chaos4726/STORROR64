# (NOT the snap in the game now: sfx/bowser_snap.wav is the user's own "Snap Finger Echo Sound Effect" - "it sounds
# nothing like a snap", 2026-11-04 - cut 0.165 s on for 1.8 s, faded out its last 0.18 s, 48 kHz stereo by ffmpeg.
# Running this writes over it.)
# Bowser's finger snap (bowser_fight.lua, the shadow clone's tell: "maybe like a finger snap then a purple hue around
# main bowser", 2026-11-04): Mario 64 has no snap, so one made here - the crack of the finger on the palm (a short
# bright burst, its high end rung at about 2.4 and 4.1 kHz) over the thump of it (a low knock), and a little room.
# Written as the other sounds: 48 kHz, 16-bit stereo. python -P tools/snap_sfx.py <sfx dir>
import sys, os, wave
import numpy as np

out = sys.argv[1]
SR = 48000
n = int(SR * 0.35)
t = np.arange(n) / SR
rng = np.random.default_rng(5)

# the crack: noise, very fast attack and decay, rung through two resonances
noise = rng.standard_normal(n)
env = np.exp(-t / 0.006) * (1.0 - np.exp(-t / 0.0004))


def ring(x, f, q):
    # a two-pole resonator at f Hz
    w = 2 * np.pi * f / SR
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    for i in range(len(x)):
        y[i] = x[i] - a1 * (y[i - 1] if i > 0 else 0.0) - a2 * (y[i - 2] if i > 1 else 0.0)
    return y


crack = noise * env
body = ring(crack, 2400.0, 6.0) * 0.6 + ring(crack, 4100.0, 8.0) * 0.4 + crack * 0.5
# (louder and fuller, 2026-11-04 - "I heard no snap": its crack was 6 ms and lost under the fight) the pop of the skin
# after it, ringing longer at 1.5 kHz, and the thump
pop = ring(noise * np.exp(-t / 0.025) * (1.0 - np.exp(-t / 0.001)), 1500.0, 10.0)
thump = np.sin(2 * np.pi * 180.0 * t) * np.exp(-t / 0.02) * 0.45
s = body / (np.abs(body).max() + 1e-9) + pop / (np.abs(pop).max() + 1e-9) * 0.55 + thump
s = np.tanh(s * 1.8)
# a little room: a few faint late copies
room = np.zeros_like(s)
for d, g in ((0.019, 0.22), (0.031, 0.16), (0.047, 0.11), (0.071, 0.07)):
    k = int(d * SR)
    room[k:] += s[:-k] * g
s = s + room
s = s / np.abs(s).max() * 0.9
pcm = (s * 32767).astype(np.int16)
st = np.stack([pcm, pcm], axis=1).reshape(-1)
with wave.open(os.path.join(out, 'bowser_snap.wav'), 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(st.tobytes())
print('ok')
