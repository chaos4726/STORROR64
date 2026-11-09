import re, sys
def sections(path):
    s = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r'texture = "([^"]*)",\s*nverts = (\d+),.*?col = \{([^}]*)\}', s, re.S):
        out.append((m.group(1), m.group(3)))
    return out
for name in sys.argv[1:]:
    a = sections('X:/mashup-work/export_nodecal/Scripts/data/%s.lua' % name)
    b = sections('X:/mashup-work/export_us/Scripts/data/%s.lua' % name)
    ch = {}
    for (ta, ca), (tb, cb) in zip(a, b):
        if ca != cb:
            vals = [float(v) for v in ca.split(',') if v.strip()][:4]
            ch[ta] = vals
    print(name, len(a), len(b), {k: [round(x, 2) for x in v] for k, v in ch.items()})
