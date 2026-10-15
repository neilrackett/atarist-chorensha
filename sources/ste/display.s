
; Atari STE / Mega STE display: ST low resolution (320 x 200, 16 colours),
; double-buffered, drawn in bitplanes:
;
;   lines 0-7     the HUD band: the X68000 text layer's row 0 (score, high
;                 score), drawn into both screens by text.s when the game
;                 writes it, never touched here;
;   lines 8-199   the playfield: 192 of the X68000's 256 lines, 1:1, 32
;                 pixels from the left edge. The window follows the ship in
;                 a stage (the ship two thirds down; at most 2 lines per
;                 frame), elsewhere it shows lines 32-223; F2 keeps it there.
;
; A picture: the background (background.s: a copy from the composed table)
; or colour 0 while the game hides it; sprites and the text layer's other
; rows in the order of the X68000's priority register R1; the borders where
; sprites reached into them cleared; the 16 colours (palette.s). The VBL
; shows it: the screen address at the next VBL (the shifter takes it a frame
; later), the colours one VBL after that, together with the new screen.

	xdef initialize_display
	xdef render_frame
	xdef present_frame
	xdef display_vbl
	xdef display_screen_address
	xdef screen_buffers
	xdef st_palette
	xdef write_screenshot
	xdef crop_mode
	xdef display_mode_changed

	xref L_00E82000
	xref WORD_00098864
	xref background_visible
	xref copy_background
	xref draw_sprites
	xref margin_top
	xref margin_bottom
	xref draw_text_rows
	xref make_hardware_palette
	xref in_stage
	xref frame_count
	xref divide_unsigned
	xref start_render_parts
	xref mark_render_part

	ifd __ORACLE__
	xref L_00E80000
	xref character_map
	xref sprite_list
	xref render_sprite_count
	endif

SCREEN_LINES=200
SCREEN_LINE=160
SCREEN_SIZE=SCREEN_LINES*SCREEN_LINE
PICTURE_X_BYTES=16
PLAYFIELD_TOP=8
PLAYFIELD_LINES=192
MAXIMUM_WINDOW=256-8-PLAYFIELD_LINES ; 56: the window shows X68000 lines 8+w..199+w.
DEFAULT_WINDOW=24 ; Lines 32-223.
SHIP_LINE=130 ; The ship's line in the playfield window.
WINDOW_STEP=2 ; Lines per frame.

VC_PRIORITY=$500

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

initialize_display:
	movem.l	d0-d1/a0,-(sp)

	move.l	#screen_memory+255,d0 ; 256-byte aligned.
	clr.b	d0
	move.l	d0,display_screen_address
	move.l	d0,screen_buffers
	add.l	#SCREEN_SIZE,d0
	move.l	d0,work_screen_address
	move.l	d0,screen_buffers+4

	move	#DEFAULT_WINDOW,window_offset

	movem.l	(sp)+,d0-d1/a0

	rts

; ------------------------------------------------------------------------------
;
; VBL: a presented picture's screen address now (the shifter takes it at the
; end of the next frame), its colours a VBL later, with it. The buffer it
; replaces is free after that. Preserves all registers.

display_vbl:
	tst.b	flip_pending
	beq		.done

	cmp.b	#2,flip_pending
	bne		.colours

	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w
	move.b	display_screen_address+3,$ffff820d.w

	bra		.flipped

.colours:
	movem.l	d0-d7,-(sp)
	movem.l	flip_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w
	movem.l	(sp)+,d0-d7

.flipped:
	subq.b	#1,flip_pending

.done:
	rts

; ------------------------------------------------------------------------------
;
; Draws the current X68000 screen into the hidden screen.

render_frame:
	movem.l	d0-d7/a0-a6,-(sp)

	ifnd __RELEASE__
	jsr		start_render_parts
	endif

	bsr		update_window

	; Background, or colour 0.

	move.l	work_screen_address,a1
	tst.b	background_visible
	beq		.no_background

	lea		PLAYFIELD_TOP*SCREEN_LINE+PICTURE_X_BYTES(a1),a1
	move	window_offset,d0
	addq	#PLAYFIELD_TOP,d0 ; The playfield's first X68000 line.
	jsr		copy_background

	bra		.layers

.no_background:
	bsr		clear_playfield

.layers:
	ifnd __RELEASE__
	moveq	#0,d0 ; Background.
	jsr		mark_render_part
	endif

	; R1 bits 13-12 = sprite priority, 11-10 = text priority (0 = front).

	move	L_00E82000+VC_PRIORITY,d0
	move	d0,d1
	lsr		#8,d0
	lsr		#4,d0
	and		#3,d0 ; Sprites.
	lsr		#8,d1
	lsr		#2,d1
	and		#3,d1 ; Text.
	cmp		d1,d0
	bhi		.text_in_front

	bsr		.text
	bsr		.sprites

	bra		.borders

.text_in_front:
	bsr		.sprites
	bsr		.text

.borders:
	bsr		clear_margins

	lea		picture_palette,a0
	jsr		make_hardware_palette

	ifnd __RELEASE__
	moveq	#3,d0 ; Borders and colours.
	jsr		mark_render_part
	endif

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.sprites:
	move.l	work_screen_address,a1
	move	window_offset,d0
	ifd __RELEASE__
	jmp		draw_sprites
	else
	jsr		draw_sprites
	moveq	#1,d0 ; Sprites.
	jmp		mark_render_part
	endif

.text:
	move.l	work_screen_address,a1
	move	window_offset,d0
	ifd __RELEASE__
	jmp		draw_text_rows
	else
	jsr		draw_text_rows
	moveq	#2,d0 ; Text.
	jmp		mark_render_part
	endif

; The window: in a stage, toward the ship (two thirds down the playfield),
; else (or with F2) the default.

update_window:
	move	#DEFAULT_WINDOW,d0
	tst.b	crop_mode
	bne		.target

	tst.b	in_stage
	beq		.target

	move	WORD_00098864+2,d0 ; Ship y, 1/64 pixel, sprite coordinates.
	asr		#6,d0
	sub		#16+PLAYFIELD_TOP+SHIP_LINE,d0
	bpl		.not_above

	moveq	#0,d0

.not_above:
	cmp		#MAXIMUM_WINDOW,d0
	ble		.target

	moveq	#MAXIMUM_WINDOW,d0

.target:
	; At most WINDOW_STEP lines per frame since the last picture.

	move.l	frame_count,d1
	sub.l	window_frame,d1
	move.l	frame_count,window_frame
	cmp.l	#MAXIMUM_WINDOW,d1
	bls		.frames_ok

	moveq	#MAXIMUM_WINDOW,d1

.frames_ok:
	add		d1,d1 ; WINDOW_STEP
	bne		.step_ok

	moveq	#WINDOW_STEP,d1

.step_ok:
	sub		window_offset,d0 ; Distance.
	cmp		d1,d0
	ble		.not_too_low

	move	d1,d0

.not_too_low:
	neg		d1
	cmp		d1,d0
	bge		.not_too_high

	move	d1,d0

.not_too_high:
	add		d0,window_offset

	rts

; The playfield in colour 0 (no background).

clear_playfield:
	move.l	work_screen_address,a0
	lea		(PLAYFIELD_TOP+PLAYFIELD_LINES)*SCREEN_LINE(a0),a0
	bsr		zero_registers
	move	#PLAYFIELD_LINES*SCREEN_LINE/40-1,d7

.loop:
	movem.l	d0-d6/a1-a3,-(a0) ; 10 longs.
	dbf		d7,.loop

	rts

; The borders (16 bytes either side) of the lines sprites reached.

clear_margins:
	move	margin_top,d6
	move	margin_bottom,d7
	sub		d6,d7
	bmi		.done

	move.l	work_screen_address,a0
	mulu	#SCREEN_LINE,d6
	add.l	d6,a0
	bsr		zero_registers

.loop:
	movem.l	d0-d3,(a0)
	movem.l	d0-d3,SCREEN_LINE-PICTURE_X_BYTES(a0)
	lea		SCREEN_LINE(a0),a0

	dbf		d7,.loop

.done:
	rts

zero_registers:
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	move.l	d0,a1
	move.l	d0,a2
	move.l	d0,a3

	rts

; ------------------------------------------------------------------------------
;
; Shows the picture drawn by render_frame.

present_frame:
	movem.l	d0-d7/a0,-(sp)

	; The previous picture must be on screen: its buffer becomes the hidden
	; one only then.

.wait_flip:
	tst.b	flip_pending
	beq		.flip_done

	move	sr,-(sp)
	stop	#$2300
	move	(sp)+,sr

	bra		.wait_flip

.flip_done:
	movem.l	picture_palette,d0-d7
	movem.l	d0-d7,flip_palette

	move.l	work_screen_address,d0
	move.l	display_screen_address,work_screen_address
	move.l	d0,display_screen_address
	move.b	#2,flip_pending

	movem.l	(sp)+,d0-d7/a0

	rts

; ------------------------------------------------------------------------------
;
; Measurement runs: d0.l = frame; the picture just presented as a Degas
; file, Snnnnnnn.PI1, with its colours (tests/ste/pi1_png.py converts it).
; GEMDOS, from the game's frame wait.

write_screenshot:
	movem.l	d0-d3/a0-a2,-(sp)

	lea		screenshot_name+8,a0 ; 'S', seven digits, '.PI1'.
	moveq	#7-1,d3

.digit_loop:
	moveq	#10,d1
	jsr		divide_unsigned
	add.b	#'0',d1
	move.b	d1,-(a0)
	dbf		d3,.digit_loop

	clr		-(sp)
	pea		screenshot_name
	move	#60,-(sp) ; Fcreate
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.done

	move	d0,d3

	pea		screenshot_header
	move.l	#2+16*2,-(sp) ; Resolution, palette.
	move	d3,-(sp)
	move	#64,-(sp) ; Fwrite
	trap	#1
	lea		12(sp),sp

	move.l	display_screen_address,-(sp)
	move.l	#SCREEN_SIZE,-(sp)
	move	d3,-(sp)
	move	#64,-(sp)
	trap	#1
	lea		12(sp),sp

	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	ifd __ORACLE__
	bsr		write_frame_dump
	endif

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

	ifd __ORACLE__

; Oracle builds (lockstep runs): with each screenshot, Fnnnnnnn.BIN, what
; the picture was drawn from, for tools/ste/refrender.py: 'CRSF', the
; window offset (word), background shown (byte), padding (byte), the pages'
; scroll Y0, Y1 and R1 (words), the sprites (word), the video controller
; shadow ($400 bytes), the text layer's character map (32 x 32 bytes), the
; sprite list (8 bytes each).

write_frame_dump:
	lea		screenshot_name,a0
	move.b	#'F',(a0)
	move.b	#'B',9(a0)
	move.b	#'I',10(a0)
	move.b	#'N',11(a0)

	lea		frame_header,a1
	move.l	#'CRSF',(a1)+
	move	window_offset,(a1)+
	move.b	background_visible,(a1)+
	clr.b	(a1)+
	move	L_00E80000+$1a,(a1)+
	move	L_00E80000+$22,(a1)+
	move	L_00E82000+VC_PRIORITY,(a1)+
	move	render_sprite_count,(a1)+

	clr		-(sp)
	pea		screenshot_name
	move	#60,-(sp) ; Fcreate
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.restore

	move	d0,d3

	lea		frame_header,a0
	moveq	#16,d1
	bsr		.write
	lea		L_00E82000,a0
	move.l	#$400,d1
	bsr		.write
	lea		character_map,a0
	move.l	#32*32,d1
	bsr		.write
	move.l	sprite_list,a0
	moveq	#0,d1
	move	render_sprite_count,d1
	lsl.l	#3,d1
	bsr		.write

	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

.restore:
	lea		screenshot_name,a0
	move.b	#'S',(a0)
	move.b	#'P',9(a0)
	move.b	#'I',10(a0)
	move.b	#'1',11(a0)

	rts

.write:
	pea		(a0)
	move.l	d1,-(sp)
	move	d3,-(sp)
	move	#64,-(sp) ; Fwrite
	trap	#1
	lea		12(sp),sp

	rts

	endif

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

screenshot_name:
	dc.b	'S0000000.PI1',0

	even

screenshot_header: ; Degas: low resolution, then the picture's colours.
	dc.w	0
flip_palette: ; The presented picture's colours.
	dcb.w	16,0

st_palette: ; At the take-over: all black.
	dcb.w	16,0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

display_screen_address: ; Shown (or about to be).
	ds.l	1
work_screen_address: ; Hidden: the next picture is drawn here.
	ds.l	1
screen_buffers: ; Both screens (the HUD band is drawn into both).
	ds.l	2
window_frame:
	ds.l	1
picture_palette: ; The colours of the picture being drawn.
	ds.w	16
window_offset:
	ds.w	1

	ifd __ORACLE__
frame_header:
	ds.b	16
	endif

flip_pending: ; 2: a new picture to show at the next VBL, 1: its colours next.
	ds.b	1
crop_mode: ; F2: the window does not follow the ship.
	ds.b	1
display_mode_changed:
	ds.b	1

	even

screen_memory:
	ds.b	SCREEN_SIZE*2+256

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
