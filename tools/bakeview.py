"""top-down view of a baked scene's shade (shadow_<scene>.lua): white lit, dark shaded - to check what the bake did"""
import sys
import numpy as np
from lupa import LuaRuntime
from PIL import Image

scene = sys.argv[1]
MOD = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map"
L = LuaRuntime()
base = L.execute(open(f"{MOD}/Scripts/data/scene_{scene}.lua", encoding="utf-8").read())
bake = L.execute(open(f"{MOD}/Scripts/data/shadow_{scene}.lua", encoding="utf-8").read())
orig = {}
for i in range(1, len(base["sections"]) + 1):
    s = base["sections"][i]
    orig[s["id"]] = s
R = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
tris = []
for sid in bake["sections"].keys():
    b = bake["sections"][sid]
    pos = np.array([b["pos"][i] for i in range(1, len(b["pos"]) + 1)]).reshape(-1, 3)
    col = np.array([b["col"][i] for i in range(1, len(b["col"]) + 1)]).reshape(-1, 4)
    idx = np.array([b["idx"][i] for i in range(1, len(b["idx"]) + 1)]).reshape(-1, 3)
    tris.append((pos, col, idx))
allp = np.concatenate([t[0] for t in tris])
x0, y0 = allp[:, 0].min(), allp[:, 1].min()
W, H = int((allp[:, 0].max() - x0) / R) + 1, int((allp[:, 1].max() - y0) / R) + 1
img = np.zeros((H, W)); zbuf = np.full((H, W), -1e9)
for pos, col, idx in tris:
    lum = col[:, 0]
    for t in idx:
        a, b, c = pos[t]
        xs = np.arange(int((min(a[0], b[0], c[0]) - x0) / R), int((max(a[0], b[0], c[0]) - x0) / R) + 1)
        ys = np.arange(int((min(a[1], b[1], c[1]) - y0) / R), int((max(a[1], b[1], c[1]) - y0) / R) + 1)
        if len(xs) == 0 or len(ys) == 0:
            continue
        gx, gy = np.meshgrid(xs * R + x0 + R / 2, ys * R + y0 + R / 2)
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        w1 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / den
        w2 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / den
        w3 = 1 - w1 - w2
        m = (w1 >= 0) & (w2 >= 0) & (w3 >= 0)
        if not m.any():
            continue
        z = w1 * a[2] + w2 * b[2] + w3 * c[2]
        v = w1 * lum[t[0]] + w2 * lum[t[1]] + w3 * lum[t[2]]
        iy, ix = (gy[m] - y0) / R, (gx[m] - x0) / R
        iy, ix = iy.astype(int), ix.astype(int)
        top = z[m] > zbuf[iy, ix]
        zbuf[iy[top], ix[top]] = z[m][top]
        img[iy[top], ix[top]] = v[m][top]
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)[::-1]).save(f"X:/mashup-work/shots/bakeview_{scene}.png")
print(W, H)
