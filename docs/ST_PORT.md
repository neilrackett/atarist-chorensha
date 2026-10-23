# Cho Ren Sha 68k: Atari ST port

The Atari ST version, by [Neil Rackett](https://neilrackett.com/atarist): the game in colour
on an Atari ST, STE or Mega STE with 4 MB. The game runs at its full speed
(50 frames per second), and the pictures are drawn as fast as the machine
allows, leaving out the rest. It builds with the atarist-toolkit-docker tools
(`stcmd`).

One program runs on all three. It needs no BLiTTER (an STE uses its
BLiTTER for the background copy only), so a plain ST draws nearly as fast
as an STE. All three play the music on the YM2149, the songs reduced from
the X68000's FM chip in advance. What the STE adds is DMA sound (on an ST
the YM2149 plays versions of the sound effects made from the samples, on
one of its voices while the music plays), 4,096 colours instead
of 512 (the same colour code: an ST ignores the extra bit) and its Jaguar
pad port; the Mega STE adds 16 MHz and its cache.

**Results, in short.** Measured in Hatari 2.6.1 with TOS 2.06 and 4 MB. The
attract demo runs 6,000 frames; the full-game replays reach stages 1 to 5.
The figures are for crop, the default layout. A plain ST (4 MB, TOS 1.04)
draws as fast as an STE: 12.7 pictures per second in the attract demo (12.9
with the release build) and 12.0 and 12.9 in the full-game replays. It
loads no samples, so its sprite cache is bigger (1,339 KB in the release
build, against the STE's 946 KB).

|                                                              | STE (8 MHz)                          | Mega STE (16 MHz, cache)            |
| ------------------------------------------------------------ | ------------------------------------ | ----------------------------------- |
| Free memory (TPA)                                            | 3,982 KB                             | same                                |
| Program + game heap                                          | 1,919 KB + 1,024 KB (871 KB used)    | same                                |
| Screens (crop)                                               | 94 KB                                | same                                |
| Sprite cache (the rest, less 64 KB for TOS)                  | 881 KB (946 KB in the release build) | same                                |
| Game logic per frame: median / 95% / mean (attract demo)     | 5.9 / 11.8 / 6.7 ms                  | 3.9 / 7.9 / 4.4 ms                  |
| Render per picture (attract demo)                            | 45.2 ms                              | 36.3 ms                             |
| **Pictures per second, attract demo**                        | **12.8** (13.1 release build)        | **17.2** (17.6 release build)       |
| **Pictures per second, full-game replays** (DEMO3, DEMO8)    | **12.0, 12.9** (9.1-15.8 by stage)   | **16.4, 17.1** (13.5-19.8 by stage) |
| **Per second of gameplay** (both replays): median, 10% / 90% | **11** (4 / 25)                      | **17** (8 / 25)                     |
| First game start (the background is composed once)           | 5.7 s                                | 3.4 s                               |

- **It fits, with room for a sprite cache.** The X68000's GVRAM and text
  planes are gone. A 1 MB table of composed background lines takes their
  place, and about 880 KB is left for sprites.
- **The game logic stays at full speed.** The 6,000-frame attract demo
  matches the Amiga port's reference (100 of 100 checkpoints). Two
  full-game replays give the same 2,048 checkpoints (122,880 frames)
  before and after the port's hand-optimised shot loop.
- **Drawing sets the picture rate.** On an STE a picture takes about 45 ms:
  12-13 for the background, 25-28 for the sprites, 3-4 for the text. That
  is about one picture every 4 frames, or every 3 on a Mega STE.
- **The music costs about 1%.** These figures were measured before the
  music (as `music=false` plays). With it, the sprite cache is 30 KB
  smaller, and the attract demo shows 12.5 pictures per second on an ST
  and an STE (12.6 and 12.7 without) and 17.2 on a Mega STE (the same);
  the game logic is unchanged.
- **Full height costs about a fifth.** With both borders open (see Full
  height) the attract demo shows 10.7 pictures per gameplay second on an
  STE and 14.9 on a Mega STE, against 13.2 and 17.4 in crop.
- **A real Mega STE** (with its drivers and accessories loaded, see On a
  real Mega STE) shows 15.3 pictures per second in crop and 12.5 at full
  height.

## Building and running

The build needs Docker running for `stcmd`, the atarist-toolkit-docker
wrapper; the repository is mounted at `/tmp` in the container. It also
needs the submodules (Xpad, and STDL for the full height): `git
submodule update --init`.

```
make, make release            binaries/st/SZ2.TOS: to play (no measurements); a copy in dist/CHORENSH/ for an ST
make debug                    binaries/st/SZ2_ST.TOS (measurements; and SZ2_DBG.TOS with symbols, and the object check)
make headless                 binaries/st/SZ2_HL.TOS: no rendering (game logic, checkpoints)
make devops                   binaries/st/SZ2_DEV.TOS: the text also on md-devops' debug stream
make check-data               that binaries/st's data is the Amiga's and the Falcon's (see below)
make test                     Hatari: checkpoints and the song (ST, STE, Mega STE; crop and full height), ESC out of the menus, pixel oracle
make others                   the X68000, Falcon and Amiga builds (build_mac.sh, or build.sh)
make clean                    removes the builds' and tests' files (keeps tmp/tos)
```

The Makefile runs `build_st.sh`, which can also be run directly:
`RELEASE=1`, `HEADLESS=1` and `DEVOPS=1` (`SZ2_DEV.TOS`, or `SZ2_DEVR.TOS`
and `SZ2_DEVH.TOS` with either of the others) pick the build, `FLAGS` and
`NAME` add defines and rename it.

Every build has both screen layouts, crop and full height (see below):
`SZ2.CFG` picks one when the program starts.

**Releases.** Each push to `main` (other than one changing only Markdown)
runs `.github/workflows/release.yml` on GitHub: it builds with `make`,
tags the commit with the next `v1.01-atarist.N` (1.01 is the original's
version this port is built from; a commit already tagged by hand keeps its
tag), moves the `latest` tag onto it and replaces `ChoRenSha-atarist.zip`
(`dist/CHORENSH`) on the `latest` release. It never creates that release or
edits its title or text. `.github/workflows/pr.yml` builds pull requests
(`make debug`, with the check below, and `make`).

`build_st.sh` also checks that the `sz2.s` changes leave the other targets
alone. The X68000, Falcon and Amiga objects of `sz2.s` must be byte-identical
to those of the `amiga-port` revision; `CHECK=0` skips the check.

`binaries/st` holds the game's data beside the programs, so they run from
there, as the Amiga's and the Falcon's do from their folders: copies of
the Amiga port's `BGM_DAT`, `ETC_DAT` (its attract demo replay, which the
checkpoint reference was recorded with) and `XSP_DAT`, and of the Falcon
port's `PCM_DAT` (its `.sam` samples) with the ST's `SZ2_YM.BIN` added,
and the ST's own `MUSIC_DAT` (see Music below). `make check-data` (and
`make test`) checks that the copies still match those.
`make release` also copies the release, `SZ2.CFG` and the data into
`dist/CHORENSH`, a clean folder to copy to an ST (an `SZ2.CFG` already
there is kept). Each machine loads only what it plays: an ST the
YM effects in `SZ2_YM.BIN` and none of the `.sam` samples, an STE or Mega
STE the samples and not `SZ2_YM.BIN`. The program checks for its files at
start and says which one is missing.

`tests/st/run_hatari.sh NAME` stages the program with the game data (only
what the machine plays) in `tmp/stage_NAME/`, which is Hatari's drive C:,
and starts it in Hatari (`/Applications/Hatari.app`). On first use, TOS
2.06 is copied from `../atarist-rott/tmp/tos/` to `tmp/tos/`.

**Settings.** `SZ2.CFG`, next to the program, holds the settings: one
`name=value` a line, in any case, `#` or `;` starting a comment
(`binaries/st/SZ2.CFG` lists them all, commented out, each set to the
opposite of its default). Without the file every setting has its default.
A setting the program does not know, or a value it cannot read, is named
on the start-up screen and ignored. A file named on the program's command
line is read instead (test runs).

| Setting           | Default |                                                                                                          |
| ----------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `screen`          | `crop`  | `crop`: the 200-line screen, the window following the ship; `full`: both borders open, the whole picture |
| `megaste_speedup` | `true`  | `false`: a Mega STE stays at 8 MHz without the cache (for comparisons)                                   |
| `lockstep`        | `false` | `true`: every frame drawn from the start (F1 switches)                                                   |
| `frames`          | `0`     | A frame limit: the game exits after that many frames, with its report (measurements); 0: none            |

```
# Playing, in a window (MACHINE=megaste for the Mega STE).
WINDOW=1 MACHINE=ste PROG=binaries/st/SZ2.TOS tests/st/run_hatari.sh play

# Measurement: 6,000 frames of the attract demo, headless, fast forward.
MACHINE=ste FRAMES=6000 tests/st/run_hatari.sh attract
python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt tmp/out/attract_CHECKPTS.BIN

# A full-game replay from the Falcon port's set instead of the attract demo.
MACHINE=ste FRAMES=190000 REPLAY=DEMO3.REP tests/st/run_hatari.sh demo3

# Pixel oracle: every screenshot of a lockstep run against the reference renderer.
tests/st/oracle.sh
```

Options:

- `MACHINE`: `st`, `ste` or `megaste`. For an ST, `TOS=tmp/tos/tos104uk.img`
  gives TOS 1.04 (copy it from `../atarist-rott/tmp/tos/`); TOS 2.06 and
  EmuTOS run on an ST too.
- `FRAMES`: exit after that many frames. The run writes `CHECKPTS.BIN`
  and a PI1 screenshot every 500 frames; `tools/st/pi1_png.py` converts
  the screenshots to PNG in `tmp/out/shots_NAME/`.
- `REPLAY`: a `binaries/atari/ETC_DAT` replay, played as the demo.
- `SCREEN=full`: at full height. With `LOCKSTEP=1`, `MEGASTE8=1` and
  `FRAMES` it goes into the staged `SZ2.CFG`.
- `INPUT`: a frame-timed joystick script in the Amiga port's text format,
  such as `tests/st/input/autofire_held.txt`.
- `PROG`, `TOS`, `MEMSIZE`, `FF`, `WINDOW`, `MEGASTE8=1`. `MEGASTE8=1`
  keeps a Mega STE at 8 MHz without the cache, for comparisons
  (`megaste_speedup=false`).
- `SOUND` (a rate, default off) and `RECORD=FILE.wav`: Hatari's sound, and
  a recording of it, started and stopped with the command
  `fifo hatari-shortcut recsound`.

The console output is in `tmp/out/NAME.log`: the start-up memory report and
the exit report, with timings per stage.

**Controls:**

| Key or control          | Action                                                                                 |
| ----------------------- | -------------------------------------------------------------------------------------- |
| Cursor keys or joystick | Move                                                                                   |
| Z, CTRL or fire         | Shoot (held in a stage: auto fire)                                                     |
| X or SHIFT              | Second button                                                                          |
| P                       | Pause                                                                                  |
| ESC                     | Back to the title (from a game, also paused or at game over, and from CONFIG or the hidden menu); on the title: quit |
| EXIT (main menu)        | Quit                                                                                   |
| F1                      | Lockstep on and off: every frame is shown and the game slows down to the drawing speed |
| F2                      | Keeps the playfield window still instead of following the ship                         |

On macOS, use Z and X rather than CTRL: Ctrl + the arrow keys are Mission
Control shortcuts there, and Hatari never sees the arrows while Ctrl is held,
so the ship cannot move and fire at once. (Or switch those shortcuts off in
System Settings, Keyboard, Keyboard Shortcuts, Mission Control.)

The STE's enhanced joystick port A (a Jaguar pad) works on the STE; the
Mega STE has no such port.

**Xpad gamepads.** With an [Xpad](https://github.com/neilrackett/atarist-xpad)
provider installed (MD/Sidepad, COMpad, STEpad or any other), every pad it
reports plays, alongside the keyboard and joysticks:

| Pad                             | Action                             |
| ------------------------------- | ---------------------------------- |
| D-pad or left stick             | Move                               |
| A, X, right shoulder or trigger | Shoot (held in a stage: auto fire) |
| B, Y, left shoulder or trigger  | Bomb (the second button)           |
| START                           | Pause                              |

The start-up text says when a provider was found. While the game runs it
owns the machine, but with a provider present it leaves TOS's Timer C and
serial interrupts running: TOS's Timer C handler calls `etv_timer`, where
providers update their pads (COMpad reads TOS's serial buffer there). That
costs about 2% of the picture rate, and only with a provider installed.

On a Mega STE the program switches to 16 MHz with the cache on, writing
`$FFFF8E21` whole with the canonical value `$FF` (`$F4` for 8 MHz without
the cache with `megaste_speedup=false`), as Atari's control panel and
MSTE_CC do.
It reports what it reads back (a real Mega STE reads `$20` at TOS's
8 MHz and `$23` after the switch: the upper bits read as clear), and
restores the register on exit (TOS's cold-boot `$F4` if it read without
its upper bits).

The MFP stays in TOS's software end-of-interrupt mode: the port's own
handlers clear their in-service bits, so TOS's Timer C and serial handlers
(kept for an Xpad provider) are never interrupted by their own channel.

**Hard disks.** The game runs from any GEMDOS drive. Two things matter
with ACSI2STM's GemDrive (5.1), which Hatari's drive never shows:

- Its program loader clears only the first 130,560 bytes of a program's
  BSS (one DMA fill of 255 sectors). The port's BSS is about 1.6 MB, so
  the program clears its own first thing (`main.s` `start`).
- Its file handles are `$3200` and up (`$32` plus the ACSI ID, then the
  slot). The game's C library keeps a handle in a byte, which made the
  first file it opened read as handle 0, the keyboard: GEMDOS then waited
  for a key the port's own IKBD handler took, and the game hung at the
  start. The game now gets Human68k handles (5 up) that the DOS layer
  maps to GEMDOS's, as the Amiga port does.

## How it works

The game core (`sources/sz2.s`, the X68000 program as 68000 source) runs
on a port layer:

- Human68k DOS through line-F and GEMDOS (Human68k file handles mapped to
  GEMDOS's).
- IOCS through trap #15.
- The 50 Hz VBL as the game's frame tick.
- Sound effects through DMA sound.
- IKBD input. The mouse reporting is off while the game runs, and back in
  relative mode at exit. At both handler changes the IKBD's bytes are
  dropped until it has been quiet for 3 ms, so the new handler starts at a
  packet, not in the middle of one.

The layer is taken from the Falcon port, with the Amiga port's frame
scheduler, its extra DOS and IOCS calls, checkpoints and input scripts.
What is new is the picture.

### Display (`display.s`)

ST low resolution, triple-buffered, drawn in bitplanes. In crop (the
default; full height is below):

- **Lines 0-7, the HUD band:** the X68000 text layer's row 0 (score, high
  score), drawn into all three screens when the game writes it.
- **Lines 8-199, the playfield:** 192 of the X68000's 256 lines at their
  real size, 32 pixels from the left.
  - In a stage the window follows the ship, which sits two thirds of the
    way down; it moves at most 2 lines per frame.
  - Elsewhere, or after F2, the window shows lines 32-223, and lines
    48-239 while the game's hidden menu is open (its title to its EXIT).
  - The lives and bombs (text rows 1-3) stay at the top of the playfield.

The screen address is written at a VBL. The colours follow one VBL later,
when the new picture appears. A presented picture is therefore on screen
only two VBLs later, and the screen shown until then cannot be drawn into
before that. So there are three screens: the one shown, the one presented
and the one being drawn. Presenting waits for the picture before it to be
on screen, which by then it nearly always is, and drawing never waits.

### Full height (`screen=full`)

With the top and bottom borders open the screen shows 273 lines, enough
for the X68000's whole picture: the HUD band and the playfield's 248 lines
(the X68000's lines 8-255; its lines 0-7 are under the HUD), so there is
no window. The 256 lines are centred, the 17 others black.

Both layouts are in every build, chosen when the program starts: the
playfield's height and the screens' page size and origin are variables
(`display.s`), set from the layout, and the screens are allocated for it
(three of 32,000 bytes in crop, of 44,032 at full height), so crop gives
none of the sprite cache away. If the borders do not open (STDL says why:
a measurement build's exit report shows it), the game plays in crop.

- **The borders are STDL's code**, `lib/stdl/src/overscan.c` (the
  atarist-stdl submodule, as in the Flashback port), compiled unchanged
  with the toolkit's gcc and linked with the port's objects and libgcc.
  `sources/st/stdl_glue.c` supplies the few parts of STDL it reaches for,
  and opens and closes the borders for `main.s`: after the take-over, with
  the interrupts on (the first opening calibrates against the display and
  then finds the GLUE's bottom border test: a third of a second of
  flickering border), and before the release.
- **What it uses:** MFP Timer A and Timer B, a prefix on the VBL (and on
  TOS's Timer C handler, which runs only with an Xpad provider). At full
  height the measurement clock moves to Timer D (st.i), so a measurement
  build at full height does not work with COMpad; release builds have no
  measurement clock.
- **The port's screens** are pages of 274 lines (row 0 hidden), each drawn
  from 9 lines in, so the drawing code is unchanged but for the
  playfield's height. STDL is given the first page as its own and never
  flips; `display.s` flips the port's three pages itself and keeps the
  page addresses STDL's interrupts compare the video counter with up to
  date (the page shown, and the next one from the VBL that names it).
- **The background is copied by the CPU** on every machine at full
  height: a BLiTTER in HOG mode would hold off the borders' interrupts.
- **Screenshots** hold the whole 256-line picture (a PI1 longer than
  Degas's 200 lines, which `tools/st/pi1_png.py` reads); the pixel oracle
  is for crop only.

Results in Hatari (attract demo, 6,000 frames): the borders open on an ST
(TOS 1.04), an STE and a Mega STE, with no frame missing a border, also
over 30,000 frames of DEMO8, with an Xpad provider (TOS's Timer C
running) and with keys pressed. The checkpoints match: the game runs at
full speed, its logic 0.1-0.2 ms a frame slower (the borders' interrupts).
The desktop comes back intact after the exit.

| Pictures per gameplay second, mean (median) | ST        | STE       | Mega STE  |
| ------------------------------------------- | --------- | --------- | --------- |
| Crop                                        | 13.1 (12) | 13.2 (12) | 17.4 (17) |
| Full height                                 | 10.9 (10) | 10.7 (10) | 14.9 (14) |

A picture costs more: 248 lines of background instead of 192 (17.9 ms on
an ST, from 13.6) and more of the sprites visible (32.2 ms, from 27.2).

### Colours (`palette.s`, `palette_map.i`, `tools/st/palette_map.py`)

Every X68000 palette entry is drawn in one of the ST's 16 colours. The
mapping is fixed: it is computed offline from colour usage measured over
the attract demo and six full-game replays.

| ST colour | Use                                                                                                                                     |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 0         | Backdrop (black while the background shows)                                                                                             |
| 1, 2      | The game's colour-cycling entries (red, green)                                                                                          |
| 3-7       | Background colours; every background entry is a 2x2 ordered dither of two of them, anchored to its layer so the pattern scrolls with it |
| 8-15      | Sprite and text colours                                                                                                                 |

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
table, wrapping at most once (192 lines x 128 bytes):

- **An STE** copies it with the BLiTTER, in HOG mode 8 lines at a time
  (each about 0.5 ms with the interrupts held, well inside an IKBD byte):
  12.2 ms, the bus's limit.
- **A plain ST and the Mega STE** copy it with `movem`, four lines a pass
  (entered part-way for the remainder): 13.6 ms on an ST, 13.0 on a Mega
  STE, whose copy is bound by the 8 MHz bus. The Mega STE does not use the
  BLiTTER: every BLiTTER operation empties its cache. (Hatari times its
  BLiTTER at 16 MHz, about twice as fast as the bus allows.) A fully
  unrolled copy was slower there: its 5.8 KB of code left the cache and
  was fetched again every picture.

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

### Sound effects (`audio.s`, `tools/st/ym_effects.py`, `PCM_DAT\SZ2_YM.BIN`)

The game loads its samples at start (`LOAD_PCM_SAMPLE_FILES`, from the
list in `PCM_DAT\SZ2_PCM.CNF`) and plays one effect at a time through
`_ADPCMOUT`. Each machine loads only what it plays:

- **STE, Mega STE:** the game loads the samples (370 KB of its heap) and
  DMA sound plays them.
- **ST:** no DMA sound, so its YM2149 plays a version made in advance from
  each sample. The program loads `PCM_DAT\SZ2_YM.BIN` at start (12 KB). In
  the game's loader, a hook (`ifd __ST__`) asks `st_ym_effect` for each
  sample's YM version by file name instead of loading it, and
  `_ADPCMOUT` hands it over. The game's heap is 384 KB smaller, and the
  sprite cache gets it.

The YM versions:

- `tools/st/ym_effects.py` cuts each `.sam` into 20 ms frames, one per
  VBL. A frame's loudness is split between tone and noise by how tonal it
  is (its spectral flatness). The tones are the strongest spectral peak, or
  its fundamental if that is strong, on channel A, and a second peak that
  is not one of its harmonics (a chord) on channel C. The noise is on
  channel B, its period from the spectral centroid. Volumes are in the
  YM's 3 dB steps. It writes `binaries/st/PCM_DAT/SZ2_YM.BIN`: 31
  effects, 1,497 frames, 12 KB.
- `tools/st/ym_effects.py --preview DIR` also writes WAV files of every
  effect as sampled and as the YM plays it. `ALL.wav` has them all, each
  sampled then YM, and `ALL.txt` says where each one starts.
- On the ST, `audio.s` writes one frame of the effect into the YM per VBL:
  a few hundred cycles, with no visible cost. Effects the game plays at 10.4 kHz go
  1.5 times slower and lower (see the open items). As in STDL's YM service,
  registers 14 and 15 are never written, the mixer keeps the port direction
  bits, and interrupts are masked between selecting a register and writing
  it.

The attract demo on an ST, with no samples at all, plays 754 effects in
6,000 frames, every one with a YM version; its game heap holds 510 KB of
640 KB, and the sprite cache is 1,275 KB (881 KB on an STE), so it empties
a half less often (6 times against 10). A Hatari recording of an ST has sound in 276 of its 500
tenths of a second, and an STE's 275.

### Music (`music.s`, `tools/music/make_st_music.py`, `MUSIC_DAT`)

The game plays its songs (`BGM_DAT\*.MDC`, for the X68000's YM2151 FM
chip) through the MCDRV driver, trap #4. The port plays them on the
YM2149 instead, from register streams made in advance:

- `tools/music/build_music.sh`, the Amiga port's, runs MCDRV 0.69 itself
  in a 68000 emulator and records each song's YM2151 writes into
  `tools/music/deps/work/NAME.log`, the song's first two passes, and
  `NAME.fade.log` with a `_FADEOUT`. (It goes on to make the Amiga's
  `MUSIC_DAT`, so stop it there, or put that folder back from git.)
- `tools/music/make_st_music.py tools/music/deps/work binaries/st/MUSIC_DAT
  [stdlconv.py]` writes each log as a VGM file, each write at least a VGM
  sample (23 us) after the one before. The song's loop is in it once: the
  intro is the first pass up to where the loop starts (the loop command's
  time less the loop's length), the loop the second pass, which starts
  with the tails it has on every repeat, as the Amiga's streams do. At
  the join, the registers that differ between the two points are written
  as they stand at the second pass's start (MCDRV does not write again
  what it wrote before). It then converts the VGM with STDL's
  `stdlconv opm` into
  `MUSIC_DAT\NAME.STM`: STDL's STM format, per 50 Hz frame the YM2149
  registers that change. It also writes `sources/st/music_fades.i`, each
  song's `_FADEOUT` length per unit of speed, measured as the Amiga's
  script does (0.42 to 0.80 s). Twelve songs, 232 KB (with both passes
  they were 416); the largest, the fourth stage's, 30 KB.
- The spacing: `mcdrv_render` logs a timer tick's writes all at the
  tick's time, but on the X68000 the YM2151 is busy for a sample (16 us)
  after each write and MCDRV waits. When MCDRV keys a channel off and on
  again in one tick, which is how it restarts a note, the chip sees the
  key go off only if time passes between the two. In ymfm's render of
  the log as it is, those notes neither end nor restart: a third to most
  of each song's key-ons lose their attack (a repeated chord in the first
  stage's song fades out after its first note). The Amiga port's
  rendered songs have the same gaps; spreading the log's writes before
  `opm_render` would fix them.
- `stdlconv opm` models each of the eight FM channels frame by frame: its
  loudness from its carriers' envelopes (within about 1 dB of ymfm's
  render, channel by channel) and its pitch (checked against the
  spectrum of ymfm's). Instruments that keep to one or two pitches, or
  are tuned inharmonically, are drums: kicks and toms as falling tones,
  snares and hi-hats as noise. The three loudest parts get the voices,
  doubled parts counting once: the two most important on A and B, the
  third on C, where the drums sound too. A chord keeps one note.

`music.s`:

- At start, with `music=true` and streams in `MUSIC_DAT`, a buffer the
  size of the largest (30 KB, taken from the sprite cache; all twelve
  would take 232 KB). The MCDRV probe in `sz2.s` then reports the driver,
  and the game loads its songs as on the X68000. The Amiga port's hooks,
  the probe and `amiga_music_loaded` after each song is loaded (which
  keeps the song's name), are now `ifd __CHUNKY__`, so the ST shares them.
- `_TRANSMDC` names the song to play, `_PLAYMUSIC` loads its stream
  (GEMDOS, from the trap, as the game's own file calls are served) and
  plays it from the next VBL, `_STOPMUSIC` silences it, and `_FADEOUT`
  fades it over the song's measured length: MCDRV's 64 steps of 0.75 dB
  are 16 of the YM's 3 dB levels. The game stops while a song loads, at
  a stage's start and when a boss appears.
- Each VBL writes the frame's registers. As in STDL's player, registers
  14 and 15 are never written and the mixer keeps the port direction
  bits. Interrupts are masked between selecting a register and writing
  it, and only then, so a border interrupt at full height never waits
  for a whole frame's writes. `audio.s` now masks the same way.
- On an ST the YM plays the effects too. While one plays, `audio.s` mixes
  it down to voice C alone (the louder tone, the noise, the loudest
  level), and the music keeps A and B; once it is over, the music's
  registers are all written again. In the attract demo an effect has
  voice C in 87% of the music's frames. With `music=false` the effects
  have all three voices, as before.

The exit report gives the songs played and those that could not be
loaded, and on an ST the music's frames with an effect on voice C.

### Text (`text.s`)

The game's characters go into a 32 x 32 map instead of the X68000's 512 KB
of text planes:

- `DRAW_CHARACTER` jumps to `st_draw_character`.
- Row 0 is drawn straight into the HUD band of all three screens.
- The other rows are drawn over each picture, masked, with `movep`. Only
  the characters that have pixels are drawn: each row keeps a mask of
  them.

### The game code (`sz2.s`)

The port's changes are all `ifd __ST__`; `-D__ST__` also defines `__PORT__`,
`__CHUNKY__` (the Amiga port's hooks) and `__PORT_CREDITS__`:

| Change                                           | What it does                                                                                                                                             |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Builder skip (`INITIALIZE_SPRITES_AND_GRAPHICS`) | The background builder runs once only                                                                                                                    |
| `DRAW_CHARACTER`                                 | Goes to the character map                                                                                                                                |
| VBL handler                                      | Only the counters and the game's vsync function                                                                                                          |
| Sprite tables                                    | Two, swapped at `XSP_OUT` instead of copied (`XOBJ_SET`'s room check reads `st_sprite_buffer_end`)                                                       |
| Shot slot loop (`L_0002B410`)                    | Kept in registers, with the collision-grid routine and `XSP_SET_ST` inlined instruction for instruction (about 0.5 ms per frame)                         |
| Stage hook                                       | Auto fire                                                                                                                                                |
| ESC (`__CHUNKY__`, from the Amiga port)          | Back to the title from a game, EXIT on the title: the Amiga port's hooks, shared (`amiga_escape_*` in `input.s`)                                         |
| ESC in CONFIG and the hidden menu                | Their EXIT, back to the title (without it ESC was only the X68000's START, which these menus read as trigger A on the item under the cursor)             |
| Title menu                                       | CONFIG chosen with trigger B held (SHIFT, X, B on a pad) opens the hidden menu, KAKUSI mode; a held trigger B no longer stops trigger A choosing an item |
| Other                                            | EXIT, `PRINTF`, the rotated screen (off), the menu credits                                                                                               |

The X68000, Falcon and Amiga objects are unchanged (`build_st.sh` checks
this).

### Timing

The 50 Hz VBL is the game's frame tick, so the game runs at 50 instead of
55.46 frames per second. After each game frame:

- If the game is on time, the frame is drawn and shown.
- If it is late, the frame is not drawn and the game catches up, with up to
  64 frames of debt.

Measurement builds time everything with MFP Timer A (38,400 Hz,
independent of the CPU speed): game logic per frame, render per picture,
and its parts. (Timer D, the serial port's baud rate clock, stays as TOS
set it, for COMpad.) At full height, whose borders need Timer A, the
clock is Timer D instead.

## Memory

| Part                                                                                     | KB                                                         |
| ---------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Code (game 246, port 14, STDL's border code and libgcc 9)                                | 269                                                        |
| Data                                                                                     | 41                                                         |
| Game BSS (includes the 128 KB demo replay buffer)                                        | 310                                                        |
| Composed background table (at the GVRAM label; GVRAM while the game builds it)           | 1,024                                                      |
| X68000 register and sprite shadows                                                       | 96                                                         |
| Background layers (made once, for the table)                                             | 45                                                         |
| Sprite tables (per-palette pair tables 32, per-pattern variants 7.5, sprite list, order) | 46                                                         |
| Checkpoints (not in the release build)                                                   | 65                                                         |
| Text, input script, stage counters, stack                                                | 27                                                         |
| **Program**                                                                              | **1,919** (1,855 release)                                  |
| Game heap (stack, sprite patterns, samples, tables)                                      | 1,024 (871 used); 640 on an ST, with no samples (510 used) |
| Three screens (allocated for the layout chosen)                                          | 94; 129 at full height                                     |
| Music buffer (the largest song; none with `music=false`)                                 | 30                                                         |
| Kept free for TOS                                                                        | 64                                                         |
| **Sprite arena**                                                                         | **881** (946 release); 846 at full height; 30 less with the music |

## Measurements

### Pictures per second over the work (attract demo, 6,000 frames)

| Step                                                                                | STE  | Mega STE |
| ----------------------------------------------------------------------------------- | ---- | -------- |
| Proof of concept: chunky buffer, C2P, 16 greys                                      | 1.0  | 2.2      |
| Colour, bitplanes, composed background, sprite masters                              | 6.6  | 11.7     |
| Preshifted sprite cache, faster text                                                | 8.8  | 14.0     |
| VBL stub, swapped sprite tables                                                     | 9.4  | 14.5     |
| HUD rows pinned, blank characters skipped, variant tables                           | 9.7  | 14.6     |
| Arena in two halves                                                                 | 9.8  | 14.7     |
| Sprite rows through registers                                                       | 10.1 | 15.3     |
| Faster masters and shifted copies (worst picture 431 to 274 ms)                     | 10.7 | 15.9     |
| Shot slots in registers (logic −0.4 ms per frame)                                   | 10.9 | 16.2     |
| Faster text rows                                                                    | 11.4 | 16.5     |
| Leaner per-sprite path                                                              | 12.0 | 17.1     |
| Masters skip empty half rows                                                        | 12.2 | 17.2     |
| Three screens: two let the next picture be drawn into the one still shown (flicker) | 12.1 | 17.1     |
| Release build (no measurements, 64 KB more sprite cache)                            | 12.4 | 17.4     |
| The work since: an STE's BLiTTER background copy, both layouts in one program       | 12.8 | 17.2     |
| Release build, now                                                                  | 13.1 | 17.6     |

### On a real Mega STE

Measured on a Mega STE (TOS 2.06, 4 MB, 16 MHz with the cache) with the
game on an ACSI2STM's GemDrive and COMpad, STinG, an accessory and
md-devops loaded: the attract demo, 6,000 frames, the measurement build
(`SZ2_DEV.TOS`, `DEVOPS=1`, run with `tests/st/hw/run_on_st.sh`) in each
layout.

| Layout      | Pictures per second (mean) | Gameplay median | Background ms | Sprites ms  | Sprite cache |
| ----------- | -------------------------- | --------------- | ------------- | ----------- | ------------ |
| Crop        | 15.3 (Hatari 17.4)         | 15 (Hatari 17)  | 13.4 (13.0)   | 23.0 (19.6) | 452 KB (881) |
| Full height | 12.5 (Hatari 14.9)         | 12 (Hatari 14)  | 17.7          | 29.1        | 417 KB (846) |

Hatari's timing holds: the background copy and the game logic (median
3.9 ms) are within a few percent. The difference is memory: the drivers
and accessories leave about 430 KB less TPA (3,553 KB), all of it taken
from the sprite cache, which then switches halves 36 times instead of 13
and makes more shifted copies. At full height both borders opened on
every one of the 6,000 frames.

### Pictures per second by stage (full-game replays, 190,000 frames)

| Stage    | ST DEMO3 | ST DEMO8 | STE DEMO3 | STE DEMO8 | Mega STE DEMO3 | Mega STE DEMO8 |
| -------- | -------- | -------- | --------- | --------- | -------------- | -------------- |
| 1        | 13.5     | 14.9     | 13.6      | 15.0      | 18.1           | 19.0           |
| 2        | 13.8     | 14.6     | 13.8      | 14.7      | 18.1           | 18.6           |
| 3        | 10.8     | 12.0     | 10.8      | 12.1      | 15.4           | 16.3           |
| 4        | 9.2      | 10.9     | 9.1       | 10.8      | 13.5           | 15.0           |
| 5 (part) | 15.8     | 10.4     | 15.8      | 10.4      | 19.8           | 14.9           |
| **All**  | **12.0** | **12.9** | **12.0**  | **12.9**  | **16.4**       | **17.1**       |

Game logic over the replays, median / 95%: ST 7.4 / 14.3 ms (DEMO3) and
6.4 / 14.3 ms (DEMO8); STE 6.9 / 14.3 and 6.4 / 13.8 ms; Mega STE 4.9 / 9.4
and 4.4 / 8.9 ms.
The stages are the low 4 bits of the game's stage word; DEMO3 ends early
in stage 5, DEMO8 later.

### Pictures per second, second by second

The exit report also counts each second of gameplay (50 ticks, every
frame in a stage) by the pictures it showed. Over both replays (about
7,300 seconds per machine):

| Pictures per second    | ST              | STE             | Mega STE         |
| ---------------------- | --------------- | --------------- | ---------------- |
| 25 (the most)          | 14.8%           | 15.8%           | 23.4%            |
| 20-24                  | 6.3%            | 6.1%            | 15.3%            |
| 15-19                  | 13.1%           | 13.7%           | 21.5%            |
| 10-14                  | 25.0%           | 23.0%           | 24.2%            |
| 5-9                    | 28.5%           | 27.9%           | 14.2%            |
| Under 5                | 12.3%           | 13.5%           | 1.4%             |
| **Median (25% / 75%)** | **11** (7 / 17) | **11** (7 / 17) | **17** (12 / 24) |
| Mean                   | 12.6            | 12.6            | 16.8             |

- **25 is the ceiling on every machine.** A picture shows when the game is
  on time after it, so 50 per second would need the game logic and a whole
  picture within one 20 ms tick. The background copy alone takes 12.2-13.6
  ms (bound by the bus, so the Mega STE's 16 MHz barely helps), so every
  picture spans at least two ticks.
- **The slowest seconds** (0 or 1 picture: 2-3% of the seconds on an ST
  or STE, 3 seconds of 7,300 on a Mega STE) are the heaviest scenes: screens full of
  explosions, the bosses, walls of shots. There the game itself can fall
  behind for a moment: over each replay it ran about 2 s behind real time
  on an ST or STE, besides the first game start.

### Where a picture's time goes

| Per picture (ms)                   | STE attract | STE DEMO3 | Mega STE attract | Mega STE DEMO3 |
| ---------------------------------- | ----------- | --------- | ---------------- | -------------- |
| Background copy                    | 12.3        | 12.6      | 13.0             | 13.5           |
| Sprites (drawing, making variants) | 27.9        | 27.2      | 19.8             | 20.3           |
| Text                               | 3.9         | 3.0       | 2.5              | 1.8            |
| Borders and colours                | 0.8         | 0.8       | 0.6              | 0.6            |
| **Render**                         | **45.2**    | **43.9**  | **36.3**         | **36.6**       |

In the attract demo an STE picture draws about 51 sprites: 315 rows of two
groups and 290 of one, about 13.5 ms. Making variants takes about 6 ms on
average: about 8 shifted copies and 1.2 masters a picture in the replays.
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

- **Full height.** `tests/st/overscan_test.sh` runs the attract demo at
  full height (`SCREEN=full`) on an ST (TOS 1.04), an STE and a Mega STE:
  the borders must open (273 lines), never miss a frame, and the
  checkpoints must match.
- **Xpad.** `tests/st/xpad_test.sh` builds a scripted provider
  (`tests/st/xpad/xpadtest.s`, a TSR for `C:\AUTO` that presses buttons
  from `etv_timer`) and runs the game with it. Its grabs show the menu
  started with A, the ship moving while it fires, and the pause. With the
  same provider idle, the attract demo still matches all its checkpoints.
- **Mouse.** `tests/st/mouse_test.sh` needs EmuMD's Hatari, whose
  `--cmd-fifo` can move the mouse (`../emumd/hatari/build-hatari.sh`
  builds it). It starts the game 40 times with the mouse moving all
  through the start. A handler taking over part-way through a mouse packet
  would read one of its bytes as F1 and turn lockstep on. Before the
  take-over drained the IKBD, 5 of 80 starts did; now none of 120 do. It
  then checks that the desktop's pointer moves after the exit.

- **Checkpoints.** Every 60 frames: score, random table index, scroll,
  sprite count and player state. They are compared with
  `tests/amiga/checkpoints.py`. The attract demo matches the Amiga port's
  reference (100 of 100) on the STE and the Mega STE, headless or not, and
  in lockstep, and on an ST with TOS 1.04 (no cookie jar), TOS 2.06 and
  EmuTOS. The DEMO3 and DEMO8 replays give the same 2,048 checkpoints
  before and after the shot slot change.
- **Pixels.** `tests/st/oracle.sh` builds with a frame dump at each
  screenshot and runs the attract demo in lockstep. `tools/st/refrender.py`
  draws each picture again from the dump, independently of the 68000 code,
  and every pixel and colour must match: 12 of 12 frames, on an STE and on
  an ST.
- **Hidden menu.** `tests/st/input/kakusi_shift_fire.txt` (run with
  `INPUT=` and `FRAMES=1100`) opens it from CONFIG with trigger B held:
  its grabs show the whole menu in crop, then the title again after its
  EXIT.
- **ESC.** `make test` runs `tests/st/input/esc_config.txt` and
  `esc_kakusi.txt`: each opens its menu, leaves it with ESC and quits
  from the title with another, so the run ends at frame 1100 ("Exit:
  game"), before its frame limit. An input script's key records (the
  Amiga's raw codes) reach the ST's keyboard handler as its scancodes.
- **Other targets.** `build_st.sh` checks that the other objects of `sz2.s`
  are unchanged.
- **Real hardware.** `tests/st/hw/run_on_st.sh` runs a build on a real ST
  through md-devops (a SidecarTridge Multi-device with the DevOps
  microfirmware, its GEMDRIVE Runner and `DEVOPS.ACC`). It uploads the
  program to md-devops' drive, and a small launcher there
  (`tests/st/hw/launch.s`) copies it to the ST's own disk and runs it
  from there, so the ST's own hard disk driver loads it. A `DEVOPS=1`
  build sends its text, the start-up and the exit report, to md-devops'
  debug stream as well as the screen. With `FRAMES` the run ends by
  itself; a program that hangs owns the interrupts, and only the reset
  button gets the ST back. Its `SCREEN` and `FRAMES` go into a settings
  file of the run's own, named on the program's command line. On a Mega
  STE with ACSI2STM's GemDrive, both layouts, measurement and release
  builds, run their frames and exit.

## Open items and next steps

- **HUD colours.** The score uses the shared sprite/text colours. A Timer B
  palette change at line 8 would give the HUD band its own exact colours.
- **More speed.**
  - The sprite cache switches halves about every 650-700 frames in the
    full game on an STE (470 on a Mega STE, which draws more pictures;
    1,200 on an ST, whose cache is bigger). More memory would
    help: samples at 6.25 kHz would free 185 KB, at some cost in sound. So
    would keeping recently used copies when a half is emptied.
  - The background copy is at the bus limit. On an STE or a Mega STE the
    table could be shown directly, with no copy: the video address
    switched mid-frame (at line 8, and where the table wraps), sprites
    drawn into the table with what they cover saved and put back once the
    picture has left the screen. That needs 160-byte table lines (256 KB
    more) and a raster split on time every frame. A plain ST cannot write
    its video address mid-frame. The `atarist-direct` branch has a
    prototype of the splits (the background only, no sprites or text, in
    Hatari): none late in the attract demo or 30,000 frames of DEMO8. It
    predates the full height and the settings.
- **Music.** The songs are reduced automatically, so a chord keeps one
  note, and how each song's parts share the voices is the converter's
  guess. Songs checked by ear, with `stdlconv opm`'s choices adjusted per
  song, would be better. A Mega STE or an STE could also stream the
  Amiga port's rendered songs from disk with DMA sound, at the cost of
  the effects' channel and the disk's bandwidth.
- **Sound effects on an ST.** The YM versions are a first conversion: the
  explosions, hits and menu sounds are close, and the sweeping lasers only
  roughly. The converter's settings, or hand-made frames for single
  effects, are the way to improve them.
- **Sound effects.** The effects the game plays at 10.4 kHz (four, the
  second boss's) play 1.5 times too fast on an STE: the Falcon port's
  `.sam` files were all converted as 15.6 kHz recordings. The ST's YM
  versions play them at the right speed.
- **Coverage.** Stages 6 and 7 are not reached by the replays used for the
  colour map and the measurements.
- **Timers.** Timer C (the TOS 200 Hz timer) is stopped while the game
  runs. That is fine with Hatari's GEMDOS drive and ACSI2STM's GemDrive on
  a real Mega STE; it is untested with floppies.
- **Testing.** Besides Hatari, the port has run on one real machine, a
  Mega STE (both layouts, 6,000 frames each, no border missed). An ST and
  an STE remain to be tried on hardware.
