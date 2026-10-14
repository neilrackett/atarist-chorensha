# Cho Ren Sha 68k: Atari STE / Mega STE proof of concept

A proof of concept that answers two questions before any real port work:
does the game fit in a 4 MB STE, and how far is the hardware from running
it well. It builds with the atarist-toolkit-docker tools (`stcmd`), runs in
Hatari on an STE and a Mega STE with 4 MB, and can be played, slowly.

**Results, in short** (Hatari 2.6.1, TOS 2.06, 4 MB; attract demo, 6,000
frames):

| | STE (8 MHz) | Mega STE (16 MHz, cache) |
|---|---|---|
| Free memory (TPA) | 3,982 KB | 3,982 KB |
| Program + game heap | 2,716 KB + 1,024 KB (871 KB used) | same |
| Left over | 242 KB (179 KB of it used as sprite cache) | same |
| Game logic per frame: median / 95% | 6.4 / 12.8 ms | 4.4 / 8.4 ms |
| Stage start (background build) | about 6 s | about 4 s |
| Pictures per second, game at full speed (this POC) | 1.0 | 2.2 |
| Frames per second in lockstep (game slowed down) | 2.0 | 3.5 |

- **It fits.** The whole game, with the X68000 shadows as the port layer
  needs them today, takes 3.65 MB of the 3.9 MB a 4 MB STE leaves free
  (TOS 1.62: 4,004 KB, EmuTOS 1.4: 3,998 KB). A full port can free more
  than 1 MB of that (see "A full port").
- **The game itself runs at full speed on both machines.** The 6,000-frame
  attract demo reaches exactly the same game states as the Amiga port's
  reference (100 of 100 checkpoints: score, random table, scroll, sprites,
  player), and its logic takes about a third of a 50 Hz frame on an STE
  (two thirds at the 95th percentile), a quarter on a Mega STE.
- **Drawing is the problem.** This POC renders through a chunky buffer and
  C2P, which is 60% of each picture's time; it shows about 1 picture per
  second on an STE. A planar-native renderer would do several times better,
  but the estimate below still puts a faithful port at roughly 5-10 pictures
  per second on an STE and 8-15 on a Mega STE, with the game itself at full
  speed.

## Building and running

The build needs Docker running (for `stcmd`, the atarist-toolkit-docker
wrapper; the repository is mounted at `/tmp` in the container).

```
./build_ste.sh                 binaries/ste/SZ2_STE.TOS (and SZ2_DBG.TOS)
HEADLESS=1 ./build_ste.sh      binaries/ste/SZ2_HL.TOS: no rendering
```

`build_ste.sh` also checks that the `sz2.s` changes leave the other targets
alone: the X68000, Falcon and Amiga objects of `sz2.s` must be byte-identical
to those of the `amiga-port` revision (`CHECK=0` skips it).

`tests/ste/run_hatari.sh NAME` stages the program with the game data in
`tmp/stage_NAME/` (Hatari's drive C:) and starts it in Hatari
(`/Applications/Hatari.app`), with TOS 2.06 copied from
`../atarist-rott/tmp/tos/` to `tmp/tos/` on first use:

```
# Measurement: 6,000 frames of the attract demo, headless, fast forward.
MACHINE=ste FRAMES=6000 tests/ste/run_hatari.sh attract
python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt tmp/out/attract_CHECKPTS.BIN

# Playing, in a window (MACHINE=megaste for the Mega STE).
WINDOW=1 MACHINE=ste tests/ste/run_hatari.sh play
WINDOW=1 LOCKSTEP=1 MACHINE=megaste tests/ste/run_hatari.sh play
```

Options: `MACHINE` (ste, megaste), `FRAMES` (exit after that many frames,
write `CHECKPTS.BIN` and a screenshot every 500 frames, converted to PNG in
`tmp/out/shots_NAME/` by `tests/ste/pi1_png.py`), `LOCKSTEP=1`, `INPUT`
(a frame-timed joystick script in the Amiga port's text format, e.g.
`tests/ste/input/autofire_held.txt` or `tests/amiga/input/menu_exit.txt`),
`TOS`, `MEMSIZE`, `FF`, `WINDOW`. Console output (the start-up memory report
and the exit report) is in `tmp/out/NAME.log`.

**Playing:** cursor keys or the joystick move; CTRL, Z or fire shoot (held:
auto fire in a stage); SHIFT or X is the second button; P or ESC pauses;
EXIT in the main menu quits. F1 switches lockstep on and off: every frame is
shown and the game slows down to the drawing speed (about 2 to 3.5 frames
per second), which makes it playable; with Hatari's fast forward (Cmd+X on
macOS, AltGr+X elsewhere) it runs at about normal speed on a fast host. F2
switches between showing all 256 lines squashed into 200 and the middle 200
lines at their real size.

The STE's enhanced joystick port A (a Jaguar pad) works on the STE; the
Mega STE has no such port.

## What it is made of

The two existing ports each had half of what an STE needs:

| From | What | Where |
|---|---|---|
| Falcon port (`sources/atari`) | TOS start-up, machine take-over, MFP and vectors, IKBD, line-F Human68k DOS through GEMDOS, the IOCS shim, sound effects through DMA sound (the STE's registers), the 8-bit samples | `sources/ste/main.s`, `machine.s`, `emulator.s`, `input.s`, `audio.s`, `mem_map.s` |
| Amiga port (`sources/amiga`) | The chunky renderer: the game's own GVRAM builder (scrolling two-layer background, which the Falcon port replaced with a frozen picture), palette merging, compiled sprites, text layer; the frame scheduler; the missing DOS and IOCS calls (`_BGTEXTGT`, `_VC_R1`, `_SETBLOCK`, `_NAMECK`, ...); checkpoints, input scripts, auto fire | `sources/ste/graphics.s`, `emulator.s`, `input.s`, `measure.s` |
| New | Display (ST low resolution, C2P, 16 greys, line table), Timer D clock and measurements, PI1 screenshots | `sources/ste/display.s`, `measure.s` |

### 68000 changes

The game core (`sz2.s`) is plain 68000 code. The ported layers needed:

- No scaled indexes (`(a0,d0.w*4)`): about 60 sites, doubled into a
  register first; no bit fields (the text renderer scans its group bits
  instead of `bfffo`); 32-bit multiply and divide (`__LMUL`, `__LDIV`) in
  software.
- Runs of the background are copied with long moves from even addresses
  only (a leading byte when a run starts at an odd x; source and
  destination always have the same parity).
- Indexed addressing has 8-bit displacements and absolute offsets of 16
  bits: the text planes ($20000 apart) are walked with `add.l`.
- Exception frames are 6 bytes (8 on the Falcon's 68030), which moves the
  line-F calls' arguments; the game's VBL handler is entered through a fake
  68000 frame (`pea`, `move sr`).

### `sz2.s`

Built with `-D__STE__`, which defines `__PORT__`, `__CHUNKY__` and
`__PORT_CREDITS__`. `__CHUNKY__` (defined by the Amiga build as well)
selects the Amiga renderer and scheduler hooks the ST shares: the frame
waits (`XSP_VSYNC`, `WAIT_VBL`), text row and clear hooks, "GVRAM rebuilt",
the raster-sync skip, the CPU benchmark and the four flipped-tile fixes in
the background builder. `__STE__` blocks: EXIT, `PRINTF`, the rotated screen
(forced off), the stage hook for auto fire, the checkpoint symbols, the menu
credits. The Falcon's text bookkeeping in `DRAW_CHARACTER` and
`CLEAR_TEXT_PLANE` (with the only 68020 instruction an ST build would meet)
is left out. The X68000, Falcon and Amiga objects are unchanged.

### Display

ST low resolution, double-buffered, the 256-pixel-wide picture 32 pixels
from the left. 200 of the 256 lines are shown: 56 evenly spread lines are
left out (all of the playfield and the score stay visible) or, after F2, the
middle 200 (the score line is cut off). The renderer composes only the lines
shown.

Colours: 16 greys (the STE's 4-bit levels). Each of the renderer's 256
palette slots gets the grey of its colour's luminance; slots are converted
again only when the game changes them, so fades and colour cycling still
show. A fixed 16-colour palette would replace one routine
(`set_slot_grey`).

C2P: a table per palette slot and pixel position (8 KB) of `movep`-format
plane bits; eight lookups ORed into a long per 8 pixels, written with
`movep.l`. About 50 cycles per pixel.

### Memory

| Part | KB |
|---|---|
| Code (game 245, port 10) and data (37, of which sincos 32) | 292 |
| Game BSS (includes the 128 KB demo replay buffer) | 310 |
| X68000 shadows: text planes 512, registers and sprite RAM 96 | 608 |
| GVRAM shadow (the converted layers live in its unused right halves) | 1,024 |
| Renderer: text overlay 130, chunky buffer 81, background runs 66, palette and sprite tables 55 | 332 |
| Display: two screens 63, C2P table 8, line table 1 | 72 |
| Checkpoints 64, input script 8, stack 4 | 77 |
| **Program** (with the basepage) | **2,716** |
| Game heap (process area: stack, sprite patterns, samples, tables) | 1,024 (871 used) |
| **Total** | **3,740** |

The layers (2 x 128 KB) are kept inside the GVRAM shadow: the game's
background builder writes only the left 256 pixels (bytes 0-511) of each
1,024-byte line, so line n of each layer sits in the right half of page 0's
line n. Without this the program left only about 50 KB free. The rotated
screen's builder writes whole lines, so that mode is switched off.

What is left goes to a cache for compiled sprites (up to 256 KB, keeping
64 KB free; 179-201 KB depending on the TOS); without it sprites are drawn
by a generic routine.

### Timing

The 50 Hz VBL is the game's frame tick, as on the Falcon: the game runs at
50 instead of 55.46 frames per second (a 55.35 Hz MFP Timer A tick would be
a small change). The frame waits keep the game on schedule and leave out
pictures when it is late (as on the Amiga, with up to 64 ticks of debt). A
picture is rendered in the game's frame wait, not in an interrupt.

Time is measured with MFP Timer D (38,400 Hz, independent of the CPU
speed). "Game logic" is the time from the end of one frame wait to the
start of the next: the game's own work for the frame, interrupts included.

## Measurements

### Game logic

| Per frame | STE | Mega STE | Amiga A1200 (68020/14) |
|---|---|---|---|
| Median | 6.4 ms | 4.4 ms | 1.8 ms |
| 95th percentile | 12.8 ms | 8.4 ms | 3.7 ms |
| Maximum (stage start, once) | 2.7 s | 1.5 s | - |

A 50 Hz frame is 20 ms (18 ms at the X68000's 55.46 Hz). The STE needs a
third of it for the game at the median, two thirds at the 95th percentile;
the Mega STE a quarter and less than half. The Mega STE (16 MHz, cache) is
about 1.45 times as fast as the STE on the game logic, 1.9 times on the
rendering.

### This POC's rendering (attract demo)

| Per picture | STE | Mega STE |
|---|---|---|
| Render (into the chunky buffer) | 257 ms | 135 ms |
| C2P | 374 ms | 196 ms |
| Pictures per second, game at full speed | 1.0 | 2.2 |
| Lockstep: render, C2P | 129 ms, 361 ms | 87 ms, 189 ms |
| Lockstep: frames per second | 2.0 | 3.5 |

Rendering costs more at full speed than in lockstep, because about 50 game
frames pass between two pictures: more palette slots, text rows and new
sprite shapes to convert each time.

Hatari's profiler (STE, 25 s of the attract demo with full-speed play, per
picture): C2P 339 ms; background composition 67 ms; text overlay update 49
ms, text drawing 17 ms; palette merge 23 ms, grey table 19 ms; sprites
about 17 ms, plus about 10 ms for each new compiled sprite shape (214 in the
window). At each stage start, the game's own GVRAM build takes 2.3 s and the
layer conversion 3.8 s.

## A full port: what it would take

**Memory is not the obstacle.** The POC keeps the X68000 layout. A full port
could drop most of it:

- The background is built by the game into a 1 MB GVRAM shadow and
  converted. Converted offline (as the Falcon port's `BACKGND.DAT` does, in
  4-bit planar form) it would be 2 x 64 KB on disk, without the shadow and
  without the 6-second stage start.
- The text planes (512 KB, of which the game uses a 256 x 256 window) could
  be replaced by drawing the game's characters directly.
- The samples (370 KB of the heap) could be halved at 6.25 kHz.

That is more than 1.5 MB, enough for preshifted or compiled planar sprites.

**The game logic is not the obstacle** either: it keeps its speed on both
machines, with most of the frame left over.

**Drawing is.** A planar-native renderer removes the C2P (60% of this POC's
time) and the chunky buffer, but still has to draw every picture:

| Per picture, estimated for an 8 MHz STE | |
|---|---|
| Background: page 0 over page 1, both scrolling, 256 x 200 in 4 planes; 44% of the 16-pixel groups mix both pages (masked), 41% are opaque, 16% empty | 35-60 ms (CPU) or similar with the BLiTTER (three passes) |
| Sprites: 70 on average, 169 at the 95th percentile, 268 at most (16 x 16, masked, shifted) | 35-85 ms, up to 135 ms |
| Text (score) | a few ms |
| **Total** | **about 75-150 ms** |

Add the game's 6-13 ms per frame and an STE would show about 5-10 pictures
per second with the game at full speed (every 5th to 10th frame), a Mega
STE about 8-15. For comparison, the Amiga port's planar AGA renderer shows
about 9.6 pictures per second on a stock A1200 (68020/14, with the blitter).

The 16 colours are the other open question. The game uses about 99 colours
at once (background 28, sprites 86, text 13); a full port needs a palette
design (for example, background and sprites sharing 16 fixed colours, or
raster palette changes), not greyscale.

**Ways to get more speed**, each a trade:

- The Mega STE's 16 MHz, or the STE BLiTTER for the background.
- Drawing at half the frame rate, or the game at 25 Hz (slowed down).
- Fewer sprites drawn (bullets as small dedicated shapes).
- Only one background layer, scrolled by the STE's hardware.

**Verdict:** the port fits and the game runs, but a faithful full port on an
8 MHz STE would play at a low picture rate. It looks worth continuing only
as a Mega STE-first port with a planar renderer, an offline background and
a fixed 16-colour palette, with the renderer prototyped first (background
and sprites in planar form, measured against the estimates above) before
the rest.

## Open items

- Music: MCDRV (YM2151 FM) is not emulated; the Amiga port streams
  pre-rendered music, which is not an option on an STE. A YM2149 conversion
  of the songs, or DMA-streamed samples from disk, would be needed.
- Sound effects: the effects the game plays at 10.4 kHz (9 of its sample
  table entries) play about 1.5 times too fast: the Falcon port's `.sam`
  files were all converted as 15.6 kHz recordings.
- Timer C (the TOS 200 Hz timer) is stopped while the game runs, as on the
  Falcon; fine with Hatari's GEMDOS drive, untested with floppies and hard
  disks on real hardware.
- The game runs at 50 Hz instead of 55.46 Hz.
- Tested in Hatari only.
