"""Regenerates the app icon assets (assets/icon/icon.png and
assets/icon/icon_foreground.png) used by flutter_launcher_icons.

Mark: a gold house with an arched door on forest green. The same shape is
drawn in lib/core/widgets/kost_logo.dart - keep the two in sync.

Run with: python3 gen_icon.py
Requires: pip install pillow
"""
from PIL import Image, ImageDraw, ImageChops

FOREST = (12, 59, 46, 255)    # #0C3B2E
GOLD = (255, 186, 0, 255)     # #FFBA00
TRANSPARENT = (0, 0, 0, 0)

SS = 4
BASE = 1024
S = BASE * SS

# House outline in unit coordinates (must match kost_logo.dart)
HOUSE = [(0.50, 0.20), (0.86, 0.50), (0.76, 0.50), (0.76, 0.80),
         (0.24, 0.80), (0.24, 0.50), (0.14, 0.50)]
DOOR_X, DOOR_R, DOOR_TOP, DOOR_BOTTOM = 0.50, 0.075, 0.62, 0.80
ROUND = 0.03  # corner softening (stroke width of the outline)


def house_mask(size):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    pts = [(x * size, y * size) for x, y in HOUSE]
    d.polygon(pts, fill=255)
    w = int(ROUND * size)
    d.line(pts + [pts[0]], fill=255, width=w, joint="curve")
    for x, y in pts:
        r = w / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    door = Image.new("L", (size, size), 0)
    dd = ImageDraw.Draw(door)
    cx, r = DOOR_X * size, DOOR_R * size
    dd.rectangle([cx - r, DOOR_TOP * size, cx + r, DOOR_BOTTOM * size + w], fill=255)
    dd.ellipse([cx - r, DOOR_TOP * size - r, cx + r, DOOR_TOP * size + r], fill=255)
    return ImageChops.subtract(m, door)


def glyph(size, color):
    img = Image.new("RGBA", (size, size), TRANSPARENT)
    img.paste(Image.new("RGBA", (size, size), color), (0, 0), house_mask(size))
    return img


# 1. Full icon: solid background + glyph, full bleed (the OS applies its mask)
full = Image.new("RGBA", (S, S), FOREST)
g = glyph(int(S * 0.74), GOLD)
off = (S - g.width) // 2
full.alpha_composite(g, (off, off))
full.resize((BASE, BASE), Image.LANCZOS).convert("RGB").save("assets/icon/icon.png")

# 2. Adaptive-icon foreground: transparent, glyph inside the safe zone
fg = Image.new("RGBA", (S, S), TRANSPARENT)
g2 = glyph(int(S * 0.66), GOLD)
off2 = (S - g2.width) // 2
fg.alpha_composite(g2, (off2, off2))
fg.resize((BASE, BASE), Image.LANCZOS).save("assets/icon/icon_foreground.png")

print("Wrote assets/icon/icon.png and assets/icon/icon_foreground.png")
