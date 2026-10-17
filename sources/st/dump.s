
; Data for the colour tools (tools/st/palette_map.py), from measurement runs
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
;   exit report, and per stage (its low 4 bits) the frames, the 50 Hz ticks,
;   the pictures shown and their render time.
; - Per second of gameplay (50 ticks, every frame in a stage): its pictures
;   per second, in a histogram, for the exit report's worst, 10%, median,
;   90% and best seconds (n%: n% of the seconds are at or below it), the
;   histogram itself and the frames where the first seconds of 0 or 1
;   picture ended.

	xdef record_stage
	xdef stage_picture
	xdef print_stages

	ifd __USAGE__
	xdef count_sprite_usage
	xdef write_usage
	endif

	ifd __DUMP__
	xdef write_graphics_dump
	xref L_00C00000
	endif

	xref sprite_list
	xref SPRITE_DATA_ADDRESS
	xref L_00E82000
	xref PLAYER_SCORE
	xref print_text
	xref create_and_write
	xref write_more
	xref close_file
	xref line_end_text
	xref space_dollar_text
	xref print_hex
	xref print_number
	xref print_tenths
	xref divide_unsigned
	xref times_500
	xref units_to_tenths_ms
	xref total_vbl_count
	xref in_stage
	xref frame_count

	include "st.i"

STAGE_SLOTS=16
SECOND_TICKS=50
MAXIMUM_RATE=50 ; Pictures per second: one per tick at most.
SLOW_SECONDS=12 ; Of 0 or 1 picture: where the first ones ended.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

	ifd __USAGE__

; d0.w = number of sprites in SPRITE_DATA_TABLE. Preserves all registers.

count_sprite_usage:
	movem.l	d0-d4/a0-a3,-(sp)

	addq.l	#1,usage_frames

	move.l	SPRITE_DATA_ADDRESS,d1
	beq		.done

	move.l	sprite_list,a0 ; The table just completed.
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

	endif

; At each frame end: remembers the stage word's low byte, counts the frame
; and the ticks since the last one for the stage; ends a gameplay second
; when its ticks are done. Preserves all registers.

record_stage:
	movem.l	d0-d3/a0,-(sp)

	moveq	#0,d0
	move.b	PLAYER_SCORE+5,d0
	move	d0,d1
	lsr		#3,d1
	lea		stages_seen,a0
	bset	d0,(a0,d1.w)

	and		#STAGE_SLOTS-1,d0
	move	d0,current_stage
	lsl		#2,d0
	lea		stage_frames,a0
	addq.l	#1,(a0,d0.w)

	move.l	total_vbl_count,d1
	move.l	d1,d2
	sub.l	stage_last_ticks,d1
	move.l	d2,stage_last_ticks
	lea		stage_ticks,a0
	add.l	d1,(a0,d0.w)

	; The second (d2 = ticks now).

	tst.b	in_stage
	bne		.in_stage

	sf		second_clean ; A frame out of a stage: not gameplay.

.in_stage:
	move.l	d2,d1
	sub.l	second_start,d1
	cmp.l	#SECOND_TICKS,d1
	bcs		.second_open

	tst.b	second_clean
	beq		.next_second

	cmp.l	#SECOND_TICKS*2,d1
	bcc		.next_second ; (A long stop, not a second of play.)

	moveq	#0,d0 ; Pictures * 50 / ticks, rounded.
	move	second_pictures,d0
	mulu	#SECOND_TICKS,d0
	move	d1,d3
	lsr		#1,d3
	add		d3,d0
	divu	d1,d0
	cmp		#MAXIMUM_RATE,d0
	bls		.rate_ok

	moveq	#MAXIMUM_RATE,d0

.rate_ok:
	cmp		#1,d0
	bhi		.not_slow

	move	slow_count,d3
	cmp		#SLOW_SECONDS,d3
	beq		.not_slow

	addq	#1,slow_count
	lsl		#2,d3
	lea		slow_frames,a0
	move.l	frame_count,(a0,d3.w)

.not_slow:
	lsl		#2,d0
	lea		rate_histogram,a0
	addq.l	#1,(a0,d0.w)

.next_second:
	move.l	d2,second_start
	clr		second_pictures
	st		second_clean

.second_open:
	movem.l	(sp)+,d0-d3/a0

	rts

; d0.l = a picture's render time (measure.s units): counted for the stage.
; Preserves all registers.

stage_picture:
	movem.l	d1/a0,-(sp)

	move	current_stage,d1
	lsl		#2,d1
	lea		stage_pictures,a0
	addq.l	#1,(a0,d1.w)
	lea		stage_render,a0
	add.l	d0,(a0,d1.w)
	addq	#1,second_pictures

	movem.l	(sp)+,d1/a0

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

	; Per stage: frames, pictures (per second of ticks), render time.

	moveq	#0,d2

.slot_loop:
	move	d2,d0
	lsl		#2,d0
	lea		stage_frames,a1
	tst.l	(a1,d0.w)
	beq		.next_slot

	lea		stage_text,a0
	jsr		print_text
	move	d2,d0
	moveq	#1,d1
	jsr		print_hex

	lea		stage_frames_text,a0
	jsr		print_text
	move	d2,d0
	lsl		#2,d0
	move.l	(a1,d0.w),d0
	jsr		print_number

	lea		stage_pictures_text,a0
	jsr		print_text
	move	d2,d0
	lsl		#2,d0
	lea		stage_pictures,a1
	move.l	(a1,d0.w),d0
	jsr		print_number

	lea		stage_per_second_text,a0
	jsr		print_text
	move	d2,d0
	lsl		#2,d0
	move.l	(a1,d0.w),d0 ; Pictures * 500 / ticks: tenths per second.
	jsr		times_500
	lea		stage_ticks,a1
	move	d2,d1
	lsl		#2,d1
	move.l	(a1,d1.w),d1
	beq		.no_ticks

	jsr		divide_unsigned
	jsr		print_tenths

.no_ticks:
	lea		stage_render_text,a0
	jsr		print_text
	move	d2,d0
	lsl		#2,d0
	lea		stage_pictures,a1
	move.l	(a1,d0.w),d1
	beq		.no_pictures

	lea		stage_render,a1
	move.l	(a1,d0.w),d0
	jsr		divide_unsigned
	jsr		units_to_tenths_ms
	jsr		print_tenths

.no_pictures:
	lea		stage_end_text,a0
	jsr		print_text

.next_slot:
	addq	#1,d2
	cmp		#STAGE_SLOTS,d2
	bne		.slot_loop

	bsr		print_rates

	movem.l	(sp)+,d0-d2/a0-a1

	rts

; Exit report: the gameplay seconds' pictures per second. Preserves all
; registers.

print_rates:
	movem.l	d0-d4/a0-a1,-(sp)

	lea		rate_histogram,a1 ; d2.l = seconds, d3.l = their pictures.
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3

.sum_loop:
	move.l	(a1)+,d0
	add.l	d0,d2
	mulu	d1,d0
	add.l	d0,d3
	addq	#1,d1
	cmp		#MAXIMUM_RATE,d1
	bls		.sum_loop

	tst.l	d2
	beq		.done

	lea		rates_text,a0
	jsr		print_text
	move.l	d2,d0
	jsr		print_number

	lea		rates_worst_text,a0
	moveq	#0,d0 ; (1 second.)
	bsr		.percentile
	lea		rates_10_text,a0
	moveq	#10,d0
	bsr		.percentile
	lea		rates_median_text,a0
	moveq	#50,d0
	bsr		.percentile
	lea		rates_90_text,a0
	moveq	#90,d0
	bsr		.percentile
	lea		rates_best_text,a0
	moveq	#100,d0
	bsr		.percentile

	lea		rates_mean_text,a0
	jsr		print_text
	move.l	d3,d0 ; Tenths: pictures * 10 / seconds.
	add.l	d0,d0
	move.l	d0,d1
	lsl.l	#2,d0
	add.l	d1,d0
	move.l	d2,d1
	jsr		divide_unsigned
	jsr		print_tenths

	lea		line_end_text,a0
	jsr		print_text

	; The histogram: rate:seconds for each rate seen.

	lea		rate_seconds_text,a0
	jsr		print_text
	lea		rate_histogram,a1
	moveq	#0,d4

.histogram_loop:
	move.l	(a1)+,d3
	beq		.next_rate

	lea		space_text,a0
	jsr		print_text
	move.l	d4,d0
	jsr		print_number
	lea		colon_text,a0
	jsr		print_text
	move.l	d3,d0
	jsr		print_number

.next_rate:
	addq	#1,d4
	cmp		#MAXIMUM_RATE,d4
	bls		.histogram_loop

	lea		line_end_text,a0
	jsr		print_text

	move	slow_count,d4
	beq		.done

	lea		slow_frames_text,a0
	jsr		print_text
	lea		slow_frames,a1
	subq	#1,d4

.slow_loop:
	lea		space_text,a0
	jsr		print_text
	move.l	(a1)+,d0
	jsr		print_number
	dbf		d4,.slow_loop

	lea		line_end_text,a0
	jsr		print_text

.done:
	movem.l	(sp)+,d0-d4/a0-a1

	rts

; a0 = label, d0 = percent: prints the lowest rate that percent of the
; d2.l seconds (at least one of them) are at or below.

.percentile:
	jsr		print_text

	mulu	d2,d0
	add.l	#99,d0
	divu	#100,d0
	and.l	#$ffff,d0
	bne		.count_ok

	moveq	#1,d0

.count_ok:
	lea		rate_histogram,a1
	moveq	#0,d1
	moveq	#0,d4

.count_loop:
	add.l	(a1)+,d1
	cmp.l	d0,d1
	bcc		.found

	addq	#1,d4
	cmp		#MAXIMUM_RATE,d4
	bcs		.count_loop

.found:
	move.l	d4,d0
	jmp		print_number

	ifd __USAGE__

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

	endif

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

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

	ifd __USAGE__
usage_file_name:
	dc.b	'USAGE.BIN',0
	endif
	ifd __DUMP__
graphics_file_name:
	dc.b	'GRAPHICS.BIN',0
	endif
stages_text:
	dc.b	'Stages reached:',0
stage_text:
	dc.b	'Stage $',0
stage_frames_text:
	dc.b	': frames ',0
stage_pictures_text:
	dc.b	', pictures ',0
stage_per_second_text:
	dc.b	' (per second ',0
stage_render_text:
	dc.b	'), render ',0
stage_end_text:
	dc.b	' ms',13,10,0
rates_text:
	dc.b	'Gameplay seconds: ',0
rates_worst_text:
	dc.b	', pictures per second: worst ',0
rates_10_text:
	dc.b	', 10% ',0
rates_median_text:
	dc.b	', median ',0
rates_90_text:
	dc.b	', 90% ',0
rates_best_text:
	dc.b	', best ',0
rates_mean_text:
	dc.b	', mean ',0
rate_seconds_text:
	dc.b	'Gameplay seconds per rate (pictures:seconds):',0
slow_frames_text:
	dc.b	'Seconds of 0 or 1 picture, ending at frames:',0
space_text:
	dc.b	' ',0
colon_text:
	dc.b	':',0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

stages_seen:
	ds.b	32
current_stage:
	ds.w	1
stage_last_ticks:
	ds.l	1
stage_frames:
	ds.l	STAGE_SLOTS
stage_ticks:
	ds.l	STAGE_SLOTS
stage_pictures:
	ds.l	STAGE_SLOTS
stage_render:
	ds.l	STAGE_SLOTS
rate_histogram: ; Per pictures per second (0-50): gameplay seconds.
	ds.l	MAXIMUM_RATE+1
second_start: ; Ticks.
	ds.l	1
second_pictures:
	ds.w	1
second_clean: ; Every frame so far in a stage.
	ds.b	1
	even
slow_count:
	ds.w	1
slow_frames: ; Frame counts.
	ds.l	SLOW_SECONDS
	ifd __USAGE__
usage_frames:
	ds.l	1
usage_counts: ; Per sprite/text palette entry: pixels shown.
	ds.l	256
histogram_made:
	ds.b	PCG_PATTERNS
	even
histograms:
	ds.b	PCG_PATTERNS*16
	endif

	; Both data runs' files.

	ifd __USAGE__
USAGE_OR_DUMP set 1
	endif
	ifd __DUMP__
USAGE_OR_DUMP set 1
	endif

	ifd USAGE_OR_DUMP
	even
usage_header:
	ds.l	2
pattern_palettes: ; Per pattern: the palettes it was drawn with.
	ds.w	2048
	endif

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
