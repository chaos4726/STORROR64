"""What surrounds a level: its sky and its music, as Mario 64's level data names them.

Skies are stored in the ROM as 32x32 tiles with a table saying where each goes; `extract_skies` puts each
one back together from the player's own ROM as textures/sky_<name>.png. A level without a sky has a flat
background colour instead, written as a small one-colour picture so that both are used the same way."""
import os, re, json, struct, sys
import sm64x as X
from sm64x import try_int

SKY_BY_BACKGROUND = {
    'BACKGROUND_OCEAN_SKY': 'water', 'BACKGROUND_FLAMING_SKY': 'bitfs', 'BACKGROUND_UNDERWATER_CITY': 'wdw',
    'BACKGROUND_BELOW_CLOUDS': 'cloud_floor', 'BACKGROUND_SNOW_MOUNTAINS': 'ccm', 'BACKGROUND_DESERT': 'ssl',
    'BACKGROUND_HAUNTED': 'bbh', 'BACKGROUND_GREEN_SKY': 'bidw', 'BACKGROUND_ABOVE_CLOUDS': 'clouds',
    'BACKGROUND_PURPLE_SKY': 'bits',
}
used_colors = set()


def area_sky(db, geo_name):
    """'water', 'bbh', ... for a level with a sky; 'color_XXXX' (RGBA5551) for one with a flat background"""
    found = []

    def walk(node, depth=0):
        for ch in node['children']:
            c, a = ch['cmd'], ch['args']
            if c == 'GEO_BACKGROUND' and a:
                found.append(SKY_BY_BACKGROUND.get(a[0].strip()))
            elif c == 'GEO_BACKGROUND_COLOR' and a:
                v = try_int(a[0])
                if v is not None:
                    used_colors.add(v)
                    found.append('color_%04x' % v)
            if depth < 12:
                walk(ch, depth + 1)
    walk(X.parse_geo(db, geo_name))
    found = [f for f in found if f]
    return found[0] if found else 'color_0001'


def area_music(level, area):
    """the sequence the area plays, as its name without SEQ_ in lower case ('level_grass'); None for silence"""
    t = X.strip_comments(open(os.path.join(X.D, 'levels', level, 'script.c'), encoding='utf-8', errors='replace').read())
    for m in re.finditer(r'\bAREA\s*\(\s*(\d+)', t):
        if int(m.group(1)) != area:
            continue
        end = t.find('END_AREA', m.end())
        s = re.search(r'SET_BACKGROUND_MUSIC\(\s*\w+\s*,\s*\(?\s*(SEQ_\w+)', t[m.end():end])
        if s and s.group(1) != 'SEQ_SOUND_PLAYER':
            return s.group(1)[4:].lower()
    return None


# ---------------------------------------------------------------- from the ROM
def _mio0(rom, o):
    assert rom[o:o + 4] == b'MIO0', 'no MIO0 block at %x' % o
    size, comp_off, raw_off = struct.unpack('>III', rom[o + 4:o + 16])
    out = bytearray()
    lay, ci, ri = o + 16, o + comp_off, o + raw_off
    bit, mask = 0, 0
    while len(out) < size:
        if bit == 0:
            mask = struct.unpack('>I', rom[lay:lay + 4])[0]
            lay += 4
            bit = 32
        if mask & 0x80000000:
            out.append(rom[ri])
            ri += 1
        else:
            v = struct.unpack('>H', rom[ci:ci + 2])[0]
            ci += 2
            length, dist = (v >> 12) + 3, (v & 0xFFF) + 1
            for _ in range(length):
                out.append(out[-dist])
        mask = (mask << 1) & 0xFFFFFFFF
        bit -= 1
    return bytes(out[:size])


def extract_skies(rom_path, out_dir, upscale=3):
    from PIL import Image
    rom = open(rom_path, 'rb').read()
    assets = json.load(open(os.path.join(X.D, 'assets.json')))
    os.makedirs(out_dir, exist_ok=True)
    made = []
    for path, info in assets.items():
        if not path.startswith('textures/skyboxes/'):
            continue
        name = os.path.splitext(os.path.basename(path))[0]
        where = info[1]['us']
        data = _mio0(rom, where[0])[where[1]:]      # (the size listed for a sky is not always this ROM's)
        size = len(data)
        table = struct.unpack('>80I', data[size - 320:size])
        img = Image.new('RGBA', (248, 248))
        for row in range(8):
            for col in range(8):
                off = table[row * 10 + col] & 0x00FFFFFF
                px = struct.unpack('>1024H', data[off:off + 2048])
                tile = Image.new('RGBA', (32, 32))
                tile.putdata([(((p >> 11) & 31) * 255 // 31, ((p >> 6) & 31) * 255 // 31, ((p >> 1) & 31) * 255 // 31, 255) for p in px])
                img.paste(tile.crop((0, 0, 31, 31)), (col * 31, row * 31))
        img = img.convert('RGB').resize((248 * upscale, 248 * upscale), Image.BICUBIC)
        img.save(os.path.join(out_dir, 'sky_%s.png' % name))
        made.append(name)
    return made


def write_colors(out_dir):
    from PIL import Image
    for v in sorted(used_colors | {0x0001}):
        rgb = (((v >> 11) & 31) * 255 // 31, ((v >> 6) & 31) * 255 // 31, ((v >> 1) & 31) * 255 // 31)
        Image.new('RGB', (16, 16), rgb).save(os.path.join(out_dir, 'sky_color_%04x.png' % v))


if __name__ == '__main__':
    print(extract_skies(sys.argv[1], sys.argv[2]))
