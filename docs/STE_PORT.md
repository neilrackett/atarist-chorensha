# Cho Ren Sha 68k on the Atari ST, STE and Mega STE

The game in colour on an Atari ST, STE or Mega STE with 4 MB. The game runs
at its full speed (50 frames per second), and the pictures are drawn as
fast as the machine allows, leaving out the rest. It builds with the
atarist-toolkit-docker tools (`stcmd`). It has been tested in Hatari only.

One program runs on all three. It needs no BLiTTER, so a plain ST draws as
fast as an STE. What the STE adds is DMA sound (on an ST the YM2149 plays
versions of the sound effects made from the samples), 4,096 colours instead
of 512 (the same colour code: an ST ignores the extra bit) and its Jaguar
pad port; the Mega STE adds 16 MHz and its cache.
The folder and file names still say STE (`sources/ste`, `SZ2_STE.TOS`).

**Results, in short.** Measured in Hatari 2.6.1 with TOS 2.06 and 4 MB. The
attract demo runs 6,000 frames; the full-game replays reach stages 1 to 5.
A plain ST (4 MB, TOS 1.04) gives the STE's figures: 12.1 pictures per
second in the attract demo, 12.4 with the release build.

| | STE (8 MHz) | Mega STE (16 MHz, cache) |
|---|---|---|
| Free memory (TPA) | 3,982 KB | same |
| Program + game heap | 2,004 KB + 1,024 KB (871 KB used) | same |
| Sprite cache (the rest, less 64 KB for TOS) | 891 KB (955 KB in the release build) | same |
| Game logic per frame: median / 95% / mean (attract demo) | 5.9 / 11.8 / 6.9 ms | 3.9 / 7.9 / 4.5 ms |
| Render per picture (attract demo) | 47.7 ms | 36.4 ms |
| **Pictures per second, attract demo** | **12.1** (12.4 release build) | **17.1** (17.4 release build) |
| **Pictures per second, full-game replays** (DEMO3, DEMO8) | **11.5, 12.4** (8.7-14.4 by stage) | **16.2, 16.9** (13.3-18.8 by stage) |
| First game start (the background is composed once) | 5.7 s | 3.4 s |

- **It fits, with room for a sprite cache.** The X68000's GVRAM and text
  planes are gone. A 1 MB table of composed background lines takes their
  place, and about 900 KB is left for sprites.
- **The game logic stays at full speed.** The 6,000-frame attract demo
  matches the Amiga port's reference (100 of 100 checkpoints). Two
  full-game replays give the same 2,048 checkpoints (122,880 frames)
  before and after the port's hand-optimised shot loop.
- **Drawing sets the picture rate.** On an STE a picture takes about 48 ms:
  14-15 for the background, 25-29 for the sprites, 3-4 for the text. That
  is about one picture every 4 frames, or every 3 on a Mega STE.

## Building and running

The build needs Docker running for `stcmd`, the atarist-toolkit-docker
wrapper; the repository is mounted at `/tmp` in the container. It also
needs the Xpad submodule: `git submodule update --init`.

```
./build_ste.sh                 binaries/ste/SZ2_STE.TOS (measurements; and SZ2_DBG.TOS with symbols)
RELEASE=1 ./build_ste.sh       binaries/ste/SZ2_REL.TOS: to play (no measurements)
HEADLESS=1 ./build_ste.sh      binaries/ste/SZ2_HL.TOS: no rendering (game logic, checkpoints)
```

`build_ste.sh` also checks that the `sz2.s` changes leave the other targets
alone. The X68000, Falcon and Amiga objects of `sz2.s` must be byte-identical
to those of the `amiga-port` revision; `CHECK=0` skips the check.

`tests/ste/run_hatari.sh NAME` stages the program with the game data in
`tmp/stage_NAME/`, which is Hatari's drive C:, and starts it in Hatari
(`/Applications/Hatari.app`). On first use, TOS 2.06 is copied from
`../atarist-rott/tmp/tos/` to `tmp/tos/`. To run the program elsewhere, put
the folders `BGM_DAT`, `ETC_DAT` and `XSP_DAT` (from `binaries/amiga`) and
`PCM_DAT` (from `binaries/atari`) next to it. The program checks for them
at start and says which one is missing.

```
# Playing, in a window (MACHINE=megaste for the Mega STE).
WINDOW=1 MACHINE=ste PROG=binaries/ste/SZ2_REL.TOS tests/ste/run_hatari.sh play

# Measurement: 6,000 frames of the attract demo, headless, fast forward.
MACHINE=ste FRAMES=6000 tests/ste/run_hatari.sh attract
python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt tmp/out/attract_CHECKPTS.BIN

# A full-game replay from the Falcon port's set instead of the attract demo.
MACHINE=ste FRAMES=190000 REPLAY=DEMO3.REP tests/ste/run_hatari.sh demo3

# Pixel oracle: every screenshot of a lockstep run against the reference renderer.
tests/ste/oracle.sh
```

Options:
- `MACHINE`: `st`, `ste` or `megaste`. For an ST, `TOS=tmp/tos/tos104uk.img`
  gives TOS 1.04 (copy it from `../atarist-rott/tmp/tos/`); TOS 2.06 and
  EmuTOS run on an ST too.
- `FRAMES`: exit after that many frames. The run writes `CHECKPTS.BIN`
  and a PI1 screenshot every 500 frames; `tests/ste/pi1_png.py` converts
  the screenshots to PNG in `tmp/out/shots_NAME/`.
- `REPLAY`: a `binaries/atari/ETC_DAT` replay, played as the demo.
- `LOCKSTEP=1`.
- `INPUT`: a frame-timed joystick script in the Amiga port's text format,
  such as `tests/ste/input/autofire_held.txt`.
- `PROG`, `TOS`, `MEMSIZE`, `FF`, `WINDOW`, `MEGASTE8=1`. `MEGASTE8=1`
  keeps a Mega STE at 8 MHz without the cache, for comparisons.
- `SOUND` (a rate, default off) and `RECORD=FILE.wav`: Hatari's sound, and
  a recording of it, started and stopped with the command
  `fifo hatari-shortcut recsound`.

The console output is in `tmp/out/NAME.log`: the start-up memory report and
the exit report, with timings per stage.

**Controls:**

| Key or control | Action |
|---|---|
| Cursor keys or joystick | Move |
| Z, CTRL or fire | Shoot (held in a stage: auto fire) |
| X or SHIFT | Second button |
| P or ESC | Pause |
| EXIT (main menu) | Quit |
| F1 | Lockstep on and off: every frame is shown and the game slows down to the drawing speed |
| F2 | Keeps the playfield window still instead of following the ship |

On macOS, use Z and X rather than CTRL: Ctrl + the arrow keys are Mission
Control shortcuts there, and Hatari never sees the arrows while Ctrl is held,
so the ship cannot move and fire at once. (Or switch those shortcuts off in
System Settings, Keyboard, Keyboard Shortcuts, Mission Control.)

The STE's enhanced joystick port A (a Jaguar pad) works on the STE; the
Mega STE has no such port.

**Xpad gamepads.** With an [Xpad](https://github.com/neilrackett/atarist-xpad)
provider installed (MD/Sidepad, COMpad, STEpad or any other), every pad it
reports plays, alongside the keyboard and joysticks:

| Pad | Action |
|---|---|
| D-pad or left stick | Move |
| A, X, right shoulder or trigger | Shoot (held in a stage: auto fire) |
| B, Y, left shoulder or trigger | Bomb (the second button) |
| START | Pause |

The start-up text says when a provider was found. While the game runs it
owns the machine, but with a provider present it leaves TOS's Timer C and
serial interrupts running: TOS's Timer C handler calls `etv_timer`, where
providers update their pads (COMpad reads TOS's serial buffer there). That
costs about 2% of the picture rate, and only with a provider installed.

On a Mega STE the program switches to 16 MHz with the cache on. It reads
`$FFFF8E21` back and reports what it finds, and restores the register on
exit.

## How it works

The game core (`sources/sz2.s`, the X68000 program as 68000 source) runs
on a port layer:
- Human68k DOS through line-F and GEMDOS.
- IOCS through trap #15.
- The 50 Hz VBL as the game's frame tick.
- Sound effects through DMA sound.
- IKBD input.

The layer is taken from the Falcon port, with the Amiga port's frame
scheduler, its extra DOS and IOCS calls, checkpoints and input scripts.
What is new is the picture.

### Display (`display.s`)

ST low resolution, triple-buffered, drawn in bitplanes:

- **Lines 0-7, the HUD band:** the X68000 text layer's row 0 (score, high
  score), drawn into both screens when the game writes it.
- **Lines 8-199, the playfield:** 192 of the X68000's 256 lines at their
  real size, 32 pixels from the left.
  - In a stage the window follows the ship, which sits two thirds of the
    way down; it moves at most 2 lines per frame.
  - Elsewhere, or after F2, the window shows lines 32-223.
  - The lives and bombs (text rows 1-3) stay at the top of the playfield.

The screen address is written at a VBL. The colours follow one VBL later,
when the new picture appears. A presented picture is therefore on screen
only two VBLs later, and the screen shown until then cannot be drawn into
before that. So there are three screens: the one shown, the one presented
and the one being drawn. Presenting waits for the picture before it to be
on screen, which by then it nearly always is, and drawing never waits.

### Colours (`palette.s`, `palette_map.i`, `tools/ste/palette_map.py`)

Every X68000 palette entry is drawn in one of the STE's 16 colours. The
mapping is fixed: it is computed offline from colour usage measured over
the attract demo and six full-game replays.

| ST colour | Use |
|---|---|
| 0 | Backdrop (black while the background shows) |
| 1, 2 | The game's colour-cycling entries (red, green) |
| 3-7 | Background colours; every background entry is a 2x2 ordered dither of two of them, anchored to its layer so the pattern scrolls with it |
| 8-15 | Sprite and text colours |

For every picture, each ST colour takes the current value of one
representative X68000 entry, read from the video controller shadow. The
game's fades, colour cycling and flashes therefore show without redrawing
anything.

### Background (`background.s`)

The game builds one background for the whole game:
- Page 0, in front, repeats every 256 lines and scrolls 4 lines per frame.
- Page 1 repeats every 32 lines and scrolls 1 line per frame.

So there are only 256 x 32 different lines, page 0's line a over page 1's
line b. All of them are composed once into a 1 MB table in ST colours and
bitplanes, which replaces GVRAM:

    T[s][a] = page 0 line a over page 1 line (a + s) & 31

For playfield line g, a = (g + Y0) & 255 and s = ((g + Y1) − a) & 31. Since
s is the same all the way down, a picture's background is one block of the
table, wrapping at most once. It is copied with `movem` (192 lines x 128
bytes, about 14 ms on an STE).

The table is built at the first game, from the GVRAM the game builds
itself (5.7 s on an STE). Later games skip the game's builder.

### Sprites (`sprites.s`)

- **Variants.** A variant is a (pattern, palette, horizontal flip); a
  vertical flip draws the rows bottom-up.
- **Masters.** A master is made on first use, two pixels at a time,
  through a table per palette. It holds 16 rows of opaque pixels and
  planes, and its first and last rows with pixels.
- **Shifted copies.** For each of the 16 positions within a 16-pixel
  group that the variant is drawn at, a copy is made on first use:
  - Each master long is rotated, then split between the two groups.
  - Per row, each group has a mask long and two plane longs.
  - When all pixels fall into one group (bullets, particles), only that
    group is kept.
- **Drawing.** Per row, the screen's two groups are read into registers,
  masked, ORed and written back with `movem`: 214 cycles per row, or 126
  for one group.
- **Cache.** Masters and copies live in an arena, found through a table
  per pattern of its 32 variants. The arena is used in two halves: when
  the active half is full, the other one is emptied and used, so what was
  made most recently stays.
- **Order.** The X68000's 64 priorities (larger in front, `$00-$0F` not
  shown), drawn in buckets. Sprites outside the playfield lines are left
  out before any variant work.

### Sound effects (`audio.s`, `ym_effects.i`, `tools/ste/ym_effects.py`)

The game plays one effect at a time through `_ADPCMOUT`. On an STE or Mega
STE, DMA sound plays the sample. An ST has no DMA sound, so its YM2149
plays a version made in advance from each sample:

- `tools/ste/ym_effects.py` cuts each `.sam` into 20 ms frames, one per
  VBL. A frame's loudness is split between tone and noise by how tonal it
  is (its spectral flatness). The tones are the strongest spectral peak, or
  its fundamental if that is strong, on channel A, and a second peak that
  is not one of its harmonics (a chord) on channel C. The noise is on
  channel B, its period from the spectral centroid. Volumes are in the
  YM's 3 dB steps. It writes `sources/ste/ym_effects.i`: 31 effects, 1,497
  frames, 12 KB.
- `tools/ste/ym_effects.py --preview DIR` also writes WAV files of every
  effect as sampled and as the YM plays it. `ALL.wav` has them all, each
  sampled then YM, and `ALL.txt` says where each one starts.
- On the ST, `audio.s` recognises the effect by the sample's length and
  first long, then writes one frame into the YM per VBL: a few hundred
  cycles, with no visible cost. Effects the game plays at 10.4 kHz go
  1.5 times slower and lower (see the open items). As in STDL's YM service,
  registers 14 and 15 are never written, the mixer keeps the port direction
  bits, and interrupts are masked between selecting a register and writing
  it.

The attract demo on an ST plays 757 effects in 6,000 frames, all of them
recognised. A Hatari recording of an ST has sound in 276 of its 500 tenths
of a second, and an STE's 275.

### Text (`text.s`)

The game's characters go into a 32 x 32 map instead of the X68000's 512 KB
of text planes:
- `DRAW_CHARACTER` jumps to `st_draw_character`.
- Row 0 is drawn straight into the HUD band of both screens.
- The other rows are drawn over each picture, masked, with `movep`. Only
  the characters that have pixels are drawn: each row keeps a mask of
  them.

### The game code (`sz2.s`)

The STE changes are all `ifd __STE__`; `-D__STE__` also defines `__PORT__`,
`__CHUNKY__` (the Amiga port's hooks) and `__PORT_CREDITS__`:

| Change | What it does |
|---|---|
| Builder skip (`INITIALIZE_SPRITES_AND_GRAPHICS`) | The background builder runs once only |
| `DRAW_CHARACTER` | Goes to the character map |
| VBL handler | Only the counters and the game's vsync function |
| Sprite tables | Two, swapped at `XSP_OUT` instead of copied (`XOBJ_SET`'s room check reads `st_sprite_buffer_end`) |
| Shot slot loop (`L_0002B410`) | Kept in registers, with the collision-grid routine and `XSP_SET_ST` inlined instruction for instruction (about 0.5 ms per frame) |
| Stage hook | Auto fire |
| Other | EXIT, `PRINTF`, the rotated screen (off), the menu credits |

The X68000, Falcon and Amiga objects are unchanged (`build_ste.sh` checks
this).

### Timing

The 50 Hz VBL is the game's frame tick, so the game runs at 50 instead of
55.46 frames per second. After each game frame:
- If the game is on time, the frame is drawn and shown.
- If it is late, the frame is not drawn and the game catches up, with up to
  64 frames of debt.

Measurement builds time everything with MFP Timer D (38,400 Hz,
independent of the CPU speed): game logic per frame, render per picture,
and its parts.

## Memory

| Part | KB |
|---|---|
| Code (game 246, port 12) | 258 |
| Data | 40 |
| Game BSS (includes the 128 KB demo replay buffer) | 310 |
| Composed background table (at the GVRAM label; GVRAM while the game builds it) | 1,024 |
| X68000 register and sprite shadows | 96 |
| Three screens | 94 |
| Background layers (made once, for the table) | 45 |
| Sprite tables (per-palette pair tables 32, per-pattern variants 7.5, sprite list, order) | 46 |
| Checkpoints (not in the release build) | 65 |
| Text, input script, stage counters, stack | 27 |
| **Program** | **2,004** (1,940 release) |
| Game heap (stack, sprite patterns, samples, tables) | 1,024 (871 used) |
| Kept free for TOS | 64 |
| **Sprite arena** | **891** (955 release) |

## Measurements

### Pictures per second over the work (attract demo, 6,000 frames)

| Step | STE | Mega STE |
|---|---|---|
| Proof of concept: chunky buffer, C2P, 16 greys | 1.0 | 2.2 |
| Colour, bitplanes, composed background, sprite masters | 6.6 | 11.7 |
| Preshifted sprite cache, faster text | 8.8 | 14.0 |
| VBL stub, swapped sprite tables | 9.4 | 14.5 |
| HUD rows pinned, blank characters skipped, variant tables | 9.7 | 14.6 |
| Arena in two halves | 9.8 | 14.7 |
| Sprite rows through registers | 10.1 | 15.3 |
| Faster masters and shifted copies (worst picture 431 to 274 ms) | 10.7 | 15.9 |
| Shot slots in registers (logic −0.4 ms per frame) | 10.9 | 16.2 |
| Faster text rows | 11.4 | 16.5 |
| Leaner per-sprite path | 12.0 | 17.1 |
| Masters skip empty half rows | 12.2 | 17.2 |
| Three screens: two let the next picture be drawn into the one still shown (flicker) | 12.1 | 17.1 |
| Release build (no measurements, 64 KB more sprite cache) | 12.4 | 17.4 |

### Pictures per second by stage (full-game replays, 190,000 frames)

| Stage | STE DEMO3 | STE DEMO8 | Mega STE DEMO3 | Mega STE DEMO8 |
|---|---|---|---|---|
| 1 | 13.0 | 14.4 | 17.8 | 18.8 |
| 2 | 13.3 | 14.1 | 18.0 | 18.5 |
| 3 | 10.3 | 11.5 | 15.2 | 16.2 |
| 4 | 8.7 | 10.3 | 13.3 | 14.8 |
| 5 (part) | 15.7 | 10.2 | 19.7 | 14.7 |
| **All** | **11.5** | **12.4** | **16.2** | **16.9** |

Game logic over the replays, median / 95%: STE 7.4 / 14.8 ms (DEMO3) and
6.4 / 14.3 ms (DEMO8); Mega STE 4.9 / 9.4 and 4.4 / 9.4 ms. The stages
are the low 4 bits of the game's stage word; DEMO3 ends early in stage 5,
DEMO8 later.

### Where a picture's time goes

| Per picture (ms) | STE attract | STE DEMO3 | Mega STE attract | Mega STE DEMO3 |
|---|---|---|---|---|
| Background copy | 14.2 | 14.9 | 13.3 | 13.9 |
| Sprites (drawing, making variants) | 28.6 | 27.5 | 19.9 | 20.6 |
| Text | 3.7 | 2.9 | 2.3 | 1.7 |
| Borders and colours | 0.8 | 0.8 | 0.6 | 0.6 |
| **Render** | **47.7** | **46.4** | **36.4** | **37.0** |

In the attract demo an STE picture draws about 51 sprites: 315 rows of two
groups and 290 of one, about 13.5 ms. Making variants takes about 6 ms on
average: about 9 shifted copies and 1.3 masters a picture in the replays.
The rest is per-sprite work and the priority sort. The background copy is
bus-bound: it gains little from the Mega STE's 16 MHz.

The game logic (headless profile of the attract demo, STE, mean 7.2 ms
before the shot loop change):
- `XOBJ_SET_ST` (multi-sprite objects): 13%.
- The collision grid: 13%.
- The shot slots: 11%.
- `XSP_SET_ST`: 9%.

The X68000's own sprite library code is already tight.

## Verification

- **Xpad.** `tests/ste/xpad_test.sh` builds a scripted provider
  (`tests/ste/xpad/xpadtest.s`, a TSR for `C:\AUTO` that presses buttons
  from `etv_timer`) and runs the game with it. Its grabs show the menu
  started with A, the ship moving while it fires, and the pause. With the
  same provider idle, the attract demo still matches all its checkpoints.

- **Checkpoints.** Every 60 frames: score, random table index, scroll,
  sprite count and player state. They are compared with
  `tests/amiga/checkpoints.py`. The attract demo matches the Amiga port's
  reference (100 of 100) on the STE and the Mega STE, headless or not, and
  in lockstep, and on an ST with TOS 1.04 (no cookie jar), TOS 2.06 and
  EmuTOS. The DEMO3 and DEMO8 replays give the same 2,048 checkpoints
  before and after the shot slot change.
- **Pixels.** `tests/ste/oracle.sh` builds with a frame dump at each
  screenshot and runs the attract demo in lockstep. `tools/ste/refrender.py`
  draws each picture again from the dump, independently of the 68000 code,
  and every pixel and colour must match: 12 of 12 frames, on an STE and on
  an ST.
- **Other targets.** `build_ste.sh` checks that the other objects of `sz2.s`
  are unchanged.

## Open items and next steps

- **The full 256 lines.** The playfield shows 192 of the 256 lines and
  follows the ship. Opening the top and bottom borders, translated from
  `../atarist-overscan`, would show them all. It is the riskiest step left:
  the timing has to hold at 16 MHz too.
- **HUD colours.** The score uses the shared sprite/text colours. A Timer B
  palette change at line 8 would give the HUD band its own exact colours.
- **More speed.**
  - The sprite cache switches halves about every 750 frames in the full
    game (500 on a Mega STE, which draws more pictures). More memory would
    help: samples at 6.25 kHz would free 185 KB, at some cost in sound. So
    would keeping recently used copies when a half is emptied.
  - The background copy is at the bus limit. Drawing from the table
    directly with save-under sprites would need raster splits of the video
    address and more memory.
- **Music.** MCDRV (YM2151 FM) is not emulated. A YM2149 conversion of the
  songs, or DMA samples streamed from disk, would be needed.
- **Sound effects on an ST.** The YM versions are a first conversion: the
  explosions, hits and menu sounds are close, and the sweeping lasers only
  roughly. The converter's settings, or hand-made frames for single
  effects, are the way to improve them. The ST still loads the samples
  (370 KB of the game's heap), though the YM needs only their lengths and
  first longs; not loading them would give the sprite cache that memory.
- **Sound effects.** The effects the game plays at 10.4 kHz (four, the
  second boss's) play 1.5 times too fast on an STE: the Falcon port's
  `.sam` files were all converted as 15.6 kHz recordings. The ST's YM
  versions play them at the right speed.
- **Coverage.** Stages 6 and 7 are not reached by the replays used for the
  colour map and the measurements.
- **Timers.** Timer C (the TOS 200 Hz timer) is stopped while the game
  runs. That is fine with Hatari's GEMDOS drive; it is untested with
  floppies and hard disks on real hardware.
- **Testing.** The port is tested in Hatari only.
