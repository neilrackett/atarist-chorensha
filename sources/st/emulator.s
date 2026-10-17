
; Human68k / X68000 emulation layer for the Atari ST, from the
; Falcon port's emulator.s, with the Amiga port's call coverage and frame
; scheduling. The game runs in supervisor mode with the machine taken over:
;
; - Human68k DOS and FLOAT calls are line-F opcodes ($FFxx / $FExx), served
;   with GEMDOS from the line-F exception (table at human68k_call_table).
; - IOCS (trap #15) is served in its trap; PCM8 (trap #2) and MCDRV (trap #4)
;   return at once (no music).
; - The 50 Hz VBL is the game's frame tick (as on the Falcon: the game runs
;   at 50 instead of 55.46 frames per second). The VBL interrupt counts it,
;   flips the screen and enters the game's VBL handler (which ends with RTE)
;   through a fake exception frame.
; - XSP_VSYNC and WAIT_VBL (amiga_xsp_vsync, amiga_wait_vbl: the names the
;   game's hooks call) follow a fixed schedule as on the Amiga: on time, the
;   finished frame is rendered and shown, then the call waits for its tick;
;   late, the picture is left out so the game keeps its speed. In lockstep
;   mode (F1) every frame is rendered and the frame waits run the game's VBL
;   handler themselves: the game slows down to the rendering speed.

	xdef start_emulator
	xdef st_exit_game
	xdef amiga_wait_vbl
	xdef amiga_xsp_vsync
	xdef vbl_handler
	xdef line_f_handler
	xdef trap_2_handler
	xdef trap_4_handler
	xdef trap_f_handler

	xdef exception_bus_error
	xdef exception_address_error
	xdef exception_illegal
	xdef exception_zero_divide
	xdef exception_chk
	xdef exception_trapv
	xdef exception_privilege
	xdef exception_line_a

	xdef heap_address
	xdef heap_size
	xdef frame_limit
	xdef frame_count
	xdef last_sprite_count
	xdef total_vbl_count
	xdef rendered_frames
	xdef poll_renders
	xdef lockstep_mode
	xdef exit_reason
	xdef exception_vector
	xdef exception_pc
	xdef exception_address
	xdef unimplemented_dos
	xdef unimplemented_iocs

	xref _start
	xref L_00000118
	xref L_00E82000
	xref L_00EB8000
	xref VBL_VWAIT_COUNTER
	xref frame_sprite_count

	xref joystick_now
	xref input_tick
	xref input_frame_end
	xref keyboard_matrix
	xref xpad_matrix_escape
	xref audio_play
	xref audio_status
	xref audio_stop
	xref audio_tick
	xref render_frame
	xref present_frame
	xref display_vbl
	xref hide_background
	xref read_timer
	xref measure_logic
	xref measure_picture
	xref record_checkpoint
	xref record_stage
	xref divide_unsigned
	xref write_screenshot

	include "st.i"

; 64 ticks (1.3 s): a picture on an 8 MHz ST takes about 25 ticks; it is
; caught up by skipping pictures, and only real pauses such as loading reset
; the schedule.

MAXIMUM_FRAME_DEBT=64

; _JOYGET's poll pictures: once no frame has ended for POLL_RENDER_TICKS.

POLL_RENDER_TICKS=3

; Screenshots of measurement runs (display.s write_screenshot).

SCREENSHOT_INTERVAL=500

MAXIMUM_UNIMPLEMENTED_DOS=8

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Starts the game the way Human68k starts a process: a0 = memory management
; block, a1 = end of program + 1, a2 = command line, a3 = environment, a4 =
; entry point. All point into the cleared process area (heap), which gives
; an empty command line and environment. Returns when the game exits.

start_emulator:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	sp,saved_stack_address

	move.l	#EXIT_GAME,exit_reason
	move.l	total_vbl_count,frame_schedule

	move.l	heap_address,a0
	move.l	a0,a1
	move.l	a0,a2
	move.l	a0,a3
	lea		_start,a4

	move	#$2300,sr ; Supervisor, the VBL and the MFP enabled.

	jmp		(a4)

; Leaves the game (EXIT in its menu, _EXIT, the frame limit, an exception):
; back to start_emulator's caller.

st_exit_game:
	move	#$2700,sr

	move.l	saved_stack_address,sp
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; VBL (level 4): the game's frame tick.

vbl_handler:
	movem.l	d0-d1/a0-a1,-(sp)

	addq.l	#1,total_vbl_count

	jsr		display_vbl
	jsr		input_tick
	jsr		audio_tick ; (An ST: the YM's effect.)

	movem.l	(sp)+,d0-d1/a0-a1

	tst.b	lockstep_mode
	bne		.done ; The frame waits run the game's handler.

	bsr		run_game_vbl

.done:
	rte

; One run of the game's VBL handler (from the VBL, or in lockstep from a
; frame wait). It ends with RTE: it gets an exception frame.

run_game_vbl:
	st		in_tick
	pea		.return(pc)
	move	sr,-(sp)
	move.l	L_00000118,-(sp)
	rts

.return:
	sf		in_tick

	rts

; Real time, the frame's ticks added to frame_schedule: N set if the game is
; on time (ahead of the VBLs). Late by more than MAXIMUM_FRAME_DEBT ticks,
; the schedule starts over. Uses d0.

check_schedule:
	move.l	total_vbl_count,d0
	sub.l	frame_schedule,d0
	bmi		.on_time

	cmp.l	#MAXIMUM_FRAME_DEBT,d0
	bls		.late

	move.l	total_vbl_count,frame_schedule ; Too far behind: start over.

.late:
	moveq	#0,d0 ; N clear.

.on_time:
	rts

; Waits until the schedule's tick. Uses d0.

wait_for_schedule:
	move.l	total_vbl_count,d0
	cmp.l	frame_schedule,d0
	bcc		.done

	bsr		wait_for_tick

	bra		wait_for_schedule

.done:
	rts

; Waits for the next interrupt (the VBL or the MFP).

wait_for_tick:
	move	sr,-(sp)
	stop	#$2300
	move	(sp)+,sr

	rts

; A change of mode restarts the schedule.

check_lockstep_change:
	move.b	lockstep_mode,d0
	cmp.b	lockstep_active,d0
	beq		.same

	move.b	d0,lockstep_active
	move.l	total_vbl_count,frame_schedule

.same:
	rts

; ------------------------------------------------------------------------------
;
; WAIT_VBL: d1.w = ticks - 1 (negative: none).

amiga_wait_vbl:
	movem.l	d0-d7/a0-a6,-(sp)

	move	d1,d7

	bsr		frame_wait_begin
	bsr		check_lockstep_change

	tst.b	lockstep_mode
	beq		.real_time

	; Lockstep: the picture, then d7 + 1 VBLs, one after the other.

	bsr		render_and_present

	tst		d7
	bmi		.done

.lockstep_loop:
	bsr		run_game_vbl
	dbf		d7,.lockstep_loop

	bra		.done

.real_time:
	ext.l	d7
	addq.l	#1,d7 ; Ticks.
	bpl		.ticks_ok

	moveq	#0,d7

.ticks_ok:
	add.l	d7,frame_schedule

	bsr		check_schedule
	bmi		.on_time

	tst.l	screenshot_due ; Late: no picture, except for a screenshot.
	beq		.done

	bsr		render_and_present

	bra		.done

.on_time:
	bsr		render_and_present
	bsr		wait_for_schedule

.done:
	bsr		frame_wait_end

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; XSP_VSYNC: d0.w = number of ticks this game frame lasts. Returns the game's
; VBL counter (VBL_VWAIT_COUNTER) in d0.w and clears it, as on the X68000.

amiga_xsp_vsync:
	movem.l	d1-d7/a0-a6,-(sp)

	moveq	#0,d7
	move	d0,d7

	bsr		frame_wait_begin
	bsr		check_lockstep_change

	add.l	d7,frame_schedule

	tst.b	lockstep_mode
	beq		.real_time

	; Lockstep: the frame's VBLs (d7), then its picture.

	subq	#1,d7
	bmi		.due

.lockstep_loop:
	bsr		run_game_vbl
	dbf		d7,.lockstep_loop

	bra		.due

.real_time:
	bsr		check_schedule
	bpl		.late

	bsr		wait_for_schedule

	bra		.due

.late:
	tst.l	screenshot_due ; Late: no picture, except for a screenshot.
	beq		.done

.due:
	bsr		render_and_present

.done:
	bsr		frame_wait_end

	movem.l	(sp)+,d1-d7/a0-a6

	move	VBL_VWAIT_COUNTER,d0
	clr		VBL_VWAIT_COUNTER

	rts

; ------------------------------------------------------------------------------
;
; Frame measurement: the time from the end of one frame wait to the start of
; the next one is the game's own work for that frame.

frame_wait_begin:
	ifnd __RELEASE__
	tst.b	frame_timed
	beq		.first

	jsr		read_timer
	sub.l	last_wake_time,d0
	jsr		measure_logic

.first:
	endif
	move	frame_sprite_count,last_sprite_count
	clr		frame_sprite_count

	rts

frame_wait_end:
	move.l	total_vbl_count,vbl_count_at_wake

	ifnd __RELEASE__
	jsr		read_timer
	move.l	d0,last_wake_time
	st		frame_timed
	endif

	addq.l	#1,frame_count

	; Measurement runs: a screenshot every SCREENSHOT_INTERVAL frames, of
	; the next frame (rendered even if late).

	tst.l	frame_limit
	beq		.no_screenshot

	subq	#1,screenshot_countdown
	bne		.no_screenshot

	move	#SCREENSHOT_INTERVAL,screenshot_countdown
	move.l	frame_count,screenshot_due

.no_screenshot:
	jsr		input_frame_end
	ifnd __RELEASE__
	jsr		record_checkpoint
	jsr		record_stage
	endif

	move.l	frame_limit,d0
	beq		.no_limit

	cmp.l	frame_count,d0
	bhi		.no_limit

	move.l	#EXIT_FRAME_LIMIT,exit_reason
	bra		st_exit_game

.no_limit:
	rts

; Renders and shows the frame the game has just finished; times both.

render_and_present:
	st		rendering
	addq.l	#1,rendered_frames

	ifd __RELEASE__
	jsr		render_frame
	jsr		present_frame
	else
	jsr		read_timer
	move.l	d0,d6

	ifnd __HEADLESS__
	jsr		render_frame
	endif

	jsr		read_timer
	move.l	d0,d5

	ifnd __HEADLESS__
	jsr		present_frame
	endif

	jsr		read_timer
	sub.l	d5,d0
	move.l	d0,d1 ; Presentation.
	move.l	d5,d0
	sub.l	d6,d0 ; Rendering.
	jsr		measure_picture
	endif

	move.l	screenshot_due,d0
	beq		.no_screenshot

	clr.l	screenshot_due
	jsr		write_screenshot

.no_screenshot:
	sf		rendering

	rts

; ------------------------------------------------------------------------------
;
; Exceptions in the game or the port: the vector and the PC are kept for the
; exit report (main.s), and the game is left.

exception_bus_error:
	move	#2,exception_vector

	bra		group_0_exception

exception_address_error:
	move	#3,exception_vector

group_0_exception:
	; Function code, access address, instruction, SR, PC.

	move.l	2(sp),exception_address
	move.l	10(sp),exception_pc

	bra		report_exception

exception_illegal:
	move	#4,exception_vector

	bra		group_2_exception

exception_zero_divide:
	move	#5,exception_vector

	bra		group_2_exception

exception_chk:
	move	#6,exception_vector

	bra		group_2_exception

exception_trapv:
	move	#7,exception_vector

	bra		group_2_exception

exception_privilege:
	move	#8,exception_vector

	bra		group_2_exception

exception_line_a:
	move	#10,exception_vector

group_2_exception:
	move.l	2(sp),exception_pc ; SR, PC.

report_exception:
	move.l	#EXIT_EXCEPTION,exit_reason

	bra		st_exit_game

; ------------------------------------------------------------------------------
;
; Human68k DOS and FLOAT calls (line-F opcodes): frame SR at 56(sp), PC (the
; opcode) at 58(sp) after saving d1-d7/a0-a6; the call's arguments follow
; the frame. Each routine gets a5 = arguments and the caller's d0-d5 and
; a0-a2; result in d0. All other registers are preserved.

line_f_handler:
	movem.l	d1-d7/a0-a6,-(sp)

	move.l	56+2(sp),a3
	move	(a3),d7 ; The opcode.
	addq.l	#2,56+2(sp)
	lea		56+6(sp),a5

	lea		human68k_call_table,a3

.find:
	move	(a3)+,d6
	beq		.unimplemented

	move.l	(a3)+,a4
	cmp		d6,d7
	bne		.find

	jsr		(a4)

.exit:
	movem.l	(sp)+,d1-d7/a0-a6

	rte

.unimplemented:
	; Remembered for the exit report (once each); returns 0.

	lea		unimplemented_dos,a3
	moveq	#MAXIMUM_UNIMPLEMENTED_DOS-1,d6

.remember:
	cmp		(a3),d7
	beq		.remembered

	tst		(a3)
	beq		.free_entry

	addq.l	#2,a3
	dbf		d6,.remember

	bra		.remembered

.free_entry:
	move	d7,(a3)

.remembered:
	moveq	#0,d0

	bra		.exit

; __LMUL: d0 = d0 * d1 (the low 32 bits, signed or unsigned).

human68k_lmul:
	move.l	d0,d2
	move.l	d1,d3
	swap	d2
	swap	d3
	mulu	d1,d2 ; High(d0) * low(d1).
	mulu	d0,d3 ; High(d1) * low(d0).
	add		d3,d2
	swap	d2
	clr		d2
	mulu	d1,d0 ; Low * low.
	add.l	d2,d0

	rts

; __LDIV: d0 = d0 / d1, signed (truncated toward zero; / 0 gives 0).

human68k_ldiv:
	moveq	#0,d4 ; Sign of the result.
	tst.l	d0
	bpl		.dividend_positive

	neg.l	d0
	not		d4

.dividend_positive:
	tst.l	d1
	bpl		.divisor_positive

	neg.l	d1
	not		d4

.divisor_positive:
	jsr		divide_unsigned

	tst		d4
	beq		.done

	neg.l	d0

.done:
	rts

human68k_return_zero:
	moveq	#0,d0

	rts

; _INPOUT(code.w): $FE/$FF read a key without waiting: a key held in the
; X68000 key matrix reads as RETURN, none as 0 (the game waits with it after
; an error message). Other codes (output) do nothing.

human68k_inpout:
	move	(a5),d1
	cmp		#$fe,d1
	bcs		human68k_return_zero

	lea		keyboard_matrix,a0
	moveq	#16/4-1,d1

.matrix:
	tst.l	(a0)+
	bne		.key

	dbf		d1,.matrix

	bra		human68k_return_zero

.key:
	moveq	#$0d,d0

	rts

human68k_exit:
	bra		st_exit_game

human68k_dskfre:
	move.l	#10000000,d0

	rts

human68k_getpdb:
	move.l	heap_address,d0
	add.l	#16,d0

	rts

; _NAMECK(name.l, buffer.l): splits a file name into the Human68k NAMECK
; structure: drive (2 bytes, "A:"), path (65, "\dir\"), name (19) and
; extension (5, ".ext"), each zero-terminated. Returns 0 (no wildcards).
; (The Amiga port's.)

NAMECK_DRIVE=0
NAMECK_PATH=2
NAMECK_NAME=67
NAMECK_EXTENSION=86
NAMECK_SIZE=91

human68k_nameck:
	move.l	4(a5),a1
	move.l	a1,a2
	moveq	#NAMECK_SIZE-1,d0

.clear:
	clr.b	(a2)+
	dbf		d0,.clear

	move.l	(a5),a0

	move.b	#'A',NAMECK_DRIVE(a1)
	move.b	#':',NAMECK_DRIVE+1(a1)

	tst.b	(a0)
	beq		.split

	cmp.b	#':',1(a0)
	bne		.split

	move.b	(a0),NAMECK_DRIVE(a1)
	addq.l	#2,a0

.split:
	move.l	a0,a2
	move.l	a0,a3

.find_name:
	move.b	(a3)+,d0
	beq		.name_found

	cmp.b	#'\',d0
	beq		.separator

	cmp.b	#'/',d0
	bne		.find_name

.separator:
	move.l	a3,a2

	bra		.find_name

.name_found:
	lea		NAMECK_PATH(a1),a3
	move.b	#'\',(a3)+
	moveq	#64-2,d1

.copy_path:
	cmp.l	a2,a0
	bcc		.path_done

	move.b	(a0)+,d0
	cmp.b	#'/',d0
	bne		.store_path

	moveq	#'\',d0

.store_path:
	cmp.b	#'\',d0
	bne		.not_leading

	cmp.b	#'\',-1(a3)
	beq		.copy_path

.not_leading:
	move.b	d0,(a3)+

	dbf		d1,.copy_path

.path_done:
	cmp.b	#'\',-1(a3)
	beq		.copy_name

	move.b	#'\',(a3)+

.copy_name:
	lea		NAMECK_NAME(a1),a3
	moveq	#18-1,d1

.name_loop:
	move.b	(a0),d0
	beq		.done

	cmp.b	#'.',d0
	beq		.extension

	move.b	d0,(a3)+
	addq.l	#1,a0

	dbf		d1,.name_loop

.skip_name:
	move.b	(a0),d0
	beq		.done

	cmp.b	#'.',d0
	beq		.extension

	addq.l	#1,a0

	bra		.skip_name

.extension:
	lea		NAMECK_EXTENSION(a1),a3
	moveq	#4-1,d1

.extension_loop:
	move.b	(a0)+,d0
	beq		.done

	move.b	d0,(a3)+

	dbf		d1,.extension_loop

.done:
	moveq	#0,d0

	rts

; _SETBLOCK(block.l, size.l): resize the process memory block, which ends at
; the end of the process area. On failure returns $81000000 + the largest
; possible size.

human68k_setblock:
	move.l	heap_address,d1
	add.l	heap_size,d1
	sub.l	(a5),d1 ; Largest possible size.

	cmp.l	4(a5),d1
	bcs		.too_large

	moveq	#0,d0

	rts

.too_large:
	move.l	d1,d0
	or.l	#$81000000,d0

	rts

; _OPEN(name.l, mode.w): GEMDOS Fopen (the same modes).

human68k_open:
	move	4(a5),-(sp)
	move.l	(a5),-(sp)
	move	#61,-(sp)
	trap	#1
	addq.l	#8,sp

	rts

; _CREATE(name.l, attributes.w): GEMDOS Fcreate (normal file).

human68k_create:
	clr		-(sp)
	move.l	(a5),-(sp)
	move	#60,-(sp)
	trap	#1
	addq.l	#8,sp

	rts

; _CLOSE(handle.w)

human68k_close:
	move	(a5),-(sp)
	move	#62,-(sp)
	trap	#1
	addq.l	#4,sp

	rts

; _READ(handle.w, buffer.l, length.l)

human68k_read:
	move.l	2(a5),-(sp)
	move.l	6(a5),d0
	and.l	#$7fffffff,d0
	move.l	d0,-(sp)
	move	(a5),-(sp)
	move	#63,-(sp)
	trap	#1
	lea		12(sp),sp

	rts

; _WRITE(handle.w, buffer.l, length.l)

human68k_write:
	move.l	2(a5),-(sp)
	move.l	6(a5),-(sp)
	move	(a5),-(sp)
	move	#64,-(sp)
	trap	#1
	lea		12(sp),sp

	rts

; _SEEK(handle.w, offset.l, mode.w): GEMDOS Fseek (the same modes).

human68k_seek:
	move	6(a5),-(sp)
	move	(a5),-(sp)
	move.l	2(a5),-(sp)
	move	#66,-(sp)
	trap	#1
	lea		10(sp),sp

	rts

; _DELETE(name.l)

human68k_delete:
	move.l	(a5),-(sp)
	move	#65,-(sp)
	trap	#1
	addq.l	#6,sp

	rts

; ------------------------------------------------------------------------------

trap_2_handler: ; PCM8.
	rte

trap_4_handler: ; MCDRV.
	rte

; ------------------------------------------------------------------------------
;
; IOCS (trap #15): d0.b = function, arguments in d1-d5/a1, result in d0. All
; other registers are preserved.

trap_f_handler:
	cmp.b	#$3b,d0 ; _JOYGET
	beq		iocs_joyget

	cmp.b	#$81,d0 ; _B_SUPER: "already in supervisor mode".
	bne		.not_b_super

	moveq	#-1,d0

	rte

.not_b_super:
	cmp.b	#$04,d0 ; _BITSNS
	bne		.not_bitsns

	move.l	a0,-(sp)

	lea		keyboard_matrix,a0
	moveq	#$f,d0
	and		d1,d0
	bne		.matrix_group

	move.b	(a0),d0
	or.b	xpad_matrix_escape,d0 ; An Xpad pad's START: ESC.

	bra		.matrix_read

.matrix_group:
	move.b	(a0,d0.w),d0

.matrix_read:
	and.l	#$ff,d0

	move.l	(sp)+,a0

	rte

.not_bitsns:
	cmp.b	#$92,d0 ; _VC_R1: d1.w = new R1 (layer priorities), -1 reads it.
	bne		.not_vc_r1

	moveq	#0,d0
	move	L_00E82000+$500,d0 ; Returns the previous value.
	cmp		#-1,d1
	beq		.vc_r1_done

	move	d1,L_00E82000+$500

.vc_r1_done:
	rte

.not_vc_r1:
	cmp.b	#$14,d0 ; _TPALET2: d1 = entry, d2 = colour (-1 reads it).
	bne		.not_tpalet2

	movem.l	d1/a0,-(sp)

	lea		L_00E82000+$200,a0
	and		#$f,d1
	add		d1,d1

	moveq	#0,d0

	tst.l	d2
	bmi		.tpalet2_get_colour

	move	d2,(a0,d1.w)

	bra		.tpalet2_done

.tpalet2_get_colour:
	move	(a0,d1.w),d0

.tpalet2_done:
	movem.l	(sp)+,d1/a0

	rte

.not_tpalet2:
	cmp.b	#$cf,d0 ; _SPALET: d1 = entry, d2 = palette block, d3 = colour.
	bne		.not_spalet

	movem.l	d2/a0,-(sp)

	lea		L_00E82000+$200,a0
	lsl		#4,d2
	add		d1,d2
	add		d2,d2

	moveq	#0,d0

	tst.l	d3
	bmi		.spalet_get_colour

	move	d3,(a0,d2.w)

	bra		.spalet_done

.spalet_get_colour:
	move	(a0,d2.w),d0

.spalet_done:
	movem.l	(sp)+,d2/a0

	rte

.not_spalet:
	cmp.b	#$ce,d0 ; _BGTEXTGT: d1 = BG page, d2 = x, d3 = y (0-63).
	bne		.not_bgtextgt

	; The word in the page's map in the sprite VRAM shadow ($EBC000 /
	; $EBE000).

	movem.l	d1-d3/a0,-(sp)

	lea		L_00EB8000+$4000,a0
	btst	#0,d1
	beq		.bg_page_0

	lea		$2000(a0),a0

.bg_page_0:
	and		#63,d3
	lsl		#6,d3
	and		#63,d2
	add		d2,d3
	add		d3,d3
	moveq	#0,d0
	move	(a0,d3.w),d0

	movem.l	(sp)+,d1-d3/a0

	rte

.not_bgtextgt:
	cmp.b	#$60,d0 ; _ADPCMOUT
	bne		.not_adpcmout

	jsr		audio_play

	bra		.return_zero

.not_adpcmout:
	cmp.b	#$66,d0 ; _ADPCMSNS
	bne		.not_adpcmsns

	jsr		audio_status

	rte

.not_adpcmsns:
	cmp.b	#$67,d0 ; _ADPCMMOD: 0 stops.
	bne		.not_adpcmmod

	tst.l	d1
	bne		.return_zero

	jsr		audio_stop

	bra		.return_zero

.not_adpcmmod:
	cmp.b	#$7f,d0 ; _ONTIME (fixed, as on the Falcon: replays stay deterministic)
	bne		.not_ontime

	move.l	#100*100,d0
	moveq	#0,d1

	rte

.not_ontime:
	cmp.b	#$b2,d0 ; _VPAGE: d1 = the graphics pages shown; none: no background.
	bne		.not_vpage

	btst	#0,d1
	bne		.return_zero

	btst	#1,d1
	bne		.return_zero

	jsr		hide_background

	bra		.return_zero

.not_vpage:
	cmp.b	#$b5,d0 ; _WIPE: GVRAM cleared: no background.
	beq		.no_background

	cmp.b	#$90,d0 ; _G_CLR_ON: likewise.
	bne		.not_g_clr_on

.no_background:
	jsr		hide_background

	bra		.return_zero

.not_g_clr_on:
	; Known calls that do nothing here (0), else remembered for the exit
	; report (and 0).

	move.l	a0,-(sp)
	lea		known_iocs_calls,a0

.known_loop:
	cmp.b	(a0),d0
	beq		.known

	tst.b	(a0)+
	bne		.known_loop

	lea		unimplemented_iocs,a0
	and		#$ff,d0
	st		(a0,d0.w)

.known:
	move.l	(sp)+,a0

.return_zero:
	moveq	#0,d0

	rte

; _JOYGET: the current state (the game also polls it in loops that complete
; no frame: the pause, the name entry's wait for the buttons' release, and
; draws in them). Once no frame has ended for POLL_RENDER_TICKS, the screen
; is shown as it is, at most once per tick; not from the game's VBL handler
; (it calls _JOYGET too) and not while rendering.

iocs_joyget:
	jsr		joystick_now

	tst.b	in_tick
	bne		.done

	tst.b	rendering
	bne		.done

	move.l	d1,-(sp)

	move.l	total_vbl_count,d1
	cmp.l	poll_render_tick,d1
	beq		.no_poll

	sub.l	vbl_count_at_wake,d1
	cmp.l	#POLL_RENDER_TICKS,d1
	bcs		.no_poll

	move.l	total_vbl_count,poll_render_tick

	movem.l	d0-d7/a0-a6,-(sp)

	addq.l	#1,poll_renders
	st		rendering

	ifnd __HEADLESS__
	jsr		render_frame
	jsr		present_frame
	endif

	sf		rendering

	movem.l	(sp)+,d0-d7/a0-a6

.no_poll:
	move.l	(sp)+,d1

.done:
	rte

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

screenshot_countdown:
	dc.w	SCREENSHOT_INTERVAL

; IOCS calls the game makes that need nothing here (zero-terminated):
; _CRTMOD, _B_PUTC, _B_COLOR, _B_LOCATE, _SKEY_MOD, _B_WPOKE, _OS_CURON,
; _OS_CUROFF, _APAGE, _HOME, _WINDOW, _SP_ON, _SP_OFF, _BGCTRLST.

known_iocs_calls:
	dc.b	$10,$20,$22,$23,$7d,$87,$ae,$af,$b1,$b3,$b4,$c1,$c2,$ca
	dc.b	0

	even

human68k_call_table:
	dc.w	$fe00 ; __LMUL
	dc.l	human68k_lmul
	dc.w	$fe01 ; __LDIV
	dc.l	human68k_ldiv
	dc.w	$fe0d ; __SRAND
	dc.l	human68k_return_zero
	dc.w	$ff00 ; _EXIT
	dc.l	human68k_exit
	dc.w	$ff06 ; _INPOUT
	dc.l	human68k_inpout
	dc.w	$ff09 ; _PRINT (the game's messages; not shown)
	dc.l	human68k_return_zero
	dc.w	$ff0d ; _FFLUSH
	dc.l	human68k_return_zero
	dc.w	$ff20 ; _SUPER
	dc.l	human68k_return_zero
	dc.w	$ff21 ; _FNCKEY
	dc.l	human68k_return_zero
	dc.w	$ff23 ; _CONCTRL
	dc.l	human68k_return_zero
	dc.w	$ff25 ; _INTVCS
	dc.l	human68k_return_zero
	dc.w	$ff36 ; _DSKFRE
	dc.l	human68k_dskfre
	dc.w	$ff37 ; _NAMECK
	dc.l	human68k_nameck
	dc.w	$ff3c ; _CREATE
	dc.l	human68k_create
	dc.w	$ff3d ; _OPEN
	dc.l	human68k_open
	dc.w	$ff3e ; _CLOSE
	dc.l	human68k_close
	dc.w	$ff3f ; _READ
	dc.l	human68k_read
	dc.w	$ff40 ; _WRITE
	dc.l	human68k_write
	dc.w	$ff41 ; _DELETE
	dc.l	human68k_delete
	dc.w	$ff42 ; _SEEK
	dc.l	human68k_seek
	dc.w	$ff44 ; _IOCTRL
	dc.l	human68k_return_zero
	dc.w	$ff4a ; _SETBLOCK
	dc.l	human68k_setblock
	dc.w	$ff4c ; _EXIT2
	dc.l	human68k_exit
	dc.w	$ff51 ; _GETPDB
	dc.l	human68k_getpdb
	dc.w	0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

saved_stack_address:
	ds.l	1
heap_address:
	ds.l	1
heap_size:
	ds.l	1
exit_reason:
	ds.l	1
exception_pc:
	ds.l	1
exception_address:
	ds.l	1
frame_limit:
	ds.l	1
frame_count:
	ds.l	1
frame_schedule:
	ds.l	1
total_vbl_count:
	ds.l	1
vbl_count_at_wake:
	ds.l	1
poll_render_tick:
	ds.l	1
last_wake_time:
	ds.l	1
rendered_frames:
	ds.l	1
poll_renders:
	ds.l	1
screenshot_due: ; Frame number of a pending screenshot, or 0.
	ds.l	1

exception_vector:
	ds.w	1
last_sprite_count:
	ds.w	1
unimplemented_dos: ; Opcodes, 0 = free.
	ds.w	MAXIMUM_UNIMPLEMENTED_DOS
unimplemented_iocs: ; Per function: non-zero if called.
	ds.b	256

lockstep_mode:
	ds.b	1
lockstep_active:
	ds.b	1
in_tick:
	ds.b	1
rendering:
	ds.b	1
frame_timed:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
