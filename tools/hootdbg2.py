import os, sys, re
sys.path.insert(0, 'X:/mashup-work/exporter')
import sm64x as X
db = X.DB()
src = open('X:/mashup-work/sm64decomp/actors/hoot/model.inc.c').read()
for m in re.finditer(r'static const Vtx (\w+)\[\] = \{(.*?)\};', src, re.S):
    n = m.group(2).count('{{')
    try:
        got = len(db.vtx(m.group(1)))
    except Exception as e:
        got = 'ERR ' + str(e)
    if got != n:
        print(m.group(1), 'src', n, 'parsed', got)
print('done')
