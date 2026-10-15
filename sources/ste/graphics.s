
; Atari STE / Mega STE renderer: the Amiga port's chunky renderer (its
; graphics.s without the planar AGA paths), for the 68000. It composes the
; X68000 screen into an 8-bit chunky buffer of palette slots; display.s
; converts that into the ST's bitplanes (C2P).
;
; Layers, back to front (X68000 default priorities; the game swaps text and
; sprites for its bomb flash through video controller register R1):
;
;   - GVRAM page 1 and page 0 (256-colour mode, each with its own scroll
;     registers; colour 0 is transparent),
;   - the text layer (4 bit planes, palette block 0) and the sprites (16x16,
;     4 bits per pixel, 16 palettes), in the order set by R1.
;
; Palette: the graphics palette and the sprite/text palette (2 x 256 X68000
; entries) are merged into one 256-entry palette of distinct colours whenever
; they change (hardware_palette, LoadRGB32 layout as on the Amiga); remap
; tables translate the X68000 indices. palette_load_table says which slots
; changed (all, or the one-colour ranges in palette_update_table).
;
; The buffer has a 16-pixel guard band on every side, which is also the
; offset of the X68000 sprite coordinates: a sprite at (x, y) is drawn at
; buffer position (x, y).
;
; GVRAM is converted once into two 8-bit layers whenever the game builds it
; (amiga_graphics_changed marks it). To fit 4 MB, the layers are kept inside
; the GVRAM shadow: the game writes only the left 256 pixels (bytes 0-511)
; of each 1024-byte GVRAM line, so line n of layer 0 is stored at byte 512
; of page 0's line n and line n of layer 1 at byte 768 (the rotated screen,
; whose builder writes whole lines, is switched off in sz2.s). Every
; graphics index the layers use keeps its own palette slot, so the layers
; are copied without remapping; page 0 is overlaid through per-line runs of
; opaque pixels.
;
; 68000 notes: no scaled indexes or bit fields; runs are copied with long
; moves from even addresses only (a run's source and destination have the
; same parity: both line strides are even).

	xdef prepare_sprite_infos
	xdef compile_sprite
	xdef compile_characters
	xdef render_frame
	xdef amiga_clear_text_planes
	xdef amiga_graphics_changed
	xdef amiga_text_row_written
	xdef initialize_renderer
	xdef release_renderer
	xdef arena_size

	xdef render_buffer
	xdef hardware_palette
	xdef palette_load_table
	xdef palette_update_table
	xdef palette_changed
	xdef frame_sprite_count

	xref SPRITE_DATA_TABLE
	xref CURRENT_SPRITE_DATA_ENTRY
	xref SPRITE_DATA_ADDRESS
	xref L_00C00000
	xref L_00E00000
	xref L_00E80000
	xref L_00E82000
	xref render_line_needed
	ifd __USAGE__
	xref count_sprite_usage
	endif

PCG_PATTERNS=$75e
MAXIMUM_SPRITES=512

GUARD=16
RENDER_WIDTH=256
RENDER_HEIGHT=256
COLOUR_HASH_SIZE=1024 ; Colour -> slot table of full palette rebuilds.
TEXT_GROUP_BITS=8 ; text_draw line: a bit per group of four pixels,
TEXT_DRAW_LINE=TEXT_GROUP_BITS+RENDER_WIDTH/4*8 ; then (mask, colours) per group with text.
RENDER_STRIDE=GUARD+RENDER_WIDTH+GUARD
RENDER_LINES=GUARD+RENDER_HEIGHT+GUARD

GVRAM_PAGE_SIZE=$80000
GVRAM_LINE=1024
TEXT_PLANE_SIZE=$20000
TEXT_LINE=128

LAYER_WIDTH=256
LAYER_LINES=512
LAYER_STRIDE=GVRAM_LINE ; The layers are kept in page 0's lines:
LAYER0_OFFSET=512 ; layer 0 in bytes 512-767,
LAYER1_OFFSET=768 ; layer 1 in bytes 768-1023.
SPAN_BUFFER_SIZE=$10000

; COPY_RUN: copies d3.w bytes (1-256) from (a5)+ to (a1)+ (the same parity)
; through computed jumps into unrolled moves: a leading byte to an even
; address, longs, then the remaining bytes. Uses d0 and d3.

COPY_RUN macro
	move	a1,d0
	lsr		#1,d0
	bcc		.aligned\@

	move.b	(a5)+,(a1)+
	subq	#1,d3

.aligned\@:
	move	d3,d0
	lsr		#2,d0 ; Longs.
	add		d0,d0
	neg		d0
	add		#LAYER_WIDTH/4*2,d0
	jmp		.longs_end\@-LAYER_WIDTH/4*2(pc,d0.w)

	rept	LAYER_WIDTH/4
	move.l	(a5)+,(a1)+
	endr

.longs_end\@:
	moveq	#3,d0
	and		d3,d0
	neg		d0
	add		d0,d0
	jmp		.bytes_end\@(pc,d0.w)

	move.b	(a5)+,(a1)+
	move.b	(a5)+,(a1)+
	move.b	(a5)+,(a1)+

.bytes_end\@:
	endm

; Compiled sprites: one routine per (pattern, flip), generated on first use
; into an arena (GEMDOS memory left after the program, if any). Entry: a6 =
; top left in the render buffer, a5 = remap block of the sprite's palette
; (16 bytes). Uses d0-d7. The pattern's eight most frequent colours are
; loaded into d0-d7, each opaque pixel is one "move.b dN,offset(a6)" or
; "move.b colour(a5),offset(a6)".

COMPILED_ARENA_SIZE=$40000
COMPILED_ARENA_MINIMUM=$8000
ARENA_RESERVE=$10000 ; Left free for TOS.
MAXIMUM_COMPILED_SIZE=8*4+256*6+2

OPCODE_LOAD_COLOUR=$102d ; move.b d16(a5),d0 (| register << 9)
OPCODE_STORE_REGISTER=$1d40 ; move.b d0,d16(a6) (| register)
OPCODE_STORE_MEMORY=$1d6d ; move.b d16(a5),d16(a6)
OPCODE_RTS=$4e75

; CRTC scroll registers (shadow): text X/Y, GR0 X/Y (page 0), GR2 X/Y (page 1).

CRTC_TEXT_X=$14
CRTC_TEXT_Y=$16
CRTC_PAGE0_X=$18
CRTC_PAGE0_Y=$1a
CRTC_PAGE1_X=$20
CRTC_PAGE1_Y=$22

; Video controller (shadow): palettes and R1 (layer priorities).

VC_PRIORITY=$500

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

; d0.l = address of a 16x16 sprite pattern (called while sprites load): the
; pattern data changes, so the compiled sprites are discarded.

compile_sprite:
	st		sprite_cache_reset

	rts

compile_characters:
	rts

; ------------------------------------------------------------------------------
;
; CLEAR_TEXT_PLANE: clears all four text planes (4 x 128 KB). Preserves all
; registers.

amiga_clear_text_planes:
	movem.l	d0-d7/a0-a6,-(sp)

	lea		L_00E00000+TEXT_PLANE_SIZE*4,a6
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7
	move.l	d1,a0
	move.l	d1,a1
	move.l	d1,a2
	move.l	d1,a3
	move.l	d1,a4
	move.l	d1,a5
	move	#TEXT_PLANE_SIZE*4/(13*4*8)-1,d0

.clear:
	rept	8
	movem.l	d1-d7/a0-a5,-(a6) ; 13 longs.
	endr

	dbf		d0,.clear

	; Remainder (the plane size is not a multiple of 13 * 4 * 8).

	move	#(TEXT_PLANE_SIZE*4-(TEXT_PLANE_SIZE*4/(13*4*8))*(13*4*8))/4-1,d0

.remainder:
	move.l	d1,-(a6)
	dbf		d0,.remainder

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; DRAW_CHARACTER: d0.w = text row (0-127, 8 pixel lines each) that has
; changed. Preserves all registers.

amiga_text_row_written:
	movem.l	d0-d1/a0,-(sp)

	and		#127,d0
	move	d0,d1
	lsr		#3,d1
	lea		text_dirty_rows,a0
	bset	d0,(a0,d1.w) ; Bit number modulo 8.

	movem.l	(sp)+,d0-d1/a0

	rts

; ------------------------------------------------------------------------------
;
; Called after the game has (re)built GVRAM: the layers are converted on the
; next frame. Preserves all registers.

amiga_graphics_changed:
	st		layers_dirty

	rts

; ------------------------------------------------------------------------------
;
; The layer line table, and the compiled sprite arena: the largest free
; block less ARENA_RESERVE, up to COMPILED_ARENA_SIZE (none below
; COMPILED_ARENA_MINIMUM: sprites are then drawn by the generic routine).
; Supervisor mode, before the machine is taken over.

initialize_renderer:
	movem.l	d0-d2/a0-a2,-(sp)

	lea		layer_lines,a0
	lea		L_00C00000,a1
	move	#LAYER_LINES-1,d0

.line_table:
	move.l	a1,(a0)+
	lea		LAYER_STRIDE(a1),a1
	dbf		d0,.line_table

	clr.l	arena
	clr.l	arena_size

	pea		-1.w
	move	#72,-(sp) ; Malloc(-1): the largest free block.
	trap	#1
	addq.l	#6,sp

	sub.l	#ARENA_RESERVE,d0
	cmp.l	#COMPILED_ARENA_SIZE,d0
	ble		.size_ok

	move.l	#COMPILED_ARENA_SIZE,d0

.size_ok:
	cmp.l	#COMPILED_ARENA_MINIMUM,d0
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
	st		sprite_cache_reset

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

; ------------------------------------------------------------------------------
;
; Renders the current X68000 screen into render_buffer.

render_frame:
	movem.l	d0-d7/a0-a6,-(sp)

	tst.b	layers_dirty
	beq		.layers_ok

	bsr		build_layers

.layers_ok:
	bsr		update_palette

	ifnd __NO_GRAPHICS__
	bsr		render_graphics
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

	ifnd __NO_TEXT__
	bsr		render_text
	endif
	ifnd __NO_SPRITES__
	bsr		render_sprites
	endif

	bra		.done

.text_in_front:
	ifnd __NO_SPRITES__
	bsr		render_sprites
	endif
	ifnd __NO_TEXT__
	bsr		render_text
	endif

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; Converts GVRAM pages 0 and 1 into layer 0 / layer 1 (graphics palette
; indices; in page 0's right halves), records the indices used, and builds
; the runs of page 0: per line a list of opaque runs and then a list of
; transparent runs, each of (start, length) words ended by start = -1, or no
; lists (span_lines entry 0) if the run buffer is full.

build_layers:
	sf		layers_dirty

	lea		used_graphics,a0
	moveq	#256/4-1,d0

.clear_used:
	clr.l	(a0)+
	dbf		d0,.clear_used

	lea		used_graphics,a3
	moveq	#0,d0

	lea		L_00C00000,a0 ; Page 0.
	lea		L_00C00000+LAYER0_OFFSET,a1
	bsr		.convert_page

	lea		L_00C00000+GVRAM_PAGE_SIZE,a0 ; Page 1.
	lea		L_00C00000+LAYER1_OFFSET,a1
	bsr		.convert_page

	clr.b	used_graphics ; Index 0 is transparent.

	; Runs of page 0.

	lea		L_00C00000+LAYER0_OFFSET,a0
	lea		span_lines,a1
	lea		span_buffer,a2
	lea		span_buffer+SPAN_BUFFER_SIZE-(LAYER_WIDTH+2)*4,a5 ; Room for a full line.
	move	#LAYER_LINES-1,d3

.span_line_loop:
	cmp.l	a5,a2
	bls		.room

	clr.l	(a1)+ ; Buffer full: this line is overlaid pixel by pixel.

	bra		.next_span_line

.room:
	move.l	a2,(a1)+
	moveq	#0,d2 ; x

.find_start:
	cmp		#LAYER_WIDTH,d2
	beq		.line_done

	tst.b	(a0,d2.w)
	bne		.run_start

	addq	#1,d2

	bra		.find_start

.run_start:
	move	d2,d1 ; Start.

.find_end:
	addq	#1,d2
	cmp		#LAYER_WIDTH,d2
	beq		.run_end

	tst.b	(a0,d2.w)
	bne		.find_end

.run_end:
	move	d1,(a2)+
	move	d2,d0
	sub		d1,d0
	move	d0,(a2)+ ; Length.

	bra		.find_start

.line_done:
	move	#-1,(a2)+
	clr		(a2)+

	; Followed by the gaps (transparent runs), where page 1 shows.

	moveq	#0,d2

.find_gap:
	cmp		#LAYER_WIDTH,d2
	beq		.gaps_done

	tst.b	(a0,d2.w)
	beq		.gap_start

	addq	#1,d2

	bra		.find_gap

.gap_start:
	move	d2,d1

.find_gap_end:
	addq	#1,d2
	cmp		#LAYER_WIDTH,d2
	beq		.gap_end

	tst.b	(a0,d2.w)
	beq		.find_gap_end

.gap_end:
	move	d1,(a2)+
	move	d2,d0
	sub		d1,d0
	move	d0,(a2)+

	bra		.find_gap

.gaps_done:
	move	#-1,(a2)+
	clr		(a2)+

.next_span_line:
	lea		LAYER_STRIDE(a0),a0

	dbf		d3,.span_line_loop

	st		layers_ready
	st		palette_rebuild ; New set of used graphics indices.

	rts

; a0 = GVRAM page, a1 = its layer's first line, a3 = used_graphics, d0.l
; upper 24 bits clear: the low byte of each word of the left 256 pixels.

.convert_page:
	move	#LAYER_LINES-1,d3

.line_loop:
	move	#LAYER_WIDTH-1,d2
	move.l	a0,a2
	move.l	a1,a4

.pixel_loop:
	move.b	1(a2),d0
	addq.l	#2,a2
	move.b	d0,(a4)+
	st		(a3,d0.w)

	dbf		d2,.pixel_loop

	lea		GVRAM_LINE(a0),a0
	lea		LAYER_STRIDE(a1),a1

	dbf		d3,.line_loop

	rts

; ------------------------------------------------------------------------------
;
; Builds hardware_palette (LoadRGB32 layout) and the remap tables when the
; X68000 palettes change. Slot 0 is the backdrop (sprite/text palette entry
; 0; graphics index 0 is transparent, so empty layer pixels show it). Every
; graphics index in use keeps its own slot. Sprite and text entries share a
; slot with an identical colour (15 RGB bits; the intensity bit is ignored)
; or take a free slot, or the nearest colour if none is left.

update_palette:
	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.compare:
	cmp.l	(a0)+,(a1)+
	dbne	d0,.compare

	bne		.changed

	tst.b	palette_rebuild
	beq		.done

	bra		.full

.changed:
	tst.b	palette_rebuild
	bne		.full

	bsr		update_palette_entries
	tst.l	d0
	beq		.done ; Updated incrementally.

.full:
	sf		palette_rebuild

	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.copy:
	move.l	(a0)+,(a1)+
	dbf		d0,.copy

	; Empty colour -> slot table.

	lea		colour_hash_keys,a0
	move	#COLOUR_HASH_SIZE/2-1,d0

.clear_hash:
	clr.l	(a0)+
	dbf		d0,.clear_hash

	lea		slot_taken,a0
	moveq	#256/4-1,d0

.clear_taken:
	clr.l	(a0)+
	dbf		d0,.clear_taken

	lea		colour_hash_keys,a2
	lea		colour_hash_slots,a3
	lea		slot_taken,a4

	lea		slot_references,a0
	move	#256/2-1,d0

.clear_references:
	clr.l	(a0)+
	dbf		d0,.clear_references

	moveq	#0,d0 ; The colour key indexes tables: keep the upper word clear.

	; Slot 0: backdrop.

	move	palette_copy+512,d0
	lsr		#1,d0
	moveq	#0,d6
	bsr		.set_slot

	; Graphics indices in use: their own slots.

	lea		palette_copy,a0
	lea		used_graphics,a1
	moveq	#1,d6

.graphics_loop:
	tst.b	(a1,d6.w)
	beq		.next_graphics

	move	d6,d1
	add		d1,d1
	move	(a0,d1.w),d0
	lsr		#1,d0
	bsr		.set_slot

.next_graphics:
	addq	#1,d6
	cmp		#256,d6
	bne		.graphics_loop

	; Sprite and text entries.

	lea		palette_copy+512,a0
	lea		sprite_remap,a1
	clr.b	(a1)+ ; Entry 0: transparent.
	moveq	#1,d7 ; Entry.
	moveq	#1,d6 ; Next slot to try.

.sprite_loop:
	move	d7,d1
	add		d1,d1
	move	(a0,d1.w),d0
	lsr		#1,d0

	bsr		.hash_find
	tst		(a2,d2.w)
	beq		.find_free

	move	(a3,d2.w),d1
	move.b	d1,(a1)+
	and		#$ff,d1
	add		d1,d1
	lea		slot_references,a5
	addq	#1,(a5,d1.w)

	bra		.next_sprite_entry

.find_free:
	cmp		#256,d6
	beq		.nearest

	tst.b	(a4,d6.w)
	beq		.free_found

	addq	#1,d6

	bra		.find_free

.free_found:
	bsr		.set_slot
	move.b	d6,(a1)+
	move	d6,d1
	add		d1,d1
	lea		slot_references,a5
	addq	#1,(a5,d1.w)
	addq	#1,d6

	bra		.next_sprite_entry

.nearest:
	addq.l	#1,palette_overflows
	bsr		.nearest_slot
	move.b	d1,(a1)+
	and		#$ff,d1
	add		d1,d1
	lea		slot_references,a5
	addq	#1,(a5,d1.w)

.next_sprite_entry:
	addq	#1,d7
	cmp		#256,d7
	bne		.sprite_loop

	; Graphics remap: identity (used for the per-pixel fallback).

	lea		graphics_remap,a0
	moveq	#0,d0

.identity:
	move.b	d0,(a0)+
	addq.b	#1,d0
	bne		.identity

	move.l	#256<<16,hardware_palette ; 256 colours from slot 0.
	clr.l	hardware_palette+4+256*3*4
	move.l	#hardware_palette,palette_load_table

	st		palette_changed

.done:
	rts

; d0 = colour key, d6 = slot: claims the slot, sets its colour and registers
; the colour (the first slot of a colour is the one found later).

.set_slot:
	st		(a4,d6.w)

	bsr		.hash_find
	tst		(a2,d2.w)
	bne		.registered

	move	d0,d1
	addq	#1,d1
	move	d1,(a2,d2.w)
	move	d6,(a3,d2.w)

.registered:
	lea		hardware_palette+4,a5
	move	d6,d1
	mulu	#12,d1
	add.l	d1,a5

	move	d0,d1
	lsr		#5,d1
	and		#$1f,d1 ; R
	bsr		expand_component
	move.l	d2,(a5)+

	move	d0,d1
	lsr		#8,d1
	lsr		#2,d1
	and		#$1f,d1 ; G
	bsr		expand_component
	move.l	d2,(a5)+

	move	d0,d1
	and		#$1f,d1 ; B
	bsr		expand_component
	move.l	d2,(a5)

	rts

; d0 = colour key -> d2 = byte offset of its entry in the colour hash (keys
; + 1 in colour_hash_keys, 0 = empty; slots in colour_hash_slots, both word
; tables), or of the empty entry where it belongs. Uses d1. Linear probing;
; the table has room for every colour of the 512 palette entries.

.hash_find:
	move	d0,d1
	addq	#1,d1
	move	d0,d2
	mulu	#40503,d2
	swap	d2
	and		#COLOUR_HASH_SIZE-1,d2
	add		d2,d2

.probe:
	cmp		(a2,d2.w),d1
	beq		.hash_done

	tst		(a2,d2.w)
	beq		.hash_done

	addq	#2,d2
	and		#(COLOUR_HASH_SIZE-1)*2,d2

	bra		.probe

.hash_done:
	rts

; d0 = colour key -> d1 = taken slot with the nearest colour.

.nearest_slot:
	movem.l	d0/d2-d7/a5,-(sp)

	move	d0,d2
	lsr		#5,d2
	and		#$1f,d2 ; R
	move	d0,d3
	lsr		#8,d3
	lsr		#2,d3
	and		#$1f,d3 ; G
	and		#$1f,d0 ; B

	lea		hardware_palette+4,a5
	move.l	#$7fffffff,d7 ; Best distance.
	moveq	#0,d1 ; Best slot.
	moveq	#0,d6 ; Slot.

.slot_loop:
	tst.b	(a4,d6.w)
	beq		.next_slot

	moveq	#0,d4
	move.b	(a5),d4
	lsr.b	#3,d4
	sub		d2,d4
	muls	d4,d4
	moveq	#0,d5
	move.b	4(a5),d5
	lsr.b	#3,d5
	sub		d3,d5
	muls	d5,d5
	add.l	d5,d4
	moveq	#0,d5
	move.b	8(a5),d5
	lsr.b	#3,d5
	sub		d0,d5
	muls	d5,d5
	add.l	d5,d4

	cmp.l	d7,d4
	bcc		.next_slot

	move.l	d4,d7
	move	d6,d1

.next_slot:
	lea		12(a5),a5
	addq	#1,d6
	cmp		#256,d6
	bne		.slot_loop

	movem.l	(sp)+,d0/d2-d7/a5

	rts

; ------------------------------------------------------------------------------
;
; Incremental palette update (the game cycles a few entries every frame):
; recolours the slots of the changed entries, moves a changed sprite/text
; entry that shares its slot to a free slot, and builds palette_update_table
; (LoadRGB32 ranges of one colour each). Returns d0 = 0 if done, -1 if a full
; rebuild is needed (a graphics slot shared with sprite entries changed, or
; no free slot is left).

update_palette_entries:
	movem.l	d1-d7/a0-a6,-(sp)

	lea		L_00E82000,a0
	lea		palette_copy,a1
	lea		palette_update_table,a6
	lea		slot_taken,a4
	lea		slot_references,a5
	lea		used_graphics,a3
	moveq	#0,d0

	; Graphics entries (identity slots). d7 = entry, d5 = entry * 2.

	moveq	#0,d7
	moveq	#0,d5

.graphics_loop:
	move	(a0,d5.w),d0
	cmp		(a1,d5.w),d0
	beq		.next_graphics

	tst		d7
	beq		.next_graphics ; Index 0: transparent.

	tst.b	(a3,d7.w)
	beq		.next_graphics ; Not shown.

	tst		(a5,d5.w)
	bne		.full ; Shared with sprite entries.

	lsr		#1,d0
	move	d7,d6
	bsr		.recolour

.next_graphics:
	addq	#1,d7
	addq	#2,d5
	cmp		#256,d7
	bne		.graphics_loop

	; Sprite/text entry 0: the backdrop in slot 0.

	move	512(a0),d0
	cmp		512(a1),d0
	beq		.sprite_entries

	tst		(a5)
	bne		.full ; Sprite entries share the backdrop's slot.

	lsr		#1,d0
	moveq	#0,d6
	bsr		.recolour

.sprite_entries:
	lea		512(a0),a0
	lea		512(a1),a1
	lea		sprite_remap,a2
	moveq	#1,d7
	moveq	#2,d5

.sprite_loop:
	move	(a0,d5.w),d0
	cmp		(a1,d5.w),d0
	beq		.next_sprite

	lsr		#1,d0
	moveq	#0,d6
	move.b	(a2,d7.w),d6 ; Current slot.
	move	d6,d4
	add		d4,d4 ; Slot * 2.
	tst		d6
	beq		.move_entry ; The backdrop's slot.

	tst.b	(a3,d6.w)
	bne		.move_entry ; A graphics slot: cannot be recoloured for it.

	cmp		#1,(a5,d4.w)
	bne		.move_entry ; Shared.

	bsr		.recolour

	bra		.next_sprite

.move_entry:
	subq	#1,(a5,d4.w)

	moveq	#1,d6

.find_free:
	tst.b	(a4,d6.w)
	beq		.free

	addq	#1,d6
	cmp		#256,d6
	bne		.find_free

	bra		.full

.free:
	st		(a4,d6.w)
	move	d6,d4
	add		d4,d4
	move	#1,(a5,d4.w)
	move.b	d6,(a2,d7.w)
	bsr		.recolour

.next_sprite:
	addq	#1,d7
	addq	#2,d5
	cmp		#256,d7
	bne		.sprite_loop

	clr.l	(a6) ; End of the LoadRGB32 table.
	move.l	#palette_update_table,palette_load_table
	st		palette_changed

	; Take over the new palette.

	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.copy:
	move.l	(a0)+,(a1)+
	dbf		d0,.copy

	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#0,d0

	rts

.full:
	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#-1,d0

	rts

; d0 = colour key, d6 = slot: sets the slot's colour in hardware_palette and
; appends a one-colour range to palette_update_table (a6).

.recolour:
	movem.l	d0-d2/a0,-(sp)

	lea		hardware_palette+4,a0
	move	d6,d1
	mulu	#12,d1
	add.l	d1,a0

	move.l	#1<<16,d1
	move	d6,d1
	move.l	d1,(a6)+ ; One colour at this slot.

	move	d0,d1
	lsr		#5,d1
	and		#$1f,d1 ; R
	bsr		expand_component
	move.l	d2,(a0)+
	move.l	d2,(a6)+

	move	d0,d1
	lsr		#8,d1
	lsr		#2,d1
	and		#$1f,d1 ; G
	bsr		expand_component
	move.l	d2,(a0)+
	move.l	d2,(a6)+

	move	d0,d1
	and		#$1f,d1 ; B
	bsr		expand_component
	move.l	d2,(a0)
	move.l	d2,(a6)+

	movem.l	(sp)+,d0-d2/a0

	rts

; d1 = 5-bit component -> d2 = 8 bits replicated into 32 bits.

expand_component:
	move	d1,d2
	lsl		#3,d2
	lsr		#2,d1
	or		d1,d2 ; 8 bits.
	move.b	d2,d1
	lsl		#8,d2
	move.b	d1,d2
	move	d2,d1
	swap	d2
	move	d1,d2

	rts

; ------------------------------------------------------------------------------
;
; GVRAM pages 0 and 1 (low byte of each word = graphics palette index), from
; the layers. Only the lines display.s shows (render_line_needed) are
; composed. The scroll registers are read once, so a tick during the
; composition cannot split the picture.

render_graphics:
	tst.b	layers_ready
	beq		render_graphics_per_pixel

	move	L_00E80000+CRTC_PAGE0_X,d0
	or		L_00E80000+CRTC_PAGE1_X,d0
	and		#511,d0
	bne		render_graphics_per_pixel ; Horizontal scroll (rotated screen).

	move	L_00E80000+CRTC_PAGE0_Y,page0_y
	move	L_00E80000+CRTC_PAGE1_Y,page1_y

	lea		span_lines,a3
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2

	moveq	#0,d7 ; Line.

.line_loop:
	lea		render_line_needed,a0
	tst.b	(a0,d7.w)
	beq		.next_line

	; Page 1 line (index 0 shows the backdrop in slot 0).

	lea		layer_lines,a0
	move	page1_y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	add		d1,d1
	add		d1,d1
	move.l	(a0,d1.w),d0
	add.l	#LAYER1_OFFSET,d0
	move.l	d0,page1_line

	; Page 0 line and its runs.

	move	page0_y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	add		d1,d1
	add		d1,d1
	move.l	(a0,d1.w),a4
	lea		LAYER0_OFFSET(a4),a4 ; Layer line.
	move.l	(a3,d1.w),d0 ; Runs of this line.
	bne		.with_runs

	; No run lists (run buffer full): page 1, then page 0 pixel by pixel.

	move.l	page1_line,a1
	move.l	a2,a5

	rept	LAYER_WIDTH/4
	move.l	(a1)+,(a5)+
	endr

	bra		.pixel_line

.with_runs:
	move.l	d0,a6

	; Page 0's opaque runs, then page 1 in the gaps between them: every
	; pixel is written once.

.run_loop:
	move	(a6)+,d2 ; Start.
	bmi		.gaps

	move	(a6)+,d3 ; Length.
	lea		(a4,d2.w),a5
	lea		(a2,d2.w),a1

	COPY_RUN

	bra		.run_loop

.gaps:
	addq.l	#2,a6 ; Rest of the end marker.
	move.l	page1_line,a4

.gap_loop:
	move	(a6)+,d2 ; Start.
	bmi		.next_line

	move	(a6)+,d3 ; Length.
	lea		(a4,d2.w),a5
	lea		(a2,d2.w),a1

	COPY_RUN

	bra		.gap_loop

.pixel_line:
	; No run list (run buffer full): overlay the non-zero pixels.

	move.l	a2,a1
	move	#LAYER_WIDTH-1,d3

.pixel_loop:
	move.b	(a4)+,d0
	beq		.transparent

	move.b	d0,(a1)

.transparent:
	addq.l	#1,a1

	dbf		d3,.pixel_loop

.next_line:
	lea		RENDER_STRIDE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; Fallback: straight from GVRAM, pixel by pixel, with any scroll.

render_graphics_per_pixel:
	lea		L_00C00000,a0 ; Page 0.
	lea		L_00C00000+GVRAM_PAGE_SIZE,a1 ; Page 1.
	lea		graphics_remap,a3
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2

	moveq	#0,d0
	move.b	sprite_remap,d4 ; Backdrop: sprite/text palette entry 0.

	move	L_00E80000+CRTC_PAGE0_X,d2
	and		#511,d2
	add		d2,d2 ; Byte offsets of the words.
	move	L_00E80000+CRTC_PAGE1_X,d3
	and		#511,d3
	add		d3,d3

	moveq	#0,d7 ; Line.

.line_loop:
	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE0_Y,d1
	add		d7,d1
	and		#511,d1
	lsl.l	#8,d1
	lsl.l	#2,d1 ; * GVRAM_LINE
	move.l	a0,a4
	add.l	d1,a4

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE1_Y,d1
	add		d7,d1
	and		#511,d1
	lsl.l	#8,d1
	lsl.l	#2,d1
	move.l	a1,a5
	add.l	d1,a5

	move	d2,d5 ; Page 0 x * 2.
	move	d3,d6 ; Page 1 x * 2.
	move	#RENDER_WIDTH-1,d1

.pixel_loop:
	move.b	1(a4,d5.w),d0
	bne		.opaque

	move.b	1(a5,d6.w),d0
	beq		.backdrop

.opaque:
	move.b	(a3,d0.w),(a2)+

	bra		.next_pixel

.backdrop:
	move.b	d4,(a2)+

.next_pixel:
	addq	#2,d5
	and		#1023,d5
	addq	#2,d6
	and		#1023,d6

	dbf		d1,.pixel_loop

	lea		RENDER_STRIDE-RENDER_WIDTH(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; ------------------------------------------------------------------------------
;
; Text layer: 4 bit planes of 1024 x 1024 pixels, palette block 0, colour 0
; transparent; the horizontal scroll is applied in whole bytes. The visible
; window is kept converted in text_draw: per line, its four-pixel groups
; with text, each as a mask and palette-mapped colours, so drawing is one
; masked long write per group. Lines are converted again only when their
; character row was written, the scroll changed or the text colours' palette
; slots changed, and only lines with text are drawn.

render_text:
	bsr		prepare_text

	lea		text_line_used,a1
	lea		text_draw,a4
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2
	moveq	#0,d7 ; Line.

.line_loop:
	tst.b	(a1,d7.w)
	beq		.next_line

	; dst = (dst & ~mask) | colour for each group whose bit is set, in
	; group order: groups 0-31, then 32-63 (128 bytes to the right).

	lea		TEXT_GROUP_BITS(a4),a5
	move.l	a2,a6
	move.l	(a4),d4
	bsr		.draw_groups

	lea		RENDER_WIDTH/2(a2),a6
	move.l	4(a4),d4
	bsr		.draw_groups

.next_line:
	lea		TEXT_DRAW_LINE(a4),a4
	lea		RENDER_STRIDE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; d4 = group bits (bit 31 = the first group), a6 = the first group's pixels,
; a5 = (mask, colours) of each group with its bit set, in order.

.draw_groups:
	tst.l	d4
	beq		.groups_done

.find_group:
	add.l	d4,d4
	bcs		.group

	addq.l	#4,a6

	bra		.find_group

.group:
	move.l	(a5)+,d2
	move.l	(a5)+,d3
	not.l	d2
	beq		.full_group

	and.l	(a6),d2
	or.l	d3,d2
	move.l	d2,(a6)+

	bra		.draw_groups

.full_group:
	move.l	d3,(a6)+

	bra		.draw_groups

.groups_done:
	rts

; Brings text_draw up to date: when the text colours' palette slots have
; changed every visible line is converted again, otherwise the lines whose
; character row was written.

prepare_text:
	lea		sprite_remap,a3
	lea		text_remap,a0
	move.l	(a3),d0
	cmp.l	(a0),d0
	bne		.remap_changed
	move.l	4(a3),d0
	cmp.l	4(a0),d0
	bne		.remap_changed
	move.l	8(a3),d0
	cmp.l	8(a0),d0
	bne		.remap_changed
	move.l	12(a3),d0
	cmp.l	12(a0),d0
	beq		.remap_same

.remap_changed:
	move.l	(a3),(a0)
	move.l	4(a3),4(a0)
	move.l	8(a3),8(a0)
	move.l	12(a3),12(a0)

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

.remap_same:
	bra		update_text_overlay

; Converts the visible lines whose character row is dirty into text_draw:
; per line, a bit for each of the 64 groups of four pixels that has text,
; then for each of those groups (in order) its mask and palette-mapped
; colours (transparent pixels 0 in both).

update_text_overlay:
	; A scroll change makes the whole window stale.

	move	L_00E80000+CRTC_TEXT_X,d0
	swap	d0
	move	L_00E80000+CRTC_TEXT_Y,d0
	cmp.l	text_overlay_scroll,d0
	beq		.scroll_same

	move.l	d0,text_overlay_scroll

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

.scroll_same:
	lea		text_draw,a2
	lea		text_dirty_rows,a6
	lea		sprite_remap,a3

	move	L_00E80000+CRTC_TEXT_X,d1
	lsr		#3,d1
	and		#TEXT_LINE-1,d1
	move	d1,a1 ; Byte column.

	moveq	#0,d7 ; Line.

.line_loop:
	moveq	#0,d1
	move	L_00E80000+CRTC_TEXT_Y,d1
	add		d7,d1
	and		#1023,d1

	move	d1,d0
	lsr		#3,d0 ; Character row.
	move	d0,d2
	lsr		#3,d2
	btst	d0,(a6,d2.w)
	beq		.next_line

	lsl.l	#7,d1 ; * TEXT_LINE
	lea		L_00E00000,a4
	add.l	d1,a4

	clr.l	(a2)
	clr.l	4(a2)
	lea		TEXT_GROUP_BITS(a2),a5

	lea		text_line_used,a3
	sf		(a3,d7.w)
	lea		sprite_remap,a3

	moveq	#0,d6 ; Byte within the line.

.byte_loop:
	move	a1,d1
	add		d6,d1
	and		#TEXT_LINE-1,d1

	lea		(a4,d1.w),a0
	move.b	(a0),d3 ; Plane 0.
	add.l	#TEXT_PLANE_SIZE,a0
	move.b	(a0),d4 ; Plane 1.
	add.l	#TEXT_PLANE_SIZE,a0
	move.b	(a0),d5 ; Plane 2.
	add.l	#TEXT_PLANE_SIZE,a0
	move.b	(a0),d1 ; Plane 3.

	move.b	d3,d0
	or.b	d4,d0
	or.b	d5,d0
	or.b	d1,d0
	beq		.next_byte

	lea		text_line_used,a3
	st		(a3,d7.w)
	lea		sprite_remap,a3

	; The byte's two groups (left four pixels first).

	bsr		.convert_group
	tst.l	(a5)
	beq		.left_empty

	move	d6,d0
	add		d0,d0
	bsr		.set_group_bit
	addq.l	#8,a5

.left_empty:
	bsr		.convert_group
	tst.l	(a5)
	beq		.next_byte

	move	d6,d0
	add		d0,d0
	addq	#1,d0
	bsr		.set_group_bit
	addq.l	#8,a5

.next_byte:
	addq	#1,d6
	cmp		#RENDER_WIDTH/8,d6
	bne		.byte_loop

.next_line:
	lea		TEXT_DRAW_LINE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	; All rows are up to date (rows outside the window are reconverted when
	; the scroll brings them in).

	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)

	rts

; d0 = group (0-63): sets its bit in the line's group bits at (a2), the
; first group in the top bit. Uses d0 and d2.

.set_group_bit:
	move	d0,d2
	lsr		#3,d2
	not		d0 ; Bit 7 - (group & 7) of the byte.
	bset	d0,(a2,d2.w)

	rts

; Four pixels from the top bits of the planes (d3 plane 0, d4 plane 1,
; d5 plane 2, d1 plane 3; shifted out): mask bytes at (a5), mapped colours
; at 4(a5). Colour = plane 3 << 3 | plane 2 << 2 | plane 1 << 1 | plane 0.

.convert_group:
	moveq	#4-1,d2

.pixel_loop:
	moveq	#0,d0
	add.b	d1,d1
	addx.b	d0,d0
	add.b	d5,d5
	addx.b	d0,d0
	add.b	d4,d4
	addx.b	d0,d0
	add.b	d3,d3
	addx.b	d0,d0
	tst.b	d0 ; (ADDX leaves Z from the ADD before it.)
	beq		.transparent

	st		(a5)+
	move.b	(a3,d0.w),3(a5)

	dbf		d2,.pixel_loop

	subq.l	#4,a5

	rts

.transparent:
	clr.b	(a5)+
	clr.b	3(a5)

	dbf		d2,.pixel_loop

	subq.l	#4,a5

	rts

; ------------------------------------------------------------------------------
;
; Sprites in priority order, as on the Falcon: 32 buckets by attribute bits
; 4-0 drawn from 0 to 31 (later is in front), the entries of a bucket in
; reverse list order.

; sprite_order = the sprites' list indices in drawing order. Returns d7 =
; the number of sprites (Z set if none or no pattern data).

order_sprites:
	move	render_sprite_count,d7
	beq		.done

	move.l	SPRITE_DATA_ADDRESS,d0
	beq		.none

	; Count per bucket.

	lea		bucket_counts,a0
	moveq	#32/2-1,d0

.clear_counts:
	clr.l	(a0)+
	dbf		d0,.clear_counts

	lea		sprite_list,a0
	lea		bucket_counts,a1
	move	d7,d0
	subq	#1,d0

.count_loop:
	moveq	#$1f,d1
	and		6(a0),d1
	add		d1,d1
	addq	#1,(a1,d1.w)
	addq.l	#8,a0

	dbf		d0,.count_loop

	; Bucket end offsets: entries are stored backwards from each end, so a
	; bucket ends up in reverse list order.

	lea		bucket_counts,a1
	lea		bucket_ends,a2
	moveq	#0,d1
	moveq	#32-1,d0

.offset_loop:
	add		(a1)+,d1
	move	d1,(a2)+

	dbf		d0,.offset_loop

	lea		sprite_list,a0
	lea		bucket_ends,a2
	lea		sprite_order,a3
	moveq	#0,d2 ; Entry index.
	move	d7,d0
	subq	#1,d0

.order_loop:
	moveq	#$1f,d1
	and		6(a0),d1
	add		d1,d1
	move	(a2,d1.w),d3
	sub		#1,d3
	move	d3,(a2,d1.w)
	add		d3,d3
	move	d2,(a3,d3.w)

	addq	#1,d2
	addq.l	#8,a0

	dbf		d0,.order_loop

	; Within a bucket the order above is reversed already; the buckets
	; follow in ascending order.

	tst		d7

.done:
	rts

.none:
	moveq	#0,d7

	rts

; Draws the sprites into render_buffer.

render_sprites:
	bsr		order_sprites
	beq		.done

	tst.b	sprite_cache_reset
	beq		.cache_ok

	bsr		reset_sprite_cache

.cache_ok:
	lea		sprite_order,a6
	move	d7,d6
	subq	#1,d6

.sprite_loop:
	move	(a6)+,d0
	lsl		#3,d0
	lea		sprite_list,a0
	add		d0,a0

	moveq	#0,d0
	move	4(a0),d0 ; Pattern.
	cmp		#PCG_PATTERNS,d0
	bcc		.next_sprite

	move	d0,d4 ; Pattern index.
	move.l	SPRITE_DATA_ADDRESS,a1
	lsl.l	#7,d0
	add.l	d0,a1 ; Pattern data.

	move	6(a0),d5 ; Attributes.
	move	d5,d0
	lsr		#4,d0
	and		#$f0,d0
	lea		sprite_remap,a3
	add		d0,a3 ; Palette block.

	moveq	#0,d0
	move	(a0),d0 ; x
	cmp		#RENDER_STRIDE-16,d0
	bhi		.next_sprite

	moveq	#0,d1
	move	2(a0),d1 ; y
	cmp		#RENDER_LINES-16,d1
	bhi		.next_sprite

	mulu	#RENDER_STRIDE,d1
	lea		render_buffer,a2
	add.l	d1,a2
	add.l	d0,a2 ; Top left.

	; Compiled routine for (pattern, flip): attributes bit 14 = horizontal,
	; bit 15 = vertical flip.

	moveq	#0,d0
	move	d5,d0
	rol		#2,d0
	and		#3,d0
	lsl		#2,d4
	add		d4,d0 ; Variant: pattern * 4 + flip.
	move	d0,d1
	add		d1,d1
	add		d1,d1
	lea		compiled_table,a4
	move.l	(a4,d1.w),d1
	bne		.call_compiled

	tst.l	arena
	beq		.generic

	bsr		compile_sprite_variant
	move.l	d0,d1
	beq		.generic

.call_compiled:
	movem.l	d6/a6,-(sp)
	move.l	d1,a0
	move.l	a2,a6
	move.l	a3,a5
	jsr		(a0)
	movem.l	(sp)+,d6/a6

	bra		.next_sprite

.generic:
	; Rows: d4 = source row step (4 bytes, or -4 for a vertical flip).

	moveq	#4,d4
	btst	#15,d5
	beq		.no_vertical_flip

	lea		15*4(a1),a1
	moveq	#-4,d4

.no_vertical_flip:
	moveq	#16-1,d3

.row_loop:
	move.l	(a1),d0 ; Left 8 pixels.
	move.l	64(a1),d1 ; Right 8 pixels.
	add		d4,a1

	btst	#14,d5
	bne		.flipped_row

	move.l	a2,a4
	bsr		.draw_8
	move.l	d1,d0
	bsr		.draw_8

	bra		.next_row

.flipped_row:
	lea		16(a2),a4
	bsr		.draw_8_flipped
	move.l	d1,d0
	bsr		.draw_8_flipped

.next_row:
	lea		RENDER_STRIDE(a2),a2

	dbf		d3,.row_loop

.next_sprite:
	dbf		d6,.sprite_loop

.done:
	rts

; d0 = 8 pixels (high nibble = left); a4 = destination, advanced by 8.

.draw_8:
	moveq	#8-1,d2

.draw_loop:
	rol.l	#4,d0
	moveq	#$f,d7
	and		d0,d7
	beq		.skip

	move.b	(a3,d7.w),(a4)

.skip:
	addq.l	#1,a4

	dbf		d2,.draw_loop

	rts

; Same, mirrored: a4 = one past the right end, moved left by 8.

.draw_8_flipped:
	moveq	#8-1,d2

.flipped_loop:
	rol.l	#4,d0
	moveq	#$f,d7
	and		d0,d7
	subq.l	#1,a4
	tst		d7
	beq		.flipped_skip

	move.b	(a3,d7.w),(a4)

.flipped_skip:
	dbf		d2,.flipped_loop

	rts

; ------------------------------------------------------------------------------

reset_sprite_cache:
	sf		sprite_cache_reset

	move.l	arena,arena_next
	move.l	arena,d0
	add.l	arena_size,d0
	move.l	d0,arena_end
	clr.l	compiled_sprite_count

	lea		compiled_table,a0
	move	#PCG_PATTERNS*4-1,d0

.clear:
	clr.l	(a0)+
	dbf		d0,.clear

	rts

; d0.l = variant (pattern * 4 + flip; bit 0 = horizontal, bit 1 = vertical
; flip), a1 = pattern data. Compiles the routine into the arena and enters it
; in compiled_table. Returns d0 = routine, or 0 if the arena is full.
; Preserves all other registers. (The 68000 has no cache, and the Mega STE's
; cache sees the CPU's writes: the new code can run at once.)

compile_sprite_variant:
	movem.l	d1-d7/a0-a6,-(sp)

	move.l	arena_end,d1
	sub.l	arena_next,d1
	cmp.l	#MAXIMUM_COMPILED_SIZE,d1
	bcs		.full

	move.l	d0,d7 ; Variant.

	; Decode into a 16 x 16 matrix of colour indices, flips applied.

	lea		decode_matrix,a2
	moveq	#0,d3 ; Row.

.decode_row:
	move	d3,d1
	btst	#1,d7
	beq		.row_ok

	moveq	#15,d1
	sub		d3,d1 ; Vertical flip.

.row_ok:
	lsl		#2,d1
	move.l	(a1,d1.w),d4 ; Left 8 pixels.
	move.l	64(a1,d1.w),d5 ; Right 8 pixels.

	moveq	#0,d2 ; x

.decode_pixel:
	cmp		#8,d2
	bne		.same_half

	move.l	d5,d4

.same_half:
	rol.l	#4,d4
	moveq	#$f,d0
	and		d4,d0

	move	d2,d1
	btst	#0,d7
	beq		.column_ok

	moveq	#15,d1
	sub		d2,d1 ; Horizontal flip.

.column_ok:
	move	d3,d6
	lsl		#4,d6
	add		d1,d6
	move.b	d0,(a2,d6.w)

	addq	#1,d2
	cmp		#16,d2
	bne		.decode_pixel

	addq	#1,d3
	cmp		#16,d3
	bne		.decode_row

	; Colour frequencies.

	lea		colour_counts,a3
	moveq	#16/2-1,d0

.clear_counts:
	clr.l	(a3)+
	dbf		d0,.clear_counts

	lea		colour_counts,a3
	move	#256-1,d1
	moveq	#0,d0

.count:
	move.b	(a2)+,d0
	add.b	d0,d0
	addq	#1,(a3,d0.w)
	dbf		d1,.count

	; Registers d0-d7 for the eight most frequent colours (1-15).

	lea		colour_registers,a4
	moveq	#16/4-1,d0

.clear_registers:
	move.l	#-1,(a4)+
	dbf		d0,.clear_registers

	lea		colour_registers,a4
	moveq	#0,d5 ; Register.

.choose:
	moveq	#0,d3 ; Best count.
	moveq	#0,d4 ; Best colour.
	moveq	#1,d1

.candidate:
	tst.b	(a4,d1.w)
	bpl		.next_candidate ; Already has a register.

	move	d1,d0
	add		d0,d0
	move	(a3,d0.w),d2
	cmp		d3,d2
	bls		.next_candidate

	move	d2,d3
	move	d1,d4

.next_candidate:
	addq	#1,d1
	cmp		#16,d1
	bne		.candidate

	tst		d3
	beq		.chosen

	move.b	d5,(a4,d4.w)
	addq	#1,d5
	cmp		#8,d5
	bne		.choose

.chosen:
	; Emit: load the register colours, then one move per opaque pixel.

	move.l	arena_next,a0
	move.l	a0,a6 ; Routine.
	moveq	#1,d1

.prologue:
	moveq	#0,d0
	move.b	(a4,d1.w),d0
	bmi		.next_prologue

	lsl		#8,d0
	add		d0,d0 ; Register << 9.
	add		#OPCODE_LOAD_COLOUR,d0
	move	d0,(a0)+
	move	d1,(a0)+ ; Colour offset in the remap block.

.next_prologue:
	addq	#1,d1
	cmp		#16,d1
	bne		.prologue

	lea		decode_matrix,a2
	moveq	#0,d3 ; Row.

.emit_row:
	moveq	#0,d2 ; x

.emit_pixel:
	moveq	#0,d0
	move.b	(a2)+,d0
	beq		.next_emit

	move	d3,d1
	mulu	#RENDER_STRIDE,d1
	add		d2,d1 ; Offset.

	move.b	(a4,d0.w),d4
	bmi		.from_memory

	ext		d4
	add		#OPCODE_STORE_REGISTER,d4
	move	d4,(a0)+
	move	d1,(a0)+

	bra		.next_emit

.from_memory:
	move	#OPCODE_STORE_MEMORY,(a0)+
	move	d0,(a0)+
	move	d1,(a0)+

.next_emit:
	addq	#1,d2
	cmp		#16,d2
	bne		.emit_pixel

	addq	#1,d3
	cmp		#16,d3
	bne		.emit_row

	move	#OPCODE_RTS,(a0)+
	move.l	a0,arena_next

	lea		compiled_table,a1
	lsl.l	#2,d7
	move.l	a6,(a1,d7.l)
	addq.l	#1,compiled_sprite_count

	move.l	a6,d0

	movem.l	(sp)+,d1-d7/a0-a6

	rts

.full:
	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#0,d0

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

layers_dirty: ; Build the layers on the first frame (GVRAM is empty until the
	dc.b	-1 ; game builds it, then amiga_graphics_changed marks it).

	even

text_dirty_rows: ; Bit per text character row (128); all dirty at start.
	dcb.b	16,$ff

text_overlay_scroll:
	dc.l	-1

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

frame_sprite_count:
	ds.w	1
render_sprite_count:
	ds.w	1
page0_y:
	ds.w	1
page1_y:
	ds.w	1
palette_changed:
	ds.b	1
palette_rebuild:
	ds.b	1
layers_ready:
	ds.b	1
sprite_cache_reset:
	ds.b	1

palette_overflows:
	ds.l	1
compiled_sprite_count:
	ds.l	1
arena:
	ds.l	1
arena_size:
	ds.l	1
arena_next:
	ds.l	1
arena_end:
	ds.l	1
page1_line:
	ds.l	1

compiled_table:
	ds.l	PCG_PATTERNS*4

decode_matrix:
	ds.b	256

colour_counts:
	ds.w	16

colour_registers:
	ds.b	16

sprite_list:
	ds.l	MAXIMUM_SPRITES*2

sprite_order:
	ds.w	MAXIMUM_SPRITES

bucket_counts:
	ds.w	32

bucket_ends:
	ds.w	32

palette_copy:
	ds.w	512

slot_references: ; Sprite/text entries per slot.
	ds.w	256

palette_load_table: ; The slots changed since display.s last took them.
	ds.l	1

palette_update_table: ; Up to 512 one-colour ranges and the terminator.
	ds.l	512*4+1

graphics_remap: ; Followed directly by sprite_remap (filled in one loop).
	ds.b	256
sprite_remap:
	ds.b	256

used_graphics:
	ds.b	256

slot_taken:
	ds.b	256

layer_lines: ; Per layer line: its GVRAM page 0 line.
	ds.l	LAYER_LINES

span_lines:
	ds.l	LAYER_LINES

span_buffer:
	ds.b	SPAN_BUFFER_SIZE

text_line_used:
	ds.b	RENDER_HEIGHT

text_remap: ; sprite_remap of the text colours (0-15) the lines were mapped with.
	ds.b	16

text_draw: ; Per line: group bits, then (mask, mapped colours) per group with text.
	ds.b	TEXT_DRAW_LINE*RENDER_HEIGHT

colour_hash_keys:
	ds.w	COLOUR_HASH_SIZE

colour_hash_slots:
	ds.w	COLOUR_HASH_SIZE

; LoadRGB32 layout: count.w, first.w, 256 R, G, B longs, terminator.

hardware_palette:
	ds.l	1+256*3+1

render_buffer:
	ds.b	RENDER_STRIDE*RENDER_LINES

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
