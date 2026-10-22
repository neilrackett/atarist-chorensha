#!/usr/bin/env python3
"""Turns the rendered songs (mcdrv_render logs) into the Atari ST's music.

For each song NAME (NAME.log: the original driver's YM2151 writes with the
loop times; NAME.fade.log: the same with _FADEOUT):

  NAME.vgm (in the work directory)   the writes as a standard VGM log:
                the intro the song's first pass up to its loop command and
                the loop its second pass, as the Amiga port's streams (a
                song without loop: until 2 s after its last write); each
                write at least a VGM sample after the one before (see
                write_vgm)
  MUSIC_DAT/NAME.STM   STDL's YM2149 register stream (stdlconv opm: the
                eight FM channels reduced to the YM2149's three voices and
                noise), played by sources/st/music.s

and sources/st/music_fades.i: each song's fade length per unit of
_FADEOUT's speed, measured as make_amiga_music.py does.

usage: make_st_music.py work_dir output_dir [stdlconv.py]
(stdlconv.py: STDL's, lib/stdl/tools/stdlconv/stdlconv.py by default)
"""

import os
import re
import struct
import subprocess
import sys

CLOCK = 4000000          # the X68000's YM2151
VGM_RATE = 44100
TIMER_REGISTERS = (0x10, 0x11, 0x12, 0x14)
FADE_AT = 1.0
FADE_SPEED = 4

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
FADES = os.path.join(ROOT, "sources", "st", "music_fades.i")


def read_log(path):
    """The YM2151 writes (time in clocks, register, value), timers left
    out, and the loop times."""
    writes = []
    loops = []
    for line in open(path):
        part = line.split()
        if part[0] == "loop":
            loops.append(int(part[1]))
        elif part[0].isdigit():
            register = int(part[1], 16)
            if register not in TIMER_REGISTERS:
                writes.append((int(part[0]), register, int(part[2], 16)))
    return writes, loops


def write_vgm(writes, loops, path):
    """VGM 1.71: the YM2151 at CLOCK, the loop from the first pass's end
    to the second's.

    mcdrv_render logs all of a timer tick's writes at the tick's time. On
    the X68000 they are spread out: the YM2151 is busy for 64 of its
    clocks after each write (16 us, a sample), and the driver waits. That
    matters to a note started again: MCDRV keys a channel off and on
    again in the same tick, and with no time between them the chip never
    sees the key go off, so the note neither ends nor restarts (ymfm's
    render loses the attack of a third to most of the key-ons, by song).
    Here each write goes at least a VGM sample (22.7 us) after the one
    before, so a player sees what the X68000's chip saw; the times stay
    the ticks' (a tick's writes take under a millisecond)."""
    if len(loops) >= 2:
        loop, end = loops[0], loops[1]
    else:
        loop, end = None, (loops[0] if loops else writes[-1][0]) + 2 * CLOCK

    def samples(clocks):
        return clocks * VGM_RATE // CLOCK

    data = bytearray()
    now = 0
    loop_offset = None

    def wait(to):
        nonlocal now
        while to > now:
            n = min(to - now, 65535)
            data.extend((0x61, n & 255, n >> 8))
            now += n

    for t, register, value in writes:
        if t >= end:
            break
        if loop is not None and loop_offset is None and t >= loop:
            wait(samples(loop))
            loop_offset = len(data)
        wait(max(samples(t), now + 1) if data else samples(t))
        data.extend((0x54, register, value))
    wait(samples(end))
    data.append(0x66)

    header = bytearray(0x100)
    header[0:4] = b"Vgm "
    struct.pack_into("<III", header, 4, len(header) + len(data) - 4, 0x171, 0)
    struct.pack_into("<I", header, 0x18, now)
    if loop_offset is not None:
        struct.pack_into("<II", header, 0x1C, len(header) + loop_offset - 0x1C,
                         now - samples(loop))
    struct.pack_into("<I", header, 0x30, CLOCK)
    struct.pack_into("<I", header, 0x34, len(header) - 0x34)
    with open(path, "wb") as f:
        f.write(header + data)


def fade_unit(path):
    """Fade length per unit of speed, in 1/10000 s (make_amiga_music.py's
    measure: from the _FADEOUT at FADE_AT to MCDRV's last write)."""
    text = open(path).read()
    fade = int(re.search(r"^fade (\d+) (\d+)", text, re.M).group(1)) / CLOCK
    assert abs(fade - FADE_AT) < 0.1
    assert not re.search(r"^end ", text, re.M), path + ": the song ended before the fade"
    last = max(int(l.split()[0]) for l in text.splitlines()
               if l and l[0].isdigit() and int(l.split()[1], 16) not in TIMER_REGISTERS) / CLOCK
    return int(round((last - fade) / FADE_SPEED * 10000))


def main(work, output, stdlconv):
    os.makedirs(output, exist_ok=True)
    names = sorted(f[:-4] for f in os.listdir(work)
                   if f.endswith(".log") and not f.endswith(".fade.log"))
    fades = []
    for name in names:
        writes, loops = read_log(os.path.join(work, name + ".log"))
        vgm = os.path.join(work, name + ".vgm")
        write_vgm(writes, loops, vgm)
        subprocess.run([sys.executable, stdlconv, "opm", vgm,
                        os.path.join(output, name + ".STM")], check=True)
        fades.append((name, fade_unit(os.path.join(work, name + ".fade.log"))))

    with open(FADES, "w") as f:
        f.write("; Made by tools/music/make_st_music.py: each song's _FADEOUT length\n"
                "; per unit of speed, in 1/10000 s (music.s).\n\n")
        for name, unit in fades:
            assert len(name) <= 8
            padded = ",".join(["'%s'" % name] + ["0"] * (8 - len(name)))
            f.write("\tdc.b\t%s\n\tdc.w\t%d\n" % (padded, unit))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else
         os.path.join(ROOT, "lib", "stdl", "tools", "stdlconv", "stdlconv.py"))
