#!/usr/bin/env python3
"""Convert Degas low-resolution pictures (.PI1: the ST port's screenshots)
to PNG.

The STE palette's 4-bit components hold their low bit in bit 3; each
component is scaled to 8 bits.

usage:
    pi1_png.py FILE.PI1 [...]          writes FILE.png next to each
    pi1_png.py --montage OUT.png FILE.PI1 [...]
                                       also a montage (4 per row)
"""

import sys

from PIL import Image

from crs_formats import read_pi1


def component(value):
    level = ((value & 7) << 1) | ((value >> 3) & 1)  # STE nibble -> 0-15.
    return level * 17


def read_pi1_image(path):
    screen, words = read_pi1(path)
    palette = [(component(w >> 8), component(w >> 4), component(w)) for w in words]
    image = Image.new("RGB", (320, len(screen)))
    pixels = image.load()
    for y, row in enumerate(screen):
        for x, colour in enumerate(row):
            pixels[x, y] = palette[colour]
    return image


def main(arguments):
    montage = None
    if arguments[:1] == ["--montage"]:
        montage = arguments[1]
        arguments = arguments[2:]

    images = []
    for path in arguments:
        image = read_pi1_image(path)
        image.save(path.rsplit(".", 1)[0] + ".png")
        images.append(image)

    if montage and images:
        columns = min(4, len(images))
        rows = (len(images) + columns - 1) // columns
        height = max(image.height for image in images)
        sheet = Image.new("RGB", (320 * columns, height * rows))
        for index, image in enumerate(images):
            sheet.paste(image, ((index % columns) * 320, (index // columns) * height))
        sheet.save(montage)


if __name__ == "__main__":
    main(sys.argv[1:])
