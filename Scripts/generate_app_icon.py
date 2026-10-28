#!/usr/bin/env python3
"""Generate a premium macOS AppIcon set for FGMacOS Optimizer."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "FGMacOSOptimizer" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
MASTER = ROOT / "FGMacOSOptimizer" / "Resources" / "AppIcon-1024.png"

SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1, c2, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))


def rounded_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top, bottom) -> Image.Image:
    """Fast vertical gradient via a 1×N strip resized."""
    strip = Image.new("RGB", (1, size))
    for y in range(size):
        strip.putpixel((0, y), mix(top, bottom, y / (size - 1)))
    return strip.resize((size, size), Image.Resampling.BILINEAR).convert("RGBA")


def radial_shade(size: int) -> Image.Image:
    """Soft radial vignette + corner light."""
    layer = Image.new("L", (size, size), 0)
    cx = cy = size / 2
    pix = layer.load()
    for y in range(size):
        for x in range(size):
            dx = (x - cx) / cx
            dy = (y - cy) / cy
            r = math.sqrt(dx * dx + dy * dy)
            # brighter center-top-left, darker edges
            hx = (x - size * 0.32) / size
            hy = (y - size * 0.28) / size
            hl = max(0.0, 1.0 - math.sqrt(hx * hx + hy * hy) * 2.8)
            val = int(max(0, min(255, (1.0 - r * 0.42) * 210 + hl * 70)))
            pix[x, y] = val
    return layer


def draw_icon(size: int = 1024) -> Image.Image:
    # Base gradient: midnight navy → electric cobalt
    base = vertical_gradient(size, (7, 20, 52), (10, 118, 210))
    # Cross-blend a second diagonal feel via overlay
    overlay = vertical_gradient(size, (20, 70, 160), (5, 30, 70)).rotate(35, expand=False)
    base = Image.blend(base, overlay, 0.28)

    shade = radial_shade(size)
    shaded = Image.new("RGBA", (size, size))
    bp = base.load()
    sp = shade.load()
    op = shaded.load()
    for y in range(size):
        for x in range(size):
            r, g, b, _ = bp[x, y]
            s = sp[x, y] / 255.0
            op[x, y] = (int(r * s), int(g * s), int(b * s), 255)

    img = shaded
    draw = ImageDraw.Draw(img)

    # Soft cyan glow ring
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    pad = int(size * 0.10)
    gdraw.ellipse([pad, pad, size - pad, size - pad], outline=(90, 200, 255, 90), width=max(3, size // 70))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=size * 0.025))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # Gauge arcs
    track_pad = int(size * 0.21)
    bbox = [track_pad, track_pad, size - track_pad, size - track_pad]
    track_w = max(8, size // 16)

    draw.arc(bbox, start=135, end=405, fill=(255, 255, 255, 40), width=track_w)
    draw.arc(bbox, start=135, end=315, fill=(110, 220, 255, 245), width=track_w)
    draw.arc(bbox, start=300, end=325, fill=(255, 255, 255, 230), width=track_w)

    cx = cy = size / 2

    # Frosted inner disc
    disc = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    inner = int(size * 0.32)
    dd.ellipse(
        [cx - inner, cy - inner, cx + inner, cy + inner],
        fill=(235, 245, 255, 32),
        outline=(255, 255, 255, 60),
        width=max(2, size // 160),
    )
    disc = disc.filter(ImageFilter.GaussianBlur(radius=max(1, size // 120)))
    img = Image.alpha_composite(img, disc)
    draw = ImageDraw.Draw(img)

    # Tick marks
    for i in range(9):
        ang = math.radians(135 + i * 30)
        r1 = size * 0.335
        r2 = size * 0.375 if i % 2 == 0 else size * 0.36
        x1, y1 = cx + math.cos(ang) * r1, cy + math.sin(ang) * r1
        x2, y2 = cx + math.cos(ang) * r2, cy + math.sin(ang) * r2
        draw.line([(x1, y1), (x2, y2)], fill=(220, 238, 255, 170), width=max(2, size // 200))

    # Needle @ ~67%
    needle_ang = math.radians(315)
    needle_len = size * 0.29
    nx = cx + math.cos(needle_ang) * needle_len
    ny = cy + math.sin(needle_ang) * needle_len
    draw.line([(cx + 3, cy + 4), (nx + 3, ny + 4)], fill=(0, 10, 30, 100), width=max(4, size // 80))
    draw.line([(cx, cy), (nx, ny)], fill=(245, 252, 255, 255), width=max(4, size // 85))
    tip = max(4, size // 60)
    draw.ellipse([nx - tip, ny - tip, nx + tip, ny + tip], fill=(100, 215, 255, 255))

    # Hub
    hub = max(10, size // 20)
    draw.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=(248, 252, 255, 255))
    draw.ellipse(
        [cx - hub * 0.52, cy - hub * 0.52, cx + hub * 0.52, cy + hub * 0.52],
        fill=(25, 105, 220, 255),
    )

    # Lightning bolt
    bolt = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bolt)
    s = size * 0.058
    bx, by = cx + size * 0.125, cy + size * 0.105
    points = [
        (bx, by - s * 1.45),
        (bx + s * 0.58, by - s * 0.12),
        (bx + s * 0.12, by - s * 0.12),
        (bx + s * 0.78, by + s * 1.45),
        (bx - s * 0.18, by + s * 0.22),
        (bx + s * 0.28, by + s * 0.22),
    ]
    bd.polygon(points, fill=(255, 214, 70, 255))
    bolt_glow = bolt.filter(ImageFilter.GaussianBlur(radius=size * 0.014))
    # tint glow yellow
    img = Image.alpha_composite(img, bolt_glow)
    img = Image.alpha_composite(img, bolt)

    # Top glass sheen
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([size * 0.10, size * 0.04, size * 0.90, size * 0.46], fill=(255, 255, 255, 34))
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=size * 0.045))
    img = Image.alpha_composite(img, sheen)

    # Subtle contrast polish
    img = ImageEnhance.Contrast(img).enhance(1.06)
    img = ImageEnhance.Color(img).enhance(1.08)

    # Apple continuous-corner mask
    radius = size * 0.2237
    mask = rounded_mask(size, radius)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask=mask)
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("Rendering 1024×1024 master…")
    master = draw_icon(1024)
    MASTER.parent.mkdir(parents=True, exist_ok=True)
    master.save(MASTER, "PNG", optimize=True)
    print(f"Wrote {MASTER}")

    images = []
    for base, scale in SIZES:
        px = base * scale
        name = f"icon_{base}x{base}@{scale}x.png"
        master.resize((px, px), Image.Resampling.LANCZOS).save(OUT_DIR / name, "PNG", optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{base}x{base}"})
        print(f"  {name}")

    (OUT_DIR / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    print("AppIcon.appiconset ready")


if __name__ == "__main__":
    main()
