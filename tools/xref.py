import struct, sys
# xref.py <exe> <rva hex>...: code spots that load the address (rip-relative lea/mov) - prints the instruction's RVA
path = sys.argv[1]
b = open(path, "rb").read()
pe = struct.unpack_from("<I", b, 0x3c)[0]
nsec = struct.unpack_from("<H", b, pe + 6)[0]
opt = struct.unpack_from("<H", b, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    name = b[o:o+8].rstrip(b"\0").decode()
    vsz, va, rsz, raw = struct.unpack_from("<IIII", b, o + 8)
    secs.append((name, va, vsz, raw, rsz))
targets = set(int(x, 16) for x in sys.argv[2:])
for name, va, vsz, raw, rsz in secs:
    if name != ".text": continue
    t = b[raw:raw + rsz]
    n = len(t)
    i = 0
    import re
    for m in re.finditer(rb"[\x48\x4c][\x8d\x8b]", t):
        j = m.start()
        if j + 7 > n: break
        modrm = t[j + 2]
        if modrm & 0xC7 != 0x05: continue
        disp = struct.unpack_from("<i", t, j + 3)[0]
        tgt = va + j + 7 + disp
        if tgt in targets:
            print(hex(va + j), hex(tgt))
