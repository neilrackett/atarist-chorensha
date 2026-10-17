
; Cho Ren Sha 68k: Atari ST port, from the Falcon
; port's main.s: memory set-up, machine detection, start-up and exit report.
;
; Memory: the TOS program (text, data, BSS: the X68000 shadows, GVRAM, the
; renderer) is followed by the game's Human68k process area (HEAP_SIZE,
; cleared, so its high-water mark can be measured at exit); the rest of the
; TPA is given back. The start-up text shows the TPA, the program's size and
; the memory left free.
;
; FRAMES.TXT (optional, next to the program): a number of frames; the game
; then exits after that many frames (the attract demo, for measurements) and
; writes CHECKPTS.BIN.
;
; MEGASTE8.TXT (optional): keep a Mega STE at 8 MHz without its cache (for
; comparisons; by default a Mega STE runs at 16 MHz with the cache on).
;
; LOCKSTEP.TXT (optional): start in lockstep mode (every frame shown, the
; game slowed down to the rendering speed; F1 switches).

	xdef start

	xref detect_machine
	xref initialize_machine
	xref release_machine
	ifd __OVERSCAN__
	xref machine_type
	xref _port_overscan_open ; (stdl_glue.c)
	xref _port_overscan_close
	xref _port_overscan_misses
	xref screen_buffers
	endif
	xref machine_is_st
	xref machine_has_ste_hardware
	xref ym_effects_played
	xref ym_effects_unknown
	xref load_ym_effects
	xref ym_file_name
	xref machine_is_ste
	xref machine_is_mega_ste
	xref set_cpu_speed
	xref restore_cpu_speed
	xref force_8mhz
	xref mega_ste_control
	xref initialize_display
	xref initialize_renderer
	xref release_renderer
	xref arena_size
	xref cache_resets
	xref half_switches
	xref masters_made
	xref shifts_made
	xref reset_input
	xref load_input_script
	xref start_emulator
	xref heap_address
	xref heap_size
	xref frame_limit
	xref frame_count
	xref total_vbl_count
	xref rendered_frames
	xref poll_renders
	xref exit_reason
	xref exception_vector
	xref exception_pc
	xref exception_address
	xref unimplemented_dos
	xref unimplemented_iocs
	xref print_text
	xref line_end_text
	xref space_dollar_text
	xref print_number
	xref print_tenths
	xref print_hex
	xref print_measurements
	xref write_checkpoints
	xref print_stages
	xref write_usage
	xref divide_unsigned
	xref find_xpad
	xref xpad_block
	xref xpad_pad_count
	xref times_500
	xref lockstep_mode

HEAP_SIZE=$100000 ; The game's process area: PSP, game stack (64 KB), heap.
HEAP_SIZE_ST=HEAP_SIZE-$60000 ; An ST loads no samples (370 KB): 640 KB.

	include "st.i"

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start:
	move.l	4(sp),a0 ; Basepage.
	lea		my_stack,sp ; In the BSS (the TPA's top is given back).

	move.l	a0,basepage
	move.l	8(a0),text_base

	move.l	4(a0),d0 ; TPA: p_hitpa - p_lowtpa.
	sub.l	(a0),d0
	move.l	d0,tpa_size

	move.l	#256,d0
	add.l	12(a0),d0
	add.l	20(a0),d0
	add.l	28(a0),d0
	move.l	d0,program_size

	; The process area follows the BSS (long aligned).

	move.l	a0,d1
	add.l	d0,d1
	addq.l	#3,d1
	and.b	#$fc,d1
	move.l	d1,heap_address

	pea		welcome_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	; Super mode (the stack stays my_stack), and the machine.

	clr.l	-(sp)
	move	#32,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,old_stack_address

	jsr		detect_machine

	; The process area's size: smaller on an ST, which loads no samples
	; (the YM plays its own versions of the effects).

	move.l	#HEAP_SIZE,d0
	tst.b	machine_has_ste_hardware
	bne		.heap_size_known

	move.l	#HEAP_SIZE_ST,d0

.heap_size_known:
	move.l	d0,heap_size
	move.l	heap_address,d1
	sub.l	basepage,d1
	add.l	d0,d1
	move.l	d1,kept_size

	cmp.l	tpa_size,d1
	bls		.memory_ok

	lea		no_memory_text,a0
	bsr		print_kilobytes_line

	bra		.wait_and_exit

.memory_ok:
	; Free the rest of the TPA.

	move.l	kept_size,-(sp)
	move.l	basepage,-(sp)
	clr		-(sp)
	move	#74,-(sp) ; Mshrink
	trap	#1
	lea		12(sp),sp

	tst.b	machine_is_st
	bne		.machine_ok

	tst.b	machine_has_ste_hardware ; An STE or a Mega STE.
	bne		.machine_ok

	lea		wrong_machine_text,a0
	jsr		print_text

	bra		.wait_and_exit

.machine_ok:
	; The game's data, next to the program (without it the game stops at
	; once, its message in black).

	lea		data_files,a1

.data_loop:
	move.l	(a1)+,d0
	beq		.data_found

	move.l	d0,a0
	bsr		file_exists
	bne		.data_loop

	; a0 = the missing file's name.

.data_missing:
	move.l	a0,-(sp)
	lea		no_data_text,a0
	jsr		print_text
	move.l	(sp)+,a0
	jsr		print_text
	lea		no_data_help_text,a0
	jsr		print_text

	bra		.wait_and_exit

.data_found:
	lea		st_text,a0
	tst.b	machine_is_st
	bne		.machine_text

	lea		ste_text,a0
	tst.b	machine_is_ste
	bne		.machine_text

	lea		mega_ste_text,a0

.machine_text:
	jsr		print_text

	jsr		find_xpad
	tst.l	xpad_block
	beq		.no_xpad

	lea		xpad_text,a0
	jsr		print_text
	moveq	#0,d0
	move	xpad_pad_count,d0
	jsr		print_number
	lea		xpad_end_text,a0
	jsr		print_text

.no_xpad:

	tst.b	machine_is_mega_ste
	beq		.speed_done

	lea		megaste8_file_name,a0
	bsr		file_exists
	sne		force_8mhz

	jsr		set_cpu_speed
	bsr		print_cpu_speed

.speed_done:

	bsr		read_frame_limit
	bsr		read_lockstep

	; An ST: its YM effects (before the sprite arena takes the rest).

	tst.b	machine_has_ste_hardware
	bne		.effects_loaded

	jsr		load_ym_effects
	bpl		.effects_loaded

	lea		ym_file_name,a0

	bra		.data_missing

.effects_loaded:
	jsr		initialize_display
	jsr		initialize_renderer

	tst.l	arena_size
	bne		.arena_ok ; (Without one no sprite would be drawn.)

	lea		no_arena_text,a0
	jsr		print_text
	jsr		restore_cpu_speed

	bra		.wait_and_exit

.arena_ok:
	jsr		reset_input
	jsr		load_input_script

	bsr		print_memory

	lea		starting_text,a0
	jsr		print_text

	; Cleared process area (the high-water mark is found at exit).

	move.l	heap_address,a0
	move.l	heap_size,d0
	lsr.l	#4,d0
	subq.l	#1,d0
	moveq	#0,d1

.clear_heap:
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	subq.l	#1,d0
	bpl		.clear_heap

	jsr		initialize_machine

	ifd __OVERSCAN__
	move	#$2300,sr ; (Opening the borders watches frames.)
	bsr		open_overscan
	endif

	jsr		start_emulator

	ifd __OVERSCAN__
	move	#$2300,sr ; (Closing them waits for frames.)
	jsr		_port_overscan_close
	jsr		_port_overscan_misses
	move.l	d0,overscan_misses
	endif

	jsr		release_machine

	move	#$2300,sr

	jsr		release_renderer

	ifd __RELEASE__
	cmp.l	#EXIT_GAME,exit_reason
	beq		.exit ; Back to the desktop (the report only after an exception).
	endif

	bsr		print_report

	tst.b	machine_is_mega_ste
	beq		.no_speed_report

	bsr		print_cpu_speed

.no_speed_report:

	tst.l	frame_limit
	beq		.wait_and_exit

	jsr		write_checkpoints

	ifd __USAGE__
	jsr		write_usage
	endif

	lea		run_end_text,a0 ; (Its files are written: tests stop here.)
	jsr		print_text

	bra		.exit

.wait_and_exit:
	lea		press_key_text,a0
	jsr		print_text

	move	#7,-(sp) ; Crawcin
	trap	#1
	addq.l	#2,sp

.exit:
	move.l	old_stack_address,-(sp)
	move	#32,-(sp)
	trap	#1
	addq.l	#6,sp

	clr		-(sp)
	trap	#1

; ------------------------------------------------------------------------------
;
; FRAMES.TXT: a decimal frame limit (none if the file is missing).

read_frame_limit:
	clr.l	frame_limit

	clr		-(sp)
	pea		frames_file_name
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.done

	move	d0,d3

	clr.l	frames_buffer
	clr.l	frames_buffer+4
	clr.l	frames_buffer+8
	clr.l	frames_buffer+12

	pea		frames_buffer
	move.l	#15,-(sp)
	move	d3,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp

	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	lea		frames_buffer,a0
	moveq	#0,d0

.digit_loop:
	moveq	#0,d1
	move.b	(a0)+,d1
	sub.b	#'0',d1
	bcs		.parsed

	cmp.b	#9,d1
	bhi		.parsed

	move.l	d0,d2 ; * 10
	lsl.l	#3,d0
	add.l	d2,d0
	add.l	d2,d0
	add.l	d1,d0

	bra		.digit_loop

.parsed:
	move.l	d0,frame_limit
	beq		.done

	lea		frame_limit_text,a0
	jsr		print_text
	jsr		print_number
	lea		line_end_text,a0
	jsr		print_text

.done:
	rts

; LOCKSTEP.TXT present: lockstep mode from the start.

read_lockstep:
	lea		lockstep_file_name,a0
	bsr		file_exists
	beq		.done

	st		lockstep_mode

	lea		lockstep_text,a0
	jsr		print_text

.done:
	rts

; a0 = file name: Z clear if the file exists (Fopen succeeds). Preserves
; a0.

file_exists:
	move.l	a0,-(sp)

	clr		-(sp)
	move.l	a0,-(sp)
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.missing

	move	d0,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	move.l	(sp)+,a0
	moveq	#1,d0 ; Z clear.

	rts

.missing:
	move.l	(sp)+,a0
	moveq	#0,d0 ; Z set.

	rts

; The Mega STE's speed, as $FFFF8E21 reads back.

print_cpu_speed:
	lea		cpu_text,a0
	jsr		print_text

	moveq	#0,d0
	move.b	mega_ste_control,d0
	moveq	#2,d1
	jsr		print_hex

	lea		cpu_8mhz_text,a0
	btst	#1,d0
	beq		.speed

	lea		cpu_16mhz_text,a0

.speed:
	jsr		print_text

	lea		cpu_no_cache_text,a0
	btst	#0,d0
	beq		.cache

	lea		cpu_cache_text,a0

.cache:
	jmp		print_text

; ------------------------------------------------------------------------------

	ifd __OVERSCAN__

; Both borders open (STDL's code, in stdl_glue.c), after the take-over with
; the interrupts on: the screens' pages 274 lines tall, 273 of them shown.
; On a machine where they do not open, the pages show their first 200
; lines. The first opening calibrates (a frame or two) and finds the
; GLUE's bottom border test (a third of a second of flickering border).

open_overscan:
	movem.l	d0-d1/a0-a1,-(sp)

	pea		overscan_error
	move.l	machine_type,d0
	bpl		.cookie

	moveq	#0,d0 ; No _MCH: an ST.

.cookie:
	move.l	d0,-(sp)
	move	#3,-(sp) ; Logbase: TOS's screen, given back at the close.
	trap	#14
	addq.l	#2,sp
	move.l	d0,-(sp)
	move.l	screen_buffers,d0
	sub.l	#SCREEN_TOP*SCREEN_LINE,d0 ; The first screen's page.
	move.l	d0,-(sp)
	jsr		_port_overscan_open
	lea		16(sp),sp
	move.l	d0,overscan_lines

	movem.l	(sp)+,d0-d1/a0-a1

	rts

; Exit report: the borders, and the frames that showed them closed.

print_overscan:
	lea		overscan_text,a0
	jsr		print_text
	move.l	overscan_lines,d0
	beq		.closed

	jsr		print_number
	lea		overscan_lines_text,a0
	jsr		print_text
	move.l	overscan_misses,d0
	jsr		print_number
	lea		line_end_text,a0
	jmp		print_text

.closed:
	lea		overscan_closed_text,a0
	jsr		print_text
	move.l	overscan_error,a0
	jsr		print_text
	lea		line_end_text,a0
	jmp		print_text

	endif

; ------------------------------------------------------------------------------

print_memory:
	lea		tpa_text,a0
	move.l	tpa_size,d0
	bsr		print_kilobytes

	lea		program_text,a0
	move.l	program_size,d0
	bsr		print_kilobytes

	lea		heap_text,a0
	move.l	heap_size,d0
	bsr		print_kilobytes

	lea		arena_text,a0
	move.l	arena_size,d0
	bsr		print_kilobytes

	; The largest block left: Malloc(-1).

	pea		-1.w
	move	#72,-(sp)
	trap	#1
	addq.l	#6,sp

	lea		free_text,a0
	bsr		print_kilobytes

	lea		kilobytes_end_text,a0
	jmp		print_text

; a0 = text, d0.l = bytes: the text, then d0 in KB.

print_kilobytes:
	jsr		print_text

	add.l	#1023,d0
	moveq	#10,d1
	lsr.l	d1,d0
	jmp		print_number

print_kilobytes_line:
	move.l	kept_size,d0
	bsr		print_kilobytes
	lea		of_text,a0
	move.l	tpa_size,d0
	bsr		print_kilobytes
	lea		kilobytes_end_text,a0
	jmp		print_text

; ------------------------------------------------------------------------------
;
; The exit report (the machine is released).

print_report:
	lea		exit_text,a0
	jsr		print_text

	move.l	exit_reason,d0
	lea		exit_frame_limit_text,a0
	cmp.l	#EXIT_FRAME_LIMIT,d0
	beq		.reason

	lea		exit_game_text,a0
	cmp.l	#EXIT_GAME,d0
	beq		.reason

	lea		exit_exception_text,a0
	jsr		print_text

	moveq	#0,d0
	move	exception_vector,d0
	jsr		print_number

	lea		exception_pc_text,a0
	jsr		print_text

	move.l	exception_pc,d0
	sub.l	text_base,d0
	moveq	#6,d1
	jsr		print_hex

	cmp		#3,exception_vector
	bhi		.no_address

	lea		exception_address_text,a0
	jsr		print_text

	move.l	exception_address,d0
	moveq	#8,d1
	jsr		print_hex

.no_address:
	lea		line_end_text,a0

.reason:
	jsr		print_text

	; Frames, ticks, pictures.

	lea		frames_text,a0
	jsr		print_text
	move.l	frame_count,d0
	jsr		print_number

	lea		ticks_text,a0
	jsr		print_text
	move.l	total_vbl_count,d0
	jsr		print_number

	lea		pictures_text,a0
	jsr		print_text
	move.l	rendered_frames,d0
	jsr		print_number

	lea		poll_pictures_text,a0
	jsr		print_text
	move.l	poll_renders,d0
	jsr		print_number

	lea		per_second_text,a0
	jsr		print_text

	move.l	rendered_frames,d0 ; Pictures per second (tenths): * 500 / ticks.
	jsr		times_500
	move.l	total_vbl_count,d1
	jsr		divide_unsigned
	jsr		print_tenths

	lea		line_end_text,a0
	jsr		print_text

	jsr		print_measurements
	jsr		print_stages

	ifd __OVERSCAN__
	bsr		print_overscan
	endif

	; Heap high-water mark: the area was cleared at start.

	move.l	heap_address,a0
	move.l	a0,a1
	add.l	heap_size,a1

.high_water_loop:
	cmp.l	a0,a1
	beq		.high_water_found

	tst.l	-(a1)
	beq		.high_water_loop

	addq.l	#4,a1

.high_water_found:
	sub.l	a0,a1
	move.l	a1,d0
	lea		heap_used_text,a0
	bsr		print_kilobytes
	lea		of_text,a0
	move.l	heap_size,d0
	bsr		print_kilobytes
	lea		kilobytes_end_text,a0
	jsr		print_text

	lea		cache_resets_text,a0
	jsr		print_text
	move.l	cache_resets,d0
	jsr		print_number
	lea		half_switches_text,a0
	jsr		print_text
	move.l	half_switches,d0
	jsr		print_number
	lea		masters_made_text,a0
	jsr		print_text
	move.l	masters_made,d0
	jsr		print_number
	lea		shifts_made_text,a0
	jsr		print_text
	move.l	shifts_made,d0
	jsr		print_number
	lea		line_end_text,a0
	jsr		print_text

	tst.b	machine_has_ste_hardware
	bne		.no_ym_report

	lea		ym_played_text,a0
	jsr		print_text
	move.l	ym_effects_played,d0
	jsr		print_number
	lea		ym_unknown_text,a0
	jsr		print_text
	move.l	ym_effects_unknown,d0
	jsr		print_number
	lea		line_end_text,a0
	jsr		print_text

.no_ym_report:

	; Calls the port does not implement.

	lea		unimplemented_dos,a2
	tst		(a2)
	beq		.no_dos

	lea		unimplemented_dos_text,a0
	jsr		print_text

.dos_loop:
	move	(a2)+,d0
	beq		.dos_done

	lea		space_dollar_text,a0
	jsr		print_text
	moveq	#4,d1
	jsr		print_hex

	bra		.dos_loop

.dos_done:
	lea		line_end_text,a0
	jsr		print_text

.no_dos:
	lea		unimplemented_iocs,a2
	moveq	#0,d2
	sf		d3

.iocs_loop:
	tst.b	(a2,d2.w)
	beq		.next_iocs

	tst.b	d3
	bne		.iocs_listed

	st		d3
	lea		unimplemented_iocs_text,a0
	jsr		print_text

.iocs_listed:
	lea		space_dollar_text,a0
	jsr		print_text
	move	d2,d0
	moveq	#2,d1
	jsr		print_hex

.next_iocs:
	addq	#1,d2
	cmp		#256,d2
	bne		.iocs_loop

	tst.b	d3
	beq		.done

	lea		line_end_text,a0
	jsr		print_text

.done:
	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

welcome_text:
	dc.b	'Cho Ren Sha 68k',13,10
	dc.b	'---------------',13,10
	dc.b	'(c) 1995 Famibe No Yosshin (X68000).',13,10
	dc.b	'Falcon port: Sascha Springer.',13,10
	dc.b	'Amiga port: Adam Polkosnik.',13,10
	dc.b	'Atari ST port: Neil Rackett.',13,10,13,10,0
st_text:
	dc.b	'Machine: Atari ST, 8 MHz.',13,10
	dc.b	'No DMA sound: YM sound effects.',13,10,0
ste_text:
	dc.b	'Machine: Atari STE, 8 MHz.',13,10,0
mega_ste_text:
	dc.b	'Machine: Atari Mega STE.',13,10,0
megaste8_file_name:
	dc.b	'MEGASTE8.TXT',0
cpu_text:
	dc.b	'CPU ($FFFF8E21): $',0
cpu_16mhz_text:
	dc.b	', 16 MHz',0
cpu_8mhz_text:
	dc.b	', 8 MHz',0
cpu_cache_text:
	dc.b	', cache on.',13,10,0
cpu_no_cache_text:
	dc.b	', cache off.',13,10,0
xpad_text:
	dc.b	'Xpad: a provider with ',0
xpad_end_text:
	dc.b	' pad slots.',13,10,0
wrong_machine_text:
	dc.b	'This program needs an Atari ST, STE',13,10
	dc.b	'or Mega STE.',13,10,0
no_data_text:
	dc.b	'Game data not found:',13,10,0
no_data_help_text:
	dc.b	13,10,'BGM_DAT, ETC_DAT and XSP_DAT',13,10
	dc.b	'(binaries/amiga) and PCM_DAT',13,10
	dc.b	'(binaries/atari; an ST: SZ2_YM.BIN',13,10
	dc.b	'from binaries/st/PCM_DAT) go next',13,10
	dc.b	'to the program.',13,10,0
bgm_data_file_name:
	dc.b	'BGM_DAT\SZ2_BGM.CNF',0
etc_data_file_name:
	dc.b	'ETC_DAT\RANDOM.TBL',0
xsp_data_file_name:
	dc.b	'XSP_DAT\SZ_TEXT.pcg',0
pcm_data_file_name:
	dc.b	'PCM_DAT\SZ2_PCM.CNF',0
	even
data_files: ; Checked at start (a file the game loads from each folder).
	dc.l	bgm_data_file_name,etc_data_file_name,xsp_data_file_name
	dc.l	pcm_data_file_name,0
no_memory_text:
	dc.b	'Not enough memory: needs ',0
no_arena_text:
	dc.b	'Not enough memory for the sprites.',13,10,0
of_text:
	dc.b	' KB of ',0
tpa_text:
	dc.b	'Memory: TPA ',0
program_text:
	dc.b	' KB, program ',0
heap_text:
	dc.b	' KB,',13,10,'game heap ',0
arena_text:
	dc.b	' KB, sprites ',0
free_text:
	dc.b	' KB, free ',0
kilobytes_end_text:
	dc.b	' KB.',13,10,0
frames_file_name:
	dc.b	'FRAMES.TXT',0
frame_limit_text:
	dc.b	'Frame limit: ',0
lockstep_file_name:
	dc.b	'LOCKSTEP.TXT',0
lockstep_text:
	dc.b	'Lockstep: every frame (F1 switches).',13,10,0
starting_text:
	dc.b	'Starting (the background takes a few',13,10
	dc.b	'seconds to build)...',13,10,0
run_end_text:
	dc.b	'End of the run.',13,10,0
	ifd __OVERSCAN__
overscan_text:
	dc.b	'Overscan: ',0
overscan_lines_text:
	dc.b	' lines, frames with a border missed: ',0
overscan_closed_text:
	dc.b	'not open: ',0
	endif
press_key_text:
	dc.b	13,10,'Press a key.',13,10,0
exit_text:
	dc.b	13,10,'Exit: ',0
exit_frame_limit_text:
	dc.b	'frame limit.',13,10,0
exit_game_text:
	dc.b	'game.',13,10,0
exit_exception_text:
	dc.b	'exception, vector ',0
exception_pc_text:
	dc.b	' at text+$',0
exception_address_text:
	dc.b	', access $',0
frames_text:
	dc.b	'Frames: ',0
ticks_text:
	dc.b	', ticks (50 Hz): ',0
pictures_text:
	dc.b	', pictures: ',0
poll_pictures_text:
	dc.b	' (+ ',0
per_second_text:
	dc.b	' while polling), per second: ',0
heap_used_text:
	dc.b	'Game heap used: ',0
cache_resets_text:
	dc.b	'Sprite cache emptied (including at start): ',0
half_switches_text:
	dc.b	', halves switched: ',0
ym_played_text:
	dc.b	'YM sound effects played: ',0
ym_unknown_text:
	dc.b	', not recognised: ',0
masters_made_text:
	dc.b	', variants made: ',0
shifts_made_text:
	dc.b	', shifted copies made: ',0
unimplemented_dos_text:
	dc.b	'Unimplemented DOS calls:',0
unimplemented_iocs_text:
	dc.b	'Unimplemented IOCS calls:',0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

basepage:
	ds.l	1
	ifd __OVERSCAN__
overscan_lines: ; Shown, or 0: the borders did not open.
	ds.l	1
overscan_misses:
	ds.l	1
overscan_error: ; STDL's message.
	ds.l	1
	endif
text_base:
	ds.l	1
tpa_size:
	ds.l	1
program_size:
	ds.l	1
kept_size:
	ds.l	1
old_stack_address:
	ds.l	1
frames_buffer:
	ds.l	4

	ds.l	1024
my_stack:

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
