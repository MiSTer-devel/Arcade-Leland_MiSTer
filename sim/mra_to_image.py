"""Build the flat download image an MRA describes (what the MiSTer sends to the core).

usage: python mra_to_image.py game.mra roms_dir out.bin

Handles <part> (hex data, name/offset/length, repeat) and <interleave output="16"> with
map="01" (even bytes) / map="10" (odd bytes). Files missing from the game's zip are
looked up in its parent sets (offroad for offroadt).
"""
import sys, zipfile, os
import xml.etree.ElementTree as ET

mra, roms, out = sys.argv[1:4]
root = ET.parse(mra).getroot()
rom = root.find('rom')
zips = [rom.get('zip')]
parents = {'offroadt.zip': ['offroad.zip'], 'pigout.zip': [], 'ataxx.zip': [], 'indyheat.zip': [], 'offroad.zip': []}
zips += parents.get(zips[0], [])
zfs = [zipfile.ZipFile(os.path.join(roms, z)) for z in zips]

def load(name):
    for z in zfs:
        if name in z.namelist():
            return z.read(name)
    raise SystemExit('missing ' + name)

def num(v, d=0):
    return int(v, 0) if v else d

def part_bytes(p):
    if p.get('name'):
        data = load(p.get('name'))
        off = num(p.get('offset'))
        n = num(p.get('length'), len(data) - off)
        return data[off:off + n]
    text = (p.text or '').split()
    data = bytes(int(t, 16) for t in text)
    return data * num(p.get('repeat'), 1)

img = bytearray()
for el in rom:
    if el.tag == 'part':
        img += part_bytes(el)
    elif el.tag == 'interleave':
        parts = [(p.get('map'), part_bytes(p)) for p in el.findall('part')]
        assert el.get('output') == '16' and len(parts) == 2, 'unsupported interleave'
        even = next(b for m, b in parts if m == '01')
        odd = next(b for m, b in parts if m == '10')
        assert len(even) == len(odd)
        buf = bytearray(len(even) * 2)
        buf[0::2] = even
        buf[1::2] = odd
        img += buf
open(out, 'wb').write(img)
print(os.path.basename(mra), len(img), 'bytes')
