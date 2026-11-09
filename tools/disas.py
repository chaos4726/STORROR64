import struct, sys, capstone
# dis.py <exe> <rva hex> [bytes]: disassemble from the start of the function holding rva; notes strings and call targets
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
def off(rva):
    for n, va, vsz, raw, rsz in secs:
        if va <= rva < va + rsz: return raw + rva - va, n
    return None, None
def s_at(rva):
    o, n = off(rva)
    if o is None or n == ".text": return None
    a = b[o:o+80]
    z = a.find(b"\0")
    if z >= 4 and all(32 <= c < 127 for c in a[:z]): return '"' + a[:z].decode() + '"'
    try:
        u = a.decode("utf-16-le", "ignore"); z = u.find("\0")
        if z >= 3 and all(32 <= ord(c) < 127 for c in u[:z]): return 'L"' + u[:z] + '"'
    except Exception: pass
    return None
rva = int(sys.argv[1+1], 16)
size = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x600
start = rva
if len(sys.argv) <= 4:
    # back to the function start: after a run of CC padding
    o, _ = off(rva)
    k = o
    while k > o - 0x4000:
        if b[k-1] == 0xCC and b[k-2] == 0xCC: break
        k -= 1
    start = rva - (o - k)
o, _ = off(start)
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
for ins in md.disasm(b[o:o+size], start):
    note = ""
    if ins.op_str.find("rip") >= 0:
        import re
        m = re.search(r"rip ([+-]) (0x[0-9a-f]+)", ins.op_str)
        if m:
            d = int(m.group(2), 16) * (1 if m.group(1) == "+" else -1)
            t = ins.address + ins.size + d
            s = s_at(t)
            note = " ; " + hex(t) + (" " + s if s else "")
    print(hex(ins.address), ins.mnemonic, ins.op_str, note)
    if ins.mnemonic == "int3" and "nostop" not in sys.argv: break
