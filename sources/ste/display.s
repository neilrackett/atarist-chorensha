
; Atari STE / Mega STE display: ST low resolution (320 x 200, 16 colours),
; double-buffered; the renderer's 256-pixel-wide chunky picture is converted
; into the bitplanes (C2P) 32 pixels from the left edge.
;
; Height: the X68000 picture has 256 lines and the screen 200. The line
; table picks the 200 source lines: by default 56 evenly spread lines are
; left out (squash: the whole playfield stays visible), or (F2) the middle
; 200 lines are shown (crop). The renderer composes only the lines used.
;
; Colour: 16 levels of grey (the STE's 4-bit DAC). Each of the renderer's
; 256 palette slots maps to the grey of its colour's luminance; the C2P
; table holds, per slot and pixel position, the slot's grey as movep-format
; plane bits. Only the slots the renderer reports as changed are converted
; again, so palette fades and colour cycling show as on the X68000.
;
; C2P: for each 8 pixels, eight table lookups ORed into one long, written
; to the four planes' bytes with movep.l (the high bytes of a 16-pixel
; group's plane words for its left 8 pixels, the low bytes for the right 8).

	xdef initialize_display
	xdef present_frame
	xdef display_vbl
	xdef display_screen_address
	xdef st_palette
	xdef render_line_needed
	xdef crop_mode
	xdef display_mode_changed
	xdef write_screenshot

	xref render_buffer
	xref hardware_palette
	xref palette_load_table
	xref palette_changed
	xref divide_unsigned

GUARD=16
RENDER_WIDTH=256
RENDER_HEIGHT=256
RENDER_STRIDE=GUARD+RENDER_WIDTH+GUARD

SCREEN_LINES=200
SCREEN_LINE=160
SCREEN_SIZE=SCREEN_LINES*SCREEN_LINE
PICTURE_X_BYTES=16 ; 32 pixels: two 16-pixel groups.
CROP_TOP=(RENDER_HEIGHT-SCREEN_LINES)/2

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

initialize_display:
	movem.l	d0-d1/a0,-(sp)

	move.l	#screen_memory+255,d0 ; 256-byte aligned.
	clr.b	d0
	move.l	d0,display_screen_address
	add.l	#SCREEN_SIZE,d0
	move.l	d0,work_screen_address

	bsr		build_line_table

	movem.l	(sp)+,d0-d1/a0

	rts

; ------------------------------------------------------------------------------
;
; VBL: a finished picture is shown from the next frame on (the shifter takes
; the new address at the start of a frame); the buffer it replaces is free
; once that frame has begun, one VBL later. Preserves all registers.

display_vbl:
	tst.b	flip_pending
	beq		.done

	cmp.b	#2,flip_pending
	bne		.shown

	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w
	move.b	display_screen_address+3,$ffff820d.w

.shown:
	subq.b	#1,flip_pending

.done:
	rts

; ------------------------------------------------------------------------------
;
; Converts render_buffer into the hidden screen and shows it at the next VBL.

present_frame:
	movem.l	d0-d7/a0-a6,-(sp)

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
	tst.b	display_mode_changed
	beq		.mode_ok

	sf		display_mode_changed
	bsr		build_line_table

.mode_ok:
	tst.b	palette_changed
	beq		.palette_ok

	sf		palette_changed
	bsr		update_c2p_table

.palette_ok:
	bsr		chunky_to_planar

	move.l	work_screen_address,d0
	move.l	display_screen_address,work_screen_address
	move.l	d0,display_screen_address
	move.b	#2,flip_pending

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; The source line of every screen line (as addresses of its first picture
; pixel in render_buffer) and the lines the renderer has to compose.

build_line_table:
	movem.l	d0-d3/a0-a1,-(sp)

	lea		render_line_needed,a0
	moveq	#RENDER_HEIGHT/4-1,d0

.clear_needed:
	clr.l	(a0)+
	dbf		d0,.clear_needed

	lea		line_table,a0
	lea		render_line_needed,a1
	moveq	#0,d1 ; Screen line.

.line_loop:
	tst.b	crop_mode
	beq		.squash

	move	d1,d2
	add		#CROP_TOP,d2

	bra		.source_line

.squash:
	move	d1,d2 ; Source line = screen line * 256 / 200.
	mulu	#RENDER_HEIGHT,d2
	divu	#SCREEN_LINES,d2

.source_line:
	st		(a1,d2.w)

	add		#GUARD,d2
	mulu	#RENDER_STRIDE,d2
	add.l	#render_buffer+GUARD,d2
	move.l	d2,(a0)+

	addq	#1,d1
	cmp		#SCREEN_LINES,d1
	bne		.line_loop

	movem.l	(sp)+,d0-d3/a0-a1

	rts

; ------------------------------------------------------------------------------
;
; C2P table entries of the slots the renderer has changed: all 256 after a
; full palette rebuild (palette_load_table = hardware_palette), else the
; one-colour ranges of palette_update_table (count << 16 | slot, R, G, B
; longs, ended by 0).

update_c2p_table:
	move.l	palette_load_table,a0
	cmp.l	#hardware_palette,a0
	bne		.ranges

	lea		hardware_palette+4,a0
	moveq	#0,d7 ; Slot.

.all_loop:
	bsr		set_slot_grey
	lea		12(a0),a0

	addq	#1,d7
	cmp		#256,d7
	bne		.all_loop

	rts

.ranges:
	move.l	(a0)+,d7
	beq		.done

	and		#$ff,d7 ; Slot (one colour each).
	bsr		set_slot_grey
	lea		12(a0),a0

	bra		.ranges

.done:
	rts

; d7.w = slot, a0 = its R, G, B longs (8-bit value in the top byte): the
; slot's grey (luminance 0.30 R + 0.59 G + 0.11 B, 16 levels) as the eight
; movep-format longs of its C2P table entry. Preserves a0 and d7.

set_slot_grey:
	moveq	#0,d0
	move.b	(a0),d0
	mulu	#77,d0
	moveq	#0,d1
	move.b	4(a0),d1
	mulu	#151,d1
	add.l	d1,d0
	moveq	#0,d1
	move.b	8(a0),d1
	mulu	#28,d1
	add.l	d1,d0
	lsr.l	#8,d0 ; 0-255.
	lsr		#4,d0 ; 0-15: the grey's colour index.

	; Plane bits of the grey: plane 0 in the top byte (movep.l writes it
	; first, to plane 0's word), plane 3 in the bottom byte.

	moveq	#0,d1
	btst	#0,d0
	beq		.no_plane_0

	move.l	#$80000000,d1

.no_plane_0:
	btst	#1,d0
	beq		.no_plane_1

	or.l	#$00800000,d1

.no_plane_1:
	btst	#2,d0
	beq		.no_plane_2

	or.l	#$00008000,d1

.no_plane_2:
	btst	#3,d0
	beq		.no_plane_3

	or.l	#$00000080,d1

.no_plane_3:
	lea		c2p_table,a1
	move	d7,d0
	lsl		#5,d0
	add		d0,a1
	moveq	#8-1,d0

.position_loop:
	move.l	d1,(a1)+
	lsr.l	#1,d1 ; The next pixel to the right (bits stay in their bytes).

	dbf		d0,.position_loop

	rts

; ------------------------------------------------------------------------------
;
; render_buffer -> the hidden screen.

C2P_PIXEL macro ; \1 = pixel position (0-7) in the group of eight.
	moveq	#0,d0
	move.b	(a0)+,d0
	lsl		#5,d0
	ifeq	\1
	move.l	(a2,d0.w),d1
	else
	or.l	\1*4(a2,d0.w),d1
	endif
	endm

C2P_EIGHT macro ; \1 = 0 (left 8 pixels) or 1 (right 8 pixels).
	C2P_PIXEL 0
	C2P_PIXEL 1
	C2P_PIXEL 2
	C2P_PIXEL 3
	C2P_PIXEL 4
	C2P_PIXEL 5
	C2P_PIXEL 6
	C2P_PIXEL 7
	movep.l	d1,\1(a1)
	endm

chunky_to_planar:
	move.l	work_screen_address,a1
	lea		PICTURE_X_BYTES(a1),a1
	lea		line_table,a3
	lea		c2p_table,a2
	move	#SCREEN_LINES-1,d7

.line_loop:
	move.l	(a3)+,a0
	moveq	#RENDER_WIDTH/16-1,d6

.group_loop:
	C2P_EIGHT 0
	C2P_EIGHT 1
	addq.l	#8,a1

	dbf		d6,.group_loop

	lea		SCREEN_LINE-RENDER_WIDTH/2(a1),a1

	dbf		d7,.line_loop

	rts

; ------------------------------------------------------------------------------
;
; Measurement runs: d0.l = frame; the picture just converted (the screen
; about to be shown) as a Degas file, Snnnnnn.PI1 (tests/ste/pi1_png.py
; converts it). GEMDOS, from the game's frame wait.

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

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

screenshot_name:
	dc.b	'S0000000.PI1',0

	even

screenshot_header: ; Degas: low resolution, then st_palette.
	dc.w	0

; 16 greys, colour n = level n. The STE's 4-bit components hold the low bit
; in bit 3: (n >> 1) | (n & 1) << 3.

st_palette:
	dc.w	$000,$888,$111,$999,$222,$aaa,$333,$bbb
	dc.w	$444,$ccc,$555,$ddd,$666,$eee,$777,$fff

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

display_screen_address: ; Shown (or about to be).
	ds.l	1
work_screen_address: ; Hidden: the next picture is drawn here.
	ds.l	1

line_table:
	ds.l	SCREEN_LINES

c2p_table: ; Per slot: 8 longs (pixel positions 0-7).
	ds.l	256*8

render_line_needed:
	ds.b	RENDER_HEIGHT

flip_pending: ; 2: a new picture to show at the next VBL, 1: shown next frame.
	ds.b	1
crop_mode:
	ds.b	1
display_mode_changed:
	ds.b	1

	even

screen_memory:
	ds.b	SCREEN_SIZE*2+256

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
