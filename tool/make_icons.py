"""Builds every app icon from app_icons/app_icon_master.png (1024x1024 watercolor Foldy, no text).

Outputs (kept in git so installers and native builds can use them directly):
  app_icons/android   launcher mipmaps, round icons, adaptive foreground + background, Play Store 512
  app_icons/ios       AppIcon.appiconset (iPhone, iPad, App Store 1024) with Contents.json
  app_icons/tablet    iPad and Android tablet sizes
  app_icons/desktop   Windows .ico, macOS .icns, PNG 16-1024
  app_icons/web       PWA any/maskable, apple-touch, favicons, Windows tile
and copies the web set into web/icons, web/favicon.ico and web/favicon.png (used by manifest.json and index.html).

Usage: python tool/make_icons.py  (requires Pillow). Without the master a navy placeholder is drawn.
"""

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app_icons"
MASTER = OUT / "app_icon_master.png"
WEB = ROOT / "web"
NAVY = (47, 74, 168, 255)
INK = (31, 42, 77, 255)
YELLOW = (255, 201, 74, 255)
WHITE = (255, 255, 255, 255)
SIZE = 1024

# Bounding boxes inside the master: the whole artwork (ring + cards) and Foldy alone for tiny sizes.
ART_BOX = (200, 250, 970, 800)
FACE_BOX = (340, 365, 660, 685)


def placeholder() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), NAVY)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1, fold = 300, 210, 724, 780, 130
    page = [(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)]
    d.polygon(page, fill=WHITE, outline=INK, width=18)
    d.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=(221, 227, 236, 255), outline=INK, width=14)
    for cx in (440, 584):
        d.ellipse([cx - 26, 420 - 26, cx + 26, 420 + 26], fill=INK)
    d.arc([372, 520, 652, 800], 200, 500, fill=YELLOW, width=44)
    return img


class Icons:
    def __init__(self, src: Image.Image, real: bool):
        self.src = src
        self.art_box = ART_BOX if real else (0, 0, SIZE, SIZE)
        self.face_box = FACE_BOX if real else (0, 0, SIZE, SIZE)
        corners = [src.getpixel(p) for p in [(4, 4), (SIZE - 5, 4), (4, SIZE - 5), (SIZE - 5, SIZE - 5)]]
        self.bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3)) + (255,)

    def square(self, size: int, fill: float, box=None) -> Image.Image:
        """Square crop where [box] takes [fill] of the side, padded with the paper color when it runs past the master."""
        box = box or self.art_box
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        side = max(box[2] - box[0], box[3] - box[1]) / fill
        pad = int(side)
        big = Image.new("RGBA", (SIZE + 2 * pad, SIZE + 2 * pad), self.bg)
        big.alpha_composite(self.src, (pad, pad))
        l, t = cx - side / 2 + pad, cy - side / 2 + pad
        return big.crop((int(l), int(t), int(l + side), int(t + side))).resize((size, size), Image.LANCZOS)

    def art(self, size: int, fill: float = 0.9) -> Image.Image:
        return self.square(size, 0.92, self.face_box) if size <= 48 else self.square(size, fill)

    def rounded(self, size: int, radius: float = 0.22, margin: float = 0.0, fill: float = 0.9) -> Image.Image:
        inner = round(size * (1 - 2 * margin))
        img = self.art(inner, fill)
        mask = Image.new("L", (inner, inner), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=int(inner * radius), fill=255)
        img.putalpha(mask)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.alpha_composite(img, ((size - inner) // 2, (size - inner) // 2))
        return out

    def circle(self, size: int) -> Image.Image:
        img = self.art(size, 0.8)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
        img.putalpha(mask)
        return img

    def opaque(self, size: int, fill: float = 0.86) -> Image.Image:
        return self.art(size, fill).convert("RGB")


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def android(ic: Icons) -> None:
    base = OUT / "android"
    for name, s, fg in [("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)]:
        d = base / f"mipmap-{name}"
        save(ic.rounded(s, radius=0.18), d / "ic_launcher.png")
        save(ic.circle(s), d / "ic_launcher_round.png")
        # Adaptive icons mask the outer third; keep the artwork inside the 66% safe zone.
        save(ic.square(fg, 0.6), d / "ic_launcher_foreground.png")
    hex_bg = "#{:02X}{:02X}{:02X}".format(*ic.bg[:3])
    save_text(
        base / "values" / "ic_launcher_background.xml",
        f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">{hex_bg}</color>\n</resources>\n',
    )
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    save_text(base / "mipmap-anydpi-v26" / "ic_launcher.xml", adaptive)
    save_text(base / "mipmap-anydpi-v26" / "ic_launcher_round.xml", adaptive)
    save(ic.opaque(512, 0.8), base / "playstore-icon-512.png")


IOS = [
    ("iphone", 20, 2), ("iphone", 20, 3), ("iphone", 29, 2), ("iphone", 29, 3), ("iphone", 40, 2), ("iphone", 40, 3),
    ("iphone", 60, 2), ("iphone", 60, 3),
    ("ipad", 20, 1), ("ipad", 20, 2), ("ipad", 29, 1), ("ipad", 29, 2), ("ipad", 40, 1), ("ipad", 40, 2),
    ("ipad", 76, 1), ("ipad", 76, 2), ("ipad", 83.5, 2),
    ("ios-marketing", 1024, 1),
]


def ios(ic: Icons) -> None:
    d = OUT / "ios" / "AppIcon.appiconset"
    images = []
    for idiom, pt, scale in IOS:
        px = round(pt * scale)
        pts = f"{pt:g}"
        name = f"Icon-App-{pts}x{pts}@{scale}x.png"
        # iOS rejects alpha in app icons and applies its own rounded mask.
        save(ic.opaque(px), d / name)
        images.append({"idiom": idiom, "size": f"{pts}x{pts}", "scale": f"{scale}x", "filename": name})
    save_text(d / "Contents.json", json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")


def tablet(ic: Icons) -> None:
    d = OUT / "tablet"
    for label, px in [("20", 20), ("29", 29), ("40", 40), ("76", 76), ("152", 152), ("167", 167)]:
        save(ic.opaque(px), d / "ipad" / f"ipad-{label}.png")
    for name, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(ic.rounded(px, radius=0.18), d / "android" / f"tablet-{name}-{px}.png")
    save(ic.opaque(512, 0.8), d / "android" / "tablet-store-512.png")


def desktop(ic: Icons) -> None:
    d = OUT / "desktop"
    for px in (16, 24, 32, 48, 64, 128, 256, 512, 1024):
        save(ic.rounded(px, radius=0.2), d / "png" / f"icon-{px}.png")
    (d / "windows").mkdir(parents=True, exist_ok=True)
    ic.rounded(256, radius=0.2).save(d / "windows" / "app_icon.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    save(ic.rounded(150, radius=0.2), d / "windows" / "Square150x150Logo.png")
    save(ic.rounded(44, radius=0.2), d / "windows" / "Square44x44Logo.png")
    # macOS icons sit inside a 824/1024 rounded square with a transparent margin.
    (d / "macos").mkdir(parents=True, exist_ok=True)
    ic.rounded(1024, radius=0.225, margin=0.098).save(d / "macos" / "AppIcon.icns")
    save(ic.rounded(1024, radius=0.225, margin=0.098), d / "macos" / "AppIcon-1024.png")


def web(ic: Icons) -> None:
    d = OUT / "web"
    for px in (96, 144, 192, 256, 384, 512):
        save(ic.rounded(px), d / f"Icon-{px}.png")
    # Maskable icons may be cut to a circle of 80% diameter.
    for px in (192, 512):
        save(ic.square(px, 0.72), d / f"Icon-maskable-{px}.png")
    save(ic.opaque(180), d / "apple-touch-icon.png")
    for px in (152, 167, 180):
        save(ic.opaque(px), d / f"apple-touch-icon-{px}.png")
    for px in (16, 32, 48):
        save(ic.rounded(px), d / f"favicon-{px}.png")
    save(ic.opaque(150), d / "mstile-150x150.png")
    ic.rounded(256).save(d / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

    icons = WEB / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for f in d.glob("*.png"):
        shutil.copy2(f, icons / f.name)
    shutil.copy2(d / "favicon.ico", WEB / "favicon.ico")
    shutil.copy2(d / "favicon-32.png", WEB / "favicon.png")


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    real = MASTER.exists()
    src = Image.open(MASTER).convert("RGBA") if real else placeholder()
    if src.size != (SIZE, SIZE):
        src = src.resize((SIZE, SIZE), Image.LANCZOS)
    ic = Icons(src, real)
    android(ic)
    ios(ic)
    tablet(ic)
    desktop(ic)
    web(ic)
    print("icons built from", "master" if real else "placeholder")


if __name__ == "__main__":
    main()
