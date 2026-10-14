#!/usr/bin/env python3
"""Convert Degas low-resolution pictures (.PI1: the STE port's screenshots)
to PNG.

The STE palette's 4-bit components hold their low bit in bit 3; each
component is scaled to 8 bits.

usage:
    pi1_png.py FILE.PI1 [...]          writes FILE.png next to each
    pi1_png.py --montage OUT.png FILE.PI1 [...]
                                       also a montage (4 per row)
"""

import struct
import sys

from PIL import Image


def component(value):
    level = ((value & 7) << 1) | ((value >> 3) & 1)  # STE nibble -> 0-15.
    return level * 17


def read_pi1(path):
    data = open(path, "rb").read()
    resolution = struct.unpack(">H", data[:2])[0]
    if resolution != 0 or len(data) < 34 + 32000:
        raise SystemExit(f"{path}: not a low-resolution Degas picture")

    palette = []
    for index in range(16):
        word = struct.unpack(">H", data[2 + 2 * index:4 + 2 * index])[0]
        palette.append((component(word >> 8), component(word >> 4), component(word)))

    image = Image.new("RGB", (320, 200))
    pixels = image.load()
    screen = data[34:34 + 32000]

    for y in range(200):
        for group in range(20):
            offset = y * 160 + group * 8
            planes = struct.unpack(">4H", screen[offset:offset + 8])
            for bit in range(16):
                colour = 0
                for plane in range(4):
                    if planes[plane] & (0x8000 >> bit):
                        colour |= 1 << plane
                pixels[group * 16 + bit, y] = palette[colour]

    return image


def main(arguments):
    montage = None
    if arguments[:1] == ["--montage"]:
        montage = arguments[1]
        arguments = arguments[2:]

    images = []
    for path in arguments:
        image = read_pi1(path)
        image.save(path.rsplit(".", 1)[0] + ".png")
        images.append(image)

    if montage and images:
        columns = min(4, len(images))
        rows = (len(images) + columns - 1) // columns
        sheet = Image.new("RGB", (320 * columns, 200 * rows))
        for index, image in enumerate(images):
            sheet.paste(image, ((index % columns) * 320, (index // columns) * 200))
        sheet.save(montage)


if __name__ == "__main__":
    main(sys.argv[1:])
