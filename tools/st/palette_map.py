#!/usr/bin/env python3
"""The Atari ST port's 16 colours: how the game's 512 X68000 palette entries
(256 graphics, 256 sprite/text) map to the ST's 16 colour registers.

The mapping is fixed; the 16 hardware colours are set for every picture from
one "representative" X68000 entry each, as the video controller shadow holds
it at that moment (sources/st/palette.s), so the game's fades, colour cycling
and flashes still show without redrawing anything.

ST colour indices:

    0      the backdrop (sprite/text entry 0; black while the background shows)
    1      the red cycling ramp: graphics $B1, sprite entries 10:1 and 11:1
           (and graphics $A1, the slow layer's light, whose own pulse is
           slower: it follows $B1's ramp here)
    2      the green cycling ramp: sprite entries 1:1 ... 9:1
    3-     background colours (--bg-colours, 5 by default; each background
           entry: a 2x2 ordered dither of two of them, baked into the
           background table)
    -15    sprite and text colours (nearest)

The representatives are real palette entries (medoids), chosen to minimise
the usage-weighted error in OKLab (weights: pixel counts to the power
--weight-power, 0.5 by default, so rare bright colours still count): the
background's from the background's
pixels (GVRAM pages in GRAPHICS.BIN), the sprites' from USAGE.BIN files (pixels
of each sprite palette entry shown, from runs of the attract demo and
replays), the text's from fixed weights (the HUD is always shown).

usage:
    palette_map.py --palette SZ_PALET.PAL --graphics GRAPHICS.BIN
                   --usage USAGE.BIN [...] -o palette_map.i [--preview DIR]
                   [--no-dither]
"""

import argparse
import itertools
import os
import struct

import numpy as np

# Cycling entries: the red ramp (graphics $B1, sprites 10:1 and 11:1; graphics
# $A1's slower red pulse shares it), the green ramp (sprites 1:1 ... 9:1).
CYCLING_GRAPHICS = {0xA1: 1, 0xB1: 1}
CYCLING_SPRITES = {**{p * 16 + 1: 2 for p in range(1, 10)}, 10 * 16 + 1: 1, 11 * 16 + 1: 1}
CYCLING_REPRESENTATIVES = [0xB1 * 2, 0x200 + (16 + 1) * 2]
FIRST_FREE_INDEX = 3
BAYER = [[0, 2], [3, 1]]  # Pixel (x & 1, y & 1) takes colour b if level > this.
TEXT_WEIGHTS = {2: 300, 4: 250, 8: 50}  # HUD pixels per frame by text colour.

# ---- colour ----------------------------------------------------------------

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])


def linear(rgb):
    c = np.asarray(rgb, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def oklab_of_linear(lin):
    return np.cbrt(np.maximum(np.asarray(lin) @ M1.T, 0)) @ M2.T


def oklab(rgb):
    return oklab_of_linear(linear(rgb))


def x68_rgb5(word):
    """X68000 palette word GGGGG RRRRR BBBBB I -> 5-bit R, G, B."""
    return ((word >> 6) & 31, (word >> 11) & 31, (word >> 1) & 31)


def rgb8_of_rgb5(rgb5):
    return tuple((c << 3) | (c >> 2) for c in rgb5)


def ste_shown(rgb5):
    """What the STE shows for an entry used as a representative: 4-bit levels
    (v5 >> 1), each level * 17."""
    return tuple((c >> 1) * 17 for c in rgb5)


# ---- data ------------------------------------------------------------------

def read_palette(path):
    words = struct.unpack(">256H", open(path, "rb").read()[:512])
    graphics = list(words)
    sprites = list(words)
    # L_000294FA: text colours 1-15 (sprite block 0) come from block 2.
    for c in range(1, 16):
        sprites[c] = words[2 * 16 + c]
    sprites[0] = words[0]
    return graphics, sprites


def read_graphics(path):
    data = open(path, "rb").read()
    if data[:4] != b"CRSG":
        raise SystemExit(f"{path}: not a CRSG dump")
    gvram = data[4:4 + 0x100000]
    patterns = data[4 + 0x100000 + 0x400 + 4096:]
    return gvram, patterns


def gvram_line(gvram, page, line):
    base = page * 0x80000 + line * 1024
    return gvram[base + 1:base + 512:2]  # Low bytes of the left 256 words.


def read_usage(paths):
    counts = np.zeros(256)
    palettes = np.zeros(2048, int)
    frames = 0
    for path in paths:
        data = open(path, "rb").read()
        if data[:4] != b"CRSU":
            raise SystemExit(f"{path}: not a CRSU file")
        frames += struct.unpack(">I", data[4:8])[0]
        counts += np.array(struct.unpack(">256I", data[8:8 + 1024]), float)
        if len(data) >= 8 + 1024 + 4096:
            palettes |= np.array(struct.unpack(">2048H", data[8 + 1024:8 + 1024 + 4096]))
    return counts, palettes, frames


def background_weights(gvram):
    """Pixels shown per graphics index over the background's 8192 distinct
    lines: page 0 (256 lines) where opaque, else page 1 (32 lines)."""
    page0 = np.array([list(gvram_line(gvram, 0, y)) for y in range(256)])
    page1 = np.array([list(gvram_line(gvram, 1, y)) for y in range(32)])
    weights = np.bincount(page0[page0 > 0], minlength=256).astype(float)
    transparent = (page0 == 0).sum(axis=0)  # Per column: page 0 lines showing page 1.
    np.add.at(weights, page1, np.broadcast_to(transparent / 32.0, page1.shape))
    return weights


# ---- choosing the representatives -----------------------------------------

def mix_table(count, dither):
    """The 2x2 dither mixes of `count` colours: (a, b, level) triples."""
    table = [(a, a, 0) for a in range(count)]
    if dither:
        table += [(a, b, level) for a in range(count) for b in range(count) if a != b
                  for level in range(1, 4)]
    return table


def mix_labs(linears, table):
    """OKLab of each mix (mixing in linear light)."""
    rows = []
    for a, b, level in table:
        t = level / 4
        rows.append(linears[a] * (1 - t) + linears[b] * t)
    return oklab_of_linear(np.array(rows))


def choose_background(entries, palette, weights, count, dither, fixed=None):
    """entries: graphics indices to cover; candidates: their distinct colours.
    Exhaustive search over `count` medoids (or the fixed representatives),
    each entry taking its best mix."""
    candidates = sorted({palette[i] >> 1 for i in entries})
    words = {}
    for i in entries:  # Representative entry per colour: the most used one.
        key = palette[i] >> 1
        if key not in words or weights[i] > weights[words[key]]:
            words[key] = i
    if fixed:
        candidates = [palette[i] >> 1 for i in fixed]
        for i in fixed:
            words[palette[i] >> 1] = i
    target_labs = np.array([oklab(rgb8_of_rgb5(x68_rgb5(palette[i]))) for i in entries])
    target_weights = np.array([weights[i] for i in entries])
    candidate_linear = {k: linear(ste_shown(x68_rgb5(k << 1))) for k in candidates}
    count = min(count, len(candidates))
    table = mix_table(count, dither)
    best = None
    for combo in itertools.combinations(candidates, count):
        labs = mix_labs([candidate_linear[k] for k in combo], table)
        distances = np.sum((target_labs[:, None, :] - labs[None, :, :]) ** 2, axis=2)
        error = float(np.sum(target_weights * distances.min(axis=1)))
        if best is None or error < best[0]:
            best = (error, combo, distances.argmin(axis=1))
    error, combo, choice = best
    mapping = {i: table[choice[n]] for n, i in enumerate(entries)}
    return [words[k] for k in combo], mapping, error


def choose_sprites(entries, palette, weights, count):
    """Weighted k-medoids (greedy start, then swaps) over the entries'
    distinct colours."""
    keys = sorted({palette[e] >> 1 for e in entries})
    key_index = {k: n for n, k in enumerate(keys)}
    key_weight = np.zeros(len(keys))
    owner = {}
    for e in entries:
        k = palette[e] >> 1
        key_weight[key_index[k]] += weights[e]
        if k not in owner or weights[e] > weights[owner[k]]:
            owner[k] = e
    labs = np.array([oklab(rgb8_of_rgb5(x68_rgb5(k << 1))) for k in keys])
    shown = np.array([oklab(ste_shown(x68_rgb5(k << 1))) for k in keys])
    distance = np.sum((labs[:, None, :] - shown[None, :, :]) ** 2, axis=2)  # [colour, medoid]

    def cost(medoids):
        return float(np.sum(key_weight * distance[:, medoids].min(axis=1)))

    medoids = []
    for _ in range(min(count, len(keys))):
        rest = [k for k in range(len(keys)) if k not in medoids]
        medoids.append(min(rest, key=lambda k: cost(medoids + [k])))
    current = cost(medoids)
    improved = True
    while improved:
        improved = False
        for i in range(len(medoids)):
            for k in range(len(keys)):
                if k in medoids:
                    continue
                trial = medoids[:i] + [k] + medoids[i + 1:]
                c = cost(trial)
                if c < current - 1e-12:
                    medoids, current, improved = trial, c, True
    mapping = {}
    for e in entries:
        k = key_index[palette[e] >> 1]
        mapping[e] = int(np.argmin(distance[k, medoids]))
    return [owner[keys[m]] for m in medoids], mapping, current


# ---- output ----------------------------------------------------------------

def write_include(path, graphics_map, sprite_map, representatives, args_text):
    lines = [
        "; Generated by tools/st/palette_map.py " + args_text,
        "; The ST's 16 colours: see that tool and sources/st/palette.s.",
        "",
        "; Per graphics palette index: colour a, colour b, dither level (0-4: how",
        "; many pixels of each 2x2 cell take b), padding.",
        "",
        "graphics_dither:",
    ]
    for i in range(0, 256, 4):
        lines.append("\tdc.b\t" + ",".join("%d,%d,%d,0" % graphics_map[j] for j in range(i, i + 4)))
    lines += ["", "; Per sprite/text palette entry (palette * 16 + colour): ST colour.", "",
              "sprite_colour_map:"]
    for i in range(0, 256, 16):
        lines.append("\tdc.b\t" + ",".join(str(sprite_map[j]) for j in range(i, i + 16)))
    lines += ["", "; Per ST colour: the video controller shadow offset of its representative",
              "; X68000 entry (graphics $000-$1FE, sprite/text $200-$3FE).", "",
              "colour_representatives:"]
    lines.append("\tdc.w\t" + ",".join("$%03x" % r for r in representatives))
    lines.append("")
    open(path, "w").write("\n".join(lines))


def preview(directory, gvram, patterns, graphics, sprites, graphics_map, sprite_map,
            representatives, pattern_palettes):
    from PIL import Image

    os.makedirs(directory, exist_ok=True)
    shown = []
    for offset in representatives:
        word = (graphics if offset < 0x200 else sprites)[(offset & 0x1FF) // 2]
        shown.append(ste_shown(x68_rgb5(word)))
    shown[0] = (0, 0, 0)

    # Background at scroll 0: page 0 over page 1, original and mapped.
    image = Image.new("RGB", (512 + 8, 256))
    pixels = image.load()
    for y in range(256):
        line0 = gvram_line(gvram, 0, y)
        line1 = gvram_line(gvram, 1, y % 32)
        for x in range(256):
            if line0[x]:
                index, layer_y = line0[x], y
            else:
                index, layer_y = line1[x], y % 32
            pixels[x, y] = rgb8_of_rgb5(x68_rgb5(graphics[index]))
            a, b, level = graphics_map[index]
            colour = b if level > BAYER[layer_y & 1][x & 1] else a
            pixels[264 + x, y] = shown[colour]
    image.resize((image.width * 2, image.height * 2), Image.NEAREST).save(
        os.path.join(directory, "background.png"))

    # Sprites: every pattern drawn, with its first palette.
    drawn = [(p, next(q for q in range(16) if pattern_palettes[p] >> q & 1))
             for p in range(min(len(patterns) // 128, 2048)) if pattern_palettes[p]]
    columns = 24
    rows = (len(drawn) + columns - 1) // columns
    image = Image.new("RGB", (columns * 18 * 2 + 8, rows * 18), (24, 24, 24))
    pixels = image.load()
    for n, (pattern, palette) in enumerate(drawn):
        data = patterns[pattern * 128:pattern * 128 + 128]
        ox, oy = (n % columns) * 18, (n // columns) * 18
        for y in range(16):
            for x in range(16):
                base = (64 if x >= 8 else 0) + y * 4 + (x & 7) // 2
                nibble = (data[base] >> 4) if (x & 1) == 0 else (data[base] & 15)
                if not nibble:
                    continue
                entry = palette * 16 + nibble
                pixels[ox + x, oy + y] = rgb8_of_rgb5(x68_rgb5(sprites[entry]))
                pixels[columns * 18 + 8 + ox + x, oy + y] = shown[sprite_map[entry]]
    image.resize((image.width * 2, image.height * 2), Image.NEAREST).save(
        os.path.join(directory, "sprites.png"))

    # The 16 colours.
    image = Image.new("RGB", (16 * 24, 24))
    for i, colour in enumerate(shown):
        for y in range(24):
            for x in range(24):
                image.putpixel((i * 24 + x, y), colour)
    image.save(os.path.join(directory, "colours.png"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--palette", required=True)
    parser.add_argument("--graphics", required=True)
    parser.add_argument("--usage", nargs="+", required=True)
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--preview")
    parser.add_argument("--no-dither", action="store_true")
    parser.add_argument("--bg-colours", type=int, default=5)
    parser.add_argument("--bg-representatives",
                        help="fixed background representatives, e.g. 90,AD,BF,9D,A4 (hex graphics indices)")
    parser.add_argument("--weight-power", type=float, default=0.5,
                        help="pixel counts are raised to this power (rare, bright colours count more below 1)")
    args = parser.parse_args()

    bg_indices = list(range(FIRST_FREE_INDEX, FIRST_FREE_INDEX + args.bg_colours))
    sprite_indices = list(range(FIRST_FREE_INDEX + args.bg_colours, 16))

    graphics, sprites = read_palette(args.palette)
    gvram, patterns = read_graphics(args.graphics)
    counts, pattern_palettes, frames = read_usage(args.usage)

    # Background.
    bg_weights = background_weights(gvram)
    bg_entries = [i for i in range(1, 256) if bg_weights[i] > 0 and i not in CYCLING_GRAPHICS]
    fixed = None
    if args.bg_representatives:
        fixed = [int(v, 16) for v in args.bg_representatives.split(",")]
    bg_reps, bg_map, bg_error = choose_background(
        bg_entries, graphics, bg_weights ** args.weight_power, len(bg_indices), not args.no_dither,
        fixed)

    # Sprites and text.
    weights = counts.copy()
    for colour, per_frame in TEXT_WEIGHTS.items():
        weights[colour] += per_frame * frames
    sprite_entries = [e for e in range(256) if e & 15 and e not in CYCLING_SPRITES]
    sprite_reps, sprite_map_local, sprite_error = choose_sprites(
        sprite_entries, sprites, weights ** args.weight_power, len(sprite_indices))

    graphics_map = []
    for i in range(256):
        if i == 0:
            graphics_map.append((0, 0, 0))
        elif i in CYCLING_GRAPHICS:
            graphics_map.append((CYCLING_GRAPHICS[i],) * 2 + (0,))
        elif i in bg_map:
            a, b, level = bg_map[i]
            graphics_map.append((bg_indices[a], bg_indices[b], level))
        else:  # Not in the background: nearest background colour.
            lab = oklab(rgb8_of_rgb5(x68_rgb5(graphics[i])))
            nearest = min(range(len(bg_reps)), key=lambda r: float(np.sum(
                (oklab(ste_shown(x68_rgb5(graphics[bg_reps[r]]))) - lab) ** 2)))
            graphics_map.append((bg_indices[nearest],) * 2 + (0,))

    sprite_map = []
    for e in range(256):
        if not e & 15:
            sprite_map.append(0)
        elif e in CYCLING_SPRITES:
            sprite_map.append(CYCLING_SPRITES[e])
        else:
            sprite_map.append(sprite_indices[sprite_map_local[e]])

    representatives = [0x200] + CYCLING_REPRESENTATIVES
    representatives += [i * 2 for i in bg_reps]
    representatives += [0x200 + e * 2 for e in sprite_reps]

    import sys
    command = " ".join(os.path.basename(a) if a.endswith((".BIN", ".PAL")) else a
                        for a in sys.argv[1:])
    write_include(args.output, graphics_map, sprite_map, representatives, command)

    print(f"frames of usage: {frames}")
    print(f"background: {len(bg_entries)} entries, representatives "
          + " ".join("$%02X" % i for i in bg_reps) + f", error {bg_error:.4f}")
    print(f"sprites/text: {len(sprite_entries)} entries, representatives "
          + " ".join("%d:%d" % (e >> 4, e & 15) for e in sprite_reps) + f", error {sprite_error:.4f}")
    if args.preview:
        preview(args.preview, gvram, patterns, graphics, sprites, graphics_map, sprite_map,
                representatives, pattern_palettes)
        print(f"previews in {args.preview}")


if __name__ == "__main__":
    main()
