#!/bin/bash
#
# Pixel oracle for the Atari STE port: builds it with -D__ORACLE__ (a frame
# dump with every screenshot) and -D__DUMP__ (the game's GVRAM as built,
# GRAPHICS.BIN), runs the attract demo in lockstep in Hatari, and compares
# every screenshot with tools/ste/refrender.py's picture of the same frame:
# all must be identical.
#
#   tests/ste/oracle.sh            (MACHINE=ste|megaste, FRAMES=6500)

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MACHINE=${MACHINE:-ste}
FRAMES=${FRAMES:-6500}
NAME=oracle_$MACHINE

FLAGS="-D__ORACLE__ -D__DUMP__" NAME=SZ2_ORC CHECK=0 ./build_ste.sh > /dev/null

PROG=binaries/ste/SZ2_ORC.TOS LOCKSTEP=1 MACHINE=$MACHINE FRAMES=$FRAMES TIMEOUT=3600 \
	tests/ste/run_hatari.sh $NAME > tmp/out/$NAME.txt 2>&1

python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt \
	tmp/out/${NAME}_CHECKPTS.BIN

python3 tools/ste/refrender.py --graphics tmp/out/${NAME}_GRAPHICS.BIN \
	--font binaries/amiga/XSP_DAT/SZ_TEXT.PCG --map sources/ste/palette_map.i \
	--diff tmp/out/diff_$NAME tmp/out/shots_$NAME
