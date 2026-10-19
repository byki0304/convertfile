"""Builds all web icons from app_icons/app_icon_master.png (1024x1024, no text).

Without the master image a placeholder is drawn: navy rounded square, white page with a folded
corner and a yellow circular arrow. Usage: python tool/make_icons.py  (requires Pillow)
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "app_icons" / "app_icon_master.png"
ICONS = ROOT / "web" / "icons"
NAVY = (47, 74, 168, 255)
INK = (31, 42, 77, 255)
YELLOW = (255, 201, 74, 255)
WHITE = (255, 255, 255, 255)
SIZE = 1024


def placeholder() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), NAVY)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1, fold = 300, 210, 724, 780, 130
    page = [(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)]
    d.polygon([(x + 14, y + 18) for x, y in page], fill=INK)
    d.polygon(page, fill=WHITE, outline=INK, width=18)
    d.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=(221, 227, 236, 255), outline=INK, width=14)
    for cx in (440, 584):
        d.ellipse([cx - 26, 420 - 26, cx + 26, 420 + 26], fill=INK)
    box = [372, 520, 652, 800]
    d.arc(box, 200, 500, fill=YELLOW, width=44)
    d.polygon([(640, 560), (700, 640), (600, 650)], fill=YELLOW)
    return img


def rounded(img: Image.Image, size: int, radius_ratio: float = 0.22) -> Image.Image:
    out = img.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    out.putalpha(mask)
    return out


def maskable(img: Image.Image, size: int) -> Image.Image:
    bg = Image.new("RGBA", (size, size), NAVY)
    inner = int(size * 0.9)
    off = (size - inner) // 2
    bg.alpha_composite(img.resize((inner, inner), Image.LANCZOS), (off, off))
    return bg


def main() -> None:
    src = Image.open(MASTER).convert("RGBA") if MASTER.exists() else placeholder()
    if src.size != (SIZE, SIZE):
        src = src.resize((SIZE, SIZE), Image.LANCZOS)
    ICONS.mkdir(parents=True, exist_ok=True)
    for s in (96, 144, 192, 256, 384, 512):
        rounded(src, s).save(ICONS / f"Icon-{s}.png")
    for s in (192, 512):
        maskable(src, s).save(ICONS / f"Icon-maskable-{s}.png")
    src.resize((180, 180), Image.LANCZOS).convert("RGB").save(ICONS / "apple-touch-icon.png")
    for s in (16, 32):
        rounded(src, s).save(ICONS / f"favicon-{s}.png")
    rounded(src, 256).save(ROOT / "web" / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    rounded(src, 32).save(ROOT / "web" / "favicon.png")
    print("icons:", "master" if MASTER.exists() else "placeholder")


if __name__ == "__main__":
    main()
