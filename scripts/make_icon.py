#!/usr/bin/env python3
"""Generates the Klowop app icon (1024x1024): indigo->purple diagonal gradient
with a soft glow and a white four-point spark, echoing the assistant's sparkle."""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S))
px = img.load()

# Diagonal gradient: deep indigo (top-left) -> vivid purple (bottom-right)
c1 = (44, 38, 110)    # deep indigo
c2 = (124, 58, 237)   # vivid purple
c3 = (167, 99, 250)   # light purple accent for the very corner
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        if t < 0.75:
            u = t / 0.75
            r = int(c1[0] + (c2[0] - c1[0]) * u)
            g = int(c1[1] + (c2[1] - c1[1]) * u)
            b = int(c1[2] + (c2[2] - c1[2]) * u)
        else:
            u = (t - 0.75) / 0.25
            r = int(c2[0] + (c3[0] - c2[0]) * u)
            g = int(c2[1] + (c3[1] - c2[1]) * u)
            b = int(c2[2] + (c3[2] - c2[2]) * u)
        px[x, y] = (r, g, b)


def spark(draw, cx, cy, radius, waist, color):
    """Four-point star with concave sides (SF-symbols 'sparkle' silhouette)."""
    points = []
    for i in range(8):
        angle = math.pi / 4 * i - math.pi / 2
        r = radius if i % 2 == 0 else waist
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=color)


# Soft glow behind the spark
glow = Image.new("L", (S, S), 0)
spark(ImageDraw.Draw(glow), S / 2, S / 2, 360, 86, 110)
glow = glow.filter(ImageFilter.GaussianBlur(70))
img.paste((255, 255, 255), (0, 0), glow)

# Main spark + companion mini-spark (like the sparkles SF Symbol)
overlay = Image.new("L", (S, S), 0)
od = ImageDraw.Draw(overlay)
spark(od, S * 0.47, S * 0.53, 330, 78, 255)
spark(od, S * 0.76, S * 0.26, 110, 30, 255)
overlay = overlay.filter(ImageFilter.GaussianBlur(2))
img.paste((255, 255, 255), (0, 0), overlay)

out = "Klowop/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out, "PNG")
print("wrote", out)
