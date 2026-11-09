# r96_overlay.py : a copy of the decomp (sm64decomp/) with the Render96 model pack's actors put over its own
# (github.com/Render96/ModelPack, branch models_vanilla - the Render96 team's), for the mod's own exporter to read
# (tools/r96_models.py). Each Render96 actor whose folder the decomp has: the decomp's model.inc.c and geo.inc.c taken
# out, Render96's put in - its declarations written the decomp's way, as the exporter's index reads them - its pictures
# beside them; the decomp's animations (anims/) kept: the models keep Mario 64's skeletons.
import os, re, shutil, sys

SRC = r"X:\mashup-work\sm64decomp"
DST = r"X:\mashup-work\r96_build\decomp"
R96 = r"X:\mashup-work\r96_dl\models\x\Render96\actors"

if os.path.exists(DST):
    shutil.rmtree(DST)
shutil.copytree(SRC, DST, ignore=shutil.ignore_patterns('.git', 'tools', 'build', '*.o'))

RULES = [
    (re.compile(r'^Lights1\s+(\w+)\s*=\s*gdSPDefLights1\(', re.M), r'static const Lights1 \1 = gdSPDefLights1('),
    (re.compile(r'^Lights0\s+(\w+)\s*=\s*gdSPDefLights0\(', re.M), r'static const Lights0 \1 = gdSPDefLights0('),
    (re.compile(r'^(?:const\s+)?(?:u8|u16|Texture)\s+(\w+)\s*\[\s*\]\s*=\s*"([^"]+)"\s*;', re.M),
     r'const Texture \1[] = {\n#include "\2.inc.c"\n};'),
    (re.compile(r'^(?:static\s+)?(?:const\s+)?Vtx\s+(\w+)\s*\[\s*\d*\s*\]\s*=\s*\{', re.M), r'const Vtx \1[] = {'),
    (re.compile(r'^(?:static\s+)?(?:const\s+)?Gfx\s+(\w+)\s*\[\s*\d*\s*\]\s*=\s*\{', re.M), r'const Gfx \1[] = {'),
    (re.compile(r'^(?:static\s+)?(?:const\s+)?GeoLayout\s+(\w+)\s*\[\s*\d*\s*\]\s*=\s*\{', re.M), r'const GeoLayout \1[] = {'),
]

# Render96's materials (fast64's) set their colour by a combiner the exporter does not read - gsDPSetCombineLERP - and
# light or texture each as that says. Put the exporter's way, each material: the picture times the light, as most; the
# picture alone (TEXEL0, no SHADE) a decal - white, no light in it: the Chain Chomp's body took the mouth's red light
# before it; the light alone (no TEXEL) untextured - the Goomba's teeth took the picture before them, black
# ("goomba teeth being black, chainchomp being red", 2026-10-31). And their pictures laid on by the view (G_TEXTURE_GEN,
# the shine of the Chomp and the stars) laid on as they lie - the exporter cannot do the view's.
COMB = re.compile(r'gsDPSetCombineLERP\(([^)]*)\)')
MAT = re.compile(r'(const Gfx \w+\[\] = \{)(.*?)(\n\};)', re.S)
def fix_material(m):
    head, body, tail = m.group(1), m.group(2), m.group(3)
    c = COMB.search(body)
    if c:
        a = [x.strip() for x in c.group(1).split(',')]
        col = a[0:4]
        tex = any(x.startswith('TEXEL') for x in col)
        shade = 'SHADE' in col
        mode = 'G_CC_DECALRGB' if (tex and not shade) else 'G_CC_MODULATERGB'
        body = body.replace(c.group(0), 'gsDPSetCombineMode(%s, %s)' % (mode, mode))
        if not tex:
            body = re.sub(r'gsSPTexture\(([^)]*?),\s*1\s*\)', r'gsSPTexture(\1, 0)', body)
    # (G_TEXTURE_GEN kept: the exporter lays those on as sphere maps now - SM64_TEXGEN_SPHERE, tools/r96_models.py)
    return head + body + tail
RULES.append((MAT, fix_material))

# Render96 models whose skeleton is one part short of Mario 64's animation: the part put back, empty. The Amp's mouth is
# in its body (amp_geo): Mario 64's dAmpGeo has a part for it before the last, and the animation's twelve joints went one
# short ("add all the 3d models", 2026-10-31).
# Eyerok's left hand (drawn mirrored) has its own eye, wound the other way round for the N64's mirror (G_CULL_FRONT);
# Unreal turns a mirrored model's faces itself, so that eye was drawn from behind - gone ("the hand on the right side is
# missing an eye", 2026-10-31). It takes the right hand's eye, as the rest of the hand does.
_EYE_L = ('\t\t\t\t\tGEO_DISPLAY_LIST(4, eyerok_000_switch_frame0left_mesh),\n\t\t\t\tGEO_CLOSE_NODE(),\n'
          '\t\t\t\tGEO_BRANCH(1, eyerok_frame0left),\n\t\t\t\tGEO_BRANCH(1, eyerok_frame1left),\n'
          '\t\t\t\tGEO_BRANCH(1, eyerok_frame3left),\n\t\t\t\tGEO_BRANCH(1, eyerok_frame2left),')
FIXES = {
    'eyerok': [(_EYE_L, _EYE_L.replace('frame0left_mesh', 'frame0_mesh').replace('left)', ')'))],
    'amp': [('''            GEO_CLOSE_NODE(),
            GEO_ANIMATED_PART(LAYER_OPAQUE, 0, 0, 0, NULL),
            GEO_OPEN_NODE(),
               //GEO_BILLBOARD(),''',
             '''            GEO_CLOSE_NODE(),
            GEO_ANIMATED_PART(LAYER_ALPHA, 0, 0, 0, NULL),
            GEO_ANIMATED_PART(LAYER_OPAQUE, 0, 0, 0, NULL),
            GEO_OPEN_NODE(),
               //GEO_BILLBOARD(),''')],
}

done, skipped = [], []
# (Render96 actors whose models the decomp keeps in another actor's folder: put in beside them, nothing taken out)
MERGE = {'pokey_body_part': 'pokey'}
for name, into in MERGE.items():
    src = os.path.join(R96, name)
    dst = os.path.join(DST, 'actors', into)
    if os.path.isdir(src) and os.path.isdir(dst):
        for f in os.listdir(src):
            s = os.path.join(src, f)
            if os.path.isdir(s):
                continue
            # (its files and pictures by its own name in the other actor's folder, and its pictures asked for there: they
            # pointed at actors/<name>/, which the decomp has not - the Pokey's body had no picture at all, and its
            # pokey_body.rgba32 had written over the head's - "dori pokey", 2026-10-31)
            out = os.path.join(dst, name + '_' + f)
            if f.endswith('.c') or f.endswith('.h'):
                t = open(s, encoding='utf-8', errors='replace').read()
                t = t.replace('"actors/%s/' % name, '"actors/%s/%s_' % (into, name))
                t = re.sub(r'\};[ \t]*(?=[A-Za-z])', '};\n', t)
                for rx, rep in RULES:
                    t = rx.sub(rep, t)
                open(out, 'w', encoding='utf-8', newline='\n').write(t)
            else:
                shutil.copy(s, out)
        done.append(name + '->' + into)
for name in sorted(os.listdir(R96)):
    src = os.path.join(R96, name)
    if not os.path.isdir(src) or name in MERGE:
        continue
    dst = os.path.join(DST, 'actors', name)
    if not os.path.isdir(dst):
        skipped.append(name)
        continue
    for f in ('model.inc.c', 'geo.inc.c', 'geo_header.h'):
        p = os.path.join(dst, f)
        if os.path.exists(p):
            os.remove(p)
    for f in os.listdir(src):
        s = os.path.join(src, f)
        if os.path.isdir(s):
            continue
        if f.endswith('.c') or f.endswith('.h'):
            t = open(s, encoding='utf-8', errors='replace').read()
            # (a declaration straight after the one before's "};", on its line: put on a line of its own)
            t = re.sub(r'\};[ \t]*(?=[A-Za-z])', '};\n', t)
            for rx, rep in RULES:
                t = rx.sub(rep, t)
            for a, b in FIXES.get(name, []):
                if f == 'geo.inc.c':
                    if a not in t:
                        print('!! fix for', name, 'not found')
                    t = t.replace(a, b)
            open(os.path.join(dst, f), 'w', encoding='utf-8', newline='\n').write(t)
        else:
            shutil.copy(s, os.path.join(dst, f))
    done.append(name)
print('Render96 actors put in:', len(done), ' '.join(done))
print('not in the decomp (left out):', ' '.join(skipped))
