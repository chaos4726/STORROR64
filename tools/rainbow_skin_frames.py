# The RAINBOW skin as the Final Bowser floors look and move (caps.lua M.SKIN_STYLE.rainbow: "for the rainbow skin make it
# look like the final bowser stage, and have it move like it too", 2026-11-04): the floors' liquid (textures/
# final_liquid_rb.png, tools/final_liquid_rb_tex.py - its flow, its web of bright lines, its stars) in the rainbow, the
# picture flowing and the colours turning through it. The body's materials (his own, copied) take a picture but have no
# way to slide one, so the flow is drawn ahead: N pictures, rainbow_skin_f00.., the liquid moved on `SHIFT` repeats over
# the N and the colours once round - a loop, each picture repeating seamlessly. Written as the game shows it (as the
# floors' picture is: c ** 2.2).
# python -P tools/rainbow_skin_frames.py <textures dir>
import sys, os
import numpy as np
from PIL import Image

d = sys.argv[1]
N, W = 192, 256
SHIFT = (1, 1)                         # (the liquid's way over the loop, in repeats: one each way - slower, "the texture moves too fast", 2026-11-04)
liq = np.asarray(Image.open(os.path.join(d, "final_liquid_rb.png")).convert("L").resize((W, W), Image.LANCZOS)).astype(np.float64) / 255.0
y, x = np.mgrid[0:W, 0:W] / W


def hsv(h, s, v):
    h6 = (h % 1.0) * 6.0
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = a[m], b[m], c[m]
    return out


for k in range(N):
    t = k / N
    # (the liquid slid along its way: whole pixels, wrapped - it repeats)
    sx, sy = int(round(SHIFT[0] * t * W)) % W, int(round(SHIFT[1] * t * W)) % W
    g = np.roll(np.roll(liq, sy, axis=0), sx, axis=1)
    # (the colours: bands of the rainbow across it on the slant, as the floors' wedges round the arena, turning once)
    hue = (x + y + t) % 1.0
    col = hsv(hue, np.full_like(hue, 0.85), np.ones_like(hue)) ** 2.2
    img = np.clip(col * g[..., None] * 1.15, 0, 1)
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save(os.path.join(d, "rainbow_skin_h%03d.png" % k))
print("ok: %d pictures, %d x %d" % (N, W, W))
