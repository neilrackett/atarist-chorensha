
; Atari ST input, from the Falcon port's input.s: IKBD keyboard
; and joystick (MFP ACIA interrupt), the STE's enhanced joystick port (a
; Jaguar pad; read every VBL, STE only: the Mega STE has no such port) and
; Xpad pads (any provider's: read every VBL).
;
; _JOYGET answers with the AND of four X68000 joystick bytes (active low:
; bits 0-3 up, down, left, right; bit 5 trigger A, bit 6 trigger B): the
; keyboard's, the IKBD joystick's, the STE pad's and the Xpad pads'.
; _BITSNS answers from an X68000 key matrix (16 groups of 8 scancodes) kept
; for the keys the game reads (as the Amiga port: ESC, 1, TAB, RETURN,
; SPACE, cursors, SHIFT, CTRL).
;
;   cursor keys          directions
;   Z, CTRL, fire        trigger A (shot)
;   X, SHIFT             trigger B (bomb)
;   P, ESC               the X68000's ESC (START: pause)
;   F1                   lockstep on / off (every frame shown, game slowed)
;   F2                   the playfield window stays still (display.s)
;
; Xpad (lib/xpad, https://github.com/neilrackett/atarist-xpad): a provider
; publishes its pads' state in a block found through the XPAD cookie; all
; the pads present count, as one:
;
;   d-pad, left stick    directions (the provider folds the stick in)
;   A, X, RB, RT         trigger A (shot; south, west, right shoulders)
;   B, Y, LB, LT         trigger B (bomb; east, north, left shoulders)
;   START                the X68000's ESC (pause)
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
	xdef find_xpad
	xdef xpad_block
	xdef xpad_pad_count
	xdef xpad_matrix_escape
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
	xref find_cookie
	xref crop_mode

	include "xpad.inc"

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

XPAD_TRIGGER_A_BUTTONS=XPAD_SOUTH|XPAD_WEST|XPAD_TR|XPAD_TR2
XPAD_TRIGGER_B_BUTTONS=XPAD_EAST|XPAD_NORTH|XPAD_TL|XPAD_TL2
X68_ESC_GROUP_0_BIT=1 ; The X68000's ESC: scancode $01.

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
	beq		.midi

	moveq	#0,d0
	move.b	$fffffc02.w,d0
	move.l	ikbd_state,a0
	jsr		(a0)

	bra		.next_byte

.midi:
	; The MIDI ACIA shares the interrupt line: a byte it holds (or an
	; overrun) keeps the line low, and no keyboard interrupt would come
	; again. Its bytes are dropped.

	moveq	#%00100001,d0 ; Overrun, receiver full.
	and.b	$fffffc04.w,d0
	beq		.done

	tst.b	$fffffc06.w

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

	rts

; ------------------------------------------------------------------------------
;
; At start, in supervisor mode: an Xpad provider's block, through the
; cookie jar, checked as xpad_valid() does (the cookie's value even, the
; magic and major version, the pads inside the block); the address of pad
; 0 in each of its two buffers worked out once (a block's layout never
; changes). xpad_block = 0 if there is none. Preserves all registers.

find_xpad:
	movem.l	d0-d3/a0-a1,-(sp)

	clr.l	xpad_block
	move.l	#XPAD_COOKIE,d0
	jsr		find_cookie
	beq		.done

	tst.l	d0
	beq		.done

	btst	#0,d0
	bne		.done ; (A word read there would be an address error.)

	move.l	d0,a0
	cmp.l	#XPAD_MAGIC,XPAD_MAGIC_OFF(a0)
	bne		.done

	cmp.b	#XPAD_VER_MAJOR,XPAD_VERSION_OFF(a0)
	bne		.done

	moveq	#0,d0
	move.b	XPAD_PADCOUNT_OFF(a0),d0
	beq		.done

	cmp		#XPAD_MAX_PADS,d0
	bhi		.done

	move	XPAD_PADSIZE_OFF(a0),d1
	cmp		#XPAD_PAD_SIZE_V1,d1
	bcs		.done

	btst	#0,d1
	bne		.done

	move	d0,xpad_pad_count
	move	d1,xpad_pad_size
	mulu	d1,d0 ; One buffer's bytes.

	moveq	#0,d2
	move	XPAD_PADSOFF_OFF(a0),d2
	btst	#0,d2
	bne		.done

	move.l	d2,d1
	add.l	d0,d1
	add.l	d0,d1 ; The end of both buffers, inside the block?
	moveq	#0,d3
	move	XPAD_HDRSIZE_OFF(a0),d3
	cmp.l	d3,d1
	bhi		.done

	lea		(a0,d2.l),a1
	move.l	a1,xpad_buffer_0
	add.l	d0,a1
	move.l	a1,xpad_buffer_1
	move.l	a0,xpad_block

.done:
	movem.l	(sp)+,d0-d3/a0-a1

	rts

; ------------------------------------------------------------------------------
;
; Every VBL: the STE's enhanced joystick port A (a Jaguar pad: button A is
; trigger A, B is trigger B), and the Xpad pads. Preserves all registers.

input_tick:
	tst.l	xpad_block
	beq		.no_xpad

	bsr		read_xpad

.no_xpad:
	tst.b	machine_is_ste
	beq		.done

	movem.l	d0-d1,-(sp)
	move	sr,-(sp)
	or		#$0700,sr ; (A provider's Timer C poll selects rows too.)

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
	move	(sp)+,sr
	move.b	d1,pad_joystick_state

	movem.l	(sp)+,d0-d1

.done:
	rts

; The Xpad pads present, as one: their buttons ORed, from the front buffer;
; a torn read (the provider committed meanwhile: active or seq changed) is
; dropped, keeping the last state (the next is a VBL away). Preserves all
; registers.

read_xpad:
	movem.l	d0-d4/a0-a1,-(sp)

	move.l	xpad_block,a0
	move	XPAD_SEQ_OFF(a0),d1
	move.b	XPAD_ACTIVE_OFF(a0),d2 ; 0 or 1.
	move.l	xpad_buffer_0,a1
	tst.b	d2
	beq		.buffer

	move.l	xpad_buffer_1,a1

.buffer:
	moveq	#0,d3 ; Buttons.
	move	xpad_pad_count,d4
	subq	#1,d4

.pad_loop:
	tst.b	XPAD_PAD_TYPE(a1)
	beq		.absent

	or.l	XPAD_PAD_BUTTONS(a1),d3

.absent:
	add		xpad_pad_size,a1

	dbf		d4,.pad_loop

	cmp.b	XPAD_ACTIVE_OFF(a0),d2
	bne		.torn

	cmp		XPAD_SEQ_OFF(a0),d1
	bne		.torn

	; X68000 joystick bits (active low): the d-pad's are bits 0-3 too.

	moveq	#XPAD_UP|XPAD_DOWN|XPAD_LEFT|XPAD_RIGHT,d0
	and.b	d3,d0
	not.b	d0

	move.l	#XPAD_TRIGGER_A_BUTTONS,d1
	and.l	d3,d1
	beq		.no_trigger_a

	bclr	#X68_TRIGGER_A,d0

.no_trigger_a:
	move.l	#XPAD_TRIGGER_B_BUTTONS,d1
	and.l	d3,d1
	beq		.no_trigger_b

	bclr	#X68_TRIGGER_B,d0

.no_trigger_b:
	move.b	d0,xpad_joystick_state

	moveq	#0,d0
	and		#XPAD_START,d3
	beq		.no_start

	moveq	#1<<X68_ESC_GROUP_0_BIT,d0

.no_start:
	move.b	d0,xpad_matrix_escape

.torn:
	movem.l	(sp)+,d0-d4/a0-a1

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
	and.b	xpad_joystick_state,d0
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
	st		xpad_joystick_state
	sf		xpad_matrix_escape
	st		script_joystick_state
	st		last_joystick_state
	sf		in_stage
	sf		st_stage_frame
	sf		autofire_released
	clr.l	autofire_frames

	lea		keyboard_matrix,a0
	moveq	#(joystick_bit_counts+8-keyboard_matrix)/4-1,d0

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

	even

xpad_block: ; The provider's block, or 0.
	ds.l	1
xpad_buffer_0: ; Pad 0 in each buffer.
	ds.l	1
xpad_buffer_1:
	ds.l	1
xpad_pad_count:
	ds.w	1
xpad_pad_size:
	ds.w	1

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
xpad_joystick_state: ; The Xpad pads', as X68000 joystick bits.
	ds.b	1
xpad_matrix_escape: ; Key matrix group 0 bits from the Xpad pads (START: ESC).
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
