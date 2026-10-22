
; Atari ST machine set-up, from the Falcon port's machine.s: the
; cookie jar, then the hardware the port takes over (shifter, DMA sound, MFP,
; exception and interrupt vectors) saved, set and restored at exit.

	xdef detect_machine
	xdef initialize_machine
	xdef release_machine

	xdef find_cookie
	xdef machine_is_st
	xdef machine_is_ste
	xdef machine_is_mega_ste
	xdef machine_has_ste_hardware
	xdef set_cpu_speed
	xdef restore_cpu_speed
	xdef old_8e21
	xdef force_8mhz
	xdef machine_type
	xdef mega_ste_control
	ifd __STREAM__
	xdef stream_8e21
	endif

	xref line_f_handler
	xref trap_2_handler
	xref trap_4_handler
	xref trap_f_handler
	xref vbl_handler
	xref ikbd_handler
	xref measure_timer_handler
	xref measure_timer_d_handler
	xref measure_timer_d
	xref full_height
	xref show_display_page
	xref ikbd_mouse_off
	xref ikbd_mouse_on
	xref ikbd_synchronise
	xref exception_bus_error
	xref exception_address_error
	xref exception_illegal
	xref exception_zero_divide
	xref exception_chk
	xref exception_trapv
	xref exception_privilege
	xref exception_line_a
	xref display_screen_address
	xref xpad_block
	xref audio_silence
	xref st_palette

	include "st.i"

; $FFFF8E21, the Mega STE's speed and cache (bit 1: 16 MHz, bit 0: the
; cache): written whole with the canonical values, as Atari's control panel
; and MSTE_CC do (the upper bits set). It reads back with them clear on a
; real Mega STE ($20 at TOS's 8 MHz, $23 at 16 MHz with the cache).
MEGA_STE_16MHZ_CACHE=$ff
MEGA_STE_8MHZ=$f4 ; Without the cache: TOS's after a cold boot.

MACHINE_STE=$00010000
MACHINE_MEGA_STE=$00010010

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

_p_cookies=$5a0

; d0.l = a cookie's tag -> d0.l = its value and Z clear, or Z set if there
; is no such cookie (or no jar: TOS 1.00-1.04). Supervisor mode. Preserves
; the other registers.

find_cookie:
	movem.l	d1/a0,-(sp)

	move.l	d0,d1
	move.l	_p_cookies.w,d0
	beq		.none

	move.l	d0,a0

.cookie_loop:
	move.l	(a0)+,d0
	beq		.none ; The jar's end.

	cmp.l	d1,d0
	beq		.found

	addq.l	#4,a0

	bra		.cookie_loop

.found:
	move.l	(a0),d0
	movem.l	(sp)+,d1/a0
	and		#$fb,ccr ; Z clear (the value may be 0).

	rts

.none:
	movem.l	(sp)+,d1/a0
	moveq	#0,d0 ; Z set.

	rts

detect_machine:
	move.l	#'_MCH',d0
	bsr		find_cookie
	beq		.no_mch

	move.l	d0,machine_type

.no_mch:
	move.l	machine_type,d0
	cmp.l	#MACHINE_STE,d0
	seq		machine_is_ste
	cmp.l	#MACHINE_MEGA_STE,d0
	seq		machine_is_mega_ste

	; An ST or Mega ST: _MCH 0, or no _MCH at all (TOS 1.00-1.04 have no
	; cookie jar).

	tst.l	d0
	beq		.st

	cmp.l	#-1,d0
	bne		.not_st

.st:
	st		machine_is_st

.not_st:
	; STE hardware (the extra video registers, DMA sound): STE, Mega STE.

	move.b	machine_is_ste,d0
	or.b	machine_is_mega_ste,d0
	move.b	d0,machine_has_ste_hardware

	rts

; ------------------------------------------------------------------------------

initialize_machine:
	; IKBD: the mouse reporting off, then two VBLs for TOS to read any
	; packet already on its way.

	jsr		ikbd_mouse_off

	moveq	#2-1,d7

.wait_for_ikbd:
	move	#37,-(sp) ; Vsync
	trap	#14
	addq.l	#2,sp
	dbf		d7,.wait_for_ikbd

	move	#$2700,sr

	; Shifter: resolution, sync, palette, screen address, STE fine scroll.

	move.b	$ffff8260.w,old_resolution
	move.b	$ffff820a.w,old_sync
	movem.l	$ffff8240.w,d0-d7
	movem.l	d0-d7,old_palette
	move.b	$ffff8201.w,old_screen_address+1
	move.b	$ffff8203.w,old_screen_address+2

	; The STE's: screen address low byte, line offset, fine scroll; DMA
	; sound off. (An ST has none of them: a bus error.)

	tst.b	machine_has_ste_hardware
	beq		.no_ste_registers

	move.b	$ffff820d.w,old_screen_address+3
	move.b	$ffff820f.w,old_line_offset
	move.b	$ffff8265.w,old_fine_scroll

	move.b	$ffff8921.w,old_sound_mode
	clr.b	$ffff8901.w

.no_ste_registers:

	; MFP.

	move.b	$fffffa07.w,old_fa07
	move.b	$fffffa09.w,old_fa09
	move.b	$fffffa13.w,old_fa13
	move.b	$fffffa15.w,old_fa15
	move.b	$fffffa17.w,old_fa17
	move.b	$fffffa19.w,old_fa19
	move.b	$fffffa1f.w,old_fa1f
	ifnd __RELEASE__
	; At full height the measurement clock is Timer D (st.i): its
	; control, and its reload value, which only shows as the largest
	; count read (its data register reads the count; TOS's baud rates
	; reload it with 1-12).

	move.b	full_height,measure_timer_d
	beq		.timer_d_kept

	move.b	$fffffa1d.w,old_fa1d
	moveq	#0,d1
	move	#255,d2

.timer_d_reload:
	move.b	$fffffa25.w,d0
	cmp.b	d1,d0
	bls		.not_larger

	move.b	d0,d1

.not_larger:
	dbf		d2,.timer_d_reload

	move.b	d1,old_fa25

.timer_d_kept:
	endif

	; Vectors.

	lea		vector_list,a0
	lea		old_vectors,a1

.save_vectors:
	move	(a0)+,d0
	beq		.vectors_saved

	addq.l	#4,a0
	move	d0,a2 ; Sign-extended: the vectors are below $8000.
	move.l	(a2),(a1)+

	bra		.save_vectors

.vectors_saved:
	clr.b	$fffffa07.w
	clr.b	$fffffa09.w
	clr.b	$fffffa13.w
	clr.b	$fffffa15.w

	lea		vector_list,a0

.install_vectors:
	move	(a0)+,d0
	beq		.vectors_installed

	move	d0,a2
	move.l	(a0)+,(a2)

	bra		.install_vectors

.vectors_installed:
	; Display: low resolution, 50 Hz, the port's screen's page (on an STE
	; its address's low byte 0 from now on: the pages are 256-aligned),
	; all colours black.

	clr.b	$ffff8260.w
	move.b	#2,$ffff820a.w

	jsr		show_display_page

	tst.b	machine_has_ste_hardware
	beq		.st_display

	clr.b	$ffff820f.w
	clr.b	$ffff8265.w
	clr.b	$ffff820d.w

.st_display:

	movem.l	st_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w

	; IKBD (ACIA).

	bset	#6,$fffffa09.w
	bset	#6,$fffffa15.w

	; With an Xpad provider, Timer C and the serial port's interrupts stay
	; as TOS had them: TOS's Timer C handler calls etv_timer, where the
	; providers update their pads (COMpad from TOS's serial receive
	; buffer, STEpad from the STE's ports).

	tst.l	xpad_block
	beq		.no_xpad

	move.b	old_fa07,d0
	and.b	#%00011110,d0 ; Serial receive and transmit, buffer and error.
	or.b	d0,$fffffa07.w
	move.b	old_fa13,d0
	and.b	#%00011110,d0
	or.b	d0,$fffffa13.w
	move.b	old_fa09,d0
	and.b	#%00100110,d0 ; Timer C, CTS, DCD.
	or.b	d0,$fffffa09.w
	move.b	old_fa15,d0
	and.b	#%00100110,d0
	or.b	d0,$fffffa15.w

.no_xpad:
	ifnd __RELEASE__
	; The measurement clock (st.i), 150 Hz overflows: Timer A, not Timer
	; D, the serial port's baud rate clock, which COMpad needs as TOS set
	; it; but Timer D at full height, whose border code needs Timer A.

	tst.b	measure_timer_d
	bne		.measure_timer_d

	clr.b	$fffffa19.w ; Timer A stopped.
	clr.b	$fffffa1f.w ; 256.
	move.b	#5,$fffffa19.w ; Divide by 64: 38400 Hz.
	bset	#5,$fffffa07.w
	bset	#5,$fffffa13.w

	bra		.measure_clock_set

.measure_timer_d:
	and.b	#$f0,$fffffa1d.w ; Timer D stopped (Timer C kept).
	clr.b	$fffffa25.w ; 256.
	or.b	#5,$fffffa1d.w ; Divide by 64: 38400 Hz.
	bset	#4,$fffffa09.w
	bset	#4,$fffffa15.w

.measure_clock_set:
	endif

	; The MFP stays in TOS's software end-of-interrupt mode (the port's
	; handlers clear their in-service bits): while a handler runs, its
	; channel and the ones below it wait, as TOS's own handlers (Timer C
	; and the serial port's, kept for an Xpad provider) and the providers'
	; code expect. In automatic mode TOS's Timer C could interrupt its own
	; handler while COMpad, at mask 5 in it, drains the serial port.

	jsr		ikbd_synchronise ; (The IKBD interrupt enabled: no edge missed.)

	jmp		audio_silence ; (An ST: the YM plays the effects.)

; ------------------------------------------------------------------------------
;
; Mega STE: 16 MHz and the cache ($FFFF8E21 = $FF), or 8 MHz without the
; cache ($F4) if force_8mhz is set (megaste_speedup=false, for
; comparisons). The register is read back into mega_ste_control (the
; start-up text and the exit report show it); release_machine puts the old
; value back.
; A Mega STE only; supervisor mode, before the take-over.

set_cpu_speed:
	move.b	$ffff8e21.w,old_8e21

	move.b	#MEGA_STE_16MHZ_CACHE,d0
	tst.b	force_8mhz
	beq		.write

	move.b	#MEGA_STE_8MHZ,d0

.write:
	move.b	d0,$ffff8e21.w
	move.b	$ffff8e21.w,mega_ste_control
	ifd __STREAM__
	move.b	d0,stream_8e21
	endif

	rts

; A Mega STE back to the speed and cache it had before set_cpu_speed: the
; value read then, or TOS's cold-boot $F4 if it read without its upper
; bits. Preserves all registers.

restore_cpu_speed:
	tst.b	machine_is_mega_ste ; (set_cpu_speed ran.)
	beq		.done

	move.b	#MEGA_STE_8MHZ,$ffff8e21.w
	ifd __STREAM__
	clr.b	stream_8e21 ; (TOS's: the cache taken as off.)
	endif
	tst.b	old_8e21
	bpl		.done ; (Upper bits clear: the cold-boot value stays.)

	move.b	old_8e21,$ffff8e21.w

.done:
	rts

; ------------------------------------------------------------------------------

release_machine:
	move	#$2700,sr

	jsr		audio_silence
	bsr		restore_cpu_speed

	tst.b	machine_has_ste_hardware
	beq		.no_sound_restored

	clr.b	$ffff8901.w
	move.b	old_sound_mode,$ffff8921.w

.no_sound_restored:
	jsr		ikbd_synchronise ; TOS's handler starts at a packet.

	move.b	old_fa07,$fffffa07.w
	move.b	old_fa09,$fffffa09.w
	move.b	old_fa13,$fffffa13.w
	move.b	old_fa15,$fffffa15.w
	move.b	old_fa17,$fffffa17.w
	clr.b	$fffffa19.w
	move.b	old_fa1f,$fffffa1f.w
	move.b	old_fa19,$fffffa19.w
	ifnd __RELEASE__
	tst.b	measure_timer_d
	beq		.timer_d_restored

	and.b	#$f0,$fffffa1d.w
	move.b	old_fa25,$fffffa25.w
	move.b	old_fa1d,$fffffa1d.w

.timer_d_restored:
	endif

	lea		vector_list,a0
	lea		old_vectors,a1

.restore_vectors:
	move	(a0)+,d0
	beq		.vectors_restored

	addq.l	#4,a0
	move	d0,a2
	move.l	(a1)+,(a2)

	bra		.restore_vectors

.vectors_restored:
	move.b	old_screen_address+1,$ffff8201.w
	move.b	old_screen_address+2,$ffff8203.w

	tst.b	machine_has_ste_hardware
	beq		.st_display_restored

	move.b	old_screen_address+3,$ffff820d.w
	move.b	old_line_offset,$ffff820f.w
	move.b	old_fine_scroll,$ffff8265.w

.st_display_restored:
	move.b	old_resolution,$ffff8260.w
	move.b	old_sync,$ffff820a.w

	movem.l	old_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w

	jmp		ikbd_mouse_on

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

machine_type: ; _MCH, -1 without one.
	dc.l	-1

; Vector address (word), handler: saved, installed and restored in order.

vector_list:
	dc.w	$08
	dc.l	exception_bus_error ; Bus error.
	dc.w	$0c
	dc.l	exception_address_error ; Address error.
	dc.w	$10
	dc.l	exception_illegal ; Illegal instruction.
	dc.w	$14
	dc.l	exception_zero_divide ; Division by zero.
	dc.w	$18
	dc.l	exception_chk ; CHK.
	dc.w	$1c
	dc.l	exception_trapv ; TRAPV.
	dc.w	$20
	dc.l	exception_privilege ; Privilege violation.
	dc.w	$28
	dc.l	exception_line_a ; Line A.
	dc.w	$2c
	dc.l	line_f_handler ; Human68k DOS and FLOAT calls.
	dc.w	$88
	dc.l	trap_2_handler ; PCM8.
	dc.w	$90
	dc.l	trap_4_handler ; MCDRV.
	dc.w	$bc
	dc.l	trap_f_handler ; IOCS.
	dc.w	$70
	dc.l	vbl_handler
	ifnd __RELEASE__
	dc.w	TIMER_A_VECTOR
	dc.l	measure_timer_handler ; (Measurements: Timer A,
	dc.w	TIMER_D_VECTOR
	dc.l	measure_timer_d_handler ; or Timer D at full height.)
	endif
	dc.w	$118
	dc.l	ikbd_handler
vector_list_end:
	dc.w	0

NUMBER_OF_VECTORS=(vector_list_end-vector_list)/6

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

old_vectors:
	ds.l	NUMBER_OF_VECTORS
old_palette:
	ds.w	16
old_screen_address:
	ds.l	1

machine_is_ste:
	ds.b	1
machine_is_st:
	ds.b	1
machine_has_ste_hardware:
	ds.b	1
machine_is_mega_ste:
	ds.b	1
old_resolution:
	ds.b	1
old_sync:
	ds.b	1
old_line_offset:
	ds.b	1
old_fine_scroll:
	ds.b	1
old_sound_mode:
	ds.b	1
old_8e21:
	ds.b	1
force_8mhz:
	ds.b	1
mega_ste_control: ; $FFFF8E21 as read back after set_cpu_speed.
	ds.b	1

	ifd __STREAM__
stream_8e21: ; $FFFF8E21 as set_cpu_speed wrote it, 0 before (main.s).
	ds.b	1
	endif

old_fa07:
	ds.b	1
old_fa09:
	ds.b	1
old_fa13:
	ds.b	1
old_fa15:
	ds.b	1
old_fa17:
	ds.b	1
old_fa19:
	ds.b	1
old_fa1f:
	ds.b	1
old_fa1d:
	ds.b	1
old_fa25:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
