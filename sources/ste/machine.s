
; Atari STE / Mega STE machine set-up, from the Falcon port's machine.s: the
; cookie jar, then the hardware the port takes over (shifter, DMA sound, MFP,
; exception and interrupt vectors) saved, set and restored at exit.

	xdef detect_machine
	xdef initialize_machine
	xdef release_machine

	xdef machine_type
	xdef machine_cpu
	xdef machine_is_st
	xdef machine_is_ste
	xdef machine_is_mega_ste
	xdef machine_has_ste_hardware
	xdef set_cpu_speed
	xdef force_8mhz
	xdef mega_ste_control

	xref line_f_handler
	xref trap_2_handler
	xref trap_4_handler
	xref trap_f_handler
	xref vbl_handler
	xref ikbd_handler
	xref timer_d_handler
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
	xref st_palette

MACHINE_STE=$00010000
MACHINE_MEGA_STE=$00010010

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

_p_cookies=$5a0

detect_machine:
	move.l	_p_cookies,d0
	beq		.exit

	move.l	d0,a6

	move.l	(a6)+,d0
	beq		.exit

.cookies_loop:
	move.l	(a6)+,d1

	cmp.l	#'_MCH',d0
	bne		.skip_mch

	move.l	d1,machine_type

	bra		.next_cookie

.skip_mch:
	cmp.l	#'_CPU',d0
	bne		.next_cookie

	move.l	d1,machine_cpu

.next_cookie:
	move.l	(a6)+,d0
	bne		.cookies_loop

.exit:
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
	move.b	$fffffa1d.w,old_fa1d
	move.b	$fffffa25.w,old_fa25

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
	; Display: low resolution, 50 Hz, the port's screen and grey palette.

	clr.b	$ffff8260.w
	move.b	#2,$ffff820a.w

	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w

	tst.b	machine_has_ste_hardware
	beq		.st_display

	clr.b	$ffff820f.w
	clr.b	$ffff8265.w
	move.b	display_screen_address+3,$ffff820d.w

.st_display:

	movem.l	st_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w

	; IKBD (ACIA) and Timer D (measurements, 150 Hz overflows; not in the
	; release build).

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
	and.b	#$f0,$fffffa1d.w ; Timer D stopped.
	clr.b	$fffffa25.w ; 256.
	or.b	#5,$fffffa1d.w ; Divide by 64: 38400 Hz.
	bset	#4,$fffffa09.w
	bset	#4,$fffffa15.w
	endif

	bclr	#3,$fffffa17.w ; Automatic end of interrupt.

	rts

; ------------------------------------------------------------------------------
;
; Mega STE: 16 MHz and the cache (bits 1 and 0 of $FFFF8E21), or 8 MHz
; without the cache if force_8mhz is set (MEGASTE8.TXT, for comparisons).
; The register is read back into mega_ste_control (the start-up text and
; the exit report show it); release_machine puts the old value back.
; Supervisor mode, before the take-over.

set_cpu_speed:
	tst.b	machine_is_mega_ste
	beq		.done

	move.b	$ffff8e21.w,d0
	move.b	d0,old_8e21
	st		cpu_speed_set

	and.b	#$fc,d0
	tst.b	force_8mhz
	bne		.write

	or.b	#3,d0 ; 16 MHz, cache.

.write:
	move.b	d0,$ffff8e21.w
	move.b	$ffff8e21.w,mega_ste_control

.done:
	rts

; ------------------------------------------------------------------------------

release_machine:
	move	#$2700,sr

	tst.b	cpu_speed_set
	beq		.speed_restored

	move.b	old_8e21,$ffff8e21.w

.speed_restored:
	tst.b	machine_has_ste_hardware
	beq		.no_sound_restored

	clr.b	$ffff8901.w
	move.b	old_sound_mode,$ffff8921.w

.no_sound_restored:

	move.b	old_fa07,$fffffa07.w
	move.b	old_fa09,$fffffa09.w
	move.b	old_fa13,$fffffa13.w
	move.b	old_fa15,$fffffa15.w
	move.b	old_fa17,$fffffa17.w
	and.b	#$f0,$fffffa1d.w
	move.b	old_fa25,$fffffa25.w
	move.b	old_fa1d,$fffffa1d.w

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

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

machine_type:
	dc.l	-1

machine_cpu:
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
	dc.w	$110
	dc.l	timer_d_handler
	dc.w	$118
	dc.l	ikbd_handler
	dc.w	0

NUMBER_OF_VECTORS=15

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
cpu_speed_set:
	ds.b	1
force_8mhz:
	ds.b	1
mega_ste_control: ; $FFFF8E21 as read back after set_cpu_speed.
	ds.b	1

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
old_fa1d:
	ds.b	1
old_fa25:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
