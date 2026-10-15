
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
; (262 cycles per row; empty rows at the top and bottom are left out). The
; masters and shifted copies live in an arena (the memory left free: about
; 900 KB with 4 MB), found through a hash table of variants; when the arena
; is full it is emptied and refilled with what is drawn next.
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

	xref SPRITE_DATA_TABLE
	xref CURRENT_SPRITE_DATA_ENTRY
	xref SPRITE_DATA_ADDRESS
	xref sprite_colour_map

	ifd __USAGE__
	xref count_sprite_usage
	endif

PCG_PATTERNS=$75e
MAXIMUM_SPRITES=512
PRIORITY_BUCKETS=64
FIRST_SHOWN_PRIORITY=$10

HASH_SIZE=8192
MAXIMUM_RECORDS=HASH_SIZE*3/4
EMPTY_KEY=$ffff

; Variant record: first row (word), row count (word), 16 shifted copies
; (pointers, 0 = not made), the master (16 rows of mask and 4 plane words).

RECORD_FIRST_ROW=0
RECORD_ROW_COUNT=2
RECORD_SHIFTS=4
RECORD_MASTER=4+16*4
RECORD_SIZE=RECORD_MASTER+16*10
ROW_BYTES=24 ; A shifted row: two groups of mask, planes 0-1, planes 2-3.

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
; sprite: x, y, pattern, attributes). Takes a copy for the renderer and
; returns d0 = 0 like the Falcon version.

prepare_sprite_infos:
	move.l	CURRENT_SPRITE_DATA_ENTRY,d0
	sub.l	#SPRITE_DATA_TABLE,d0
	lsr.l	#3,d0
	cmp		#MAXIMUM_SPRITES,d0
	bls		.count_ok

	move	#MAXIMUM_SPRITES,d0

.count_ok:
	move	d0,frame_sprite_count
	move	d0,render_sprite_count

	ifd __USAGE__
	jsr		count_sprite_usage ; Colour statistics (dump.s).
	endif

	movem.l	a0/a2,-(sp)

	lea		SPRITE_DATA_TABLE,a0
	lea		sprite_list,a2
	subq	#1,d0
	bmi		.copy_done

.copy_loop:
	move.l	(a0)+,(a2)+
	move.l	(a0)+,(a2)+

	dbf		d0,.copy_loop

.copy_done:
	movem.l	(sp)+,a0/a2

	move.l	#SPRITE_DATA_TABLE,CURRENT_SPRITE_DATA_ENTRY

	moveq	#0,d0

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

; Empties the arena and the hash table. Preserves all registers.

reset_cache:
	movem.l	d0-d1/a0,-(sp)

	sf		cache_reset_pending
	move.l	arena,arena_next
	move.l	arena,d0
	add.l	arena_size,d0
	move.l	d0,arena_end
	clr		record_count

	lea		hash_keys,a0
	moveq	#-1,d0
	move	#HASH_SIZE/2-1,d1

.clear:
	move.l	d0,(a0)+
	dbf		d1,.clear

	addq.l	#1,cache_resets

	movem.l	(sp)+,d0-d1/a0

	rts

; d0.l = size (even) -> a0 = memory from the arena, or Z set if it is full.

allocate:
	move.l	arena_next,a0
	move.l	a0,-(sp)
	add.l	d0,a0
	cmp.l	arena_end,a0
	bhi		.full

	move.l	a0,arena_next
	move.l	(sp)+,a0
	moveq	#1,d0 ; Z clear.

	rts

.full:
	addq.l	#4,sp
	moveq	#0,d0 ; Z set.

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
	lea		sprite_list,a5
	add		d0,a5 ; x, y, pattern, attributes.

	movem.l	d7/a6,-(sp)
	sf		retried

.retry:
	bsr		draw_one_sprite
	bpl		.next_sprite ; Drawn (or nothing to draw).

	; The arena was full: empty it and try once more.

	tst.b	retried
	bne		.next_sprite

	st		retried
	bsr		reset_cache

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
	bsr		find_variant ; a4 = record.
	bmi		.full

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

	mulu	#ROW_BYTES,d0
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

	mulu	#ROW_BYTES,d0
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

.nothing:
	moveq	#0,d0 ; N clear.

	rts

.full:
	moveq	#-1,d0 ; N set.

	rts

; ------------------------------------------------------------------------------
;
; d0.w = variant key, d1.w = pattern, d4.w = attributes -> a4 = its record
; (made if new). N set if the arena is full.

find_variant:
	move	d0,d5
	mulu	#40503,d5
	swap	d5
	and		#HASH_SIZE-1,d5
	add		d5,d5 ; Byte offset in the word table.

	lea		hash_keys,a0

.probe:
	move	(a0,d5.w),d6
	cmp		d0,d6
	beq		.found

	cmp		#EMPTY_KEY,d6
	beq		.new

	addq	#2,d5
	and		#(HASH_SIZE-1)*2,d5

	bra		.probe

.found:
	lea		hash_records,a0
	add		d5,d5
	move.l	(a0,d5.w),a4
	moveq	#0,d0 ; N clear.

	rts

.new:
	cmp		#MAXIMUM_RECORDS,record_count
	bcc		.full

	movem.l	d0-d1/d4-d5,-(sp)
	move.l	#RECORD_SIZE,d0
	bsr		allocate
	movem.l	(sp)+,d0-d1/d4-d5
	beq		.full

	move.l	a0,a4
	addq	#1,record_count

	lea		hash_keys,a0
	move	d0,(a0,d5.w)
	lea		hash_records,a0
	add		d5,d5
	move.l	a4,(a0,d5.w)

	bsr		make_master

	moveq	#0,d0 ; N clear.

	rts

.full:
	moveq	#-1,d0 ; N set.

	rts

; a4 = new record, d1.w = pattern, d4.w = attributes (palette bits 8-11,
; horizontal flip bit 14): its master, first row and row count, no shifted
; copies yet. Preserves d2-d4/a5.

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

	move	d4,d0
	lsr		#4,d0
	and		#$f0,d0
	lea		sprite_colour_map,a2
	add		d0,a2 ; This palette's 16 colours.

	lea		RECORD_MASTER(a4),a3 ; Rows: mask, planes 0-3.
	moveq	#-1,d6 ; First row with pixels (none yet).
	moveq	#-1,d7 ; Last one.
	moveq	#0,d5 ; Row.

.row_loop:
	; The row's 16 pixels, left to right (or right to left).

	move.l	(a1),d0 ; Pixels 0-7, high nibble first.
	move.l	64(a1),d1 ; Pixels 8-15.
	addq.l	#4,a1

	lea		row_pixels,a0
	moveq	#8-1,d2

.split:
	rol.l	#4,d0
	moveq	#$f,d3
	and		d0,d3
	move.b	d3,(a0)
	rol.l	#4,d1
	moveq	#$f,d3
	and		d1,d3
	move.b	d3,8(a0)
	addq.l	#1,a0

	dbf		d2,.split

	moveq	#0,d0 ; Mask (1 = transparent).
	moveq	#0,d1 ; Planes 0-1 (high word plane 0).
	moveq	#0,d2 ; Planes 2-3.

	lea		row_pixels,a0
	moveq	#1,d3 ; Step through the row.
	btst	#14,d4
	beq		.pixels_forward

	lea		15(a0),a0
	moveq	#-1,d3

.pixels_forward:
	movem.l	d4-d7,-(sp)
	moveq	#16-1,d7

.pixel_loop:
	add		d0,d0
	add.l	d1,d1
	add.l	d2,d2
	and.l	#$fffefffe,d1 ; (The low words' bits do not carry into the high
	and.l	#$fffefffe,d2 ; words: they are 0 after 16 pixels anyway.)

	moveq	#0,d4
	move.b	(a0),d4
	add		d3,a0
	bne		.opaque

	addq	#1,d0

	bra		.next_pixel

.opaque:
	move.b	(a2,d4.w),d4 ; ST colour.
	lsr.b	#1,d4
	bcc		.no_plane_0
	bset	#16,d1
.no_plane_0:
	lsr.b	#1,d4
	bcc		.no_plane_1
	addq	#1,d1
.no_plane_1:
	lsr.b	#1,d4
	bcc		.no_plane_2
	bset	#16,d2
.no_plane_2:
	lsr.b	#1,d4
	bcc		.next_pixel
	addq	#1,d2

.next_pixel:
	dbf		d7,.pixel_loop

	movem.l	(sp)+,d4-d7

	move	d0,(a3)+
	move.l	d1,(a3)+
	move.l	d2,(a3)+

	cmp		#$ffff,d0
	beq		.empty_row

	tst		d6
	bpl		.first_known

	move	d5,d6

.first_known:
	move	d5,d7

.empty_row:
	addq	#1,d5
	cmp		#16,d5
	bne		.row_loop

	clr		RECORD_ROW_COUNT(a4)
	move	d6,RECORD_FIRST_ROW(a4)
	bmi		.done ; No pixels.

	sub		d6,d7
	addq	#1,d7
	move	d7,RECORD_ROW_COUNT(a4)

.done:
	movem.l	(sp)+,d2-d7/a1-a3/a5

	rts

; a4 = record, d5.w = shift (0-15) -> d0 = its shifted copy (made now), N
; set if the arena is full. Preserves d2/a5.

make_shifted:
	movem.l	d1-d7/a1-a3,-(sp)

	move	RECORD_ROW_COUNT(a4),d0
	mulu	#ROW_BYTES,d0
	bsr		allocate
	beq		.full

	move.l	a0,a3 ; The copy.
	move	d5,d0
	lsl		#2,d0
	move.l	a3,RECORD_SHIFTS(a4,d0.w)

	lea		RECORD_MASTER(a4),a1
	move	RECORD_FIRST_ROW(a4),d0
	mulu	#10,d0
	add		d0,a1
	move	RECORD_ROW_COUNT(a4),d7
	subq	#1,d7

.row_loop:
	; Opaque bits and planes, each shifted into two groups:
	; value << 16 >> shift.

	move	(a1)+,d0
	not		d0 ; Opaque.
	bsr		.shift_word ; d1 = group 1 : group 2.
	not.l	d1
	move.l	d1,d6 ; Masks (1 = keep).

	move	(a1)+,d0
	bsr		.shift_word
	move.l	d1,d2 ; Plane 0.
	move	(a1)+,d0
	bsr		.shift_word
	move.l	d1,d3 ; Plane 1.
	move	(a1)+,d0
	bsr		.shift_word
	move.l	d1,d4 ; Plane 2.
	move	(a1)+,d0
	bsr		.shift_word ; d1: plane 3.

	; Group 1: mask:mask, plane 0:plane 1, plane 2:plane 3 (high words).

	swap	d6
	move	d6,(a3)+
	move	d6,(a3)+
	swap	d2
	move	d2,(a3)+
	swap	d3
	move	d3,(a3)+
	swap	d4
	move	d4,(a3)+
	swap	d1
	move	d1,(a3)+

	; Group 2 (low words).

	swap	d6
	move	d6,(a3)+
	move	d6,(a3)+
	swap	d2
	move	d2,(a3)+
	swap	d3
	move	d3,(a3)+
	swap	d4
	move	d4,(a3)+
	swap	d1
	move	d1,(a3)+

	dbf		d7,.row_loop

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

; d0.w = 16 pixels, d5 = shift -> d1.l = d0 << 16 >> shift.

.shift_word:
	moveq	#0,d1
	move	d0,d1
	swap	d1
	lsr.l	d5,d1

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

	lea		sprite_list,a0
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

	lea		sprite_list,a0
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
record_count:
	ds.w	1
cache_reset_pending:
	ds.b	1
retried:
	ds.b	1

screen_base:
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

	xdef cache_resets

row_pixels:
	ds.b	16
sprite_list:
	ds.l	MAXIMUM_SPRITES*2
sprite_order:
	ds.w	MAXIMUM_SPRITES
bucket_counts:
	ds.w	PRIORITY_BUCKETS
bucket_ends:
	ds.w	PRIORITY_BUCKETS
hash_keys:
	ds.w	HASH_SIZE
hash_records:
	ds.l	HASH_SIZE

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
