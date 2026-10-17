"""The Atari ST port's file formats, read in one place (by palette_map.py,
refrender.py and pi1_png.py).

- CRSG (GRAPHICS.BIN, from -D__DUMP__ builds: sources/st/dump.s): 'CRSG',
  GVRAM (pages 0 and 1, $80000 bytes each: 512 lines of 1024), the video
  controller's palettes ($400 bytes), the patterns' palettes (2048 words),
  the sprite patterns (128 bytes each).
- X68000 sprite patterns: 16 x 16 pixels of 4 bits, the left 8 columns at
  +0 and the right 8 at +64, 4 bytes a row, the left pixel of each pair in
  the high nibble; 0 is transparent.
- PI1 (Degas, low resolution: the port's screenshots): the resolution
  word, 16 colour words, 32000 bytes of interleaved bitplanes.
"""

import struct

GVRAM_SIZE = 0x100000
GVRAM_PAGE = 0x80000
GVRAM_LINE = 1024
VC_SIZE = 0x400
PATTERN_PALETTES_SIZE = 2048 * 2
PATTERN_SIZE = 128


def read_graphics(path):
    """GRAPHICS.BIN: (GVRAM, the sprite patterns)."""
    data = open(path, "rb").read()
    if data[:4] != b"CRSG":
        raise SystemExit(f"{path}: not a CRSG dump")
    gvram = data[4:4 + GVRAM_SIZE]
    patterns = data[4 + GVRAM_SIZE + VC_SIZE + PATTERN_PALETTES_SIZE:]
    return gvram, patterns


def gvram_line(gvram, page, line):
    """A GVRAM line's 256 pixels (the low bytes of its left 256 words)."""
    base = page * GVRAM_PAGE + line * GVRAM_LINE
    return gvram[base + 1:base + 512:2]


def pattern_pixel(pattern, row, column):
    """The colour (0-15, 0 transparent) of a 128-byte pattern's pixel."""
    base = (64 if column >= 8 else 0) + row * 4 + (column & 7) // 2
    return pattern[base] >> 4 if column & 1 == 0 else pattern[base] & 15


def read_pi1(path):
    """A low-resolution Degas picture: (200 lines of 320 colour indices, the
    16 colour words)."""
    data = open(path, "rb").read()
    resolution = struct.unpack(">H", data[:2])[0]
    if resolution != 0 or len(data) < 34 + 32000:
        raise SystemExit(f"{path}: not a low-resolution Degas picture")
    palette = list(struct.unpack(">16H", data[2:34]))
    screen = []
    for y in range(200):
        row = []
        for group in range(20):
            offset = 34 + y * 160 + group * 8
            planes = struct.unpack(">4H", data[offset:offset + 8])
            for bit in range(16):
                mask = 0x8000 >> bit
                row.append(sum(1 << plane for plane in range(4) if planes[plane] & mask))
        screen.append(row)
    return screen, palette
