"""ground_tex.py: the seamless pictures of the ground far under the daytime levels (sunsky.lua's ground plane):
ground_sea, ground_sand, ground_snow - 512 x 512, tiling (noise made in frequency space, so it wraps).
("what to do with the border right now it just shows a blank greyness going on infinitely", 2026-10-31)
python tools/ground_tex.py   (from X:/mashup-work)"""
import numpy as np
from PIL import Image

OUT = "E:\\SteamLibrary\\steamapps\\common\\STORROR Parkour Pro\\STORRORParkourPRO\\Binaries\\Win64\\ue4ss\\Mods\\SM64Map\\textures\\"
N = 512
rng = np.random.default_rng(64)


def noise(power, lo=1.0, hi=None):
    """tiling noise: white noise shaped by 1/f^power in frequency space, scaled to 0..1"""
    f = np.fft.fftfreq(N) * N
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    amp = 1.0 / r ** power
    amp[r < lo] = 0.0
    if hi:
        amp[r > hi] = 0.0
    spec = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) * amp
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    return n / n.max()


def soften(rgb, keep=20.0):
    """only what is bigger than a 1/keep of the picture kept (the mod's pictures have no smaller copies for the
    distance: fine grain drew shimmering stripes across the far ground - Cool, Cool Mountain's snow plain, 2026-10-31)"""
    f = np.fft.fftfreq(N) * N
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy)
    lp = np.exp(-(r / keep) ** 2)
    out = np.empty_like(rgb)
    for c in range(3):
        out[..., c] = np.real(np.fft.ifft2(np.fft.fft2(rgb[..., c]) * lp))
    return out


def save(name, rgb):
    rgb = soften(rgb)
    Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB").save(OUT + name + ".png")
    # (and its far copy: the picture's own average, one colour - far off the ground is one haze; sunsky.lua lays it
    # past GROUND_NEAR)
    avg = rgb.reshape(-1, 3).mean(axis=0)
    flat = np.ones((8, 8, 3)) * avg
    Image.fromarray(np.clip(flat * 255.0, 0, 255).astype(np.uint8), "RGB").save(OUT + name + "_far.png")
    print("wrote", name, "and", name + "_far", (avg * 255).round())


# the sea: deep blue, lighter in the swells, small bright flecks where the light catches the crests
big = noise(1.6, 1.0, 40.0)
small = noise(1.0, 20.0)
crest = np.clip((small - 0.72) * 5.0, 0.0, 1.0) * (0.4 + 0.6 * big)
deep = np.array([0.10, 0.30, 0.47])
light = np.array([0.22, 0.50, 0.64])
# (the swells kept faint: big blotches repeated tile after tile as a grid across the sea, seen from a height)
k = (0.18 * big + 0.82 * small)[..., None]
sea = deep * (1.0 - k) + light * k + crest[..., None] * np.array([0.35, 0.4, 0.42])
save("ground_sea", sea)

# sand: warm, ripples along one way and grain
ripple = 0.5 + 0.5 * np.sin(np.linspace(0, 2 * np.pi * 24, N, endpoint=False)[None, :] + noise(1.8, 1.0, 12.0) * 6.0)
grain = noise(0.6, 40.0)
mix = (0.25 * ripple + 0.35 * noise(1.5, 1.0, 30.0) + 0.4 * grain)[..., None]
sand = np.array([0.66, 0.53, 0.34]) * (0.82 + 0.3 * mix)
save("ground_sand", sand)

# snow: near white, blue-grey in the hollows of soft drifts, a little sparkle
drift = noise(1.7, 1.0, 30.0)
sparkle = np.clip((noise(0.4, 60.0) - 0.8) * 6.0, 0.0, 1.0)
k = drift[..., None]
snow = np.array([0.72, 0.78, 0.88]) * (1.0 - k) + np.array([0.93, 0.95, 0.98]) * k + sparkle[..., None] * 0.06
save("ground_snow", snow)
