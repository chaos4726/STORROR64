# normal_srgb.py <in.png> <out.png>: a normal map stored so that it comes out right through the mod's texture import, which
# reads every PNG as colour (sRGB): R and G (the slopes the material reads; it works out B) put through linear->sRGB, so
# that the engine's sRGB->linear on sampling gives the slopes back. (water96_normal as it was: every normal leant to one
# side, and RENDER 96's water mirrored the ground under it in black blotches, 2026-10-31)
import sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float64) / 255.0
def to_srgb(x):
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)
out = a.copy()
out[..., 0] = to_srgb(a[..., 0])
out[..., 1] = to_srgb(a[..., 1])
Image.fromarray((out * 255.0).round().clip(0, 255).astype(np.uint8), "RGB").save(sys.argv[2])
print("written", sys.argv[2], "flat R,G now", round(float(to_srgb(np.array(0.5))) * 255))
