; Constants shared by the Atari ST port's modules.

; The screens: ST low resolution, three buffers (shown, presented, drawn).

SCREEN_LINE=160 ; Bytes per line.
SCREEN_LINES=200
SCREEN_SIZE=SCREEN_LINES*SCREEN_LINE
SCREENS=3

; The picture: the X68000's 256 pixels, 32 pixels into the line; lines 0-7
; the HUD band, then the playfield.

PICTURE_X_BYTES=16
PLAYFIELD_TOP=8
PLAYFIELD_LINES=192
PLAYFIELD_BOTTOM=PLAYFIELD_TOP+PLAYFIELD_LINES-1

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
