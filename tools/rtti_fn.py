import struct, sys, re
# rtti_fn.py <exe> <typedescriptor-name rva hex>: type descriptor -> complete object locators -> vtables -> code that loads the vtable
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
def sec(n): return [s for s in secs if s[0] == n][0]
td = int(sys.argv[2], 16) - 0x10
_, rva_, _, rraw, rrs = sec(".rdata")
rd = b[rraw:rraw + rrs]
cols = []
for m in re.finditer(re.escape(struct.pack("<I", td)), rd):
    i = m.start() - 12
    if i < 0: continue
    sig, off_, cd, tdr, cdr, selfr = struct.unpack_from("<IIIIII", rd, i)
    if sig == 1 and tdr == td and selfr == rva_ + i:
        cols.append(rva_ + i)
print("COLs", [hex(c) for c in cols])
vts = []
for c in cols:
    for m in re.finditer(re.escape(struct.pack("<Q", base + c)), rd):
        vts.append(rva_ + m.start() + 8)
print("vtables", [hex(v) for v in vts])
for v in vts:
    fns = [struct.unpack_from("<Q", rd, v - rva_ + 8 * k)[0] - base for k in range(4)]
    print("  vt", hex(v), "fns", [hex(f) for f in fns])
_, tva, _, traw, trs = sec(".text")
t = b[traw:traw + trs]
vset = set(vts)
for m in re.finditer(rb"[\x48\x4c]\x8d", t):
    j = m.start()
    if j + 7 > len(t): break
    if t[j + 2] & 0xC7 != 0x05: continue
    tgt = tva + j + 7 + struct.unpack_from("<i", t, j + 3)[0]
    if tgt in vset: print("loaded at", hex(tva + j), "vt", hex(tgt))
