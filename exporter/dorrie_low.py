# dorrie_low.py: Dorrie's head-lowered collision (dorrie_seg6_collision_0600FBB8, dorrie_act_move -> LOWER_HEAD) as a
# model-less template in data/extra_statics.lua (hmc.templates) - platforms.lua B.dorrie swaps to it while her head is down
import os, sys, re, json
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import platx as P
textures, templates = {}, {}
key = P.template(BA.db, textures, templates, lambda s: s, 'none', 'dorrie_seg6_collision_0600FBB8')
t = templates[key]
print('key', key, 'tris', t['collision']['ntris'])
def fmt(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s
def lua(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k if re.match(r'^[A-Za-z_]\w*$', k) else '["%s"]' % k, lua(x)) for k, x in v.items()) + ' }'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, int): return str(v)
    if isinstance(v, float): return fmt(v)
    if v is None: return 'nil'
    return json.dumps(v)
p = os.path.join(BA.DATA, 'extra_statics.lua')
s = open(p, encoding='utf-8').read()
if key in s:
    print('already there'); sys.exit()
line = '      ["%s"] = %s,\n' % (key, lua(t))
if re.search(r'\n  hmc = \{', s):
    s = re.sub(r'(\n  hmc = \{\n    templates = \{\n)', lambda mm: mm.group(1) + line, s, 1)
else:
    i = s.rindex('}')
    s = s[:i].rstrip() + ('' if s[:i].rstrip().endswith(',') else ',') + '\n  hmc = {\n    templates = {\n' + line + '    },\n    objects = {},\n  },\n' + s[i:]
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('added')
