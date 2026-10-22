; Constants shared by the Atari ST port's modules.

; The screens: ST low resolution, three buffers (shown, presented, drawn).
; Each is drawn from its origin (screen_buffers), SCREEN_TOP lines into a
; page of PAGE_SIZE bytes (256-aligned) whose start the shifter is given.

SCREEN_LINE=160 ; Bytes per line.
SCREENS=3

	ifd __OVERSCAN__
; Overscan (-D__OVERSCAN__: both borders open, STDL's code, stdl_glue.c):
; pages of OVERSCAN_ROWS lines, row 0 hidden, rows 1-273 shown. The
; picture, the HUD band and the X68000's whole playfield (lines 8-255),
; is drawn SCREEN_TOP lines in, centred; the lines around it stay black.
OVERSCAN_ROWS=274
SCREEN_TOP=9
SCREEN_LINES=256
PAGE_SIZE=(OVERSCAN_ROWS*SCREEN_LINE+255)&~255
	else
SCREEN_TOP=0
SCREEN_LINES=200
PAGE_SIZE=SCREEN_LINES*SCREEN_LINE
	endif
SCREEN_SIZE=SCREEN_LINES*SCREEN_LINE

; The picture: the X68000's 256 pixels, 32 pixels into the line; lines 0-7
; the HUD band, then the playfield (a window of the X68000's lines 8-255,
; or all of them with the borders open).

PICTURE_X_BYTES=16
PLAYFIELD_TOP=8
	ifd __OVERSCAN__
PLAYFIELD_LINES=248
	else
PLAYFIELD_LINES=192
	endif
PLAYFIELD_BOTTOM=PLAYFIELD_TOP+PLAYFIELD_LINES-1

; The measurement clock (measure.s; not in release builds): MFP Timer A,
; or Timer D with the borders open, whose code needs Timer A. Timer D is
; also the serial port's baud rate clock, so COMpad does not work in an
; overscan measurement build.

	ifd __OVERSCAN__
MEASURE_VECTOR=$110
MEASURE_DATA=$fffffa25
MEASURE_PENDING=$fffffa0d ; IPRB.
MEASURE_ENABLE=$fffffa09 ; IERB.
MEASURE_MASK=$fffffa15 ; IMRB.
MEASURE_IN_SERVICE=$fffffa11 ; ISRB.
MEASURE_BIT=4
	else
MEASURE_VECTOR=$134
MEASURE_DATA=$fffffa1f
MEASURE_PENDING=$fffffa0b ; IPRA.
MEASURE_ENABLE=$fffffa07 ; IERA.
MEASURE_MASK=$fffffa13 ; IMRA.
MEASURE_IN_SERVICE=$fffffa0f ; ISRA.
MEASURE_BIT=5
	endif

; The X68000's: sprite patterns, the video controller's priority register
; R1 (in L_00E82000), the CRTC's graphics page scrolls (in L_00E80000).

PCG_PATTERNS=$75e
VC_PRIORITY=$500
CRTC_PAGE0_Y=$1a
CRTC_PAGE1_Y=$22

; Why the game ended (exit_reason).

EXIT_FRAME_LIMIT=1
EXIT_GAME=2
EXIT_EXCEPTION=3
