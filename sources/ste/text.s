
; The X68000 text layer on the Atari STE / Mega STE: the game draws 8x8
; characters (DRAW_CHARACTER, its font SZ_TEXT.pcg: 4 planes, X68000
; sprite/text palette block 0) into a 32 x 32 window that never scrolls. The
; port keeps the characters in a 32 x 32 map instead of the X68000's 512 KB
; of text planes:
;
; - Row 0 is the HUD (score, high score): it is drawn at once into the top 8
;   lines of both screens, the HUD band, which the playfield never touches,
;   so it costs nothing per picture.
; - The other rows ("STAGE n", pause, game over, menus) are drawn over every
;   picture, through the playfield window, masked (colour 0 transparent).
;
; Characters are converted on first use into ST bitplane bytes (through the
; colour map, palette_map.i): per line a long of four plane bytes and a mask
; long, written with movep (eight pixels: one byte of each plane).

	xdef st_draw_character
	xdef amiga_clear_text_planes
	xdef amiga_text_row_written
	xdef compile_characters
	xdef draw_text_rows

	xref TEXT_GRAPHICS_ADDRESS
	xref sprite_colour_map
	xref screen_buffers

COLUMNS=32
ROWS=32
CHARACTERS=128
SPACE=$20

SCREEN_LINE=160
PICTURE_X_BYTES=16 ; The picture starts 32 pixels into the line.
PLAYFIELD_TOP=8 ; ST lines: 0-7 the HUD band, 8-199 the playfield.
PLAYFIELD_BOTTOM=199

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; DRAW_CHARACTER (column.l, row.l, code.l), C calling convention: reached by
; a jump at its start (sz2.s), so it returns to the game itself.

st_draw_character:
	movem.l	d0-d3/a0-a2,-(sp)

	move	7*4+4+2(sp),d0 ; Column.
	and		#$7f,d0
	cmp		#COLUMNS,d0
	bcc		.done

	move	7*4+8+2(sp),d1 ; Row.
	and		#$7f,d1
	cmp		#ROWS,d1
	bcc		.done

	move.l	7*4+12(sp),d2 ; Code.
	and		#CHARACTERS-1,d2

	move	d1,d3
	lsl		#5,d3
	add		d0,d3
	lea		character_map,a0
	add		d3,a0

	; Characters per row (empty rows are skipped when drawing).

	lea		row_counts,a1
	cmp.b	#SPACE,(a0)
	beq		.was_space

	subq.b	#1,(a1,d1.w)

.was_space:
	move.b	d2,(a0)
	cmp.b	#SPACE,d2
	beq		.counted

	addq.b	#1,(a1,d1.w)

.counted:

	tst		d1
	bne		.done

	; The HUD: both screens' band, opaque on colour 0.

	bsr		character_lines ; a0 = its lines.
	move.l	screen_buffers,a1
	bsr		.band_character
	move.l	screen_buffers+4,a1
	bsr		.band_character

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

; a0 = character lines, d0 = column, a1 = screen.

.band_character:
	bsr		column_address
	move.l	a0,a2

	rept	8
	move.l	(a2)+,d3 ; Planes.
	addq.l	#4,a2 ; (Mask.)
	movep.l	d3,0(a1)
	lea		SCREEN_LINE(a1),a1
	endr

	rts

; d0 = column, a1 = screen -> a1 = the column's first byte in line 0.
; Uses d1.

column_address:
	move	d0,d1
	lsr		#1,d1
	lsl		#3,d1 ; Group * 8.
	add		#PICTURE_X_BYTES,d1
	btst	#0,d0
	beq		.even

	addq	#1,d1 ; The groups' low bytes: pixels 8-15.

.even:
	add		d1,a1

	rts

; d2 = code -> a0 = its 8 lines (planes long, mask long), converted on first
; use. Uses d3.

character_lines:
	move	d2,d3
	lsl		#6,d3 ; 64 bytes per character.
	lea		character_data,a0
	add		d3,a0

	lea		character_ready,a1
	tst.b	(a1,d2.w)
	bne		.ready

	st		(a1,d2.w)
	bsr		convert_character

.ready:
	rts

; d2 = code, a0 = its lines: from the font (TEXT_GRAPHICS_ADDRESS + (code >> 2)
; * 128 + (0, 16, 1, 17)[code & 3]; the four planes 32 bytes apart, the lines
; 2 apart; plane 0 is colour bit 0).

convert_character:
	movem.l	d0-d7/a0-a3,-(sp)

	move.l	TEXT_GRAPHICS_ADDRESS,a1
	move	d2,d0
	lsr		#2,d0
	lsl		#7,d0
	add		d0,a1
	moveq	#3,d0
	and		d2,d0
	lea		font_offsets(pc),a3
	move.b	(a3,d0.w),d0
	add		d0,a1

	lea		sprite_colour_map,a2 ; Block 0: the text colours.
	move	#8,lines_left

.line_loop:
	move.b	(a1),d0 ; Planes 0-3 of the line.
	move.b	32(a1),d1
	move.b	64(a1),d2
	move.b	96(a1),d3
	addq.l	#2,a1

	moveq	#0,d4 ; ST planes 0-3 in bytes 3-0.
	moveq	#0,d5 ; Opaque pixels.
	moveq	#8-1,d6

.pixel_loop:
	moveq	#0,d7
	add.b	d3,d3
	addx.b	d7,d7
	add.b	d2,d2
	addx.b	d7,d7
	add.b	d1,d1
	addx.b	d7,d7
	add.b	d0,d0
	addx.b	d7,d7 ; X68000 colour.

	lsl.l	#1,d4 ; The next pixel in bit 0 of every byte (8 pixels: no
	add.b	d5,d5 ; bit leaves its byte).

	tst.b	d7
	beq		.next_pixel

	addq.b	#1,d5
	move.b	(a2,d7.w),d7 ; ST colour.
	lsr.b	#1,d7
	bcc		.no_plane_0
	bset	#24,d4
.no_plane_0:
	lsr.b	#1,d7
	bcc		.no_plane_1
	bset	#16,d4
.no_plane_1:
	lsr.b	#1,d7
	bcc		.no_plane_2
	bset	#8,d4
.no_plane_2:
	lsr.b	#1,d7
	bcc		.next_pixel
	bset	#0,d4

.next_pixel:
	dbf		d6,.pixel_loop

	move.l	d4,(a0)+ ; Planes (movep: plane 0 first).
	not.b	d5 ; Mask: 1 = keep the picture.
	move.b	d5,d4
	lsl		#8,d4
	move.b	d5,d4
	move	d4,d5
	swap	d4
	move	d5,d4
	move.l	d4,(a0)+

	subq	#1,lines_left
	bne		.line_loop

	movem.l	(sp)+,d0-d7/a0-a3

	rts

font_offsets:
	dc.b	0,16,1,17

; ------------------------------------------------------------------------------
;
; CLEAR_TEXT_PLANE: an empty map and HUD band. Preserves all registers.

amiga_clear_text_planes:
	movem.l	d0-d7/a0-a1,-(sp)

	lea		character_map,a0
	move.l	#SPACE<<24|SPACE<<16|SPACE<<8|SPACE,d0
	move	#COLUMNS*ROWS/4-1,d1

.clear_map:
	move.l	d0,(a0)+
	dbf		d1,.clear_map

	lea		row_counts,a0
	moveq	#ROWS/4-1,d1

.clear_counts:
	clr.l	(a0)+
	dbf		d1,.clear_counts

	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7

	suba.l	a1,a1

	move.l	screen_buffers,a0
	bsr		.clear_band
	move.l	screen_buffers+4,a0
	bsr		.clear_band

	movem.l	(sp)+,d0-d7/a0-a1

	rts

.clear_band:
	moveq	#SCREEN_LINE*8/32-1,d1

.band_loop:
	movem.l	d0/d2-d7/a1,(a0) ; 8 longs.
	lea		32(a0),a0
	dbf		d1,.band_loop

	rts

; The DRAW_CHARACTER hook of other ports (dead code on the STE).

amiga_text_row_written:
	rts

; SZ_TEXT.pcg (re)loaded: the characters are converted again on first use.

compile_characters:
	movem.l	d0/a0,-(sp)

	lea		character_ready,a0
	moveq	#CHARACTERS/4-1,d0

.clear:
	clr.l	(a0)+
	dbf		d0,.clear

	movem.l	(sp)+,d0/a0

	rts

; ------------------------------------------------------------------------------
;
; a1 = the screen, d0.w = the window offset (playfield ST line = X68000
; line - offset): rows 1-31 of the map, masked, the lines in the playfield.
; Uses d0-d7/a0-a3.

draw_text_rows:
	move	d0,d6 ; Window offset.
	move.l	a1,a3
	lea		character_map+COLUMNS,a2 ; Row 1.
	moveq	#1,d5 ; Row.

.row_loop:
	; ST lines of the row: row * 8 - offset ... + 7.

	move	d5,d7
	lsl		#3,d7
	sub		d6,d7
	cmp		#PLAYFIELD_BOTTOM,d7
	bgt		.done ; Below the playfield (the rows below are too).

	move	d7,d0
	addq	#7,d0
	cmp		#PLAYFIELD_TOP,d0
	blt		.next_row ; Above it.

	lea		row_counts,a0
	tst.b	(a0,d5.w)
	beq		.next_row ; No characters.

	moveq	#0,d4 ; Column.

.column_loop:
	moveq	#0,d2
	move.b	(a2,d4.w),d2
	cmp.b	#SPACE,d2
	beq		.next_column

	movem.l	d4-d7/a2-a3,-(sp)

	bsr		character_lines ; a0 = lines.
	move.l	a3,a1
	move	d4,d0
	bsr		column_address

	; First line's address, and the lines inside the playfield.

	move	d7,d0 ; ST line of character line 0.
	moveq	#0,d1 ; Character lines skipped at the top.
	cmp		#PLAYFIELD_TOP,d0
	bge		.top_ok

	move	#PLAYFIELD_TOP,d1
	sub		d0,d1
	move	#PLAYFIELD_TOP,d0

.top_ok:
	mulu	#SCREEN_LINE,d0
	add.l	d0,a1
	lsl		#3,d1
	add		d1,a0 ; 8 bytes per character line.
	lsr		#3,d1

	moveq	#8,d2
	sub		d1,d2 ; Lines left.
	move	d7,d0
	addq	#7,d0
	sub		#PLAYFIELD_BOTTOM,d0
	ble		.bottom_ok

	sub		d0,d2

.bottom_ok:
	subq	#1,d2
	bmi		.drawn

.line_loop:
	movep.l	0(a1),d0
	move.l	(a0)+,d1 ; Planes.
	and.l	(a0)+,d0 ; Mask.
	or.l	d1,d0
	movep.l	d0,0(a1)
	lea		SCREEN_LINE(a1),a1

	dbf		d2,.line_loop

.drawn:
	movem.l	(sp)+,d4-d7/a2-a3

.next_column:
	addq	#1,d4
	cmp		#COLUMNS,d4
	bne		.column_loop

.next_row:
	lea		COLUMNS(a2),a2
	addq	#1,d5
	cmp		#ROWS,d5
	bne		.row_loop

.done:
	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

character_map: ; Codes, row by row; SPACE = empty.
	dcb.b	COLUMNS*ROWS,SPACE
row_counts: ; Characters other than SPACE per row.
	dcb.b	ROWS,0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

lines_left:
	ds.w	1
character_ready:
	ds.b	CHARACTERS
character_data: ; Per character, 8 lines of planes and mask longs.
	ds.l	CHARACTERS*8*2

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
