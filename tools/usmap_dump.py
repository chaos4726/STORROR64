# usmap_dump.py <file> <regex>: enums and structs (with their properties) whose names or property names match
import struct, sys, re
d = open(sys.argv[1], 'rb').read()
pat = re.compile(sys.argv[2], re.I)
o = 0
def u8():
    global o; v = d[o]; o += 1; return v
def u16():
    global o; v = struct.unpack_from('<H', d, o)[0]; o += 2; return v
def u32():
    global o; v = struct.unpack_from('<I', d, o)[0]; o += 4; return v
def u64():
    global o; v = struct.unpack_from('<Q', d, o)[0]; o += 8; return v
magic = u16(); ver = u8()
hasv = u32() if ver >= 1 else 0
if hasv:
    o += 4 + 4 + 4  # ue4/ue5 versions
    n = u32(); o += n * 20
    o += 4
comp = u8(); csz = u32(); dsz = u32()
names = []
for _ in range(u32()):
    l = u16() if ver >= 2 else u8()
    names.append(d[o:o + l].decode('utf-8', 'replace')); o += l
enums = []
for _ in range(u32()):
    nm = names[u32()]
    cnt = u16() if ver >= 3 else u8()
    vals = []
    for _ in range(cnt):
        if ver >= 4:
            v = u64(); vals.append((v, names[u32()]))
        else:
            vals.append((len(vals), names[u32()]))
    enums.append((nm, vals))
TYPES = ['Byte','Bool','Int','Float','Object','Name','Delegate','Double','Array','Struct','Str','Text','Interface','MulticastDelegate','WeakObject','LazyObject','AssetObject','SoftObject','UInt64','UInt32','UInt16','Int64','Int16','Int8','Map','Set','Enum','FieldPath','OptionalProperty','Utf8Str','AnsiStr']
def ptype():
    t = u8(); s = TYPES[t] if t < len(TYPES) else str(t)
    if s == 'Enum': inner = ptype(); return 'Enum<%s>' % names[u32()]
    if s == 'Struct': return 'Struct<%s>' % names[u32()]
    if s in ('Array', 'Set', 'OptionalProperty'): return '%s<%s>' % (s, ptype())
    if s == 'Map': a = ptype(); b = ptype(); return 'Map<%s,%s>' % (a, b)
    return s
schemas = []
for _ in range(u32()):
    nm = names[u32()]; sup = u32(); sup = names[sup] if sup != 0xFFFFFFFF else ''
    pc = u16(); sc = u16()
    props = []
    for _ in range(sc):
        idx = u16(); dim = u8(); pn = names[u32()]; t = ptype()
        props.append((pn, t))
    schemas.append((nm, sup, props))
for nm, vals in enums:
    if pat.search(nm) or any(pat.search(v[1]) for v in vals):
        print("ENUM %s: %s" % (nm, ", ".join(v[1] for v in vals)))
for nm, sup, props in schemas:
    hit = [p for p in props if pat.search(p[0])]
    if pat.search(nm) or hit:
        print("STRUCT %s : %s" % (nm, sup))
        for p in (props if pat.search(nm) else hit)[:400]: print("    %s  %s" % p)
