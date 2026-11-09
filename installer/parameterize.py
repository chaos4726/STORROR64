"""Makes the mod's generator scripts run on any PC: the paths of this one written into them become environment
variables, today's path kept as each one's default (so they run here as before).

  the install's mod folder ...\\Mods\\SM64Map[\\rest]   -> os.path.join(os.environ.get("SM64_MOD", <it>), <rest>)
  X:/mashup-work/sm64decomp[/rest]                     -> os.path.join(os.environ.get("SM64_DECOMP", <it>), <rest>)
  X:/mashup-work/exporter                              -> the exporter folder beside this script's folder (or in it)
  X:/mashup-work/shots/...                             -> left (a debug picture)

python parameterize.py <script.py>...   (a .bak_before_param copy of each is kept)"""
import os, re, shutil, sys

MOD_RE = re.compile(r'''(r?)(['"])([EeXx]:[/\\]SteamLibrary[/\\]steamapps[/\\]common[/\\]STORROR Parkour Pro[/\\]STORRORParkourPRO'''
                    r'''[/\\]Binaries[/\\]Win64[/\\]ue4ss[/\\]Mods[/\\]SM64Map)([^'"]*)\2''')
DEC_RE = re.compile(r'''(r?)(['"])(X:[/\\]mashup-work[/\\]sm64decomp)([^'"]*)\2''')
EXP_RE = re.compile(r'''(r?)(['"])X:[/\\]mashup-work[/\\]exporter\2''')


def join(var, base, rest):
    rest = rest.strip('/\\')
    head = 'os.environ.get("%s", r"%s")' % (var, base)
    if not rest:
        return head
    if rest.endswith('/') or rest.endswith('\\'):
        rest = rest.rstrip('/\\')
    return 'os.path.join(%s, r"%s")' % (head, rest.replace('\\', '/'))


def fix(path):
    s = open(path, encoding='utf-8').read()
    o = s
    s = MOD_RE.sub(lambda m: join('SM64_MOD', m.group(3), m.group(4)) + (' + "/"' if m.group(4).endswith(('/', '\\')) else ''), s)
    s = DEC_RE.sub(lambda m: join('SM64_DECOMP', m.group(3), m.group(4)), s)
    here = os.path.basename(os.path.dirname(os.path.abspath(path)))
    rel = '"..", "exporter"' if here != 'mashup-work' else '"exporter"'
    s = EXP_RE.sub('os.path.join(os.path.dirname(os.path.abspath(__file__)), %s)' % rel, s)
    if s == o:
        return 'unchanged'
    if not re.search(r'^\s*import\s+(?:[\w, ]*\b)?os\b', s, re.M):
        # (after a module docstring and any __future__ import)
        m = re.match(r'(\s*(?:[rRbBuU]?"""[\s\S]*?"""|[rRbBuU]?\'\'\'[\s\S]*?\'\'\')\s*\n)?', s)
        i = m.end() if m else 0
        s = s[:i] + 'import os\n' + s[i:]
    shutil.copy(path, path + '.bak_before_param')
    open(path, 'w', encoding='utf-8', newline='').write(s)
    return 'changed'


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(p, fix(p))
