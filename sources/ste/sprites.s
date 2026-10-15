
; Sprites on the Atari STE / Mega STE, in bitplanes.
;
; The game's sprites are 16 x 16 X68000 patterns (4 bits per pixel, 16
; palettes, flips), up to 512 per frame in its sprite list. A variant is a
; (pattern, palette, horizontal flip); a vertical flip only draws the rows in
; reverse order. For each variant used, a master in ST colours (palette_map.i)
; is made on first use: 16 rows of a mask word (1 = transparent) and four
; plane words. For each horizontal position within a 16-pixel group (shift)
; it is drawn at, a shifted copy is made on first use from the master: per
; row two groups of a mask long and two plane longs, the planes already 0
; where transparent, so drawing is
;
;     movem.l (a0)+,d0-d5      ; mask, planes 0-1, planes 2-3 of each group
;     and.l d0,(a1) / or.l d1,(a1) / and.l d0,4(a1) / or.l d2,4(a1)
;     ... the same for the second group at 8(a1)
;
; (262 cycles per row; empty rows at the top and bottom are left out). When
; the shifted pixels all fall into one of the two groups (narrow shapes:
; bullets, particles), only that group is kept and drawn (142 cycles). The
; masters and shifted copies live in an arena (the memory left free: about
; 900 KB with 4 MB), found through a table per pattern of its 32 variants.
; The arena is used in two halves: when the active half is full, the other
; one is emptied (everything kept there forgotten) and used, so what was
; made most recently stays.
;
; Order: the X68000's priority (the attribute's low 6 bits; larger is in
; front, $00-$0F not shown), in 64 buckets drawn upwards; within a bucket the
; later list entry is behind (as the Falcon and Amiga ports draw them).
;
; Sprites are drawn at ST x = X68000 x + 16 (the picture starts at 32; the
; sprite coordinates carry a 16-pixel offset), always inside the 320-pixel
; line; rows outside the playfield lines are clipped. Sprites that reach into
; the 32-pixel borders are recorded (margin_top / margin_bottom) for display.s
; to clear those lines' borders afterwards.

	xdef prepare_sprite_infos
	xdef compile_sprite
	xdef initialize_renderer
	xdef release_renderer
	xdef arena_size
	xdef frame_sprite_count
	xdef draw_sprites
	xdef margin_top
	xdef margin_bottom
	xdef sprite_list
	xdef st_sprite_buffer_end
	xdef st_sprite_tables_reset
	xdef render_sprite_count

	xref SPRITE_DATA_TABLE
	xref CURRENT_SPRITE_DATA_ENTRY
	xref SPRITE_DATA_ADDRESS
	xref BUFF_END_ADR
	xref sprite_colour_map

	ifd __USAGE__
	xref count_sprite_usage
	endif

PCG_PATTERNS=$75e
MAXIMUM_SPRITES=512
PRIORITY_BUCKETS=64
FIRST_SHOWN_PRIORITY=$10

EMPTY_KEY=$ffff ; No variant (last_key).

; Variant record: first row (word), row count (word), 16 shifted copies
; (pointers, 0 = not made), the master (16 rows of mask and 4 plane words).

RECORD_FIRST_ROW=0
RECORD_ROW_COUNT=2
RECORD_SHIFTS=4
RECORD_MASTER=4+16*4
RECORD_SIZE=RECORD_MASTER+16*10
ROW_BYTES=24 ; A shifted row: two groups of mask, planes 0-1, planes 2-3.
GROUP_BYTES=12

; Shifted copy: groups (word: 0 both, 1 the first only, 2 the second only),
; then the rows.

SHIFTED_BOTH=0
SHIFTED_FIRST=1
SHIFTED_SECOND=2

ARENA_MAXIMUM=$180000
ARENA_MINIMUM=$20000
ARENA_RESERVE=$10000 ; Left free for TOS.

SCREEN_LINE=160
PLAYFIELD_TOP=8
PLAYFIELD_BOTTOM=199
FIRST_PICTURE_GROUP=2
LAST_PICTURE_GROUP=17

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Called from XSP_OUT once the game has built its sprite list (8 bytes per
; sprite: x, y, pattern, attributes): that table becomes the renderer's, and
; the game fills the other one of two next (each ends in the $FFFF the XSP
; routines stop at; XOBJ_SET's room check reads st_sprite_buffer_end, sz2.s).
; Returns d0 = 0 like the Falcon version.

prepare_sprite_infos:
	move.l	CURRENT_SPRITE_DATA_ENTRY,d0
	move.l	game_sprite_table,a0
	sub.l	a0,d0
	lsr.l	#3,d0
	cmp		#MAXIMUM_SPRITES,d0
	bls		.count_ok

	move	#MAXIMUM_SPRITES,d0

.count_ok:
	move	d0,frame_sprite_count
	move	d0,render_sprite_count
	move.l	a0,sprite_list

	ifd __USAGE__
	jsr		count_sprite_usage ; Colour statistics (dump.s).
	endif

	; The other table for the game's next frame.

	cmp.l	#SPRITE_DATA_TABLE,a0
	bne		.back_to_first

	lea		second_sprite_table,a0
	move.l	#second_sprite_table_end,st_sprite_buffer_end

	bra		.swapped

.back_to_first:
	lea		SPRITE_DATA_TABLE,a0
	move.l	#BUFF_END_ADR,st_sprite_buffer_end

.swapped:
	move.l	a0,game_sprite_table
	move.l	a0,CURRENT_SPRITE_DATA_ENTRY

	moveq	#0,d0

	rts

; XSP_BUFF_INIT (sz2.s) has set the game's table back to SPRITE_DATA_TABLE.
; Preserves all registers.

st_sprite_tables_reset:
	move.l	#SPRITE_DATA_TABLE,game_sprite_table
	move.l	#BUFF_END_ADR,st_sprite_buffer_end

	rts

; A sprite pattern file was loaded (at start): the variants are made again.

compile_sprite:
	st		cache_reset_pending

	rts

; ------------------------------------------------------------------------------
;
; The arena: the largest free block less ARENA_RESERVE, up to ARENA_MAXIMUM.
; Supervisor mode, before the machine is taken over.

initialize_renderer:
	movem.l	d0-d2/a0-a2,-(sp)

	move.l	#SPRITE_DATA_TABLE,sprite_list
	moveq	#-1,d0
	move.l	d0,second_sprite_table_end ; Where the XSP routines stop.

	clr.l	arena
	clr.l	arena_size

	pea		-1.w
	move	#72,-(sp) ; Malloc(-1): the largest free block.
	trap	#1
	addq.l	#6,sp

	sub.l	#ARENA_RESERVE,d0
	cmp.l	#ARENA_MAXIMUM,d0
	ble		.size_ok

	move.l	#ARENA_MAXIMUM,d0

.size_ok:
	cmp.l	#ARENA_MINIMUM,d0
	blt		.done

	and.b	#$fc,d0
	move.l	d0,d2

	move.l	d0,-(sp)
	move	#72,-(sp) ; Malloc
	trap	#1
	addq.l	#6,sp
	tst.l	d0
	ble		.done

	move.l	d0,arena
	move.l	d2,arena_size

.done:
	bsr		reset_cache

	movem.l	(sp)+,d0-d2/a0-a2

	rts

release_renderer:
	movem.l	d0-d2/a0-a2,-(sp)

	move.l	arena,d0
	beq		.done

	clr.l	arena
	move.l	d0,-(sp)
	move	#73,-(sp) ; Mfree
	trap	#1
	addq.l	#6,sp

.done:
	movem.l	(sp)+,d0-d2/a0-a2

	rts

; Empties the arena and the variant tables. Preserves all registers.

reset_cache:
	movem.l	d0-d1/a0,-(sp)

	sf		cache_reset_pending
	clr		active_half
	move.l	arena,arena_next
	move.l	arena_size,d0
	lsr.l	#1,d0
	and.b	#$fc,d0
	move.l	d0,half_size
	add.l	arena,d0
	move.l	d0,arena_end
	lea		pattern_tables,a0
	moveq	#0,d0
	move	#PCG_PATTERNS-1,d1

.clear:
	move.l	d0,(a0)+
	dbf		d1,.clear

	addq.l	#1,cache_resets
	move	#EMPTY_KEY,last_key

	movem.l	(sp)+,d0-d1/a0

	rts

; d0.l = size (even) -> a0 = memory from the arena's active half, or Z set if
; it is full (draw_sprites then switches halves and draws the sprite again).

allocate:
	move.l	arena_next,a0
	move.l	a0,-(sp)
	add.l	d0,a0
	cmp.l	arena_end,a0 ; (The active half's end.)
	bhi		.full

	move.l	a0,arena_next
	move.l	(sp)+,a0
	moveq	#1,d0 ; Z clear.

	rts

.full:
	addq.l	#4,sp
	moveq	#0,d0 ; Z set.

	rts

; The active half is full: the other half becomes the active one, and
; everything kept in it is forgotten (pointers to it cleared: variant
; tables, records, shifted copies). What was made most recently, in the
; half just filled, stays. Preserves all registers.

switch_half:
	movem.l	d0-d7/a0-a3,-(sp)

	not		active_half
	move.l	arena,d6 ; The new half: d6 <= address < d7.
	tst		active_half
	beq		.first_half

	add.l	half_size,d6

.first_half:
	move.l	d6,d7
	add.l	half_size,d7
	move.l	d6,arena_next
	move.l	d7,arena_end

	lea		pattern_tables,a0
	move	#PCG_PATTERNS-1,d5

.pattern_loop:
	move.l	(a0)+,d0
	beq		.next_pattern

	cmp.l	d6,d0
	bcs		.table_kept

	cmp.l	d7,d0
	bcc		.table_kept

	clr.l	-4(a0) ; The table goes (its records in the other half too).

	bra		.next_pattern

.table_kept:
	move.l	d0,a1
	moveq	#32-1,d4

.variant_loop:
	move.l	(a1)+,d0
	beq		.next_variant

	cmp.l	d6,d0
	bcs		.record_kept

	cmp.l	d7,d0
	bcc		.record_kept

	clr.l	-4(a1)

	bra		.next_variant

.record_kept:
	move.l	d0,a2
	lea		RECORD_SHIFTS(a2),a2
	moveq	#16-1,d3

.shift_loop:
	move.l	(a2)+,d0
	beq		.next_shift

	cmp.l	d6,d0
	bcs		.next_shift

	cmp.l	d7,d0
	bcc		.next_shift

	clr.l	-4(a2)

.next_shift:
	dbf		d3,.shift_loop

.next_variant:
	dbf		d4,.variant_loop

.next_pattern:
	dbf		d5,.pattern_loop

	move	#EMPTY_KEY,last_key
	addq.l	#1,half_switches

	movem.l	(sp)+,d0-d7/a0-a3

	rts

; ------------------------------------------------------------------------------
;
; a1 = the screen (line 0), d0.w = the window offset (playfield ST line =
; X68000 line - offset): draws the sprites in the playfield lines. Sets
; margin_top / margin_bottom (ST lines whose borders sprites reached; top >
; bottom if none).

draw_sprites:
	movem.l	d0-d7/a0-a6,-(sp)

	move	d0,window_offset
	move.l	a1,screen_base
	move	#PLAYFIELD_BOTTOM+1,margin_top
	move	#PLAYFIELD_TOP-1,margin_bottom

	tst.l	arena
	beq		.done

	tst.b	cache_reset_pending
	beq		.cache_ok

	bsr		reset_cache

.cache_ok:
	bsr		order_sprites
	beq		.done

	lea		sprite_order,a6
	subq	#1,d7

.sprite_loop:
	move	(a6)+,d0
	lsl		#3,d0
	move.l	sprite_list,a5
	add		d0,a5 ; x, y, pattern, attributes.

	movem.l	d7/a6,-(sp)
	sf		retried

.retry:
	bsr		draw_one_sprite
	bpl		.next_sprite ; Drawn (or nothing to draw).

	; The arena's half was full: switch halves and try once more.

	tst.b	retried
	bne		.next_sprite

	st		retried
	bsr		switch_half

	bra		.retry

.next_sprite:
	movem.l	(sp)+,d7/a6

	dbf		d7,.sprite_loop

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; a5 = sprite list entry. N set if the arena was full.

draw_one_sprite:
	move	4(a5),d1 ; Pattern.
	cmp		#PCG_PATTERNS,d1
	bcc		.nothing

	move	(a5),d2 ; x
	cmp		#272,d2
	bhi		.nothing

	move	2(a5),d3 ; y
	cmp		#272,d3
	bhi		.nothing

	; Variant key: pattern (bits 0-10), palette (11-14), horizontal flip
	; (15).

	move	6(a5),d4 ; Attributes.
	move	d4,d0
	and		#$0f00,d0
	lsl		#3,d0
	or		d1,d0
	btst	#14,d4
	beq		.no_flip

	bset	#15,d0

.no_flip:
	cmp		last_key,d0 ; The same variant as the sprite before?
	bne		.find

	move.l	last_record,a4

	bra		.variant_found

.find:
	move	d0,-(sp)
	bsr		find_variant ; a4 = record.
	movem	(sp)+,d0 ; (Flags kept.)
	bmi		.full

	move	d0,last_key
	move.l	a4,last_record

.variant_found:

	move	RECORD_ROW_COUNT(a4),d6
	beq		.nothing ; Empty pattern.

	; Shifted copy for this position.

	move	(a5),d2
	add		#16,d2 ; ST x.
	moveq	#15,d5
	and		d2,d5 ; Shift.
	lsr		#4,d2 ; Group.

	move	d5,d0
	lsl		#2,d0
	move.l	RECORD_SHIFTS(a4,d0.w),d0
	bne		.shifted

	bsr		make_shifted ; d5 = shift -> d0 = copy.
	bmi		.full

.shifted:
	move.l	d0,a0
	move	(a0)+,d4 ; Groups.
	moveq	#ROW_BYTES,d1
	tst		d4
	beq		.row_size

	moveq	#GROUP_BYTES,d1

.row_size:
	move	d1,row_bytes

	; Rows and lines: normal: data row i is line y0 + first + i, going
	; down; vertical flip: line y0 + 15 - first - i, going up.

	move	2(a5),d3
	sub		#16,d3
	sub		window_offset,d3 ; ST line of pattern row 0.
	move	RECORD_FIRST_ROW(a4),d1

	btst	#15,6(a5)
	bne		.vertical_flip

	add		d1,d3 ; Line of data row 0.
	move	#SCREEN_LINE,a2

	cmp		#PLAYFIELD_TOP,d3
	bge		.top_ok

	move	#PLAYFIELD_TOP,d0
	sub		d3,d0 ; Rows above the playfield.
	sub		d0,d6
	ble		.nothing

	mulu	row_bytes,d0
	add.l	d0,a0
	move	#PLAYFIELD_TOP,d3

.top_ok:
	move	d3,d0
	add		d6,d0
	subq	#1,d0 ; Last line.
	sub		#PLAYFIELD_BOTTOM,d0
	ble		.lines_ok

	sub		d0,d6
	ble		.nothing

	bra		.lines_ok

.vertical_flip:
	add		#15,d3
	sub		d1,d3 ; Line of data row 0 (the lowest).
	move	#-SCREEN_LINE,a2

	cmp		#PLAYFIELD_BOTTOM,d3
	ble		.bottom_ok

	move	d3,d0
	sub		#PLAYFIELD_BOTTOM,d0 ; Rows below the playfield.
	sub		d0,d6
	ble		.nothing

	mulu	row_bytes,d0
	add.l	d0,a0
	move	#PLAYFIELD_BOTTOM,d3

.bottom_ok:
	move	d3,d0
	sub		d6,d0
	addq	#1,d0 ; Highest line.
	cmp		#PLAYFIELD_TOP,d0
	bge		.lines_ok

	sub		#PLAYFIELD_TOP,d0
	add		d0,d6 ; (d0 negative)
	ble		.nothing

.lines_ok:
	; Borders reached: record the lines.

	cmp		#FIRST_PICTURE_GROUP,d2
	bcs		.margin

	cmp		#LAST_PICTURE_GROUP,d2
	bcs		.no_margin

.margin:
	move	d3,d0 ; Lines d3 ... d3 +/- (d6 - 1).
	move	d3,d1
	cmp.l	#0,a2
	bmi		.going_up

	add		d6,d1
	subq	#1,d1

	bra		.margin_range

.going_up:
	sub		d6,d0
	addq	#1,d0

.margin_range:
	cmp		margin_top,d0
	bge		.top_kept

	move	d0,margin_top

.top_kept:
	cmp		margin_bottom,d1
	ble		.no_margin

	move	d1,margin_bottom

.no_margin:
	move.l	screen_base,a1
	mulu	#SCREEN_LINE,d3
	add.l	d3,a1
	lsl		#3,d2
	add		d2,a1

	move	d6,d7
	subq	#1,d7

	tst		d4
	bne		.one_group

.row_loop:
	movem.l	(a0)+,d0-d5
	and.l	d0,(a1)
	or.l	d1,(a1)
	and.l	d0,4(a1)
	or.l	d2,4(a1)
	and.l	d3,8(a1)
	or.l	d4,8(a1)
	and.l	d3,12(a1)
	or.l	d5,12(a1)
	add.l	a2,a1

	dbf		d7,.row_loop

	bra		.nothing

.one_group:
	cmp		#SHIFTED_FIRST,d4
	beq		.group_row_loop

	addq.l	#8,a1 ; The second group only.

.group_row_loop:
	movem.l	(a0)+,d0-d2
	and.l	d0,(a1)
	or.l	d1,(a1)
	and.l	d0,4(a1)
	or.l	d2,4(a1)
	add.l	a2,a1

	dbf		d7,.group_row_loop

.nothing:
	moveq	#0,d0 ; N clear.

	rts

.full:
	moveq	#-1,d0 ; N set.

	rts

; ------------------------------------------------------------------------------
;
; d0.w = variant key, d1.w = pattern, d4.w = attributes -> a4 = its record
; (made if new). N set if the arena is full. Two levels: per pattern a table
; (in the arena) of its 32 variants' records (palette, horizontal flip).

find_variant:
	lea		pattern_tables,a0
	move	d1,d5
	add		d5,d5
	add		d5,d5
	move.l	(a0,d5.w),d6
	bne		.table

	; The pattern's first variant: its table.

	movem.l	d0-d1/d4-d5,-(sp)
	move.l	#32*4,d0
	bsr		allocate
	movem.l	(sp)+,d0-d1/d4-d5
	beq		.full

	moveq	#32-1,d6

.clear_table:
	clr.l	(a0)+
	dbf		d6,.clear_table

	lea		-32*4(a0),a0
	lea		pattern_tables,a1
	move.l	a0,(a1,d5.w)
	move.l	a0,d6

.table:
	move.l	d6,a1 ; The pattern's table.
	move	d0,d5
	rol		#5,d5 ; Horizontal flip and palette (key bits 15-11).
	and		#31,d5
	add		d5,d5
	add		d5,d5
	move.l	(a1,d5.w),d6
	beq		.new

	move.l	d6,a4
	moveq	#0,d0 ; N clear.

	rts

.new:
	movem.l	d0-d1/d4-d5/a1,-(sp)
	move.l	#RECORD_SIZE,d0
	bsr		allocate
	movem.l	(sp)+,d0-d1/d4-d5/a1
	beq		.full

	move.l	a0,a4
	move.l	a4,(a1,d5.w)

	bsr		make_master

	moveq	#0,d0 ; N clear.

	rts

.full:
	moveq	#-1,d0 ; N set.

	rts

;  a4 = new record, d1.w = pattern, d4.w = attributes (palette bits 8-11,
; horizontal flip bit 14): its master, first row and row count, no shifted
; copies yet. Preserves d2-d4/a5.

; One pixel into the row's mask (d0) and planes (d1: 0 and 1, d2: 2 and 3)
; from the nibble in d4 (0 transparent): \1 = 0 for the next pixel from the
; left of d3 (rol), 1 from its right (lsr).

MASTER_PIXEL macro
	ifeq	\1
	rol.l	#4,d3
	moveq	#$f,d4
	and		d3,d4
	else
	moveq	#$f,d4
	and		d3,d4
	lsr.l	#4,d3
	endif
	add		d0,d0
	add.l	d1,d1
	add.l	d2,d2
	lsl		#3,d4
	bne.s	.opaque\@

	addq	#1,d0

	bra.s	.done\@

.opaque\@:
	or.l	(a5,d4.w),d1
	or.l	4(a5,d4.w),d2

.done\@:
	endm

make_master:
	movem.l	d2-d7/a1-a3/a5,-(sp)

	lea		RECORD_SHIFTS(a4),a0
	moveq	#16-1,d0

.clear_shifts:
	clr.l	(a0)+
	dbf		d0,.clear_shifts

	move.l	SPRITE_DATA_ADDRESS,a1
	moveq	#0,d0
	move	d1,d0
	lsl.l	#7,d0
	add.l	d0,a1 ; Pattern: rows of 8 pixels at +4r and +64+4r.

	; The palette's colours as plane bits to OR in: per X68000 colour,
	; planes 0 and 1 (bits 16 and 0), planes 2 and 3.

	move	d4,d0
	lsr		#4,d0
	and		#$f0,d0
	lea		sprite_colour_map,a2
	add		d0,a2
	lea		colour_bits,a5
	move.l	a5,a0
	moveq	#16-1,d0

.colour_loop:
	move.b	(a2)+,d1 ; ST colour.
	moveq	#0,d2
	moveq	#0,d3
	lsr.b	#1,d1
	bcc		.no_plane_0
	bset	#16,d2
.no_plane_0:
	lsr.b	#1,d1
	bcc		.no_plane_1
	addq	#1,d2
.no_plane_1:
	lsr.b	#1,d1
	bcc		.no_plane_2
	bset	#16,d3
.no_plane_2:
	lsr.b	#1,d1
	bcc		.no_plane_3
	addq	#1,d3
.no_plane_3:
	move.l	d2,(a0)+
	move.l	d3,(a0)+

	dbf		d0,.colour_loop

	lea		RECORD_MASTER(a4),a3 ; Rows: mask, planes 0-3.
	moveq	#-1,d6 ; First row with pixels (none yet).
	moveq	#-1,d7 ; Last one.
	moveq	#0,d5 ; Row.
	btst	#14,d4
	bne		.flipped_row

.row_loop:
	moveq	#0,d0 ; Mask (1 = transparent).
	moveq	#0,d1
	moveq	#0,d2

	move.l	(a1),d3 ; Pixels 0-7, high nibble first.
	rept	8
	MASTER_PIXEL 0
	endr
	move.l	64(a1),d3 ; Pixels 8-15.
	rept	8
	MASTER_PIXEL 0
	endr

	bsr		.store_row
	cmp		#16,d5
	bne		.row_loop

	bra		.rows_done

.flipped_row:
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2

	move.l	64(a1),d3 ; Pixels 15-8.
	rept	8
	MASTER_PIXEL 1
	endr
	move.l	(a1),d3 ; Pixels 7-0.
	rept	8
	MASTER_PIXEL 1
	endr

	bsr		.store_row
	cmp		#16,d5
	bne		.flipped_row

.rows_done:
	clr		RECORD_ROW_COUNT(a4)
	move	d6,RECORD_FIRST_ROW(a4)
	bmi		.done ; No pixels.

	sub		d6,d7
	addq	#1,d7
	move	d7,RECORD_ROW_COUNT(a4)

.done:
	movem.l	(sp)+,d2-d7/a1-a3/a5

	rts

; Stores row d5 (mask d0, planes d1, d2), notes the first and last rows with
; pixels, advances.

.store_row:
	move	d0,(a3)+
	move.l	d1,(a3)+
	move.l	d2,(a3)+
	addq.l	#4,a1

	cmp		#$ffff,d0
	beq		.empty_row

	tst		d6
	bpl		.first_known

	move	d5,d6

.first_known:
	move	d5,d7

.empty_row:
	addq	#1,d5

	rts

; a4 = record, d5.w = shift (0-15) -> d0 = its shifted copy (made now), N
; set if the arena is full. Preserves d2/a5.

; d\1 = the next master word << 16 >> shift (the two groups' halves).

SHIFT_WORD macro
	moveq	#0,\1
	move	(a1)+,\1
	swap	\1
	lsr.l	d5,\1
	endm

make_shifted:
	movem.l	d1-d7/a1-a3,-(sp)

	move	RECORD_ROW_COUNT(a4),d0
	mulu	#ROW_BYTES,d0
	addq.l	#2,d0
	bsr		allocate
	beq		.full

	move.l	a0,a3 ; The copy.
	move	d5,d0
	lsl		#2,d0
	move.l	a3,RECORD_SHIFTS(a4,d0.w)
	addq.l	#2,a3 ; (The groups word.)

	lea		RECORD_MASTER(a4),a1
	move	RECORD_FIRST_ROW(a4),d0
	mulu	#10,d0
	add		d0,a1
	move	RECORD_ROW_COUNT(a4),d7
	subq	#1,d7
	moveq	#0,d0 ; Opaque pixels of all rows (both groups).

.row_loop:
	moveq	#0,d1 ; Opaque, shifted.
	move	(a1)+,d1
	not		d1
	swap	d1
	lsr.l	d5,d1
	or.l	d1,d0
	not.l	d1 ; Masks (1 = keep).

	SHIFT_WORD d2 ; Plane 0.
	SHIFT_WORD d3 ; Plane 1.
	SHIFT_WORD d4 ; Plane 2.
	SHIFT_WORD d6 ; Plane 3.

	; Group 1: mask:mask, plane 0:plane 1, plane 2:plane 3 (high words),
	; then group 2 (low words).

	swap	d1
	move	d1,(a3)+
	move	d1,(a3)+
	swap	d2
	move	d2,(a3)+
	swap	d3
	move	d3,(a3)+
	swap	d4
	move	d4,(a3)+
	swap	d6
	move	d6,(a3)+

	swap	d1
	move	d1,(a3)+
	move	d1,(a3)+
	swap	d2
	move	d2,(a3)+
	swap	d3
	move	d3,(a3)+
	swap	d4
	move	d4,(a3)+
	swap	d6
	move	d6,(a3)+

	dbf		d7,.row_loop

	; One group only? Then its rows are moved together and the arena gets
	; the rest back (this copy is its last allocation).

	move	d5,d1
	lsl		#2,d1
	move.l	RECORD_SHIFTS(a4,d1.w),a0 ; The copy.
	clr		(a0)

	moveq	#SHIFTED_FIRST,d1
	tst		d0
	beq		.one_group ; Nothing in group 2.

	moveq	#SHIFTED_SECOND,d1
	swap	d0
	tst		d0
	bne		.done ; Pixels in both.

.one_group:
	move	d1,(a0)+
	move.l	a0,a1 ; Source rows.
	cmp		#SHIFTED_FIRST,d1
	beq		.compact

	lea		GROUP_BYTES(a1),a1 ; The second group's half.

.compact:
	move.l	a0,a2 ; Destination.
	move	RECORD_ROW_COUNT(a4),d7
	subq	#1,d7

.compact_loop:
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	move.l	(a1)+,(a2)+
	lea		GROUP_BYTES(a1),a1

	dbf		d7,.compact_loop

	move.l	a2,arena_next

.done:
	move	d5,d0
	lsl		#2,d0
	move.l	RECORD_SHIFTS(a4,d0.w),d0

	movem.l	(sp)+,d1-d7/a1-a3

	tst.l	d0 ; N clear (an address in ST RAM).

	rts

.full:
	movem.l	(sp)+,d1-d7/a1-a3

	moveq	#-1,d0 ; N set.

	rts

; ------------------------------------------------------------------------------
;
; sprite_order = the shown sprites' list indices in drawing order. Returns
; d7 = their number (Z set if none or no pattern data).

order_sprites:
	moveq	#0,d7
	move	render_sprite_count,d6
	beq		.done

	move.l	SPRITE_DATA_ADDRESS,d0
	beq		.done

	lea		bucket_counts,a0
	moveq	#PRIORITY_BUCKETS/2-1,d0

.clear_counts:
	clr.l	(a0)+
	dbf		d0,.clear_counts

	move.l	sprite_list,a0
	lea		bucket_counts,a1
	move	d6,d0
	subq	#1,d0

.count_loop:
	moveq	#PRIORITY_BUCKETS-1,d1
	and		6(a0),d1
	cmp		#FIRST_SHOWN_PRIORITY,d1
	bcs		.not_counted

	add		d1,d1
	addq	#1,(a1,d1.w)

.not_counted:
	addq.l	#8,a0

	dbf		d0,.count_loop

	; Bucket end offsets: each bucket is filled backwards from its end, so
	; its entries end up in reverse list order.

	lea		bucket_counts,a1
	lea		bucket_ends,a2
	moveq	#0,d1
	moveq	#PRIORITY_BUCKETS-1,d0

.offset_loop:
	add		(a1)+,d1
	move	d1,(a2)+

	dbf		d0,.offset_loop

	move	d1,d7 ; Shown sprites.

	move.l	sprite_list,a0
	lea		bucket_ends,a2
	lea		sprite_order,a3
	moveq	#0,d2 ; List index.
	move	d6,d0
	subq	#1,d0

.order_loop:
	moveq	#PRIORITY_BUCKETS-1,d1
	and		6(a0),d1
	cmp		#FIRST_SHOWN_PRIORITY,d1
	bcs		.not_ordered

	add		d1,d1
	move	(a2,d1.w),d3
	subq	#1,d3
	move	d3,(a2,d1.w)
	add		d3,d3
	move	d2,(a3,d3.w)

.not_ordered:
	addq	#1,d2
	addq.l	#8,a0

	dbf		d0,.order_loop

.done:
	tst		d7

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

game_sprite_table: ; The table the game fills now.
	dc.l	SPRITE_DATA_TABLE
st_sprite_buffer_end:
	dc.l	BUFF_END_ADR

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

frame_sprite_count:
	ds.w	1
render_sprite_count:
	ds.w	1
window_offset:
	ds.w	1
margin_top:
	ds.w	1
margin_bottom:
	ds.w	1
row_bytes:
	ds.w	1
active_half:
	ds.w	1
last_key: ; The variant of the sprite before (EMPTY_KEY: none).
	ds.w	1
cache_reset_pending:
	ds.b	1
retried:
	ds.b	1

screen_base:
	ds.l	1
last_record:
	ds.l	1
arena:
	ds.l	1
arena_size:
	ds.l	1
arena_next:
	ds.l	1
arena_end:
	ds.l	1
cache_resets:
	ds.l	1
half_switches:
	ds.l	1
half_size:
	ds.l	1

	xdef cache_resets
	xdef half_switches

colour_bits: ; make_master: per colour, the plane bits to OR in.
	ds.l	16*2
sprite_list: ; The renderer's sprite table (the game's last complete one).
	ds.l	1
second_sprite_table: ; The game fills this and SPRITE_DATA_TABLE in turn.
	ds.l	MAXIMUM_SPRITES*2
second_sprite_table_end:
	ds.l	1 ; $FFFFFFFF
sprite_order:
	ds.w	MAXIMUM_SPRITES
bucket_counts:
	ds.w	PRIORITY_BUCKETS
bucket_ends:
	ds.w	PRIORITY_BUCKETS
pattern_tables: ; Per pattern: its variants' table, or 0.
	ds.l	PCG_PATTERNS

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
