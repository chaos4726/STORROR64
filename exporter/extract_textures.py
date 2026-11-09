#!/usr/bin/env python3
"""Reads every texture the decomp's assets.json lists out of the player's own Mario 64 ROM and writes it
into the decomp tree as a PNG, where the exporter expects to find it. (The decomp's own extract_assets.py
does the same but needs its C tools built.)"""
import json, os, struct, sys
from PIL import Image

ROM = sys.argv[1]; D = sys.argv[2]
rom = open(ROM, "rb").read()
assets = json.load(open(os.path.join(D, "assets.json")))
_cache = {}

def mio0(o):
    if o in _cache: return _cache[o]
    assert rom[o:o+4] == b"MIO0", hex(o)
    size, co, uo = struct.unpack(">III", rom[o+4:o+16])
    out = bytearray(); lp = o + 16; cp = o + co; up = o + uo; bits = 0; n = 0
    while len(out) < size:
        if n == 0:
            bits = struct.unpack(">I", rom[lp:lp+4])[0]; lp += 4; n = 32
        if bits & 0x80000000:
            out.append(rom[up]); up += 1
        else:
            v = (rom[cp] << 8) | rom[cp+1]; cp += 2
            ln = (v >> 12) + 3; off = (v & 0xFFF) + 1
            for _ in range(ln): out.append(out[-off])
        bits = (bits << 1) & 0xFFFFFFFF; n -= 1
    _cache[o] = bytes(out[:size]); return _cache[o]

def decode(fmt, w, h, b):
    px = bytearray(w * h * 4)
    if fmt == "rgba16":
        for i in range(w * h):
            v = (b[i*2] << 8) | b[i*2+1]
            px[i*4:i*4+4] = bytes(((v >> 11 & 31) * 255 // 31, (v >> 6 & 31) * 255 // 31, (v >> 1 & 31) * 255 // 31, 255 if v & 1 else 0))
    elif fmt == "ia16":
        for i in range(w * h): px[i*4:i*4+4] = bytes((b[i*2], b[i*2], b[i*2], b[i*2+1]))
    elif fmt == "ia8":
        for i in range(w * h):
            t = (b[i] >> 4) * 17; a = (b[i] & 15) * 17; px[i*4:i*4+4] = bytes((t, t, t, a))
    elif fmt == "ia4":
        for i in range(w * h):
            nib = (b[i // 2] >> 4) if i % 2 == 0 else (b[i // 2] & 15)
            t = (nib >> 1) * 255 // 7; px[i*4:i*4+4] = bytes((t, t, t, 255 if nib & 1 else 0))
    elif fmt == "ia1":
        for i in range(w * h):
            bit = (b[i // 8] >> (7 - i % 8)) & 1; t = 255 if bit else 0; px[i*4:i*4+4] = bytes((t, t, t, t))
    else:
        return None
    return Image.frombytes("RGBA", (w, h), bytes(px))

n = skipped = 0
for path, info in assets.items():
    if not path.endswith(".png") or path.startswith("@"): continue
    parts = path.split(".")
    fmt = parts[-2] if len(parts) >= 3 else ""
    if fmt not in ("rgba16", "ia16", "ia8", "ia4", "ia1"): skipped += 1; continue
    w, h, size, where = info[0], info[1], info[2], info[3].get("us")
    if not where: skipped += 1; continue
    data = rom[where[0]:where[0]+size] if len(where) == 1 else mio0(where[0])[where[1]:where[1]+size]
    img = decode(fmt, w, h, data)
    out = os.path.join(D, path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out); n += 1
print("textures written:", n, "skipped (other formats):", skipped)
