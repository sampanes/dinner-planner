"""Builds the Android icons from art/icon.png.

    python tool/make_icons.py            write the icon files
    python tool/make_icons.py --check    exit 1 when a file is missing or stale

The art is a cream rounded square on white holding a clipboard, a bowl,
steam and a spoon. From it come:

  mipmap-*/ic_launcher.png            the icon as drawn, for old launchers
  mipmap-*/ic_launcher_foreground.png the drawing alone, sized so a round
                                      mask cannot cut it
  drawable-*/ic_stat_dinner.png       the drawing as a white shape, which is
                                      all Android shows in the status bar

Needs Pillow and numpy.
"""

import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

APP = Path(__file__).resolve().parent.parent
RES = APP / 'android' / 'app' / 'src' / 'main' / 'res'
ART = APP / 'art' / 'icon.png'

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# The share of the 108 dp adaptive canvas the drawing may reach from the
# center. Launchers guarantee a circle of radius 33 dp.
SAFE_RADIUS = 32 / 108


def classes(rgb):
    """0 for paper and background, else 1 green, 2 yellow, 3 orange."""
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    top, low = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    ink = ((top - low) > 50) | (top < 170)
    out = np.zeros(r.shape, dtype=np.uint8)
    out[ink & (g >= r)] = 1
    out[ink & (r > g) & (g >= 130)] = 2
    out[ink & (r > g) & (g < 130)] = 3
    return out


def outside(rgb):
    """True where the white around the rounded square is."""
    filled = Image.fromarray(((rgb.min(axis=2) > 244) * 255).astype(np.uint8))
    w, h = filled.size
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(filled, corner, 128)
    mask = np.array(filled) == 128
    # The square's own edge is a soft blend: take a couple of pixels of it too.
    return np.array(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0


def blur(mask, radius):
    return np.array(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))) / 255.0


def build():
    art = Image.open(ART).convert('RGB')
    rgb = np.array(art)
    h, w = rgb.shape[:2]
    out = outside(rgb)
    kind = classes(rgb)
    kind[out] = 0
    ink = kind > 0
    ys, xs = np.nonzero(ink)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    reach = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2).max()

    # The square's color, taken where nothing is drawn.
    plain = ~ink & ~out
    cream = tuple(int(v) for v in np.median(rgb[plain], axis=0))

    files = {}

    def png(image):
        buf = io.BytesIO()
        image.save(buf, 'PNG', optimize=True)
        return buf.getvalue()

    # As drawn: the rounded square, clear outside it.
    alpha = 1 - blur(out, 1.2)
    square = Image.fromarray(np.dstack([rgb, (alpha * 255).astype(np.uint8)]), 'RGBA')
    oy, ox = np.nonzero(~out)
    square = square.crop((ox.min(), oy.min(), ox.max() + 1, oy.max() + 1))
    for name, scale in DENSITIES.items():
        px = round(48 * scale)
        files[f'mipmap-{name}/ic_launcher.png'] = png(square.resize((px, px), Image.LANCZOS))

    # The drawing alone on a canvas big enough that `reach` lands on the
    # safe radius. Everything that is not ink is left clear, so the paper
    # takes the background color behind it.
    side = int(round(reach / SAFE_RADIUS))
    soft = np.clip(blur(ink, 0.8) * 1.6, 0, 1)
    drawing = Image.fromarray(np.dstack([rgb, (soft * 255).astype(np.uint8)]), 'RGBA')
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(drawing, (int(round(side / 2 - cx)), int(round(side / 2 - cy))))
    for name, scale in DENSITIES.items():
        px = round(108 * scale)
        files[f'mipmap-{name}/ic_launcher_foreground.png'] = png(canvas.resize((px, px), Image.LANCZOS))

    # The white shape. Where two colors meet (the spoon over the bowl, the
    # bowl over the clipboard) a clear line is cut so the parts stay apart.
    edge = np.zeros_like(ink)
    for a in (1, 2, 3):
        grown = np.array(Image.fromarray(((kind == a) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(15))) > 0
        edge |= grown & ink & (kind != a)
    shape = ink & ~edge
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    box = max(x1 - x0, y1 - y0)
    white = np.zeros((box, box), dtype=np.uint8)
    top, left = (box - (y1 - y0)) // 2, (box - (x1 - x0)) // 2
    white[top:top + (y1 - y0), left:left + (x1 - x0)] = shape[y0:y1, x0:x1] * 255
    stat = Image.merge('RGBA', [Image.new('L', (box, box), 255)] * 3 + [Image.fromarray(white)])
    for name, scale in DENSITIES.items():
        px = round(24 * scale)
        inner = round(22 * scale)
        tile = Image.new('RGBA', (px, px), (255, 255, 255, 0))
        tile.alpha_composite(stat.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
        files[f'drawable-{name}/ic_stat_dinner.png'] = png(tile)

    color = '#%02X%02X%02X' % cream
    files['values/ic_launcher_background.xml'] = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background">{color}</color>\n'
        '</resources>\n'
    ).encode()
    files['mipmap-anydpi-v26/ic_launcher.xml'] = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    ).encode()
    return files


def main():
    files = build()
    if '--check' in sys.argv:
        stale = [name for name, data in files.items() if not (RES / name).exists() or (RES / name).read_bytes() != data]
        for name in stale:
            print('stale:', name)
        sys.exit(1 if stale else 0)
    for name, data in files.items():
        path = RES / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(name, len(data))


if __name__ == '__main__':
    main()
