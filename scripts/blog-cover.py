#!/usr/bin/env python3
"""Blog cover in the site style: blue grainy sky, eyebrow, title, subtitle, optional chips.
Usage: scripts/blog-cover.py <out dir> "<title>" "<subtitle>" [chip ...]
Writes cover.webp (page) and og.jpg (social card), both 1200x630. Needs rsvg-convert, cwebp, sips."""
import os, subprocess, sys
from html import escape

out, title, subtitle, chips = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
W, H = 1200, 630

def width(t):  # ponytail: rough per-script glyph widths, good enough to centre pills
    return sum(26 if ord(c) > 0x2e80 else 19 if ord(c) > 0x0900 else 14.5 for c in t) + 44

rows, row = [], []
for c in chips:  # wrap chips into rows under 1000 px
    if row and sum(width(x) + 14 for x in row) + width(c) > 1000: rows.append(row); row = []
    row.append(c)
if row: rows.append(row)
top = 300 if chips else 270
title_y = 210 if chips else 300
pills, y = [], top
for r in rows:
    x = (W - sum(width(t) for t in r) - 14 * (len(r) - 1)) / 2
    for i, t in enumerate(r):
        first = y == top and i == 0
        pills.append(f'<rect x="{x:.0f}" y="{y}" width="{width(t):.0f}" height="48" rx="24" fill="{"#fff" if first else "rgba(255,255,255,0.16)"}" stroke="rgba(255,255,255,0.45)"/>'
                     f'<text x="{x + width(t) / 2:.0f}" y="{y + 31}" text-anchor="middle" font-size="22" font-weight="500" fill="{"#0A0A0A" if first else "#fff"}">{escape(t)}</text>')
        x += width(t) + 14
    y += 64

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="Helvetica Neue, PingFang SC, Hiragino Sans, Apple SD Gothic Neo, Geeza Pro, Thonburi, Kohinoor Devanagari, sans-serif">
<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1f57c9"/><stop offset="0.35" stop-color="#2d6ce0"/><stop offset="0.7" stop-color="#4f8ae9"/><stop offset="1" stop-color="#8cb8f3"/></linearGradient>
<filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>
<filter id="noise"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter></defs>
<rect width="{W}" height="{H}" fill="url(#sky)"/>
<ellipse cx="120" cy="140" rx="260" ry="120" fill="#fff" opacity="0.35" filter="url(#blur)"/><ellipse cx="1100" cy="90" rx="260" ry="110" fill="#fff" opacity="0.3" filter="url(#blur)"/>
<ellipse cx="300" cy="600" rx="420" ry="130" fill="#fff" opacity="0.4" filter="url(#blur)"/><ellipse cx="1000" cy="620" rx="380" ry="120" fill="#fff" opacity="0.35" filter="url(#blur)"/>
<rect width="{W}" height="{H}" filter="url(#noise)" opacity="0.18"/>
<text x="600" y="{title_y - 82}" text-anchor="middle" font-size="22" font-weight="500" fill="rgba(255,255,255,0.8)" letter-spacing="3">STASH</text>
<text x="600" y="{title_y}" text-anchor="middle" font-size="64" font-weight="500" fill="#fff" letter-spacing="-1.5">{escape(title)}</text>
<text x="600" y="{title_y + 46}" text-anchor="middle" font-size="22" fill="rgba(255,255,255,0.8)">{escape(subtitle)}</text>
{"".join(pills)}</svg>'''

os.makedirs(out, exist_ok=True)
svg_path, png = os.path.join(out, '.cover.svg'), os.path.join(out, '.cover.png')
open(svg_path, 'w').write(svg)
subprocess.run(['rsvg-convert', '-w', str(W), svg_path, '-o', png], check=True)
subprocess.run(['cwebp', '-quiet', '-q', '82', png, '-o', os.path.join(out, 'cover.webp')], check=True)
subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '75', png, '--out', os.path.join(out, 'og.jpg')], check=True, capture_output=True)
os.remove(svg_path); os.remove(png)
print(f'Wrote {out}/cover.webp and {out}/og.jpg')
