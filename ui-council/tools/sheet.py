#!/usr/bin/env python3
"""Contact sheet of a screenshot folder: sheet.py <dir> <out.jpg> [light|dark] [height]"""
import sys, glob, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
look = sys.argv[3] if len(sys.argv) > 3 else "light"
h = int(sys.argv[4]) if len(sys.argv) > 4 else 700
files = sorted(glob.glob(os.path.join(d, f"*-{look}.png")))
ims = [Image.open(f).convert("RGB") for f in files]
ims = [i.resize((int(i.width * h / i.height), h)) for i in ims]
cols = 8
w = ims[0].width
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (w + 10), rows * (h + 40)), "#888")
dr = ImageDraw.Draw(sheet)
for k, (f, im) in enumerate(zip(files, ims)):
    x, y = (k % cols) * (w + 10), (k // cols) * (h + 40)
    sheet.paste(im, (x, y + 30))
    dr.text((x + 4, y + 8), os.path.basename(f).rsplit("-", 1)[0], fill="white")
sheet.save(out, quality=82)
