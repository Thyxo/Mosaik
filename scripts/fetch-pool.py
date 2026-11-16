#!/usr/bin/env python3
"""Henter billedpuljen (Picsum/Unsplash-licens) til ios/Mosaik/Resources/Pool/ og laver pool.json
med gennemsnitsfarve (Lab) + 2x2 delfarver for hvert billede. Køres én gang; resultatet committes."""
import io, json, os, sys, urllib.request, concurrent.futures as cf
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios', 'Mosaik', 'Resources', 'Pool')
SIZE = 300
os.makedirs(OUT, exist_ok=True)

def srgb_to_lab(r, g, b):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = lin(r), lin(g), lin(b)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return [round(116 * fy - 16, 2), round(500 * (fx - fy), 2), round(200 * (fy - fz), 2)]

def fetch(i):
    path = os.path.join(OUT, f'p{i:04d}.jpg')
    if not os.path.exists(path):
        try:
            data = urllib.request.urlopen(f'https://picsum.photos/id/{i}/{SIZE}/{SIZE}', timeout=30).read()
        except Exception:
            return None
        im = Image.open(io.BytesIO(data)).convert('RGB').resize((SIZE, SIZE))
        im.save(path, 'JPEG', quality=72, optimize=True, progressive=False)
    im = Image.open(path).convert('RGB')
    avg = im.resize((1, 1), Image.BOX).getpixel((0, 0))
    q = im.resize((2, 2), Image.BOX)
    quads = [srgb_to_lab(*q.getpixel((x, y))) for y in range(2) for x in range(2)]
    return {'f': f'p{i:04d}', 'lab': srgb_to_lab(*avg), 'q': quads}

ids = range(0, int(sys.argv[1]) if len(sys.argv) > 1 else 1085)
with cf.ThreadPoolExecutor(12) as ex:
    items = [r for r in ex.map(fetch, ids) if r]
json.dump(items, open(os.path.join(OUT, '..', 'pool.json'), 'w'), separators=(',', ':'))
print(len(items), 'billeder')
