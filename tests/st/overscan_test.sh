#!/bin/bash
#
# Full-height test: runs the attract demo at full height (SZ2.CFG's
# screen=full: both borders open with STDL's code, lib/stdl) on an ST (TOS
# 1.04), an STE and a Mega STE. Each run must open the borders (273 lines),
# show them on every frame (no frame with a border missed) and match the
# Amiga port's reference checkpoints: the game logic is untouched by the
# taller picture.
#
#   tests/st/overscan_test.sh        (FRAMES=6000)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FRAMES=${FRAMES:-6000}
REFERENCE=tests/amiga/reference/attract-6000.txt

mkdir -p tmp/out
CHECK=0 ./build_st.sh > /dev/null 2>&1 || exit 1

SCREEN=full MACHINE=st TOS=tmp/tos/tos104uk.img FRAMES=$FRAMES \
	tests/st/run_hatari.sh overscan_st > /dev/null 2>&1 &
SCREEN=full MACHINE=ste FRAMES=$FRAMES \
	tests/st/run_hatari.sh overscan_ste > /dev/null 2>&1 &
SCREEN=full MACHINE=megaste FRAMES=$FRAMES \
	tests/st/run_hatari.sh overscan_megaste > /dev/null 2>&1 &
wait

failed=0
for machine in st ste megaste; do
	log=tmp/out/overscan_$machine.log
	borders=$(grep -h "^Overscan:" $log)
	rate=$(grep -h "pictures per second:" $log | sed 's/.*mean //')
	checkpoints=$(python3 tests/amiga/checkpoints.py compare \
		tmp/out/overscan_${machine}_CHECKPTS.BIN $REFERENCE 2>&1 | tail -1 | sed 's/.*: //')
	echo "$machine: ${borders:-no report}; $checkpoints; pictures per second ${rate:-?}"
	case "$borders" in
		*"273 lines, frames with a border missed: 0"*) ;;
		*) failed=1 ;;
	esac
	case "$checkpoints" in
		"matches "*) ;;
		*) failed=1 ;;
	esac
done

exit $failed
