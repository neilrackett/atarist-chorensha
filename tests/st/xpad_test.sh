#!/bin/bash
#
# Xpad test: builds the scripted test provider (tests/st/xpad/xpadtest.s)
# and runs the game with it in C:\AUTO. The provider starts a game from the
# menu with A, holds right then left with A (the ship moves while it
# fires), then presses START (pause). Screen grabs go to
# tmp/out/shots_xpad/ (the timeline is in real time: about 50 ticks a
# second from boot); the start-up text must report the provider.
#
#   tests/st/xpad_test.sh            (MACHINE=ste|megaste, PROG=...)

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MACHINE=${MACHINE:-ste}
PROG=${PROG:-binaries/st/SZ2_REL.TOS}

mkdir -p tmp/xpadtest
STCMD_NO_TTY=1 STCMD_QUIET=1 ST_WORKING_FOLDER="$ROOT" stcmd vasmm68k_mot \
	/tmp/tests/st/xpad/xpadtest.s -quiet -Ftos -m68000 -I/tmp/lib/xpad/src \
	-o /tmp/tmp/xpadtest/XPADTEST.PRG

GRABS="shot;sleep 2;shot;sleep 17.5;shot;sleep 0.8;shot;sleep 1.2;shot"
GRABS="$GRABS;sleep 0.8;shot;sleep 2.2;shot;sleep 1.0;shot;sleep 2.5;shot"

AUTO=tmp/xpadtest/XPADTEST.PRG PROG=$PROG MACHINE=$MACHINE BOOT_WAIT=10 \
	TIMEOUT=120 tests/st/run_hatari.sh xpad "$GRABS" > tmp/out/xpad.txt 2>&1 || true

grep "Xpad" tmp/out/xpad.txt
ls tmp/out/shots_xpad/
