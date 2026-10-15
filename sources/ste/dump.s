
; Data for the colour tools (tools/ste/palette_map.py), from measurement runs
; (a frame limit set):
;
; - USAGE.BIN: how many pixels of each sprite/text palette entry the game
;   shows, summed over its frames ('CRSU', frames, 256 longs: entry
;   palette * 16 + colour), then per pattern the palettes it was drawn with
;   (2048 words, bit n = palette n). Counted at XSP_OUT from the sprite list
;   (each pattern's colour histogram, made on first use) for displayed
;   sprites (priority $10 and up); text is weighted by the tool itself.
; - GRAPHICS.BIN (-D__DUMP__ builds with GVRAM): the Amiga port's 'CRSG'
;   dump (GVRAM pages 0-1, the video controller palettes, the patterns'
;   palettes as above, the sprite patterns), read by tests/amiga/graphics_summary.py
;   and the colour tools.
; - The stages the game reached (the stage word, PLAYER_SCORE + 4), for the
;   exit report.

	xdef count_sprite_usage
	xdef record_stage
	xdef write_usage
	xdef print_stages

	ifd __DUMP__
	xdef write_graphics_dump
	xref L_00C00000
	endif

	xref SPRITE_DATA_TABLE
	xref SPRITE_DATA_ADDRESS
	xref L_00E82000
	xref PLAYER_SCORE
	xref print_text
	xref print_hex

PCG_PATTERNS=$75e

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; d0.w = number of sprites in SPRITE_DATA_TABLE. Preserves all registers.

count_sprite_usage:
	movem.l	d0-d4/a0-a3,-(sp)

	addq.l	#1,usage_frames

	move.l	SPRITE_DATA_ADDRESS,d1
	beq		.done

	lea		SPRITE_DATA_TABLE,a0
	subq	#1,d0
	bmi		.done

.sprite_loop:
	moveq	#0,d1
	move.b	7(a0),d1 ; Priority.
	cmp.b	#$10,d1
	bcs		.next_sprite ; Not displayed.

	moveq	#0,d1
	move	4(a0),d1 ; Pattern.
	cmp		#PCG_PATTERNS,d1
	bcc		.next_sprite

	; The pattern's histogram (16 bytes; made once).

	lea		histogram_made,a1
	tst.b	(a1,d1.w)
	bne		.histogram_ok

	st		(a1,d1.w)
	bsr		make_histogram

.histogram_ok:
	lsl		#4,d1
	lea		histograms,a1
	add		d1,a1 ; Counts of colours 0-15.

	moveq	#0,d2
	move	6(a0),d2 ; Palette: bits 8-11.
	lsr		#8,d2
	and		#$f,d2

	lea		pattern_palettes,a2 ; This pattern was drawn with it.
	move	d1,d3
	lsr		#3,d3 ; Pattern * 2 (d1 is pattern * 16 here).
	move	(a2,d3.w),d4
	bset	d2,d4
	move	d4,(a2,d3.w)

	lsl		#6,d2 ; 16 longs per palette.
	lea		usage_counts,a2
	add		d2,a2

	moveq	#16-1,d3

.colour_loop:
	moveq	#0,d4
	move.b	(a1)+,d4
	add.l	d4,(a2)+

	dbf		d3,.colour_loop

.next_sprite:
	addq.l	#8,a0

	dbf		d0,.sprite_loop

.done:
	movem.l	(sp)+,d0-d4/a0-a3

	rts

; d1.w = pattern: counts its pixels per colour into histograms (colour 0,
; transparent, left 0; 255 at most). Preserves all registers but the flags.

make_histogram:
	movem.l	d0-d3/a0-a1,-(sp)

	move.l	SPRITE_DATA_ADDRESS,a0
	moveq	#0,d0
	move	d1,d0
	lsl.l	#7,d0
	add.l	d0,a0 ; 128 bytes, two pixels per byte.

	lea		histograms,a1
	lsl		#4,d1
	add		d1,a1

	moveq	#128-1,d3

.byte_loop:
	move.b	(a0)+,d0
	moveq	#$f,d2
	and		d0,d2
	beq		.low_done

	cmp.b	#255,(a1,d2.w)
	beq		.low_done

	addq.b	#1,(a1,d2.w)

.low_done:
	lsr.b	#4,d0
	and		#$f,d0
	beq		.high_done

	cmp.b	#255,(a1,d0.w)
	beq		.high_done

	addq.b	#1,(a1,d0.w)

.high_done:
	dbf		d3,.byte_loop

	movem.l	(sp)+,d0-d3/a0-a1

	rts

; At each frame end: remembers the stage word's low byte. Preserves all
; registers.

record_stage:
	movem.l	d0-d1/a0,-(sp)

	moveq	#0,d0
	move.b	PLAYER_SCORE+5,d0
	move	d0,d1
	lsr		#3,d1
	lea		stages_seen,a0
	bset	d0,(a0,d1.w)

	movem.l	(sp)+,d0-d1/a0

	rts

; Exit report: the stage words seen.

print_stages:
	movem.l	d0-d2/a0-a1,-(sp)

	lea		stages_text,a0
	jsr		print_text

	lea		stages_seen,a1
	moveq	#0,d2

.stage_loop:
	move	d2,d0
	lsr		#3,d0
	btst	d2,(a1,d0.w)
	beq		.next_stage

	lea		space_dollar_text,a0
	jsr		print_text
	move	d2,d0
	moveq	#2,d1
	jsr		print_hex

.next_stage:
	addq	#1,d2
	cmp		#256,d2
	bne		.stage_loop

	lea		line_end_text,a0
	jsr		print_text

	movem.l	(sp)+,d0-d2/a0-a1

	rts

; USAGE.BIN (GEMDOS, after the machine has been released).

write_usage:
	movem.l	d0-d3/a0-a2,-(sp)

	lea		usage_file_name,a0
	lea		usage_header,a1
	move.l	#'CRSU',(a1)
	move.l	usage_frames,4(a1)
	moveq	#8,d1
	bsr		create_and_write
	bmi		.done

	lea		usage_counts,a1
	move.l	#256*4,d1
	bsr		write_more

	lea		pattern_palettes,a1
	move.l	#2048*2,d1
	bsr		write_more

	bsr		close_file

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

	ifd __DUMP__

; GRAPHICS.BIN: 'CRSG', GVRAM ($100000), the video controller palettes
; ($400), the patterns' palettes (2048 words), the patterns.

write_graphics_dump:
	movem.l	d0-d3/a0-a2,-(sp)

	lea		graphics_file_name,a0
	lea		usage_header,a1
	move.l	#'CRSG',(a1)
	moveq	#4,d1
	bsr		create_and_write
	bmi		.done

	lea		L_00C00000,a1
	move.l	#$100000,d1
	bsr		write_more

	lea		L_00E82000,a1
	move.l	#$400,d1
	bsr		write_more

	lea		pattern_palettes,a1
	move.l	#2048*2,d1
	bsr		write_more

	move.l	SPRITE_DATA_ADDRESS,a1
	move.l	#PCG_PATTERNS*128,d1
	bsr		write_more

	bsr		close_file

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

	endif

; a0 = name, a1 = data, d1.l = size: creates the file (handle in d3) and
; writes the data. N set if it could not be created.

create_and_write:
	movem.l	d1/a1,-(sp)

	clr		-(sp)
	move.l	a0,-(sp)
	move	#60,-(sp) ; Fcreate
	trap	#1
	addq.l	#8,sp

	movem.l	(sp)+,d1/a1

	move	d0,d3
	tst.l	d0
	bmi		.failed

	bsr		write_more

	moveq	#0,d0 ; N clear.

.failed:
	rts

; a1 = data, d1.l = size, d3 = handle.

write_more:
	pea		(a1)
	move.l	d1,-(sp)
	move	d3,-(sp)
	move	#64,-(sp) ; Fwrite
	trap	#1
	lea		12(sp),sp

	rts

close_file:
	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

usage_file_name:
	dc.b	'USAGE.BIN',0
graphics_file_name:
	dc.b	'GRAPHICS.BIN',0
stages_text:
	dc.b	'Stages reached:',0
space_dollar_text:
	dc.b	' $',0
line_end_text:
	dc.b	13,10,0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

usage_header:
	ds.l	2
usage_frames:
	ds.l	1
usage_counts: ; Per sprite/text palette entry: pixels shown.
	ds.l	256
stages_seen:
	ds.b	32
histogram_made:
	ds.b	PCG_PATTERNS
	even
histograms:
	ds.b	PCG_PATTERNS*16

pattern_palettes: ; Per pattern: the palettes it was drawn with.
	ds.w	2048

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
