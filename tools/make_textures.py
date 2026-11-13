"""Generates the addon's own textures (plain Python, no image libraries).

    python tools/make_textures.py

Writes addon/KorKronCompanion/Media/Page.tga: a book page, 512 x 512, of warm aged paper: uneven patches and mottling,
paper fibres, a few faint stain rings and foxing spots, and worn edges that darken unevenly into the corners. Darker
and rougher than a clean page (the first one was too bright), but still even enough in the middle to read text on.
"""
import os
import random
import struct

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "addon", "KorKronCompanion", "Media")


def smooth_noise(cells, seed):
    """Value noise: a coarse random grid, smoothly interpolated up to SIZE x SIZE. Returns a function (x, y) -> 0..1."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells + 1)] for _ in range(cells + 1)]

    def ease(t):
        return t * t * (3 - 2 * t)

    def at(x, y):
        gx, gy = x / SIZE * cells, y / SIZE * cells
        x0, y0 = int(gx), int(gy)
        tx, ty = ease(gx - x0), ease(gy - y0)
        a = grid[y0][x0] + (grid[y0][x0 + 1] - grid[y0][x0]) * tx
        b = grid[y0 + 1][x0] + (grid[y0 + 1][x0 + 1] - grid[y0 + 1][x0]) * tx
        return a + (b - a) * ty

    return at


def page():
    base = (208, 184, 136)   # warm, aged paper
    edge = (128, 96, 58)     # burned, worn edges
    blotch = smooth_noise(6, 1)    # large uneven patches
    mottle = smooth_noise(18, 4)   # smaller mottling
    fine = smooth_noise(64, 2)     # paper texture
    ragged = smooth_noise(14, 5)   # makes the edge wear uneven
    rnd = random.Random(3)

    # A few faint stain rings and small foxing spots (brown age marks), placed once.
    rings = [(rnd.uniform(80, 430), rnd.uniform(80, 430), rnd.uniform(40, 90)) for _ in range(2)]
    spots = [(rnd.uniform(10, 500), rnd.uniform(10, 500), rnd.uniform(1.5, 4.5)) for _ in range(70)]
    # Fibres: short, mostly horizontal streaks a shade lighter or darker.
    fibres = {}
    for _ in range(900):
        fx, fy, length, tone = rnd.randrange(SIZE), rnd.randrange(SIZE), rnd.randint(6, 26), rnd.choice((-7, -5, 4, 6))
        slope = rnd.uniform(-0.15, 0.15)
        for i in range(length):
            key = (int(fy + i * slope) % SIZE, (fx + i) % SIZE)
            fibres[key] = fibres.get(key, 0) + tone

    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            dx, dy = abs(x / (SIZE - 1) * 2 - 1), abs(y / (SIZE - 1) * 2 - 1)
            # Edge wear: starts at an uneven distance from the border, deeper in the corners.
            start = 0.72 + (ragged(x, y) - 0.5) * 0.16
            rim = max(0.0, max(dx, dy) - start) / (1 - start)
            corner = max(0.0, (dx * dx + dy * dy) / 2 - 0.5) / 0.5
            v = min(1.0, rim ** 1.6 * 0.95 + corner * 0.45)

            n = ((blotch(x, y) - 0.5) * 30 + (mottle(x, y) - 0.5) * 14 + (fine(x, y) - 0.5) * 8
                 + (rnd.random() - 0.5) * 9 + fibres.get((y, x), 0))
            for (cx, cy, r) in rings:  # a coffee-ring stain: darker on its rim
                d = abs(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 - r)
                if d < 5:
                    n -= (5 - d) * 0.9
            for (sx, sy, r) in spots:
                d2 = (x - sx) ** 2 + (y - sy) ** 2
                if d2 < r * r:
                    n -= 16 * (1 - d2 / (r * r))
            px = []
            for c in range(3):
                value = base[c] + (edge[c] - base[c]) * v + n * (1.0 if c < 2 else 0.7)
                px.append(max(0, min(255, int(value))))
            r, g, b = px
            row += bytes((b, g, r, 255))  # TGA stores BGRA
        rows.append(row)
    return rows


def write_tga(path, rows):
    # Uncompressed true-color TGA, 32 bits, origin top-left (descriptor bit 5) with 8 alpha bits.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        for row in rows:
            f.write(row)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    target = os.path.join(OUT, "Page.tga")
    write_tga(target, page())
    print("wrote", os.path.normpath(target))
