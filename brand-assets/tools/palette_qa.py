"""Palette QA for generated photos: median tone, light-source colour, and share of red / gold / violet pixels.

Run from backend/venv:  python palette_qa.py path/to/a.png path/to/b.png ...
Reads: the brightest 3% of pixels (the light source) and the median pixel (the overall tone). In the Mayordommo
pack every night frame should have a violet median (aubergine/plum), a light source with Lantern Gold's hue
(~38 degrees, more saturated is fine for a light source), and almost no red pixels (no red wall bands).
"""
import colorsys, sys
from PIL import Image

print("%-40s %-8s %-8s %5s %5s %5s" % ("file", "bright", "median", "red%", "gold%", "viol%"))
for p in sys.argv[1:]:
    im = Image.open(p).convert("RGB")
    im.thumbnail((320, 180))
    px = sorted(im.getdata(), key=sum)
    n = len(px)
    top, mid = px[int(n * 0.97):], px[n // 2]
    avg = lambda L: "#%02X%02X%02X" % tuple(sum(c[i] for c in L) // len(L) for i in range(3))
    red = gold = viol = 0
    for r, g, b in px:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        h *= 360
        if s > 0.45 and v > 0.2:
            if h < 14 or h > 346:
                red += 1
            elif 30 <= h <= 50:
                gold += 1
        if 250 <= h <= 295 and s > 0.2:
            viol += 1
    print("%-40s %-8s %-8s %5.1f %5.1f %5.1f" % (p[-40:], avg(top), "#%02X%02X%02X" % mid, 100 * red / n, 100 * gold / n, 100 * viol / n))
