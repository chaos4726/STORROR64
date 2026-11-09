# pngtile.py <in.png> <out.png> <n> : the picture repeated n x n in one (no libraries: PNG read and written by hand)
import struct, sys, zlib


def read_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    o, idat, w, h, bd, ct, plte, trns = 8, b"", 0, 0, 0, 0, None, None
    while o < len(d):
        n = struct.unpack(">I", d[o:o + 4])[0]
        t = d[o + 4:o + 8]
        c = d[o + 8:o + 8 + n]
        o += 12 + n
        if t == b"IHDR":
            w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", c)
            assert il == 0 and bd == 8, ("unsupported", bd, il)
        elif t == b"PLTE":
            plte = c
        elif t == b"tRNS":
            trns = c
        elif t == b"IDAT":
            idat += c
    bpp = {6: 4, 2: 3, 0: 1, 4: 2, 3: 1}[ct]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            cc = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - cc), abs(a - cc), abs(a + b - 2 * cc)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else cc)
                line[i] = (line[i] + pr) & 255
        rows.append(line); prev = line
    # to RGBA
    out = []
    for line in rows:
        px = bytearray()
        for x in range(w):
            if ct == 6: px += line[x * 4:x * 4 + 4]
            elif ct == 2: px += line[x * 3:x * 3 + 3] + b"\xff"
            elif ct == 0: g = line[x]; px += bytes((g, g, g, 255))
            elif ct == 4: g, al = line[x * 2], line[x * 2 + 1]; px += bytes((g, g, g, al))
            elif ct == 3:
                k = line[x]
                al = trns[k] if trns and k < len(trns) else 255
                px += plte[k * 3:k * 3 + 3] + bytes((al,))
        out.append(px)
    return w, h, out


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, c):
        return struct.pack(">I", len(c)) + t + c + struct.pack(">I", zlib.crc32(t + c) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)


def tile(src, dst, n):
    w, h, rows = read_png(src)
    out = []
    for _ in range(n):
        for r in rows:
            out.append(bytes(r) * n)
    write_png(dst, w * n, h * n, out)
    return w, h


if __name__ == "__main__":
    print(tile(sys.argv[1], sys.argv[2], int(sys.argv[3])))
