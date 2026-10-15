
; Measurements for the proof of concept, printed at exit (Cconws, so Hatari's
; --conout 2 copies them to the host):
;
; - Time: MFP Timer D divides 2457600 Hz by 64 (38400 Hz, 26.04 us units)
;   and overflows every 256 counts (150 Hz); the overflows are counted, so
;   read_timer gives a 32-bit clock independent of the CPU speed.
; - Game logic per frame (from the end of one frame wait to the start of the
;   next one: the game's own work, the interrupts included, no rendering):
;   median, 95th percentile, maximum, mean.
; - Rendering (composition into the chunky buffer) and presentation (C2P)
;   per picture: mean and maximum; pictures per second.
; - Game state checkpoints every CHECKPOINT_INTERVAL frames, written to
;   CHECKPTS.BIN in the Amiga port's checkpoints.bin format (compared with
;   tests/amiga/checkpoints.py against tests/amiga/reference/).

	xdef timer_d_handler
	xdef read_timer
	xdef measure_logic
	xdef measure_picture
	xdef start_render_parts
	xdef mark_render_part
	xdef record_checkpoint
	xdef write_checkpoints
	xdef print_text
	xdef print_number
	xdef print_tenths
	xdef print_hex
	xdef divide_unsigned
	xdef units_to_tenths_ms

	xref frame_count
	xref last_sprite_count
	xref PLAYER_SCORE
	xref PLAYER_INFO_STRUCT
	xref WORD_00088E6C
	xref BACKGROUND_SCROLL_COUNTER

CHECKPOINT_INTERVAL=60
CHECKPOINT_SIZE=32
MAXIMUM_CHECKPOINTS=2048 ; 122,880 frames.
RENDER_PARTS=4

HISTOGRAM_BUCKETS=256
BUCKET_UNITS=19 ; 0.495 ms.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

timer_d_handler:
	addq.l	#1,timer_overflows

	rte

; d0.l = time in Timer D units (26.04 us). Preserves the other registers.

read_timer:
	move.l	d1,-(sp)
	move	sr,-(sp)
	ori		#$0700,sr

	; An overflow pending (not yet counted: masked here) means the count
	; read after it is in the new period; without one, the count read
	; before the check is in the counted period.

	moveq	#0,d0
	move.b	$fffffa25.w,d0 ; Counts down from 256 (reads 0 just after a reload).
	move.l	timer_overflows,d1
	btst	#4,$fffffa0d.w
	beq		.counted

	move.b	$fffffa25.w,d0
	addq.l	#1,d1

.counted:
	neg.b	d0 ; Counts of this period: (256 - count) & 255.
	lsl.l	#8,d1
	add.l	d1,d0

	move	(sp)+,sr
	move.l	(sp)+,d1

	rts

; d0.l = one frame's game logic time (units). Preserves all registers.

measure_logic:
	movem.l	d0-d1/a0,-(sp)

	addq.l	#1,logic_frames
	add.l	d0,logic_total
	cmp.l	logic_maximum,d0
	bls		.not_maximum

	move.l	d0,logic_maximum

.not_maximum:
	move.l	d0,d1
	cmp.l	#BUCKET_UNITS*(HISTOGRAM_BUCKETS-1),d1
	bcs		.in_range

	move.l	#BUCKET_UNITS*(HISTOGRAM_BUCKETS-1),d1

.in_range:
	divu	#BUCKET_UNITS,d1
	lsl		#2,d1
	lea		logic_histogram,a0
	addq.l	#1,(a0,d1.w)

	movem.l	(sp)+,d0-d1/a0

	rts

; d0.l = render time, d1.l = presentation (C2P) time of a picture (units).
; Preserves all registers.

measure_picture:
	addq.l	#1,pictures_measured
	add.l	d0,render_total
	add.l	d1,present_total
	cmp.l	render_maximum,d0
	bls		.render_ok

	move.l	d0,render_maximum

.render_ok:
	cmp.l	present_maximum,d1
	bls		.present_ok

	move.l	d1,present_maximum

.present_ok:
	rts

; The render's parts: start_render_parts at the start of a picture, then
; mark_render_part with d0.w = the part ending (RENDER_PARTS of them) adds
; the time since the previous mark. Preserve all registers.

start_render_parts:
	move.l	d0,-(sp)
	bsr		read_timer
	move.l	d0,part_start
	move.l	(sp)+,d0

	rts

mark_render_part:
	movem.l	d0-d2/a0,-(sp)

	move	d0,d2
	bsr		read_timer
	move.l	d0,d1
	sub.l	part_start,d0
	move.l	d1,part_start
	lsl		#2,d2
	lea		render_parts,a0
	add.l	d0,(a0,d2.w)

	movem.l	(sp)+,d0-d2/a0

	rts

; At each frame end: every CHECKPOINT_INTERVAL frames, frame (long), score
; (long), random table index (word), background scroll counter (word),
; sprites (word), padding (word), player structure (14 bytes), padding.

record_checkpoint:
	movem.l	d0-d1/a0-a1,-(sp)

	subq	#1,checkpoint_countdown ; Every CHECKPOINT_INTERVAL frames.
	bne		.done

	move	#CHECKPOINT_INTERVAL,checkpoint_countdown

	move.l	checkpoint_count,d0
	cmp.l	#MAXIMUM_CHECKPOINTS,d0
	bcc		.done

	lsl.l	#5,d0 ; CHECKPOINT_SIZE
	lea		checkpoints,a0
	add.l	d0,a0

	move.l	frame_count,(a0)+
	move.l	PLAYER_SCORE,(a0)+
	move	WORD_00088E6C,(a0)+
	move	BACKGROUND_SCROLL_COUNTER,(a0)+
	move	last_sprite_count,(a0)+
	clr		(a0)+

	lea		PLAYER_INFO_STRUCT,a1
	moveq	#14-1,d0

.copy:
	move.b	(a1)+,(a0)+
	dbf		d0,.copy

	clr		(a0)+

	addq.l	#1,checkpoint_count

.done:
	movem.l	(sp)+,d0-d1/a0-a1

	rts

; CHECKPTS.BIN: 'CRSC', number of checkpoints, the checkpoints (GEMDOS;
; after the machine has been released).

write_checkpoints:
	movem.l	d0-d3/a0-a2,-(sp)

	clr		-(sp)
	pea		checkpoints_file_name
	move	#60,-(sp) ; Fcreate
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.done

	move	d0,d3

	move.l	#'CRSC',checkpoints_header
	move.l	checkpoint_count,checkpoints_header+4

	pea		checkpoints_header
	move.l	#8,-(sp)
	move	d3,-(sp)
	move	#64,-(sp) ; Fwrite
	trap	#1
	lea		12(sp),sp

	pea		checkpoints
	move.l	checkpoint_count,d0
	lsl.l	#5,d0
	move.l	d0,-(sp)
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
;
; Summary lines (after the machine has been released).

	xdef print_measurements

print_measurements:
	movem.l	d0-d7/a0-a6,-(sp)

	tst.l	logic_frames
	beq		.no_logic

	lea		logic_text,a0
	bsr		print_text

	; Median and 95th percentile from the histogram.

	move.l	logic_frames,d0
	lsr.l	#1,d0
	bsr		.percentile
	bsr		print_tenths

	lea		logic_p95_text,a0
	bsr		print_text

	move.l	logic_frames,d0
	moveq	#20,d1
	bsr		divide_unsigned ; 5 %
	move.l	logic_frames,d1
	sub.l	d0,d1
	move.l	d1,d0
	bsr		.percentile
	bsr		print_tenths

	lea		logic_maximum_text,a0
	bsr		print_text

	move.l	logic_maximum,d0
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		logic_mean_text,a0
	bsr		print_text

	move.l	logic_total,d0
	move.l	logic_frames,d1
	bsr		divide_unsigned
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		line_end_text,a0
	bsr		print_text

.no_logic:
	tst.l	pictures_measured
	beq		.no_pictures

	lea		render_text,a0
	bsr		print_text

	move.l	render_total,d0
	move.l	pictures_measured,d1
	bsr		divide_unsigned
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		maximum_text,a0
	bsr		print_text

	move.l	render_maximum,d0
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		present_text,a0
	bsr		print_text

	move.l	present_total,d0
	move.l	pictures_measured,d1
	bsr		divide_unsigned
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		maximum_text,a0
	bsr		print_text

	move.l	present_maximum,d0
	bsr		units_to_tenths_ms
	bsr		print_tenths

	lea		close_line_text,a0
	bsr		print_text

	; The render's parts.

	lea		parts_text,a0
	bsr		print_text

	lea		render_parts,a1
	lea		part_names,a2
	moveq	#RENDER_PARTS-1,d7

.part_loop:
	move.l	a2,a0
	bsr		print_text

.name_end:
	tst.b	(a2)+
	bne		.name_end

	move.l	(a1)+,d0
	move.l	pictures_measured,d1
	bsr		divide_unsigned
	bsr		units_to_tenths_ms
	bsr		print_tenths

	dbf		d7,.part_loop

	lea		line_end_text,a0
	bsr		print_text

.no_pictures:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; d0.l = rank (frames below) -> d0.l = the bucket's upper end in tenths of
; a millisecond.

.percentile:
	lea		logic_histogram,a0
	moveq	#0,d1 ; Bucket.
	moveq	#0,d2 ; Frames so far.

.bucket_loop:
	add.l	(a0)+,d2
	cmp.l	d0,d2
	bhi		.bucket_found

	addq	#1,d1
	cmp		#HISTOGRAM_BUCKETS,d1
	bne		.bucket_loop

	subq	#1,d1

.bucket_found:
	addq	#1,d1
	mulu	#BUCKET_UNITS,d1
	move.l	d1,d0

	bra		units_to_tenths_ms

; ------------------------------------------------------------------------------
;
; d0.l = Timer D units -> d0.l = tenths of a millisecond (units * 25 / 96).
; Preserves the other registers.

units_to_tenths_ms:
	move.l	d1,-(sp)

	move.l	d0,d1 ; * 25 (fits: up to 171 s)
	add.l	d0,d0
	add.l	d1,d0
	lsl.l	#3,d0
	add.l	d1,d0
	moveq	#96,d1
	bsr		divide_unsigned

	move.l	(sp)+,d1

	rts

; d0.l / d1.l (unsigned) -> d0.l = quotient, d1.l = remainder (0 / 0 = 0).

divide_unsigned:
	movem.l	d2-d3,-(sp)

	tst.l	d1
	bne		.divide

	moveq	#0,d0

	bra		.done

.divide:
	moveq	#0,d2 ; Remainder.
	moveq	#32-1,d3

.loop:
	add.l	d0,d0
	addx.l	d2,d2
	cmp.l	d1,d2
	bcs		.next

	sub.l	d1,d2
	addq.l	#1,d0

.next:
	dbf		d3,.loop

	move.l	d2,d1

.done:
	movem.l	(sp)+,d2-d3

	rts

; a0 = zero-terminated text (GEMDOS Cconws). Preserves all registers.

print_text:
	movem.l	d0-d2/a0-a2,-(sp)

	pea		(a0)
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	movem.l	(sp)+,d0-d2/a0-a2

	rts

; d0.l = unsigned number, in decimal. Preserves all registers.

print_number:
	movem.l	d0-d3/a0,-(sp)

	lea		number_buffer+12,a0
	clr.b	-(a0)

.digit_loop:
	; d0 / 10 in two 16-bit steps.

	move.l	d0,d2
	clr		d2
	swap	d2
	divu	#10,d2
	move	d2,d3
	move	d0,d2
	divu	#10,d2
	swap	d3
	move	d2,d3
	swap	d2
	add.b	#'0',d2
	move.b	d2,-(a0)
	move.l	d3,d0
	bne		.digit_loop

	bsr		print_text

	movem.l	(sp)+,d0-d3/a0

	rts

; d0.l = tenths, printed as "n.n". Preserves all registers.

print_tenths:
	movem.l	d0-d1/a0,-(sp)

	moveq	#10,d1
	bsr		divide_unsigned
	bsr		print_number
	lea		point_text,a0
	bsr		print_text
	move.l	d1,d0
	bsr		print_number

	movem.l	(sp)+,d0-d1/a0

	rts

; d0.l = number, d1 = digits, in hexadecimal. Preserves all registers.

print_hex:
	movem.l	d0-d2/a0,-(sp)

	lea		number_buffer+12,a0
	clr.b	-(a0)
	subq	#1,d1

.hex_loop:
	moveq	#$f,d2
	and		d0,d2
	move.b	hex_digits(pc,d2.w),-(a0)
	lsr.l	#4,d0
	dbf		d1,.hex_loop

	bsr		print_text

	movem.l	(sp)+,d0-d2/a0

	rts

hex_digits:
	dc.b	'0123456789ABCDEF'

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

checkpoint_countdown:
	dc.w	CHECKPOINT_INTERVAL

checkpoints_file_name:
	dc.b	'CHECKPTS.BIN',0
logic_text:
	dc.b	'Game logic per frame (ms): median ',0
logic_p95_text:
	dc.b	', 95% ',0
logic_maximum_text:
	dc.b	', max ',0
logic_mean_text:
	dc.b	', mean ',0
render_text:
	dc.b	'Per picture (ms): render ',0
present_text:
	dc.b	'), present ',0
maximum_text:
	dc.b	' (max ',0
parts_text:
	dc.b	'Render parts (ms):',0
part_names: ; RENDER_PARTS
	dc.b	' background ',0
	dc.b	', sprites ',0
	dc.b	', text ',0
	dc.b	', borders and colours ',0
close_line_text:
	dc.b	')'
line_end_text:
	dc.b	13,10,0
point_text:
	dc.b	'.',0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

timer_overflows:
	ds.l	1

logic_frames:
	ds.l	1
logic_total:
	ds.l	1
logic_maximum:
	ds.l	1
logic_histogram:
	ds.l	HISTOGRAM_BUCKETS

pictures_measured:
	ds.l	1
render_total:
	ds.l	1
render_maximum:
	ds.l	1
present_total:
	ds.l	1
present_maximum:
	ds.l	1
part_start:
	ds.l	1
render_parts:
	ds.l	RENDER_PARTS

	xdef pictures_measured

checkpoint_count:
	ds.l	1
checkpoints_header:
	ds.l	2
checkpoints:
	ds.b	CHECKPOINT_SIZE*MAXIMUM_CHECKPOINTS

number_buffer:
	ds.b	12

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
