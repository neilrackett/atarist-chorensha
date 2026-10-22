#!/bin/bash
#
# Runs a build on a real ST through md-devops (a SidecarTridge Multi-device
# with the DevOps microfirmware, in its GEMDRIVE Runner mode, DEVOPS.ACC
# loaded): the program is copied from md-devops' drive to the ST's own
# disk and started there, so the ST's own hard disk driver loads it, as
# from the desktop. The ST's text comes back on md-devops' debug stream
# with a STREAM=1 build (build_st.sh), and the launcher's results with
# any build (tests/st/hw/launch.s).
#
#   tests/st/hw/run_on_st.sh binaries/st/SZ2_STS.TOS
#   FRAMES=3000 SCREEN=full tests/st/hw/run_on_st.sh binaries/st/SZ2_STS.TOS
#
# SIDECART   md-devops' address (default http://sidecart.local)
# DIR        the folder on the ST that holds the game's data (default
#            C:\GAMES\CHORENSH)
# MD_DRIVE   md-devops' drive letter on the ST (default D)
# FRAMES     a frame limit: the game exits after that many frames
# SCREEN     crop or full: the screen layout
#            (With either, the run's settings go in SZ2TEST.CFG beside the
#            program, named on its command line and deleted afterwards: the
#            ST's own SZ2.CFG is left alone. Without, the program reads it.)
# TIMEOUT    seconds to wait for the program's exit (default 600)
#
# The stream goes to tmp/out/st_<program>.log. A program that never exits
# (it hung, or waits for a key) leaves the ST to be reset by hand: the
# Runner cannot reach a program that owns the interrupts.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

PROG=$1
if [ ! -f "$PROG" ]; then
	echo "usage: $0 binaries/st/PROGRAM.TOS" >&2
	exit 1
fi

H=${SIDECART:-http://sidecart.local}
DIR=${DIR:-'C:\GAMES\CHORENSH'}
MD_DRIVE=${MD_DRIVE:-D}
TIMEOUT=${TIMEOUT:-600}
NAME=$(basename "$PROG")
LOG=tmp/out/st_${NAME%.*}.log
mkdir -p tmp/out

if [ ! -f binaries/st/LAUNCH.TOS ] || [ tests/st/hw/launch.s -nt binaries/st/LAUNCH.TOS ]; then
	STCMD_NO_TTY=1 STCMD_QUIET=1 ST_WORKING_FOLDER="$ROOT" stcmd vasmm68k_mot \
		/tmp/tests/st/hw/launch.s -quiet -Ftos -m68000 -o /tmp/binaries/st/LAUNCH.TOS || exit 1
fi

status=$(curl -s -m 5 "$H/api/v1/runner")
case "$status" in
	*'"accessory":true'*'"busy":false'*) ;;
	*)
		echo "md-devops at $H is not ready (DEVOPS.ACC loaded and idle): $status" >&2
		exit 1
		;;
esac

upload() {
	curl -s -f --upload-file "$1" "$H/api/v1/gemdrive/files/$2?overwrite=1" > /dev/null || {
		echo "upload of $1 failed" >&2
		exit 1
	}
}

curl -s -X POST "$H/api/v1/gemdrive/folders/CRS" > /dev/null
upload binaries/st/LAUNCH.TOS LAUNCH.TOS
upload "$PROG" "CRS/$NAME"

# The launcher's commands, in a file (past the command line's 127
# characters).

SETTINGS=""
if [ -n "${FRAMES:-}" ] || [ -n "${SCREEN:-}" ]; then
	SETTINGS=SZ2TEST.CFG
	{
		[ -n "${FRAMES:-}" ] && printf 'frames=%s\r\n' "$FRAMES"
		[ -n "${SCREEN:-}" ] && printf 'screen=%s\r\n' "$SCREEN"
	} > tmp/out/$SETTINGS
	upload tmp/out/$SETTINGS CRS/$SETTINGS
fi
{
	printf '%s\r\n' "copy $MD_DRIVE:\\CRS\\$NAME $DIR\\$NAME"
	[ -n "$SETTINGS" ] && printf '%s\r\n' "copy $MD_DRIVE:\\CRS\\$SETTINGS $DIR\\$SETTINGS"
	printf '%s\r\n' "run $DIR\\$NAME $SETTINGS"
	[ -n "$SETTINGS" ] && printf '%s\r\n' "del $DIR\\$SETTINGS"
} > tmp/out/RUN.TXT
upload tmp/out/RUN.TXT CRS/RUN.TXT

curl -s --no-buffer "$H/api/v1/debug/log" > "$LOG" &
stream=$!
trap 'kill $stream 2> /dev/null' EXIT
sleep 1

body="{\"path\":\"/LAUNCH.TOS\",\"cmdline\":\"@$MD_DRIVE:\\\\CRS\\\\RUN.TXT\"}"
reply=$(curl -s -m 10 -X POST -H 'Content-Type: application/json' -d "$body" "$H/api/v1/runner/run")
case "$reply" in
	*'"accepted":true'*) ;;
	*)
		echo "md-devops did not start the launcher: $reply" >&2
		exit 1
		;;
esac

started=$SECONDS
while [ $((SECONDS - started)) -lt "$TIMEOUT" ]; do
	sleep 2
	case "$(curl -s -m 3 "$H/api/v1/runner")" in
		*'"busy":false'*) break ;;
	esac
done

# The stream can lag behind the Runner: up to 10 s for the launcher's end.

for i in 1 2 3 4 5 6 7 8 9 10; do
	grep -q -a '^\[EXIT' "$LOG" && break
	sleep 1
done

tr -d '\r' < "$LOG"
case "$(curl -s -m 3 "$H/api/v1/runner")" in
	*'"busy":false'*) ;;
	*)
		echo "$NAME has not exited after $TIMEOUT s: the ST needs a reset." >&2
		exit 1
		;;
esac
