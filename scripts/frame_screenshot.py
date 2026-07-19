#!/usr/bin/env python3
"""frame_screenshot.py — frame a macOS screenshot onto a background at App Store size.

Turns a raw screenshot (a menu-bar popover, a window, or a full desktop) into a
polished App Store / marketing image: the content centered on a gradient — or on
the screenshot's own blurred wallpaper — with a soft drop shadow, exported at a
valid App Store size. No services; just Pillow + numpy (both open source).

    pip install pillow numpy

Examples
--------
# Menu popover cropped from a desktop shot, centered on the Mou Sugu gradient:
  ./frame_screenshot.py shot.png out.png --crop 1270,31,1521,623 --shadow

# Same, but reuse the screenshot's own wallpaper (blurred) as the background:
  ./frame_screenshot.py shot.png out.png --crop 1270,31,1521,623 --bg auto --shadow

# Just resize a full clean screenshot to a valid App Store size (cover-crop):
  ./frame_screenshot.py clean.png out.png --fit cover

Valid macOS App Store sizes: 1280x800, 1440x900, 2560x1600, 2880x1800.
"""
import argparse
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

def parse_size(s):
    w, h = s.lower().split("x"); return int(w), int(h)

def hx(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def gradient(W, H, c1, c2, glow):
    t = np.linspace(0, 1, H)[:, None, None]
    base = np.repeat(np.array(c1, float) * (1 - t) + np.array(c2, float) * t, W, axis=1)
    if glow:
        Y, X = np.mgrid[0:H, 0:W]; d = np.sqrt((X - W / 2) ** 2 + (Y - H * 0.46) ** 2)
        g = np.exp(-(d / (W * 0.24)) ** 2)[..., None]
        base = base + np.array(glow, float) * g * 0.20
        base = base * (1 - 0.45 * np.clip((d / (W * 0.60)) ** 2, 0, 1)[..., None])
    return Image.fromarray(np.clip(base, 0, 255).astype("uint8"), "RGB")

def cover(img, W, H):
    r = max(W / img.width, H / img.height)
    s = img.resize((round(img.width * r), round(img.height * r)), Image.LANCZOS)
    ox, oy = (s.width - W) // 2, (s.height - H) // 2
    return s.crop((ox, oy, ox + W, oy + H))

def rounded(img, radius):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    img = img.convert("RGBA"); img.putalpha(m); return img

def main():
    p = argparse.ArgumentParser(description="Frame a screenshot at App Store size.")
    p.add_argument("input"); p.add_argument("output")
    p.add_argument("--size", default="2560x1600", type=parse_size)
    p.add_argument("--crop", help="x0,y0,x1,y1 region to lift from the input (the menu/window)")
    p.add_argument("--scale", type=float, default=None, help="scale factor for the cropped element")
    p.add_argument("--bg", default="gradient:#141211,#08080a",
                   help="'gradient:#hex,#hex' | 'solid:#hex' | 'auto' (blur input) | path/to/bg.png")
    p.add_argument("--glow", default="#DF4B3B", help="warm glow hex for gradient bg ('none' to disable)")
    p.add_argument("--radius", type=int, default=16, help="corner radius for the cropped element")
    p.add_argument("--shadow", action="store_true")
    p.add_argument("--fit", choices=["cover", "contain"], default="cover",
                   help="with no --crop: fit the whole screenshot to size")
    a = p.parse_args()

    W, H = a.size
    src = Image.open(a.input).convert("RGB")

    if not a.crop:
        if a.fit == "contain":
            r = min(W / src.width, H / src.height)
            s = src.resize((round(src.width * r), round(src.height * r)), Image.LANCZOS)
            out = Image.new("RGB", (W, H), hx("#0a0a0b")); out.paste(s, ((W - s.width) // 2, (H - s.height) // 2))
        else:
            out = cover(src, W, H)
        out.save(a.output, quality=95); print("saved", a.output, (W, H)); return

    x0, y0, x1, y1 = (int(v) for v in a.crop.split(","))
    el = rounded(src.crop((x0, y0, x1, y1)), a.radius)
    scale = a.scale or (H * 0.66) / el.height
    el = el.resize((round(el.width * scale), round(el.height * scale)), Image.LANCZOS)
    ew, eh = el.size

    if a.bg == "auto":
        bg = cover(src.filter(ImageFilter.GaussianBlur(160)), W, H).convert("RGBA")
    elif a.bg.startswith("solid:"):
        bg = Image.new("RGBA", (W, H), hx(a.bg.split(":", 1)[1]) + (255,))
    elif a.bg.startswith("gradient:"):
        c1, c2 = a.bg.split(":", 1)[1].split(",")[:2]
        bg = gradient(W, H, hx(c1), hx(c2), None if a.glow.lower() == "none" else hx(a.glow)).convert("RGBA")
    else:
        bg = cover(Image.open(a.bg).convert("RGB"), W, H).convert("RGBA")

    x, y = (W - ew) // 2, (H - eh) // 2
    if a.shadow:
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        blk = Image.new("RGBA", (ew, eh), (0, 0, 0, 150)); blk.putalpha(el.split()[3])
        sh.paste(blk, (x, y + 34), blk); sh = sh.filter(ImageFilter.GaussianBlur(40))
        bg = Image.alpha_composite(bg, sh)
    bg.paste(el, (x, y), el)
    bg.convert("RGB").save(a.output, quality=95)
    print("saved", a.output, (W, H), "| element", (ew, eh))

if __name__ == "__main__":
    main()
