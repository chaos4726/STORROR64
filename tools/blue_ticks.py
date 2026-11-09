"""The blue coin switch's ticking, as long as its coins are out: switch_ticks.wav (8.5 s - Mario 64's 200 + 40 frames
of ticking) with one more of its slow 1.495 s rounds put in, 10.0 s, so it ends as the coins go (game.lua
G.reveal_blue: 10 s - "do 10", 2026-10-17; "blue coin timer not making coins dissappear when audio ends",
2026-10-28). Its own file: the switch stairs' ticking (platforms.lua) keeps switch_ticks.wav.

python tools/blue_ticks.py <SM64Map mod dir>
"""
import os, sys, wave

SRC = os.path.join(sys.argv[1], "sfx", "switch_ticks.wav")      # (the mod's own, its 0.3 s of silence after as the others have)
ROUND = (1.525, 3.020)          # s: its second slow round, from just before its first tick to just before the next
                                 # round's (the ticks at 1.545 and 3.040; silence before each)

w = wave.open(SRC, "rb")
params = w.getparams()
fr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
data = w.readframes(w.getnframes())
w.close()
step = ch * sw
a, b = int(ROUND[0] * fr) * step, int(ROUND[1] * fr) * step
out = data[:b] + data[a:b] + data[b:]
outs = [os.path.join(sys.argv[1], "sfx", "switch_ticks_blue.wav")]
for path in outs:
    o = wave.open(path, "wb")
    o.setparams(params)
    o.writeframes(out)
    o.close()
    print("written", path, round(len(out) / step / fr, 3), "s")
