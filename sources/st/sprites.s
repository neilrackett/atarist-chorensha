
; Sprites on the Atari ST, in bitplanes.
;
; The game's sprites are 16 x 16 X68000 patterns (4 bits per pixel, 16
; palettes, flips), up to 512 per frame in its sprite list. A variant is a
; (pattern, palette, horizontal flip); a vertical flip only draws the rows in
; reverse order. For each variant used, a master in ST colours (palette_map.i)
; is made on first use, two pixels at a time through a table per palette: 16
; rows of the opaque pixels and the four plane words. For each horizontal
; position within a 16-pixel group (shift) it is drawn at, a shifted copy is
; made on first use from the master (each long rotated, then split between
; the two groups): per row two groups of a mask long (1 = keep, in both
; words) and two plane longs, the planes already 0 where transparent, so
; drawing reads the screen's row, masks it and writes it back:
;
;     movem.l (a1),d0-d3 / move.l (a0)+,d4 / and.l d4,d0 / and.l d4,d1
;     or.l (a0)+,d0 / or.l (a0)+,d1 / ... the same for d2-d3 / movem.l d0-d3,(a1)
;
; (214 cycles per row; empty rows at the top and bottom are left out). When
; the shifted pixels all fall into one of the two groups (narrow shapes:
; bullets, particles), only that group is kept and drawn (126 cycles). The
; masters and shifted copies live in an arena (the memory left free: about
; 850 KB with 4 MB), found through a table per pattern of its 32 variants.
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

; Variant record: first row (word), row count (word), the opaque pixels of
; all rows (word, OR), 16 shifted copies (pointers, 0 = not made), the
; master: 16 rows of the opaque pixels (both words), planes 0:1 and 2:3.

RECORD_FIRST_ROW=0
RECORD_ROW_COUNT=2
RECORD_UNION=4
RECORD_SHIFTS=8
RECORD_MASTER=8+16*4
MASTER_ROW_BYTES=12
RECORD_SIZE=RECORD_MASTER+16*MASTER_ROW_BYTES
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
	bsr		build_pair_tables
	bsr		reset_cache

	movem.l	(sp)+,d0-d2/a0-a2

	rts

; For make_master, per palette and per byte of two X68000 pixels (the left
; one in the high nibble): their plane bits, as a long of planes 0 (bits
; 17-16, the left pixel's higher) and 1 (bits 1-0), and one of planes 2 and
; 3; nibble 0 (transparent) gives none. Also each byte with its nibbles
; swapped (horizontal flip).

build_pair_tables:
	movem.l	d0-d7/a0-a2,-(sp)

	lea		sprite_colour_map,a0
	lea		pair_tables,a1
	moveq	#16-1,d7 ; Palettes.

.palette_loop:
	lea		colour_bits,a2
	moveq	#16-1,d6

.colour_loop:
	move.b	(a0)+,d1 ; ST colour.
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
	move.l	d2,(a2)+
	move.l	d3,(a2)+

	dbf		d6,.colour_loop

	lea		colour_bits,a2
	clr.l	(a2)+ ; Nibble 0: transparent.
	clr.l	(a2)+
	lea		-8(a2),a2
	moveq	#0,d6 ; Left nibble.

.left_loop:
	move	d6,d0
	lsl		#3,d0
	move.l	(a2,d0.w),d2
	add.l	d2,d2
	move.l	4(a2,d0.w),d3
	add.l	d3,d3
	moveq	#0,d5 ; Right nibble.

.right_loop:
	move	d5,d0
	lsl		#3,d0
	move.l	(a2,d0.w),d4
	or.l	d2,d4
	move.l	d4,(a1)+
	move.l	4(a2,d0.w),d4
	or.l	d3,d4
	move.l	d4,(a1)+

	addq	#1,d5
	cmp		#16,d5
	bne		.right_loop

	addq	#1,d6
	cmp		#16,d6
	bne		.left_loop

	dbf		d7,.palette_loop

	lea		pair_swapped,a0
	moveq	#0,d0

.swap_loop:
	move.b	d0,d1
	ror.b	#4,d1
	move.b	d1,(a0)+
	addq	#1,d0
	cmp		#256,d0
	bne		.swap_loop

	movem.l	(sp)+,d0-d7/a0-a2

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
	move	#PLAYFIELD_BOTTOM+1,margin_top
	move	#PLAYFIELD_TOP-1,margin_bottom

	tst.l	arena
	beq		.done

	tst.b	cache_reset_pending
	beq		.cache_ok

	bsr		reset_cache

.cache_ok:
	move.l	a1,a5
	bsr		order_sprites ; (Uses a0-a3.)
	beq		.done

	move.l	a5,a3 ; Kept by draw_one_sprite: a3, a6, d6, d7.

	lea		sprite_order,a6
	subq	#1,d7
	move	window_offset,d6
	add		#16,d6 ; (The sprite y's 16-line offset.)

.sprite_loop:
	move.l	(a6)+,a5 ; x, y, pattern, attributes.
	bsr		draw_one_sprite
	bpl		.next_sprite ; Drawn (or nothing to draw).

	; The arena's half was full: switch halves and try once more.

	bsr		switch_half
	bsr		draw_one_sprite

.next_sprite:
	dbf		d7,.sprite_loop

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; a5 = sprite list entry, a3 = the screen (line 0), d6.w = window offset
; + 16. N set if the arena was full (nothing drawn). Uses d0-d5/a0-a2/a4.

draw_one_sprite:
	movem.w	(a5),d0-d3 ; x, y, pattern, attributes.
	cmp		#PCG_PATTERNS,d2
	bcc		.nothing

	cmp		#272,d0
	bhi		.nothing

	cmp		#272,d1
	bhi		.nothing

	; Outside the playfield lines: nothing (before any variant work).

	sub		d6,d1 ; ST line of pattern row 0.
	cmp		#PLAYFIELD_BOTTOM,d1
	bgt		.nothing

	cmp		#PLAYFIELD_TOP-15,d1
	blt		.nothing

	; Variant key: pattern (bits 0-10), palette (11-14), horizontal flip
	; (15).

	move	d3,d4
	and		#$0f00,d4
	lsl		#3,d4
	or		d2,d4
	btst	#14,d3
	beq		.no_flip

	bset	#15,d4

.no_flip:
	cmp		last_key,d4 ; The same variant as the sprite before?
	bne		.find

	move.l	last_record,a4

	bra		.variant_found

.find:
	; Its record, through the pattern's table of 32 variants (palette,
	; horizontal flip: key bits 15-11).

	move	d2,d5
	add		d5,d5
	add		d5,d5
	lea		pattern_tables,a0
	move.l	(a0,d5.w),d5
	beq		.make

	move.l	d5,a0
	move	d4,d5
	rol		#5,d5
	and		#31,d5
	add		d5,d5
	add		d5,d5
	move.l	(a0,d5.w),d5
	beq		.make

	move.l	d5,a4

.found:
	move	d4,last_key
	move.l	a4,last_record

.variant_found:
	move	RECORD_ROW_COUNT(a4),d5
	beq		.nothing ; Empty pattern.

	; Shifted copy for this position: ST x = x + 16.

	add		#16,d0
	moveq	#15,d4
	and		d0,d4 ; Shift.
	lsr		#4,d0 ; Group.
	add		d4,d4
	add		d4,d4
	move.l	RECORD_SHIFTS(a4,d4.w),d2
	beq		.make_shifted

.shifted:
	move.l	d2,a0
	move	(a0)+,d4 ; Groups (0 both).

	; Rows and lines: normal: data row i is line y0 + first + i, going
	; down; vertical flip: line y0 + 15 - first - i, going up.

	move	RECORD_FIRST_ROW(a4),d2
	btst	#15,d3
	bne		.vertical_flip

	add		d2,d1 ; Line of data row 0.
	move	#SCREEN_LINE,a2

	cmp		#PLAYFIELD_TOP,d1
	bge		.top_ok

	move	#PLAYFIELD_TOP,d2
	sub		d1,d2 ; Rows above the playfield.
	sub		d2,d5
	ble		.nothing

	bsr		.skip_rows
	move	#PLAYFIELD_TOP,d1

.top_ok:
	move	d1,d2
	add		d5,d2
	sub		#PLAYFIELD_BOTTOM+1,d2 ; Rows below it.
	ble		.lines_ok

	sub		d2,d5
	ble		.nothing

	bra		.lines_ok

.vertical_flip:
	add		#15,d1
	sub		d2,d1 ; Line of data row 0 (the lowest).
	move	#-SCREEN_LINE,a2

	cmp		#PLAYFIELD_BOTTOM,d1
	ble		.bottom_ok

	move	d1,d2
	sub		#PLAYFIELD_BOTTOM,d2 ; Rows below the playfield.
	sub		d2,d5
	ble		.nothing

	bsr		.skip_rows
	move	#PLAYFIELD_BOTTOM,d1

.bottom_ok:
	move	d1,d2
	sub		d5,d2
	sub		#PLAYFIELD_TOP-1,d2 ; Lines above the highest, in it.
	bge		.lines_ok

	add		d2,d5 ; (d2 negative: rows above it)
	ble		.nothing

.lines_ok:
	; Borders reached: record the lines.

	cmp		#FIRST_PICTURE_GROUP,d0
	bcs		.margin

	cmp		#LAST_PICTURE_GROUP,d0
	bcs		.no_margin

.margin:
	move	d1,d2 ; Lines d1 ... d1 +/- (d5 - 1).
	move	d1,d3
	cmp.l	#0,a2
	bmi		.going_up

	add		d5,d3
	subq	#1,d3

	bra		.margin_range

.going_up:
	sub		d5,d2
	addq	#1,d2

.margin_range:
	cmp		margin_top,d2
	bge		.top_kept

	move	d2,margin_top

.top_kept:
	cmp		margin_bottom,d3
	ble		.no_margin

	move	d3,margin_bottom

.no_margin:
	move.l	a3,a1
	mulu	#SCREEN_LINE,d1
	add.l	d1,a1
	lsl		#3,d0
	add		d0,a1

	subq	#1,d5

	tst		d4
	bne		.one_group

	; The screen's row is read into registers, masked and written back
	; (214 cycles per row of two groups, 126 of one).

.row_loop:
	movem.l	(a1),d0-d3
	move.l	(a0)+,d4
	and.l	d4,d0
	and.l	d4,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	move.l	(a0)+,d4
	and.l	d4,d2
	and.l	d4,d3
	or.l	(a0)+,d2
	or.l	(a0)+,d3
	movem.l	d0-d3,(a1)
	add.l	a2,a1

	dbf		d5,.row_loop

	bra		.nothing

.one_group:
	cmp		#SHIFTED_FIRST,d4
	beq		.group_row_loop

	addq.l	#8,a1 ; The second group only.

.group_row_loop:
	movem.l	(a1),d0-d1
	move.l	(a0)+,d2
	and.l	d2,d0
	and.l	d2,d1
	or.l	(a0)+,d0
	or.l	(a0)+,d1
	movem.l	d0-d1,(a1)
	add.l	a2,a1

	dbf		d5,.group_row_loop

.nothing:
	moveq	#0,d0 ; N clear.

	rts

; d2.w = rows to leave out at the copy's start (a0): one group's or two.

.skip_rows:
	mulu	#GROUP_BYTES,d2
	tst		d4
	bne		.one_group_skipped

	add.l	d2,d2

.one_group_skipped:
	add.l	d2,a0

	rts

.make:
	; A new variant (find_variant makes it).

	movem.l	d0-d4/d6,-(sp)
	move	d4,d0 ; Key.
	move	d2,d1 ; Pattern.
	move	d3,d4 ; Attributes.
	bsr		find_variant
	movem.l	(sp)+,d0-d4/d6
	bmi		.full

	bra		.found

.make_shifted:
	movem.l	d0-d1/d3,-(sp)
	move	d4,d5
	lsr		#2,d5 ; Shift.
	bsr		make_shifted
	move.l	d0,d2
	movem.l	(sp)+,d0-d1/d3
	tst.l	d2
	bmi		.full

	move	RECORD_ROW_COUNT(a4),d5

	bra		.shifted

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
; horizontal flip bit 14): its master, first row, row count and opaque
; pixels, no shifted copies yet. Preserves d2-d7/a1-a6.

; The next two pixels (the pattern byte at \1(a1)) into the row's planes
; 0:1 (d1) and 2:3 (d2), through the palette's pair table (a5); \2 = 1 for
; a horizontal flip (nibbles swapped through a6).

MASTER_PAIR macro
	moveq	#0,d3
	move.b	\1(a1),d3
	if \2
	move.b	(a6,d3.w),d3
	endif
	lsl		#3,d3
	lsl.l	#2,d1
	or.l	(a5,d3.w),d1
	lsl.l	#2,d2
	or.l	4(a5,d3.w),d2
	endm

; Eight pixels: the pattern long at \1(a1), its bytes in the order \2-\5
; (\6 = 1: flipped). An empty half only moves the planes along (nothing to
; look up).

MASTER_HALF macro
	tst.l	\1(a1)
	beq.s	.empty\@

	MASTER_PAIR \2,\6
	MASTER_PAIR \3,\6
	MASTER_PAIR \4,\6
	MASTER_PAIR \5,\6

	bra.s	.done\@

.empty\@:
	lsl.l	#8,d1
	lsl.l	#8,d2

.done\@:
	endm

make_master:
	movem.l	d2-d7/a1-a3/a5-a6,-(sp)

	addq.l	#1,masters_made

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

	move	d4,d0
	and		#$0f00,d0
	lsl		#3,d0 ; Palette * 2048.
	lea		pair_tables,a5
	add		d0,a5
	lea		pair_swapped,a6

	lea		RECORD_MASTER(a4),a3
	clr		RECORD_UNION(a4)
	moveq	#-1,d6 ; First row with pixels (none yet).
	moveq	#-1,d7 ; Last one.
	moveq	#0,d5 ; Row.
	btst	#14,d4
	bne		.flipped_row

.row_loop:
	moveq	#0,d1
	moveq	#0,d2
	MASTER_HALF 0,0,1,2,3,0
	MASTER_HALF 64,64,65,66,67,0

	bsr		.store_row
	cmp		#16,d5
	bne		.row_loop

	bra		.rows_done

.flipped_row:
	moveq	#0,d1
	moveq	#0,d2
	MASTER_HALF 64,67,66,65,64,1
	MASTER_HALF 0,3,2,1,0,1

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
	movem.l	(sp)+,d2-d7/a1-a3/a5-a6

	rts

; Stores row d5 (planes d1, d2) with its opaque pixels (any plane set: the
; sprite colours are never ST colour 0), notes the first and last rows with
; pixels, advances.

.store_row:
	move.l	d1,d0
	or.l	d2,d0
	move.l	d0,d3
	swap	d3
	or		d3,d0 ; Opaque pixels.
	move	d0,d3
	swap	d0
	move	d3,d0 ; In both words.
	move.l	d0,(a3)+
	move.l	d1,(a3)+
	move.l	d2,(a3)+
	addq.l	#4,a1

	or		d3,RECORD_UNION(a4)
	tst		d3
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
;
; Each master long (two words: opaque or planes) rotated right by the shift
; holds both groups' halves: ANDed with the low 16 - shift bits of each word
; (d6) the first group's, with the top shift bits (swapped) the second's.

; d\1 rotated right by the shift: \2 = 0: by d5 (= shift), 1: swapped and
; rotated left by d5 (= 16 - shift; faster for shifts 9-15).

SHIFT_ROTATE macro
	ifeq	\2
	ror.l	d5,\1
	else
	swap	\1
	rol.l	d5,\1
	endif
	endm

; Rows of both groups: mask, planes 0:1, planes 2:3 of each.

SHIFT_BOTH macro
.both\@:
	movem.l	(a1)+,d0-d2
	SHIFT_ROTATE d0,\1
	move.l	d0,d3
	and.l	d6,d0
	eor.l	d0,d3
	not.l	d0
	not.l	d3
	SHIFT_ROTATE d1,\1
	move.l	d1,d4
	and.l	d6,d1
	eor.l	d1,d4
	swap	d4
	move.l	d0,(a3)+
	move.l	d1,(a3)+
	SHIFT_ROTATE d2,\1
	move.l	d2,d0
	and.l	d6,d2
	eor.l	d2,d0
	swap	d0
	move.l	d2,(a3)+
	move.l	d3,(a3)+
	move.l	d4,(a3)+
	move.l	d0,(a3)+

	dbf		d7,.both\@

	bra		.made
	endm

; Rows of one group: \2 = 0 the first (d6 = its bits), 1 the second (d6 =
; its bits; the plane words swapped back).

SHIFT_ONE macro
.one\@:
	movem.l	(a1)+,d0-d2
	SHIFT_ROTATE d0,\1
	and.l	d6,d0
	not.l	d0
	SHIFT_ROTATE d1,\1
	and.l	d6,d1
	SHIFT_ROTATE d2,\1
	and.l	d6,d2
	if \2
	swap	d1
	swap	d2
	endif
	move.l	d0,(a3)+
	move.l	d1,(a3)+
	move.l	d2,(a3)+

	dbf		d7,.one\@

	bra		.made
	endm

make_shifted:
	movem.l	d1-d7/a1-a3,-(sp)

	addq.l	#1,shifts_made

	; Groups with pixels, from all rows' opaque pixels: the first gets
	; bits shift-15, the second bits 0 to shift-1.

	move	RECORD_UNION(a4),d0
	moveq	#-1,d1
	lsl		d5,d1 ; $ffff << shift: the first group's bits.
	move	d0,d2
	and		d1,d2
	not		d1
	and		d0,d1
	moveq	#SHIFTED_SECOND,d4
	tst		d2
	beq		.groups_known ; Nothing in the first.

	moveq	#SHIFTED_FIRST,d4
	tst		d1
	beq		.groups_known ; Nothing in the second.

	moveq	#SHIFTED_BOTH,d4

.groups_known:
	move	RECORD_ROW_COUNT(a4),d0
	mulu	#GROUP_BYTES,d0
	tst		d4
	bne		.size_known

	add.l	d0,d0 ; ROW_BYTES

.size_known:
	addq.l	#2,d0
	bsr		allocate
	beq		.full

	move.l	a0,a3 ; The copy.
	move	d5,d0
	lsl		#2,d0
	move.l	a3,RECORD_SHIFTS(a4,d0.w)
	move	d4,(a3)+

	lea		RECORD_MASTER(a4),a1
	move	RECORD_FIRST_ROW(a4),d0
	mulu	#MASTER_ROW_BYTES,d0
	add		d0,a1
	move	RECORD_ROW_COUNT(a4),d7
	subq	#1,d7

	; d6 = the first group's bits in both words (the low 16 - shift).

	moveq	#-1,d0
	lsr		d5,d0
	move	d0,d6
	swap	d6
	move	d0,d6

	cmp		#9,d5
	bcc		.rotate_left

	; Shifts 0-8: rotated right by the shift.

	cmp		#SHIFTED_FIRST,d4
	bcs		.both_right
	beq		.first_right

	not.l	d6
	SHIFT_ONE 0,1

.first_right:
	SHIFT_ONE 0,0

.both_right:
	SHIFT_BOTH 0

.rotate_left:
	; Shifts 9-15: swapped, rotated left by 16 - shift.

	neg		d5
	add		#16,d5

	cmp		#SHIFTED_FIRST,d4
	bcs		.both_left
	beq		.first_left

	not.l	d6
	SHIFT_ONE 1,1

.first_left:
	SHIFT_ONE 1,0

.both_left:
	SHIFT_BOTH 1

.made:
	move.l	a0,d0

	movem.l	(sp)+,d1-d7/a1-a3

	tst.l	d0 ; N clear (an address in ST RAM).

	rts

.full:
	movem.l	(sp)+,d1-d7/a1-a3

	moveq	#-1,d0 ; N set.

	rts

; ------------------------------------------------------------------------------
;
; sprite_order = the shown sprites' list entries in drawing order. Returns
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
	add		d3,d3
	move.l	a0,(a3,d3.w)

.not_ordered:
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
active_half:
	ds.w	1
last_key: ; The variant of the sprite before (EMPTY_KEY: none).
	ds.w	1
cache_reset_pending:
	ds.b	1
	even

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
masters_made:
	ds.l	1
shifts_made:
	ds.l	1
half_size:
	ds.l	1

	xdef cache_resets
	xdef half_switches
	xdef masters_made
	xdef shifts_made

colour_bits: ; build_pair_tables: per colour, its plane bits.
	ds.l	16*2
pair_tables: ; Per palette, per byte of two pixels: planes 0:1, planes 2:3.
	ds.l	16*256*2
pair_swapped: ; Per byte, its nibbles swapped.
	ds.b	256
sprite_list: ; The renderer's sprite table (the game's last complete one).
	ds.l	1
second_sprite_table: ; The game fills this and SPRITE_DATA_TABLE in turn.
	ds.l	MAXIMUM_SPRITES*2
second_sprite_table_end:
	ds.l	1 ; $FFFFFFFF
sprite_order:
	ds.l	MAXIMUM_SPRITES
bucket_counts:
	ds.w	PRIORITY_BUCKETS
bucket_ends:
	ds.w	PRIORITY_BUCKETS
pattern_tables: ; Per pattern: its variants' table, or 0.
	ds.l	PCG_PATTERNS

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
