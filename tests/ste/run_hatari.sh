#!/bin/bash
#
# Runs the Atari STE / Mega STE proof of concept in Hatari (modelled on
# atarist-stdl/tests/hatari/run.sh).
#
#   tests/ste/run_hatari.sh NAME ["cmd;cmd;..."]
#
# The program and the game data are staged in tmp/stage_NAME/, which Hatari
# mounts as GEMDOS drive C: and the program starts from (the Amiga port's
# BGM_DAT, ETC_DAT and XSP_DAT, which its attract demo reference was
# recorded with, and the Falcon port's PCM_DAT with the 8-bit samples).
# The console output (the program's start-up text and exit report, through
# --conout 2) goes to tmp/out/NAME.log, screenshots to tmp/out/shots_NAME/.
#
# Environment:
#   MACHINE   ste (default) or megaste (the program switches the Mega STE to
#             16 MHz and its cache; no --cpuclock)
#   FRAMES    a frame limit: the game exits after that many frames (the
#             attract demo) and writes CHECKPTS.BIN, copied to tmp/out/
#   FF        fast forward, on (default with FRAMES) or off
#   WINDOW    1: show Hatari's window (default: headless, SDL dummy driver)
#   PROG      the program (default binaries/ste/SZ2_STE.TOS)
#   TOS       the TOS image (default tmp/tos/tos206uk.img, copied from
#             ../atarist-rott/tmp/tos/ when missing)
#   MEMSIZE   RAM in MB (default 4)
#   TIMEOUT   seconds before Hatari is stopped (default 900)
#   BOOT_WAIT seconds from launch to the first command (default 10)
#   MEGASTE8  1: keep a Mega STE at 8 MHz without the cache (MEGASTE8.TXT)
#   LOCKSTEP  1: start in lockstep mode (every frame rendered; LOCKSTEP.TXT)
#   REPLAY    a replay from binaries/atari/ETC_DAT (e.g. DEMO3.REP) used as
#             the attract demo (ETC_DAT/DEMO.REP)
#   INPUT     an input script (text, as tests/amiga/input/*.txt; only its
#             joystick lines are used), staged as INPUT.BIN
#   EXTRA     extra Hatari options
#
# Commands (after the program has started):
#   sleep N, shot, key VAL, keydown VAL, keyup VAL, fifo CMD..., waitfor STR
#   (as in the stdl script; VAL is an ST scancode such as 0x39, or a
#   character)
#
# Measurement runs (FRAMES) also write a screenshot every 500 frames
# (Snnnnnnn.PI1), copied to tmp/out/shots_NAME/ and converted to PNG with a
# montage (tests/ste/pi1_png.py).

set -u

NAME=$1
SCRIPT=${2:-}

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HATARI=${HATARI:-/Applications/Hatari.app/Contents/MacOS/hatari}
MACHINE=${MACHINE:-ste}
FRAMES=${FRAMES:-}
WINDOW=${WINDOW:-0}
PROG=${PROG:-binaries/ste/SZ2_STE.TOS}
TOS=${TOS:-tmp/tos/tos206uk.img}
MEMSIZE=${MEMSIZE:-4}
TIMEOUT=${TIMEOUT:-900}
BOOT_WAIT=${BOOT_WAIT:-10}
if [ -n "$FRAMES" ]; then
	FF=${FF:-on}
else
	FF=${FF:-off}
fi

OUT=tmp/out
STAGE=tmp/stage_$NAME
FIFO=$OUT/fifo_$NAME
SHOTDIR=$OUT/shots_$NAME
LOG=$OUT/$NAME.log

mkdir -p "$OUT"
rm -rf "$STAGE" "$SHOTDIR" "$FIFO" "$LOG" "$OUT/$NAME.err" "$OUT/${NAME}_CHECKPTS.BIN"
mkdir -p "$STAGE" "$SHOTDIR"

if [ ! -f "$TOS" ] && [ "$TOS" = tmp/tos/tos206uk.img ]; then
	mkdir -p tmp/tos
	cp "../atarist-rott/tmp/tos/TOS 2.06 - UK - Original.IMG" "$TOS" || exit 2
fi
if [ ! -f "$TOS" ]; then
	echo "$0: TOS image not found: $TOS" >&2
	exit 2
fi
if [ ! -f "$PROG" ]; then
	echo "$0: program not found: $PROG (run ./build_ste.sh)" >&2
	exit 2
fi

PROGRAM_NAME=$(basename "$PROG")
cp "$PROG" "$STAGE/$PROGRAM_NAME"
cp -R binaries/amiga/BGM_DAT binaries/amiga/ETC_DAT binaries/amiga/XSP_DAT "$STAGE/"
cp -R binaries/atari/PCM_DAT "$STAGE/"
if [ -n "${REPLAY:-}" ]; then
	cp "binaries/atari/ETC_DAT/$REPLAY" "$STAGE/ETC_DAT/DEMO.REP" || exit 2
fi
if [ -n "$FRAMES" ]; then
	echo "$FRAMES" > "$STAGE/FRAMES.TXT"
fi
if [ "${MEGASTE8:-0}" = "1" ]; then
	echo "8 MHz" > "$STAGE/MEGASTE8.TXT"
fi
if [ "${LOCKSTEP:-0}" = "1" ]; then
	echo "lockstep" > "$STAGE/LOCKSTEP.TXT"
fi
if [ -n "${INPUT:-}" ]; then
	python3 tests/amiga/make_input_script.py "$INPUT" "$STAGE/INPUT.BIN" || exit 2
fi

if [ "$WINDOW" != "1" ]; then
	export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
fi

"$HATARI" ${EXTRA:-} --tos "$TOS" --machine "$MACHINE" --memsize "$MEMSIZE" \
	--fast-boot on --fast-forward "$FF" --sound off --statusbar off \
	--confirm-quit off --conout 2 --cmd-fifo "$FIFO" \
	--screenshot-dir "$SHOTDIR" --screenshot-format png \
	"$STAGE/$PROGRAM_NAME" > "$LOG" 2> "$OUT/$NAME.err" &
HPID=$!

for i in $(seq 1 50); do
	[ -p "$FIFO" ] && break
	sleep 0.2
done

START=$(date +%s)

# Waits until STR is in the log, Hatari has ended or the timeout is reached.
wait_for() {
	while ! grep -q "$1" "$LOG" 2>/dev/null; do
		kill -0 $HPID 2>/dev/null || return 1
		[ $(( $(date +%s) - START )) -ge "$TIMEOUT" ] && return 1
		sleep 0.5
	done
}

# Hatari's console output reaches the log only in blocks (the program's
# start-up text may appear only at the end), so commands start after a
# fixed BOOT_WAIT.

if [ -n "$SCRIPT" ]; then
	sleep "$BOOT_WAIT"
	IFS=';' read -ra CMDS <<< "$SCRIPT"
	for cmd in "${CMDS[@]}"; do
		set -- $cmd
		case $1 in
			sleep)   sleep "$2" ;;
			shot)    echo "hatari-shortcut screenshot" > "$FIFO" ;;
			key)     echo "hatari-event keypress $2" > "$FIFO" ;;
			keydown) echo "hatari-event keydown $2" > "$FIFO" ;;
			keyup)   echo "hatari-event keyup $2" > "$FIFO" ;;
			fifo)    shift; echo "$*" > "$FIFO" ;;
			waitfor) shift; wait_for "$*" ;;
			*)       echo "unknown command: $cmd" >&2 ;;
		esac
	done
fi

if [ -n "$FRAMES" ]; then
	# The exit report ends with the heap line; then Hatari is stopped.
	wait_for "Game heap used" || echo "$0: no exit report (timeout or Hatari ended)" >&2
	sleep 1
	kill $HPID 2>/dev/null
elif [ -n "$SCRIPT" ]; then
	sleep 1
	kill $HPID 2>/dev/null
fi

wait $HPID 2>/dev/null

[ -f "$STAGE/CHECKPTS.BIN" ] && cp "$STAGE/CHECKPTS.BIN" "$OUT/${NAME}_CHECKPTS.BIN"
[ -f "$STAGE/USAGE.BIN" ] && cp "$STAGE/USAGE.BIN" "$OUT/${NAME}_USAGE.BIN"
[ -f "$STAGE/GRAPHICS.BIN" ] && cp "$STAGE/GRAPHICS.BIN" "$OUT/${NAME}_GRAPHICS.BIN"
if ls "$STAGE"/F*.BIN > /dev/null 2>&1; then
	cp "$STAGE"/F*.BIN "$SHOTDIR/"
fi
if ls "$STAGE"/S*.PI1 > /dev/null 2>&1; then
	cp "$STAGE"/S*.PI1 "$SHOTDIR/"
	python3 tests/ste/pi1_png.py --montage "$SHOTDIR/montage.png" "$SHOTDIR"/S*.PI1
fi

echo "=== $NAME ($MACHINE, ${MEMSIZE} MB) console output ==="
tr -d '\r' < "$LOG"
if ls "$SHOTDIR"/* > /dev/null 2>&1; then
	echo "=== screenshots ==="
	ls "$SHOTDIR"
fi
