#!/bin/bash
#
# Atari ST / STE / Mega STE port: builds binaries/st/SZ2_ST.TOS
# (stripped) and SZ2_DBG.TOS (with symbols, for the Hatari profiler) with the
# atarist-toolkit-docker cross tools, through "stcmd" (the repository is
# mounted at /tmp in the container; one tool per call).
#
# Then checks that the sz2.s changes leave the other targets alone: the
# X68000, Falcon and Amiga objects of sz2.s must be identical to those of
# the base revision's sz2.s (CHECK=0 skips this; BASE=<revision>, default
# amiga-port).
#
#   ./build_st.sh                 the game
#   HEADLESS=1 ./build_st.sh      the game without rendering (SZ2_HL.TOS:
#                                  game logic, checkpoints and timing only)
#   RELEASE=1 ./build_st.sh       the game without the measurements (SZ2_REL.TOS:
#                                  no Timer D, timing, checkpoints or report)
#   FLAGS=... NAME=... ./build_st.sh  extra defines, another program name

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

BASE=${BASE:-amiga-port}
CHECK=${CHECK:-1}

st() {
	STCMD_NO_TTY=1 STCMD_QUIET=1 ST_WORKING_FOLDER="$ROOT" stcmd "$@"
}

OUT=binaries/st
mkdir -p "$OUT" tmp/check

if [ ! -f lib/xpad/src/xpad.inc ]; then
	echo "$0: lib/xpad is missing: git submodule update --init" >&2
	exit 1
fi

# FLAGS: extra defines for the port modules (e.g. "-D__USAGE__ -D__DUMP__"
# for the colour tools' data runs); NAME: the program's name.

PORT_FLAGS="${FLAGS:-}"
DEFAULT_NAME=SZ2_ST
if [ "${HEADLESS:-0}" = "1" ]; then
	PORT_FLAGS="$PORT_FLAGS -D__HEADLESS__"
	DEFAULT_NAME=SZ2_HL
fi
if [ "${RELEASE:-0}" = "1" ]; then
	PORT_FLAGS="$PORT_FLAGS -D__RELEASE__"
	DEFAULT_NAME=SZ2_REL
fi
NAME=${NAME:-$DEFAULT_NAME}

st vasmm68k_mot /tmp/sources/sz2.s -quiet -no-opt -Faout -m68000 -D__ST__ -I/tmp/sources -o /tmp/$OUT/sz2_ste.o

MODULES="main machine emulator input audio measure dump display background palette text sprites mem_map"

for module in $MODULES; do
	st vasmm68k_mot /tmp/sources/st/$module.s -quiet -Faout -m68000 -I/tmp/sources/st -I/tmp/lib/xpad/src $PORT_FLAGS -o /tmp/$OUT/$module.o
done

OBJECTS=""
for module in main sz2_ste mem_map machine emulator input audio measure dump display background palette text sprites; do
	OBJECTS="$OBJECTS /tmp/$OUT/$module.o"
done

if [ "$NAME" = "SZ2_ST" ]; then
	st vlink $OBJECTS -bataritos -tos-flags 1 -estart -o /tmp/$OUT/SZ2_DBG.TOS
fi
st vlink $OBJECTS -s -bataritos -tos-flags 1 -estart -o /tmp/$OUT/$NAME.TOS

ls -l "$OUT"/*.TOS

if [ "$CHECK" = "1" ]; then
	# Both versions are assembled from the same path (the ELF object holds
	# the source file's name).

	# The container must see the file just written (Docker's shared folders
	# can lag): a stale copy would compare a version with itself.

	for source in sz2_base sz2; do
		if [ $source = sz2 ]; then
			cp sources/sz2.s tmp/check/sz2.s
		else
			git show "$BASE":sources/sz2.s > tmp/check/sz2.s
		fi
		file=/tmp/tmp/check/sz2.s
		sum=$(md5 -q tmp/check/sz2.s 2>/dev/null || md5sum tmp/check/sz2.s | cut -d' ' -f1)
		for attempt in 1 2 3 4 5 6 7 8 9 10; do
			seen=$(st md5sum $file | cut -d' ' -f1)
			[ "$seen" = "$sum" ] && break
			sleep 1
		done
		if [ "$seen" != "$sum" ]; then
			echo "$0: the container does not see tmp/check/sz2.s as written" >&2
			exit 1
		fi
		st vasmm68k_mot $file -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -I/tmp/sources -o /tmp/tmp/check/${source}_x68k.o
		st vasmm68k_mot $file -quiet -no-opt -Faout -m68030 -D__ATARI__ -I/tmp/sources -o /tmp/tmp/check/${source}_atari.o
		st vasmm68k_mot $file -quiet -no-opt -Fhunk -m68030 -D__AMIGA__ -I/tmp/sources -o /tmp/tmp/check/${source}_amiga.o
	done

	for target in x68k atari amiga; do
		cmp tmp/check/sz2_base_$target.o tmp/check/sz2_$target.o
	done

	echo "sz2.s: the X68000, Falcon and Amiga objects are unchanged."
fi
