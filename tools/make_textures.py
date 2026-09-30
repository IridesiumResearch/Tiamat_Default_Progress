# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the placeholder textures for mods/tiamat_default_progress/textures.

A flat colour for a block, the Spindle's convention: variation across a
surface is the renderer's, never baked into the picture. An item is flat
colours in one silhouette on a clear ground, so it reads in a slot. Every
picture here was meant to be replaced, and the keystone and the research
table have been: drawn by hand (2026-09-30). A picture that exists is kept;
`--force` replaces it with the placeholder.

No dependencies beyond the standard library, and no randomness: the same
bytes on every machine. Run from the repository root:

    python tools/make_textures.py [--force]
"""
import struct
import sys
import zlib
from pathlib import Path

SIZE = 16
OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_progress" / "textures"

PLANK = (138, 104, 66)
PLANK_DARK = (98, 72, 44)
CLAY = (176, 122, 88)
CLAY_DARK = (128, 86, 60)
IRON = (96, 104, 118)
GOLD = (214, 172, 72)
ORICHALCUM = (206, 106, 70)
ORICHALCUM_LIGHT = (250, 176, 120)


def png(pixels):
    """RGBA rows of (r, g, b, a) tuples, as PNG bytes."""
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


class Canvas:
    def __init__(self, ground=None):
        fill = (ground + (255,)) if ground else (0, 0, 0, 0)
        self.p = [[fill for _ in range(SIZE)] for _ in range(SIZE)]

    def dot(self, x, y, colour):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.p[y][x] = colour + (255,)

    def rect(self, x0, y0, x1, y1, colour):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.dot(x, y, colour)


def research_table():
    """Planks, with two clay tablets laid on them."""
    c = Canvas(PLANK)
    for y in (3, 7, 11, 15):
        c.rect(0, y, 15, y, PLANK_DARK)
    c.rect(2, 1, 6, 6, CLAY)
    c.rect(2, 6, 6, 6, CLAY_DARK)
    c.rect(9, 8, 13, 13, CLAY)
    c.rect(9, 13, 13, 13, CLAY_DARK)
    for x in (3, 5):
        c.dot(x, 3, CLAY_DARK)
    for x in (10, 12):
        c.dot(x, 10, CLAY_DARK)
    return c


def keystone():
    """A wedge of orichalcum banded in gold, in an iron frame."""
    c = Canvas()
    for y in range(2, 14):
        half = 3 + (y - 2) // 3
        c.rect(8 - half, y, 7 + half, y, ORICHALCUM)
    c.rect(4, 7, 11, 8, GOLD)
    for y in range(2, 14):
        half = 3 + (y - 2) // 3
        c.dot(8 - half, y, IRON)
        c.dot(7 + half, y, IRON)
    c.rect(5, 2, 10, 2, IRON)
    c.rect(1, 13, 14, 13, IRON)
    c.dot(7, 4, ORICHALCUM_LIGHT)
    c.dot(8, 5, ORICHALCUM_LIGHT)
    return c


def main():
    force = "--force" in sys.argv[1:]
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in (("research_table", research_table), ("keystone", keystone)):
        target = OUT / f"{name}.png"
        if target.exists() and not force:
            print(f"kept {name}.png (it is somebody's art; --force to replace it)")
            continue
        target.write_bytes(png(make().p))
        print(f"wrote {name}.png")


if __name__ == "__main__":
    main()
