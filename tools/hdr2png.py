# Radiance .hdr (from devtmp/capture_hdr.lua) -> PNG, brightness scaled so the 99th percentile is white, gamma 2.2.
# python -P tools/hdr2png.py in.hdr out.png [scale]
import sys, re
import numpy as np
from PIL import Image
data = open(sys.argv[1], 'rb').read()
head_end = data.index(b'\n\n') + 2
line_end = data.index(b'\n', head_end)
m = re.match(rb'-Y (\d+) \+X (\d+)', data[head_end:line_end])
H, W = int(m.group(1)), int(m.group(2))
p = line_end + 1
img = np.zeros((H, W, 4), np.uint8)
for y in range(H):
    if data[p] == 2 and data[p + 1] == 2 and ((data[p + 2] << 8) | data[p + 3]) == W:   # new run-length scanline
        p += 4
        for ch in range(4):
            x = 0
            while x < W:
                n = data[p]; p += 1
                if n > 128:
                    n -= 128; img[y, x:x + n, ch] = data[p]; p += 1
                else:
                    n = min(n, W - x)
                    img[y, x:x + n, ch] = np.frombuffer(data[p:p + n], np.uint8); p += n
                x += n
    else:
        img[y] = np.frombuffer(data[p:p + W * 4], np.uint8).reshape(W, 4); p += W * 4
e = img[..., 3].astype(np.int32)
f = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
rgb = img[..., :3].astype(np.float64) * f[..., None]
scale = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0 / max(np.percentile(rgb, 99), 1e-6)
out = np.clip(rgb * scale, 0, 1) ** (1 / 2.2)
Image.fromarray((out * 255).astype(np.uint8)).save(sys.argv[2])
print('max %.3f p99 %.3f scale %.3f' % (rgb.max(), np.percentile(rgb, 99), scale))
