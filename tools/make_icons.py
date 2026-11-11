#!/usr/bin/env python3
"""Draws the addon's icons and writes them as TGA files.

    python tools/make_icons.py                 # writes ForeverMusicPlayer/Media/*.tga
    python tools/make_icons.py --preview x.png # also writes a contact sheet to look at

The game reads 32-bit uncompressed TGA files whose sides are powers of two.
Icons are white with transparency, so the addon can tint them, except the
logo. No dependency: the shapes are rasterised here with 4x4 supersampling.
"""

import argparse
import math
import struct
import zlib
from pathlib import Path

SIZE = 64
SUBSAMPLES = 4

WHITE = (255, 255, 255)
GOLD = (255, 209, 0)
NIGHT = (22, 22, 30)


# Shapes: functions (x, y) -> bool, in a 64 x 64 coordinate space, y down. ----

def rect(x0, y0, x1, y1):
    return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1


def circle(cx, cy, radius):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def ring(cx, cy, inner, outer):
    return lambda x, y: inner ** 2 <= (x - cx) ** 2 + (y - cy) ** 2 <= outer ** 2


def ellipse(cx, cy, rx, ry, degrees=0.0):
    cos_a, sin_a = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))

    def inside(x, y):
        dx, dy = x - cx, y - cy
        u = dx * cos_a + dy * sin_a
        v = -dx * sin_a + dy * cos_a
        return (u / rx) ** 2 + (v / ry) ** 2 <= 1

    return inside


def polygon(points):
    def inside(x, y):
        hit = False
        for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]):
            if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                hit = not hit
        return hit

    return inside


def stroke(points, width):
    """A line through the points, with round ends and corners."""
    half = width / 2

    def inside(x, y):
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            dx, dy = x1 - x0, y1 - y0
            t = ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)
            t = max(0.0, min(1.0, t))
            if (x - x0 - t * dx) ** 2 + (y - y0 - t * dy) ** 2 <= half * half:
                return True
        return False

    return inside


# Icons: lists of (shape, colour), painted in order. ---------------------------

def mono(*shapes):
    return [(shape, WHITE) for shape in shapes]


ICONS = {
    "play": mono(polygon([(21, 13), (21, 51), (52, 32)])),
    "pause": mono(rect(17, 14, 28, 50), rect(36, 14, 47, 50)),
    "stop": mono(rect(17, 17, 47, 47)),
    "next": mono(polygon([(13, 14), (13, 50), (40, 32)]), rect(43, 14, 51, 50)),
    "previous": mono(polygon([(51, 14), (51, 50), (24, 32)]), rect(13, 14, 21, 50)),
    "close": mono(stroke([(18, 18), (46, 46)], 7), stroke([(46, 18), (18, 46)], 7)),
    "arrow": mono(polygon([(12, 22), (52, 22), (32, 46)])),
    "shuffle": mono(
        stroke([(8, 20), (20, 20), (40, 44), (47, 44)], 5),
        polygon([(46, 35), (58, 44), (46, 53)]),
        stroke([(8, 44), (20, 44), (40, 20), (47, 20)], 5),
        polygon([(46, 11), (58, 20), (46, 29)]),
    ),
    "repeat": mono(
        stroke([(12, 34), (12, 20), (45, 20)], 5),
        polygon([(44, 11), (56, 20), (44, 29)]),
        stroke([(52, 30), (52, 44), (19, 44)], 5),
        polygon([(20, 35), (8, 44), (20, 53)]),
    ),
    # Logo: two joined notes in a dark disc with a gold rim.
    "icon": [
        (circle(32, 32, 30.5), NIGHT),
        (ring(32, 32, 28, 30.5), GOLD),
        (ellipse(21.5, 45, 7.5, 5.5, -20), GOLD),
        (ellipse(41.5, 40, 7.5, 5.5, -20), GOLD),
        (rect(25.5, 19, 29, 45), GOLD),
        (rect(45.5, 14, 49, 40), GOLD),
        (polygon([(25.5, 19), (49, 14), (49, 22), (25.5, 27)]), GOLD),
    ],
}


def render(layers):
    """Returns SIZE rows (top first) of SIZE (r, g, b, a) tuples."""
    fallback = layers[0][1]  # colour given to fully transparent pixels
    samples = SUBSAMPLES * SUBSAMPLES
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            covered = 0
            total = [0, 0, 0]
            for sy in range(SUBSAMPLES):
                for sx in range(SUBSAMPLES):
                    x = px + (sx + 0.5) / SUBSAMPLES
                    y = py + (sy + 0.5) / SUBSAMPLES
                    colour = None
                    for shape, layer_colour in layers:
                        if shape(x, y):
                            colour = layer_colour
                    if colour:
                        covered += 1
                        for channel in range(3):
                            total[channel] += colour[channel]
            if covered:
                rgb = tuple(round(channel / covered) for channel in total)
            else:
                rgb = fallback
            row.append((*rgb, round(255 * covered / samples)))
        rows.append(row)
    return rows


def write_tga(path, rows):
    height, width = len(rows), len(rows[0])
    # Type 2 = uncompressed true colour, 32 bits, 8 alpha bits, bottom row first.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    body = bytearray()
    for row in reversed(rows):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    path.write_bytes(header + bytes(body))


def write_preview(path, icons, scale=3, background=(40, 40, 48)):
    """Contact sheet of all icons on a dark background, as a PNG."""
    names = list(icons)
    width, height = SIZE * scale * len(names), SIZE * scale
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # PNG filter type: none
        for x in range(width):
            r, g, b, a = icons[names[x // (SIZE * scale)]][y // scale][(x // scale) % SIZE]
            for channel, back in zip((r, g, b), background):
                raw.append(round((channel * a + back * (255 - a)) / 255))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_out = Path(__file__).resolve().parent.parent / "ForeverMusicPlayer" / "Media"
    parser.add_argument("--out", type=Path, default=default_out, help="folder for the .tga files")
    parser.add_argument("--preview", type=Path, help="also write a PNG contact sheet here")
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    rendered = {name: render(layers) for name, layers in ICONS.items()}
    for name, rows in rendered.items():
        write_tga(args.out / f"{name}.tga", rows)
        print(f"wrote {args.out / (name + '.tga')}")
    if args.preview:
        write_preview(args.preview, rendered)
        print(f"wrote {args.preview}")


if __name__ == "__main__":
    main()
