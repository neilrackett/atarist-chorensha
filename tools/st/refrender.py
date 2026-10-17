#!/usr/bin/env python3
"""Reference renderer for the Atari ST port: draws, from a frame dump
(Fnnnnnnn.BIN, written by -D__ORACLE__ builds in lockstep runs), the picture
the port should have drawn, independently of its 68000 code, and compares it
with the port's screenshot of the same frame (Snnnnnnn.PI1): every pixel's
colour index and the 16 colours must be identical.

Inputs besides the dump: the game's background as it builds it (GVRAM pages
in a GRAPHICS.BIN 'CRSG' dump) and its sprite patterns (the same file), the
text font (XSP_DAT/SZ_TEXT.PCG) and the colour map (sources/st/palette_map.i).

usage:
    refrender.py --graphics GRAPHICS.BIN --font SZ_TEXT.PCG --map palette_map.i
                 SHOTDIR [--diff DIR]

exits with status 1 if any frame differs.
"""

import argparse
import glob
import os
import re
import struct
import sys

from crs_formats import gvram_line, pattern_pixel, read_graphics, read_pi1

SPACE = 0x20
BAYER = [0, 2, 3, 1]  # (y & 1) * 2 + (x & 1)
PCG_PATTERNS = 0x75E


def read_map(path):
    text = open(path).read()

    def block(name):
        body = text.split(name + ":")[1]
        values = []
        for line in body.splitlines()[1:]:
            line = line.strip()
            if not line:
                if values:
                    break
                continue
            if line.startswith(";"):
                if values:
                    break
                continue
            m = re.match(r"dc\.[bw]\s+(.*)", line)
            if not m:
                break
            for v in m.group(1).split(","):
                v = v.strip()
                values.append(int(v[1:], 16) if v.startswith("$") else int(v))
        return values

    dither = block("graphics_dither")
    sprite_map = block("sprite_colour_map")
    representatives = block("colour_representatives")
    return [dither[i * 4:i * 4 + 3] for i in range(256)], sprite_map, representatives


def layers(gvram, dither):
    """Page 0 (256 lines, None = transparent) and page 1 (32 lines), as ST
    colour indices with the ordered dither."""
    def colour(index, x, y):
        a, b, level = dither[index]
        return b if level > BAYER[(y & 1) * 2 + (x & 1)] else a

    page0, page1 = [], []
    for y in range(256):
        line = gvram_line(gvram, 0, y)
        page0.append([colour(line[x], x, y) if line[x] else None for x in range(256)])
    for y in range(32):
        line = gvram_line(gvram, 1, y)
        page1.append([colour(line[x], x, y) if line[x] else 0 for x in range(256)])
    return page0, page1


def ste_word(word):
    def nibble(v5):
        v4 = v5 >> 1
        return (v4 >> 1) | ((v4 & 1) << 3)
    r, g, b = (word >> 6) & 31, (word >> 11) & 31, (word >> 1) & 31
    return (nibble(r) << 8) | (nibble(g) << 4) | nibble(b)


def font_pixel(font, code, row, x):
    base = (code >> 2) * 128 + [0, 16, 1, 17][code & 3] + row * 2
    colour = 0
    for plane in range(4):
        if font[base + plane * 32] & (0x80 >> x):
            colour |= 1 << plane
    return colour


def render(dump, page0, page1, patterns, font, sprite_map, representatives):
    (magic, window, visible, _, y0, y1, r1, count) = struct.unpack(">4sHBBhhHH", dump[:16])
    if magic != b"CRSF":
        raise SystemExit("not a CRSF frame dump")
    vc = struct.unpack(">512H", dump[16:16 + 0x400])
    characters = dump[16 + 0x400:16 + 0x400 + 1024]
    sprites = [struct.unpack(">HHHH", dump[16 + 0x400 + 1024 + 8 * i:16 + 0x400 + 1024 + 8 * i + 8])
               for i in range(count)]

    screen = [[0] * 320 for _ in range(200)]

    # HUD band: text row 0, opaque.
    for column in range(32):
        code = characters[column]
        for r in range(8):
            for x in range(8):
                c = font_pixel(font, code, r, x)
                screen[r][32 + column * 8 + x] = sprite_map[c] if c else 0

    # Playfield background.
    if visible:
        for y in range(8, 200):
            g = y + window
            a = (g + y0) & 255
            b = (g + y1) & 31
            line0, line1 = page0[a], page1[b]
            row = screen[y]
            for x in range(256):
                row[32 + x] = line0[x] if line0[x] is not None else line1[x]

    def draw_sprites():
        buckets = [[] for _ in range(64)]
        for index, (x, y, pattern, info) in enumerate(sprites):
            priority = info & 63
            if priority >= 16:
                buckets[priority].append(index)
        for bucket in buckets:
            for index in reversed(bucket):
                x, y, pattern, info = sprites[index]
                if pattern >= PCG_PATTERNS or x > 272 or y > 272:
                    continue
                palette = (info >> 8) & 15
                data = patterns[pattern * 128:pattern * 128 + 128]
                for py in range(16):
                    sy = y - 16 - window + py
                    if sy < 8 or sy > 199:
                        continue
                    row = 15 - py if info & 0x8000 else py
                    for px in range(16):
                        column = 15 - px if info & 0x4000 else px
                        nibble = pattern_pixel(data, row, column)
                        if nibble:
                            screen[sy][x + 16 + px] = sprite_map[palette * 16 + nibble]

    def draw_text():
        for row in range(1, 32):
            for column in range(32):
                code = characters[row * 32 + column]
                if code == SPACE:
                    continue
                for r in range(8):
                    # Rows 1-3 (lives, bombs) stay at the playfield's top.
                    sy = row * 8 + r - (window if row >= 4 else 0)
                    if sy < 8 or sy > 199:
                        continue
                    for x in range(8):
                        c = font_pixel(font, code, r, x)
                        if c:
                            screen[sy][32 + column * 8 + x] = sprite_map[c]

    if (r1 >> 12) & 3 > (r1 >> 10) & 3:
        draw_sprites()
        draw_text()
    else:
        draw_text()
        draw_sprites()

    # Borders of the playfield lines.
    for y in range(8, 200):
        for x in list(range(32)) + list(range(288, 320)):
            screen[y][x] = 0

    palette = [ste_word(vc[offset // 2]) for offset in representatives]
    if visible:
        palette[0] = 0
    return screen, palette


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--graphics", required=True)
    parser.add_argument("--font", required=True)
    parser.add_argument("--map", required=True)
    parser.add_argument("--diff")
    parser.add_argument("shots")
    args = parser.parse_args()

    dither, sprite_map, representatives = read_map(args.map)
    gvram, patterns = read_graphics(args.graphics)
    font = open(args.font, "rb").read()
    page0, page1 = layers(gvram, dither)

    failures = 0
    dumps = sorted(glob.glob(os.path.join(args.shots, "F*.BIN")))
    if not dumps:
        raise SystemExit(f"{args.shots}: no frame dumps (F*.BIN)")
    for dump_path in dumps:
        frame = os.path.basename(dump_path)[1:8]
        expected, expected_palette = render(open(dump_path, "rb").read(), page0, page1,
                                            patterns, font, sprite_map, representatives)
        actual, actual_palette = read_pi1(os.path.join(args.shots, f"S{frame}.PI1"))
        differences = [(x, y) for y in range(200) for x in range(320)
                       if expected[y][x] != actual[y][x]]
        palette_ok = expected_palette == actual_palette
        status = "ok" if not differences and palette_ok else "DIFFERENT"
        print(f"frame {int(frame):6d}: {status}: {len(differences)} pixels differ"
              + ("" if palette_ok else ", colours differ"))
        if differences:
            print("   first:", differences[:8])
        if not palette_ok:
            print("   expected", " ".join("%03x" % w for w in expected_palette))
            print("   actual  ", " ".join("%03x" % w for w in actual_palette))
        if (differences or not palette_ok):
            failures += 1
            if args.diff:
                from PIL import Image
                os.makedirs(args.diff, exist_ok=True)
                image = Image.new("RGB", (320, 200))
                for y in range(200):
                    for x in range(320):
                        e, a = expected[y][x], actual[y][x]
                        image.putpixel((x, y), (255, 0, 0) if e != a else (e * 12, e * 12, e * 12))
                image.resize((640, 400)).save(os.path.join(args.diff, f"diff_{frame}.png"))
    print(f"{len(dumps) - failures} of {len(dumps)} frames identical")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
