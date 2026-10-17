#!/bin/bash
#
# Mouse test: the IKBD at the port's take-over and at its exit, in EmuMD's
# Hatari, whose --cmd-fifo can move the mouse (built by
# ../emumd/hatari/build-hatari.sh).
#
# - Starts: RUNS runs (PARALLEL at once) with the mouse moving all through
#   the start, a packet ($F8 $00 $3B: down 59) about every frame. A handler
#   taking over part-way through a packet would read $3B as F1 and turn
#   lockstep on, every frame shown. Each run must show under 2/3 of its
#   frames. (Before the take-over drained the IKBD, 5 runs in 80 did, so
#   40 runs miss a fault that rare about 1 time in 13.)
# - Desktop: after the program exits, a mouse move must move the desktop's
#   pointer (two screen grabs differ).
#
#   tests/st/mouse_test.sh           (MACHINE=ste|st|megaste, PROG=...,
#                                     RUNS=40, PARALLEL=8, HATARI=...)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

export HATARI=${HATARI:-$HOME/.cache/emumd/hatari-fork/build/src/hatari}
export MACHINE=${MACHINE:-ste}
export PROG=${PROG:-binaries/st/SZ2_ST.TOS}
RUNS=${RUNS:-40}
PARALLEL=${PARALLEL:-8}
FRAMES=300

if [ ! -x "$HATARI" ]; then
	echo "$0: no EmuMD Hatari at $HATARI (../emumd/hatari/build-hatari.sh builds it)" >&2
	exit 1
fi
if [ "$MACHINE" = "st" ]; then
	export TOS=${TOS:-tmp/tos/tos104uk.img}
fi

mkdir -p tmp/out

start_run() {
	local name=mouse_$1
	rm -f tmp/out/fifo_$name
	python3 tests/st/mouse_stream.py tmp/out/fifo_$name 0 59 15 &
	FRAMES=$FRAMES FF=off TIMEOUT=300 tests/st/run_hatari.sh $name > tmp/out/$name.txt 2>&1
	wait
	rm -rf tmp/stage_$name
}

run=1
while [ $run -le $RUNS ]; do
	for i in $(seq 1 $PARALLEL); do
		[ $run -le $RUNS ] && start_run $run &
		run=$((run + 1))
	done
	wait
done

failed=0
for run in $(seq 1 $RUNS); do
	pictures=$(sed -n 's/.*pictures: \([0-9]*\).*/\1/p' tmp/out/mouse_$run.log)
	if [ -z "$pictures" ] || [ "$pictures" -ge $((FRAMES * 2 / 3)) ]; then
		echo "start $run: ${pictures:-no} pictures of $FRAMES frames"
		failed=1
	fi
done
[ $failed = 0 ] && echo "Starts: $RUNS with the mouse moving, none misread it."

FRAMES=100 FF=off TIMEOUT=120 tests/st/run_hatari.sh mouse_desktop \
	"waitfor End of the run.;sleep 4;shot;fifo hatari-event mousemove 100 50;sleep 2;shot" \
	> tmp/out/mouse_desktop.txt 2>&1
GRABS=tmp/out/shots_mouse_desktop
if [ ! -f $GRABS/grab0002.png ]; then
	echo "Desktop: no screen grabs"
	failed=1
elif cmp -s $GRABS/grab0001.png $GRABS/grab0002.png; then
	echo "Desktop: the pointer did not move after the exit"
	failed=1
else
	echo "Desktop: the pointer moves after the exit."
fi

exit $failed
