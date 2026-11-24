#!/usr/bin/env python3
"""Renders the HCG System Tester app icon (obsidian/navy squircle, cyan→violet
connection rings and a host node) at every macOS icon size.

Usage: python3 scripts/render-icon.py <AppIcon.appiconset directory>
Only Pillow is required. The output is deterministic.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def render(px):
    s = 4  # supersample
    n = px * s
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    inset = int(n * 0.098)  # macOS icon grid margin
    size = n - 2 * inset
    radius = int(size * 0.225)

    # Background gradient squircle.
    bg = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(bg)
    top, bottom = (14, 22, 44, 255), (6, 8, 14, 255)
    for y in range(n):
        d.line([(0, y), (n, y)], fill=lerp(top, bottom, y / n))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, n - inset, n - inset], radius=radius, fill=255)
    img.paste(bg, (0, 0), mask)

    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    cx, cy = n / 2, n / 2
    cyan, violet = (0, 219, 255), (148, 102, 255)

    # Orbit rings.
    for i, r in enumerate([0.36, 0.27, 0.18]):
        rr = size * r
        col = lerp(cyan, violet, i / 2) + (255,)
        g.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=col, width=max(2, int(n * 0.012)))

    # Satellite device nodes on the outer ring, linked to the host.
    for k, ang in enumerate([-60, 20, 140, 220]):
        a = math.radians(ang)
        rr = size * 0.36
        x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
        col = lerp(cyan, violet, k / 3) + (255,)
        g.line([(cx, cy), (x, y)], fill=col[:3] + (150,), width=max(1, int(n * 0.008)))
        nr = size * 0.045
        g.ellipse([x - nr, y - nr, x + nr, y + nr], fill=(10, 16, 32, 255), outline=col, width=max(2, int(n * 0.01)))

    # Host core.
    hr = size * 0.085
    g.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=cyan + (255,))
    blurred = glow.filter(ImageFilter.GaussianBlur(n * 0.02))
    img = Image.alpha_composite(img, Image.composite(blurred, Image.new("RGBA", (n, n), (0, 0, 0, 0)), mask))
    img = Image.alpha_composite(img, Image.composite(glow, Image.new("RGBA", (n, n), (0, 0, 0, 0)), mask))

    # Metallic hairline.
    ImageDraw.Draw(img).rounded_rectangle([inset, inset, n - inset, n - inset], radius=radius,
                                          outline=(170, 180, 205, 110), width=max(1, int(n * 0.006)))
    return img.resize((px, px), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.appiconset"
    os.makedirs(out, exist_ok=True)
    images = []
    for pt, scale in SIZES:
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        render(px).save(os.path.join(out, name))
        images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}", "filename": name})
    with open(os.path.join(out, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print(f"Wrote {len(images)} icons to {out}")


if __name__ == "__main__":
    main()
