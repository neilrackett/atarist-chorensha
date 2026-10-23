
; The X68000 text layer on the Atari ST: the game draws 8x8
; characters (DRAW_CHARACTER, its font SZ_TEXT.pcg: 4 planes, X68000
; sprite/text palette block 0) into a 32 x 32 window that never scrolls. The
; port keeps the characters in a 32 x 32 map instead of the X68000's 512 KB
; of text planes:
;
; - Rows 0-3 are the HUD (score, high score; lives and bombs): drawn over
;   every picture at the top of the screen (the X68000's screen, which the
;   playfield window shows part of), masked (colour 0 transparent). With
;   hud=band row 0 is drawn instead, when the game writes it, into the top 8
;   lines of all three screens, the HUD band, which the playfield never
;   touches: it costs nothing per picture.
; - The other rows ("STAGE n", pause, game over, menus) are drawn over every
;   picture, through the playfield window, masked.
;
; Characters are converted on first use into ST bitplane bytes (through the
; colour map, palette_map.i): per line a long of four plane bytes and a mask
; long, written with movep (eight pixels: one byte of each plane).

	xdef st_draw_character
	xdef amiga_clear_text_planes
	xdef amiga_text_row_written
	xdef amiga_text_character
	xdef amiga_text_cleared
	xdef compile_characters
	xdef draw_text_rows
	xdef character_map

	xref TEXT_GRAPHICS_ADDRESS
	xref sprite_colour_map
	xref screen_buffers
	xref playfield_top
	xref playfield_bottom
	xref hud_band
	xref text_window
	xref text_unpinned

	include "st.i"

COLUMNS=32
ROWS=32
CHARACTERS=128
SPACE=$20
HUD_ROWS=4 ; Rows 0-3: score, lives and bombs (pinned).
BAND_ROWS=1 ; With hud=band: row 0 in the band.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; DRAW_CHARACTER (column.l, row.l, code.l), C calling convention: reached by
; a jump at its start (sz2.s), so it returns to the game itself.

st_draw_character:
	movem.l	d0-d4/a0-a3,-(sp)

	move	9*4+4+2(sp),d0 ; Column.
	and		#$7f,d0
	cmp		#COLUMNS,d0
	bcc		.done

	move	9*4+8+2(sp),d1 ; Row.
	and		#$7f,d1
	cmp		#ROWS,d1
	bcc		.done

	move.l	9*4+12(sp),d2 ; Code.
	and		#CHARACTERS-1,d2

	move	d1,d3
	lsl		#5,d3
	add		d0,d3
	lea		character_map,a3
	add		d3,a3
	cmp.b	(a3),d2
	beq		.done ; Already there (the score's unchanged digits).

	move.b	d2,(a3)

	; The glyph, converted now if new (blank glyphs are not drawn).

	move	d0,d4
	bsr		character_lines ; a0 = its lines.
	move	d4,d0 ; The column.

	; The row's characters with pixels (bit 31 - column), the only ones
	; drawn.

	lea		row_masks,a1
	move	d1,d3
	lsl		#2,d3
	add		d3,a1
	move.l	(a1),d3
	moveq	#31,d4
	sub		d0,d4
	bclr	d4,d3
	lea		character_blank,a2
	tst.b	(a2,d2.w)
	bne		.blank

	bset	d4,d3

.blank:
	move.l	d3,(a1)

	tst		d1
	bne		.done

	tst.b	hud_band
	beq		.done ; Row 0 over the playfield, with the others.

	; The HUD band of every screen, opaque on colour 0.

	lea		column_offsets,a1
	add		d0,d0
	move	(a1,d0.w),d0
	add		#PICTURE_X_BYTES,d0 ; The column's first byte in line 0.
	lea		screen_buffers,a3
	moveq	#SCREENS-1,d4

.screen_loop:
	move.l	(a3)+,a1
	add		d0,a1
	move.l	a0,a2

	rept	8
	move.l	(a2)+,d3 ; Planes.
	addq.l	#4,a2 ; (Mask.)
	movep.l	d3,0(a1)
	lea		SCREEN_LINE(a1),a1
	endr

	dbf		d4,.screen_loop

.done:
	movem.l	(sp)+,d0-d4/a0-a3

	rts

; d2 = code -> a0 = its 8 lines (planes long, mask long), converted on first
; use. Uses d0/a1.

character_lines:
	lea		character_data,a0
	move	d2,d0
	lsl		#6,d0 ; 64 bytes per character.
	add		d0,a0

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

	; Blank: no pixel in any line (its 8 masks all ones).

	moveq	#-1,d0
	moveq	#8-1,d1

.blank_loop:
	and.l	-(a0),d0
	subq.l	#4,a0
	dbf		d1,.blank_loop

	move	2*4+2(sp),d2 ; The saved d2: the code.
	lea		character_blank,a1
	cmp.l	#-1,d0
	seq		(a1,d2.w)

	movem.l	(sp)+,d0-d7/a0-a3

	rts

font_offsets:
	dc.b	0,16,1,17

; ------------------------------------------------------------------------------
;
; The Amiga port's hooks for its "mouse on" message (sz2.s, __CHUNKY__: a
; character drawn, the text planes cleared): the ST has no such message.

amiga_text_character:
amiga_text_cleared:
	rts

; ------------------------------------------------------------------------------
;
; CLEAR_TEXT_PLANE: an empty map (and HUD band); the window and pinned rows
; a screen asked for (display.s, st_name_entry_window) end with its text.
; Preserves all registers.

amiga_clear_text_planes:
	movem.l	d0-d7/a0-a2,-(sp)

	move	#-1,text_window
	sf		text_unpinned

	lea		character_map,a0
	move.l	#SPACE<<24|SPACE<<16|SPACE<<8|SPACE,d0
	move	#COLUMNS*ROWS/4-1,d1

.clear_map:
	move.l	d0,(a0)+
	dbf		d1,.clear_map

	lea		row_masks,a0
	moveq	#ROWS-1,d1

.clear_masks:
	clr.l	(a0)+
	dbf		d1,.clear_masks

	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7

	suba.l	a1,a1

	tst.b	hud_band
	beq		.cleared

	lea		screen_buffers,a2

.screen_loop:
	move.l	(a2)+,a0
	bsr		.clear_band
	cmp.l	#screen_buffers+SCREENS*4,a2
	bne		.screen_loop

.cleared:
	movem.l	(sp)+,d0-d7/a0-a2

	rts

.clear_band:
	moveq	#SCREEN_LINE*8/32-1,d1

.band_loop:
	movem.l	d0/d2-d7/a1,(a0) ; 8 longs.
	lea		32(a0),a0
	dbf		d1,.band_loop

	rts

; The DRAW_CHARACTER hook of other ports (dead code on the ST).

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
; line - offset): the map's rows (but for the HUD band's), masked, the
; lines in the playfield. Uses d0-d7/a0-a4/a6.

; Character line \1 (0-7) at line \1 of a1: planes and mask from (a0)+.

TEXT_LINE macro
	movep.l	\1*SCREEN_LINE(a1),d0
	move.l	(a0)+,d2
	and.l	(a0)+,d0
	or.l	d2,d0
	movep.l	d0,\1*SCREEN_LINE(a1)
	endm

draw_text_rows:
	move	d0,d6 ; Window offset.
	move.l	a1,a3
	lea		character_map,a2
	lea		column_offsets,a6
	moveq	#0,d5 ; Row.
	tst.b	hud_band
	beq		.row_loop

	lea		BAND_ROWS*COLUMNS(a2),a2
	moveq	#BAND_ROWS,d5

.row_loop:
	; ST lines of the row: row * 8 - offset ... + 7; rows 0-3 (the HUD)
	; stay at the top of the screen, as they overlay the X68000's (but
	; for a screen whose rows 1-3 are not the HUD's: text_unpinned).

	move	d5,d7
	lsl		#3,d7
	cmp		#HUD_ROWS,d5
	bcc		.not_pinned

	tst.b	text_unpinned
	beq		.pinned

.not_pinned:
	sub		d6,d7
	cmp		playfield_bottom,d7
	bgt		.done ; Below the playfield (the rows below are too).

.pinned:
	move	d7,d0
	addq	#7,d0
	cmp		playfield_top,d0
	blt		.next_row ; Above it.

	move	d5,d0
	lsl		#2,d0
	lea		row_masks,a0
	tst.l	(a0,d0.w)
	beq		.next_row ; No characters.

	; The lines inside the playfield: d3 = character lines skipped at the
	; top (* 8: bytes), d4 = lines drawn - 1, a4 = the first one's address.

	moveq	#0,d3
	move	d7,d0
	cmp		playfield_top,d0
	bge		.top_ok

	move	playfield_top,d3
	sub		d0,d3
	move	playfield_top,d0

.top_ok:
	moveq	#8-1,d4
	sub		d3,d4
	move	d7,d1
	addq	#7,d1
	sub		playfield_bottom,d1
	ble		.bottom_ok

	sub		d1,d4

.bottom_ok:
	mulu	#SCREEN_LINE,d0
	lea		PICTURE_X_BYTES(a3,d0.l),a4
	lsl		#3,d3

	move	d5,d0
	lsl		#2,d0
	lea		row_masks,a0
	move.l	(a0,d0.w),d7 ; Columns to draw (bit 31: column 0).
	moveq	#-1,d1 ; Column.

.next_column:
	tst.l	d7
	beq		.next_row

	addq	#1,d1
	add.l	d7,d7
	bcc		.next_column

	moveq	#0,d2
	move.b	(a2,d1.w),d2
	bsr		character_lines
	add		d3,a0
	move	d1,d0
	add		d0,d0
	move	(a6,d0.w),d0
	lea		(a4,d0.w),a1

	cmp		#8-1,d4
	bne		.clipped

	TEXT_LINE 0
	TEXT_LINE 1
	TEXT_LINE 2
	TEXT_LINE 3
	TEXT_LINE 4
	TEXT_LINE 5
	TEXT_LINE 6
	TEXT_LINE 7

	bra		.next_column

.clipped:
	move	d4,lines_left

.line_loop:
	TEXT_LINE 0
	lea		SCREEN_LINE(a1),a1

	subq	#1,lines_left
	bpl		.line_loop

	bra		.next_column

.next_row:
	lea		COLUMNS(a2),a2
	addq	#1,d5
	cmp		#ROWS,d5
	bne		.row_loop

.done:
	rts

column_offsets: ; Per column: the byte of its 8 pixels in the line.
COLUMN set 0
	rept	COLUMNS
	dc.w	(COLUMN>>1)*8+(COLUMN&1)
COLUMN set COLUMN+1
	endr

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

character_map: ; Codes, row by row; SPACE = empty.
	dcb.b	COLUMNS*ROWS,SPACE
row_masks: ; Per row, its characters with pixels (bit 31 - column).
	dcb.l	ROWS,0
character_blank: ; Per code: no pixels (SPACE until converted).
	dcb.b	SPACE,0
	dc.b	-1
	dcb.b	CHARACTERS-SPACE-1,0

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
