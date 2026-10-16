; Scripted Xpad provider, for tests: a TSR for C:\AUTO that publishes an
; XPAD block with two pad slots (pad 0 an Xbox pad, pad 1 empty) and, from
; etv_timer (50 Hz, called by TOS's Timer C handler), presses pad 0's
; buttons along TIMELINE, in ticks since it was installed. It checks the
; whole path a real provider takes: the cookie, the double-buffered block
; and an etv_timer hook still being called while the game owns the
; machine.
;
;   vasmm68k_mot -Ftos -m68000 -I lib/xpad/src tests/st/xpad/xpadtest.s
;
; (tests/st/xpad_test.sh builds and runs it.)

	include "xpad.inc"

PAD_COUNT=2
PADS_OFFSET=26 ; After the fixed header, the provider name and req pointers.
BLOCK_SIZE=PADS_OFFSET+2*XPAD_MAX_PADS*XPAD_PAD_SIZE_V1 ; sizeof(XPAD)
JAR_SLOTS=32 ; When TOS's jar is full: a bigger one here.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start:
	move.l	4(sp),a0 ; Basepage.
	move.l	$c(a0),d0 ; Text, data, BSS and the basepage stay.
	add.l	$14(a0),d0
	add.l	$1c(a0),d0
	add.l	#$100,d0
	move.l	d0,keep_size

	pea		install(pc)
	move	#38,-(sp) ; Supexec
	trap	#14
	addq.l	#6,sp

	pea		installed_text(pc)
	move	#9,-(sp) ; Cconws
	trap	#1
	addq.l	#6,sp

	clr		-(sp)
	move.l	keep_size(pc),-(sp)
	move	#49,-(sp) ; Ptermres
	trap	#1

; Supervisor: the block, the cookie, the hook.

install:
	lea		block,a0
	move.l	#XPAD_MAGIC,XPAD_MAGIC_OFF(a0)
	move	#XPAD_VERSION,XPAD_VERSION_OFF(a0)
	move	#BLOCK_SIZE,XPAD_HDRSIZE_OFF(a0)
	move	#PADS_OFFSET,XPAD_PADSOFF_OFF(a0)
	move	#XPAD_PAD_SIZE_V1,XPAD_PADSIZE_OFF(a0)
	clr		XPAD_CAPS_OFF(a0)
	clr		XPAD_SEQ_OFF(a0)
	move.b	#PAD_COUNT,XPAD_PADCOUNT_OFF(a0)
	clr.b	XPAD_ACTIVE_OFF(a0)
	move.l	#provider_name,XPAD_HDR_FIXED(a0)
	clr.l	XPAD_HDR_FIXED+4(a0) ; No request area.

	; Pad 0 present in both buffers (pad 1 stays empty: type 0).

	move.b	#XPAD_TYPE_XBOX,PADS_OFFSET+XPAD_PAD_TYPE(a0)
	move.b	#XPAD_TYPE_XBOX,PADS_OFFSET+PAD_COUNT*XPAD_PAD_SIZE_V1+XPAD_PAD_TYPE(a0)

	bsr		add_cookie

	move.l	$400.w,old_etv
	move.l	#etv_tick,$400.w

	rts

; The XPAD cookie, at the jar's end, in a bigger jar of our own if full.

add_cookie:
	move.l	$5a0.w,d0
	bne		.jar

	lea		own_jar,a1 ; No jar at all: ours.
	clr.l	(a1)
	move.l	#JAR_SLOTS,4(a1)
	move.l	a1,$5a0.w

	bra		add_cookie

.jar:
	move.l	d0,a1
	moveq	#0,d1 ; Cookies.

.walk:
	tst.l	(a1)
	beq		.end

	addq.l	#8,a1
	addq.l	#1,d1

	bra		.walk

.end:
	move.l	4(a1),d2 ; Slots.
	addq.l	#2,d1 ; Ours and the terminator.
	cmp.l	d2,d1
	bls		.room

	; Full: the cookies into our jar.

	move.l	$5a0.w,a0
	lea		own_jar,a2

.copy:
	move.l	(a0)+,d0
	move.l	(a0)+,d1
	tst.l	d0
	beq		.copied

	move.l	d0,(a2)+
	move.l	d1,(a2)+

	bra		.copy

.copied:
	clr.l	(a2)
	move.l	#JAR_SLOTS,4(a2)
	move.l	#own_jar,$5a0.w

	bra		add_cookie

.room:
	move.l	#XPAD_COOKIE,(a1)
	move.l	#block,4(a1)
	clr.l	8(a1)
	move.l	d2,12(a1)

	rts

; etv_timer: the timeline's buttons into the back buffer, then the commit
; (seq first, then active), then the previous handler.

etv_tick:
	movem.l	d0-d2/a0-a1,-(sp)

	addq.l	#1,ticks
	move.l	ticks,d0
	moveq	#0,d1 ; Buttons.
	lea		timeline,a0

.entry:
	move.l	(a0)+,d2 ; From.
	bmi		.buttons_known

	cmp.l	d2,d0
	bcs		.next_entry

	cmp.l	(a0),d0 ; To (not included).
	bcc		.next_entry

	or.l	4(a0),d1

.next_entry:
	addq.l	#8,a0

	bra		.entry

.buttons_known:
	lea		block,a0
	move.b	XPAD_ACTIVE_OFF(a0),d2
	eor.b	#1,d2 ; The back buffer.
	lea		PADS_OFFSET(a0),a1
	tst.b	d2
	beq		.buffer_0

	lea		PAD_COUNT*XPAD_PAD_SIZE_V1(a1),a1

.buffer_0:
	move.l	d1,XPAD_PAD_BUTTONS(a1)
	addq	#1,XPAD_SEQ_OFF(a0)
	move.b	d2,XPAD_ACTIVE_OFF(a0)

	movem.l	(sp)+,d0-d2/a0-a1

	move.l	old_etv,-(sp)

	rts

keep_size:
	dc.l	0

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

; From tick, to tick (50 per second after installation), buttons.

timeline:
	ifnd IDLE ; (-DIDLE: no buttons, the provider only running.)
	dc.l	550,565,XPAD_SOUTH ; The menu's START.
	dc.l	1350,1450,XPAD_RIGHT|XPAD_SOUTH ; Right, shooting.
	dc.l	1450,1550,XPAD_LEFT|XPAD_SOUTH ; Left, shooting.
	dc.l	1600,1610,XPAD_START ; Pause.
	dc.l	1750,1760,XPAD_START ; And on.
	endif
	dc.l	-1

provider_name:
	dc.b	'Scripted test provider',0
installed_text:
	dc.b	'Xpad test provider installed.',13,10,0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

old_etv:
	ds.l	1
ticks:
	ds.l	1
block:
	ds.b	BLOCK_SIZE
own_jar:
	ds.l	JAR_SLOTS*2
