; Constants shared by the Atari ST port's modules.

; The screens: ST low resolution, three buffers (shown, presented, drawn).
; Each is drawn from its origin (screen_buffers), screen_top_offset bytes
; into a page of page_size bytes (256-aligned) whose start the shifter is
; given (display.s, from the layout chosen at start: SZ2.CFG's screen).

SCREEN_LINE=160 ; Bytes per line.
SCREENS=3

; Crop: the 200-line screen, a window of the playfield that follows the
; ship.

CROP_SCREEN_LINES=200
CROP_PAGE_SIZE=CROP_SCREEN_LINES*SCREEN_LINE ; (256-aligned.)

; Full height: both borders open (STDL's code, stdl_glue.c), pages of
; FULL_ROWS lines, row 0 hidden, rows 1-273 shown. The picture, the
; X68000's 256 lines, is drawn FULL_SCREEN_TOP lines in, centred; the lines
; around it stay black.

FULL_ROWS=274
FULL_SCREEN_TOP=9
FULL_PAGE_SIZE=(FULL_ROWS*SCREEN_LINE+255)&~255
FULL_SCREEN_LINES=256

; The picture: the X68000's 256 pixels, 32 pixels into the line; its line
; s shows the X68000's line s + the window offset (0 at full height). The
; score (the text layer's row 0) is drawn over the playfield, as on the
; X68000, or with hud=band (SZ2.CFG) into a band of its own, lines 0-7,
; the playfield below it (playfield_top, playfield_lines, playfield_bottom).

PICTURE_X_BYTES=16
HUD_BAND_LINES=8

; The measurement clock (measure.s; not in release builds): MFP Timer A,
; or Timer D at full height, whose border code needs Timer A (machine.s
; chooses). Timer D is also the serial port's baud rate clock, so COMpad
; does not work in a measurement build at full height.

TIMER_A_VECTOR=$134
TIMER_D_VECTOR=$110

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
