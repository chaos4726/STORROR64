import struct, sys
# qref.py <exe> <rva hex>...: qwords holding the address (base+rva), with the next qword (as rva) - native name/fn pairs
exe = sys.argv[1]
b = open(exe, "rb").read()
pe = struct.unpack_from("<I", b, 0x3C)[0]
nsec = struct.unpack_from("<H", b, pe + 6)[0]
sopt = struct.unpack_from("<H", b, pe + 20)[0]
base = struct.unpack_from("<Q", b, pe + 24 + 24)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + sopt + i * 40
    name = b[o:o + 8].rstrip(b"\0").decode()
    vsize, va, rsize, raw = struct.unpack_from("<IIII", b, o + 8)
    secs.append((name, va, vsize, raw, rsize))
for t in sys.argv[2:]:
    rva = int(t, 16)
    pat = struct.pack("<Q", base + rva)
    for name, va, vs, raw, rs in secs:
        if name == ".text": continue
        d = b[raw:raw + rs]
        i = d.find(pat)
        while i >= 0:
            nxt = struct.unpack_from("<Q", d, i + 8)[0] if i + 16 <= len(d) else 0
            print(t, "at", name, hex(va + i), "next", hex(nxt - base) if base <= nxt < base + 0x10000000 else hex(nxt))
            i = d.find(pat, i + 1)
