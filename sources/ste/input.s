
; Atari STE / Mega STE input, from the Falcon port's input.s: IKBD keyboard
; and joystick (MFP ACIA interrupt), and the STE's enhanced joystick port
; (a Jaguar pad; read every VBL, STE only: the Mega STE has no such port).
;
; _JOYGET answers with the AND of three X68000 joystick bytes (active low:
; bits 0-3 up, down, left, right; bit 5 trigger A, bit 6 trigger B): the
; keyboard's, the IKBD joystick's and the pad's. _BITSNS answers from an
; X68000 key matrix (16 groups of 8 scancodes) kept for the keys the game
; reads (as the Amiga port: ESC, 1, TAB, RETURN, SPACE, cursors, SHIFT, CTRL).
;
;   cursor keys          directions
;   CTRL, Z, fire        trigger A (shot)
;   SHIFT, X             trigger B
;   P, ESC               the X68000's ESC (START: pause)
;   F1                   lockstep on / off (every frame shown, game slowed)
;   F2                   the playfield window stays still (display.s)
;
; INPUT.BIN (optional, next to the program; tests): joystick states from
; given frames on, in the Amiga port's input script format (made by
; tests/amiga/make_input_script.py; only its joystick records are used).
;
; Auto fire (as in the Amiga port; the original game fires once per press):
; in a stage (the game ran its ship control this frame), a held trigger A
; reads released every other AUTOFIRE_FRAMES frames.

	xdef ikbd_handler
	xdef input_tick
	xdef joystick_now
	xdef keyboard_matrix
	xdef reset_input
	xdef input_frame_end
	xdef st_stage_frame
	xdef in_stage
	xdef load_input_script

	xref frame_count

	xref machine_is_ste
	xref lockstep_mode
	xref display_mode_changed
	xref crop_mode

X68_UP=0
X68_DOWN=1
X68_LEFT=2
X68_RIGHT=3
X68_TRIGGER_A=5
X68_TRIGGER_B=6

NO_KEY=$ff
NO_BIT=$ff
SPECIAL_LOCKSTEP=$80
SPECIAL_CROP=$81

MAXIMUM_SCRIPT_RECORDS=1024
SCRIPT_JOYSTICK=0

AUTOFIRE_SHIFT=1
AUTOFIRE_FRAMES=1<<AUTOFIRE_SHIFT ; Pressed for 2 frames, released for 2.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; IKBD/MIDI interrupt (MFP, automatic end of interrupt): every byte the ACIA
; holds goes to the current packet state.

ikbd_handler:
	movem.l	d0-d4/a0-a2,-(sp)

.next_byte:
	btst	#0,$fffffc00.w ; Receiver full?
	beq		.done

	moveq	#0,d0
	move.b	$fffffc02.w,d0
	move.l	ikbd_state,a0
	jsr		(a0)

	bra		.next_byte

.done:
	movem.l	(sp)+,d0-d4/a0-a2

	rte

; d0.b = the first byte of a packet, or a key code.

ikbd_idle:
	cmp.b	#$f6,d0
	bcs		process_key

	cmp.b	#$fe,d0 ; Joystick event: one data byte.
	bcs		.not_joystick

	move.b	d0,ikbd_joystick_port
	move.l	#ikbd_joystick,ikbd_state

	rts

.not_joystick:
	lea		packet_lengths-$f6,a0
	move.b	(a0,d0.w),ikbd_skip ; Bytes to skip (mouse, status, clock).
	move.l	#ikbd_skip_bytes,ikbd_state

	rts

ikbd_skip_bytes:
	subq.b	#1,ikbd_skip
	bne		.more

	move.l	#ikbd_idle,ikbd_state

.more:
	rts

; d0.b = %t000dddd (t = trigger, d = up, down, left, right).

ikbd_joystick:
	moveq	#$0f,d1
	and.b	d0,d1
	not.b	d1 ; Directions, active low; bits 4-7 released.
	tst.b	d0
	bpl		.no_fire

	bclr	#X68_TRIGGER_A,d1

.no_fire:
	lea		stick_joystick_state,a0
	btst	#0,ikbd_joystick_port
	bne		.port_1

	addq.l	#1,a0

.port_1:
	move.b	d1,(a0)
	move.l	#ikbd_idle,ikbd_state

	rts

; d0.b = key code (bit 7: release): the key matrix, the keyboard's joystick
; bits and the special keys.

process_key:
	moveq	#$7f,d1
	and.b	d0,d1
	add		d1,d1
	lea		key_map,a1
	add		d1,a1

	; X68000 scancode -> key matrix bit, counting the keys that hold it.

	moveq	#0,d1
	move.b	(a1),d1
	cmp.b	#NO_KEY,d1
	beq		.no_matrix_key

	lea		matrix_key_counts,a2
	add		d1,a2
	tst.b	d0
	bmi		.matrix_up

	addq.b	#1,(a2)

	bra		.matrix_update

.matrix_up:
	tst.b	(a2)
	beq		.no_matrix_key ; Not held (pressed before the start).

	subq.b	#1,(a2)

.matrix_update:
	move	d1,d2
	lsr		#3,d2
	lea		keyboard_matrix,a0
	add		d2,a0
	and		#7,d1
	tst.b	(a2)
	beq		.matrix_clear

	bset	d1,(a0)

	bra		.no_matrix_key

.matrix_clear:
	bclr	d1,(a0)

.no_matrix_key:
	moveq	#0,d1
	move.b	1(a1),d1
	cmp.b	#NO_BIT,d1
	beq		.done

	cmp.b	#SPECIAL_LOCKSTEP,d1
	bcc		.special

	; Joystick bit (active low), counting the keys that hold it.

	lea		joystick_bit_counts,a2
	add		d1,a2
	tst.b	d0
	bmi		.bit_up

	addq.b	#1,(a2)

	cmp		#X68_LEFT,d1
	bcs		.vertical

	move.b	d1,latest_horizontal

	bra		.bit_update

.vertical:
	move.b	d1,latest_vertical

	bra		.bit_update

.bit_up:
	tst.b	(a2)
	beq		.done

	subq.b	#1,(a2)

.bit_update:
	tst.b	(a2)
	beq		.bit_released

	bclr	d1,keyboard_joystick_state

	rts

.bit_released:
	bset	d1,keyboard_joystick_state

.done:
	rts

.special:
	tst.b	d0
	bmi		.done ; Released.

	cmp.b	#SPECIAL_LOCKSTEP,d1
	bne		.not_lockstep

	not.b	lockstep_mode

	rts

.not_lockstep:
	not.b	crop_mode
	st		display_mode_changed

	rts

; ------------------------------------------------------------------------------
;
; Every VBL: the STE's enhanced joystick port A (a Jaguar pad: button A is
; trigger A, B is trigger B). Preserves all registers.

input_tick:
	tst.b	machine_is_ste
	beq		.done

	movem.l	d0-d1,-(sp)

	moveq	#-1,d1

	move	#$fffe,$ffff9202.w ; Group: A, directions.
	move	$ffff9200.w,d0
	btst	#1,d0
	bne		.a_up

	bclr	#X68_TRIGGER_A,d1

.a_up:
	move	$ffff9202.w,d0
	lsr		#8,d0
	or.b	#$f0,d0 ; Up, down, left, right in bits 0-3, active low.
	and.b	d0,d1

	move	#$fffd,$ffff9202.w ; Group: B.
	move	$ffff9200.w,d0
	btst	#1,d0
	bne		.b_up

	bclr	#X68_TRIGGER_B,d1

.b_up:
	move.b	d1,pad_joystick_state

	movem.l	(sp)+,d0-d1

.done:
	rts

; ------------------------------------------------------------------------------
;
; _JOYGET: d0.l = the current state (all sources), as the X68000 hardware
; answers. With both of a pair of opposite cursor keys held, the one pressed
; last counts (the game reads left + right as START). Preserves the other
; registers.

joystick_now:
	move.l	d1,-(sp)

	move.b	keyboard_joystick_state,d1
	moveq	#1<<X68_LEFT|1<<X68_RIGHT,d0
	and.b	d1,d0
	bne		.horizontal_done ; Not both pressed (active low).

	moveq	#X68_LEFT+X68_RIGHT,d0
	sub.b	latest_horizontal,d0 ; The other one.
	bset	d0,d1

.horizontal_done:
	moveq	#1<<X68_UP|1<<X68_DOWN,d0
	and.b	d1,d0
	bne		.vertical_done

	moveq	#X68_UP+X68_DOWN,d0
	sub.b	latest_vertical,d0
	bset	d0,d1

.vertical_done:
	moveq	#-1,d0
	move.b	stick_joystick_state,d0
	and.b	stick_joystick_state+1,d0
	and.b	pad_joystick_state,d0
	and.b	script_joystick_state,d0
	and.b	d1,d0
	move.b	d0,last_joystick_state ; For the auto fire at the frame end.

	tst.b	in_stage
	beq		.done

	tst.b	autofire_released
	beq		.done

	bset	#X68_TRIGGER_A,d0

.done:
	move.l	(sp)+,d1

	rts

; At each frame end (the game's frame wait): the auto fire's phase.
; Preserves all registers.

input_frame_end:
	movem.l	d0/a0,-(sp)

	; The input script's joystick records due by this frame.

	move.l	script_next,a0

.script_loop:
	cmp.l	script_end,a0
	bcc		.script_done

	move.l	frame_count,d0
	cmp.l	(a0),d0
	bcs		.script_done

	cmp.b	#SCRIPT_JOYSTICK,4(a0)
	bne		.script_next_record

	move.b	5(a0),script_joystick_state

.script_next_record:
	addq.l	#8,a0

	bra		.script_loop

.script_done:
	move.l	a0,script_next

	movem.l	(sp)+,d0/a0

	move.b	st_stage_frame,in_stage
	sf		st_stage_frame
	beq		.no_autofire

	btst	#X68_TRIGGER_A,last_joystick_state
	bne		.no_autofire ; Released.

	addq.l	#1,autofire_frames
	btst	#AUTOFIRE_SHIFT,autofire_frames+3 ; Odd periods: released.
	sne		autofire_released

	rts

.no_autofire:
	clr.l	autofire_frames
	sf		autofire_released

	rts

; INPUT.BIN: 'CRSI', number of records, 8-byte records (frame, kind, value,
; extra, padding). GEMDOS, before the machine is taken over.

load_input_script:
	movem.l	d0-d3/a0-a2,-(sp)

	lea		script_records,a0
	move.l	a0,script_next
	move.l	a0,script_end

	clr		-(sp)
	pea		input_file_name
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.done

	move	d0,d3

	pea		script_header
	move.l	#8,-(sp)
	move	d3,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp

	cmp.l	#'CRSI',script_header
	bne		.close

	move.l	script_header+4,d0
	cmp.l	#MAXIMUM_SCRIPT_RECORDS,d0
	bls		.count_ok

	move.l	#MAXIMUM_SCRIPT_RECORDS,d0

.count_ok:
	lsl.l	#3,d0

	pea		script_records
	move.l	d0,-(sp)
	move	d3,-(sp)
	move	#63,-(sp)
	trap	#1
	lea		12(sp),sp
	tst.l	d0
	bmi		.close

	and.b	#$f8,d0 ; Whole records.
	add.l	d0,script_end

.close:
	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

; All keys and sticks released (at start).

reset_input:
	move.l	#ikbd_idle,ikbd_state
	st		keyboard_joystick_state
	st		stick_joystick_state
	st		stick_joystick_state+1
	st		pad_joystick_state
	st		script_joystick_state
	st		last_joystick_state
	sf		in_stage
	sf		st_stage_frame
	sf		autofire_released
	clr.l	autofire_frames

	lea		keyboard_matrix,a0
	moveq	#(16+128+8)/4-1,d0 ; keyboard_matrix ... joystick_bit_counts

.clear:
	clr.l	(a0)+
	dbf		d0,.clear

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

input_file_name:
	dc.b	'INPUT.BIN',0

	even

ikbd_state:
	dc.l	ikbd_idle

; Bytes after the header $f6-$fd: status, absolute mouse, relative mouse
; (4 headers), time of day, joystick report.

packet_lengths:
	dc.b	7,5,2,2,2,2,6,2

; Per ST key code ($00-$7f): X68000 scancode (key matrix), X68000 joystick
; bit or special key.

key_map:
	dc.b	NO_KEY,NO_BIT ; $00
	dc.b	$01,NO_BIT ; $01 ESC
	dc.b	$02,NO_BIT ; $02 1
	dcb.b	($0f-$03)*2,NO_KEY
	dc.b	$10,NO_BIT ; $0f TAB
	dcb.b	($19-$10)*2,NO_KEY
	dc.b	$01,NO_BIT ; $19 P: the X68000's ESC (START: pause)
	dcb.b	($1c-$1a)*2,NO_KEY
	dc.b	$1d,NO_BIT ; $1c RETURN
	dc.b	$71,X68_TRIGGER_A ; $1d CTRL
	dcb.b	($2a-$1e)*2,NO_KEY
	dc.b	$70,X68_TRIGGER_B ; $2a left SHIFT
	dc.b	NO_KEY,NO_BIT ; $2b
	dc.b	NO_KEY,X68_TRIGGER_A ; $2c Z
	dc.b	NO_KEY,X68_TRIGGER_B ; $2d X
	dcb.b	($36-$2e)*2,NO_KEY
	dc.b	$70,X68_TRIGGER_B ; $36 right SHIFT
	dcb.b	($39-$37)*2,NO_KEY
	dc.b	$35,NO_BIT ; $39 SPACE
	dc.b	NO_KEY,NO_BIT ; $3a
	dc.b	NO_KEY,SPECIAL_LOCKSTEP ; $3b F1
	dc.b	NO_KEY,SPECIAL_CROP ; $3c F2
	dcb.b	($48-$3d)*2,NO_KEY
	dc.b	$3c,X68_UP ; $48 cursor up
	dcb.b	($4b-$49)*2,NO_KEY
	dc.b	$3b,X68_LEFT ; $4b cursor left
	dc.b	NO_KEY,NO_BIT ; $4c
	dc.b	$3d,X68_RIGHT ; $4d cursor right
	dcb.b	($50-$4e)*2,NO_KEY
	dc.b	$3e,X68_DOWN ; $50 cursor down
	dcb.b	($72-$51)*2,NO_KEY
	dc.b	$1d,NO_BIT ; $72 keypad ENTER
	dcb.b	($80-$73)*2,NO_KEY

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

keyboard_matrix: ; Must be followed by matrix_key_counts, joystick_bit_counts.
	ds.b	16
matrix_key_counts: ; Per X68000 scancode: keys holding it.
	ds.b	128
joystick_bit_counts: ; Per joystick bit: keys holding it.
	ds.b	8

keyboard_joystick_state:
	ds.b	1
stick_joystick_state: ; IKBD joystick 1, joystick 0.
	ds.b	2
pad_joystick_state:
	ds.b	1
latest_horizontal:
	ds.b	1
latest_vertical:
	ds.b	1
ikbd_joystick_port:
	ds.b	1
ikbd_skip:
	ds.b	1
last_joystick_state:
	ds.b	1
st_stage_frame: ; Set by the game's ship control (sz2.s).
	ds.b	1
in_stage: ; The last frame was in a stage.
	ds.b	1
autofire_released:
	ds.b	1

	even

autofire_frames:
	ds.l	1

script_next:
	ds.l	1
script_end:
	ds.l	1
script_header:
	ds.l	2
script_records:
	ds.b	MAXIMUM_SCRIPT_RECORDS*8
script_joystick_state:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
