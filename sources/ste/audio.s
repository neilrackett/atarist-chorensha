; Atari ST / STE / Mega STE sound effects, from the Falcon port: the game
; plays one effect at a time with IOCS _ADPCMOUT (keeping its own
; priorities, stopping the one before with _ADPCMMOD) and asks _ADPCMSNS
; whether one still plays. The effects are the Falcon port's PCM_DAT/*.sam
; files (signed 8-bit mono, 12517 Hz), which the game loads into its heap
; itself. No music (MCDRV is not emulated).
;
; - STE, Mega STE: DMA sound plays the samples once each.
; - ST (no DMA sound): the YM2149 plays versions made by
;   tools/ste/ym_effects.py (ym_effects.i): per 50 Hz VBL a frame of two
;   tones (channels A and C) and noise (channel B). The effect is found by
;   the sample's length and first long; effects the game plays at 10.4 kHz
;   (its mode's rate 3: the .sam files are all 15.6 kHz conversions) go 1.5
;   times slower and lower. As in STDL's YM service: registers 14 and 15
;   (TOS's floppy select) are never written, the mixer keeps the port
;   direction bits, and interrupts are masked between selecting a register
;   and writing it (TOS's Timer C, running with an Xpad provider, outranks
;   the VBL).

	xdef audio_play
	xdef audio_status
	xdef audio_stop
	xdef audio_tick
	xdef audio_silence
	xdef ym_effects_played
	xdef ym_effects_unknown

	xref machine_has_ste_hardware

YM_SELECT=$ffff8800 ; (Reads the selected register.)
YM_DATA=$ffff8802
YM_MIXER=7
YM_MIXER_OFF=%111111 ; Tones and noises off (1 = off).
YM_MIXER_EFFECT=%101010 ; Tone A, noise B, tone C on.
YM_SLOW_RATE=3 ; _ADPCMOUT's mode, bits 8-10: 3 = 10.4 kHz.
POSITION_STEP=256 ; Frames in 1/256: one per VBL.
POSITION_STEP_SLOW=171 ; Two thirds.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; _ADPCMOUT: a1 = sample, d2.l = length, d1 = the X68000 mode (rate in bits
; 8-10, output in 0-1). Preserves all registers.

audio_play:
	tst.b	machine_has_ste_hardware
	beq		ym_play

	move.l	d0,-(sp)

	clr.b	$ffff8901.w ; Stop.

	move.b	#$81,$ffff8921.w ; Mono, 12517 Hz.

	move.l	a1,d0
	move.b	d0,$ffff8907.w
	lsr		#8,d0
	move.b	d0,$ffff8905.w
	swap	d0
	move.b	d0,$ffff8903.w

	move.l	a1,d0
	add.l	d2,d0
	move.b	d0,$ffff8913.w
	lsr		#8,d0
	move.b	d0,$ffff8911.w
	swap	d0
	move.b	d0,$ffff890f.w

	move.b	#1,$ffff8901.w ; Play once.

	move.l	(sp)+,d0

	rts

; _ADPCMSNS: d0.l = 2 while an effect plays, else 0.

audio_status:
	moveq	#0,d0

	tst.b	machine_has_ste_hardware
	beq		.ym

	btst	#0,$ffff8901.w
	beq		.idle

	moveq	#2,d0

.idle:
	rts

.ym:
	tst.b	ym_playing
	beq		.idle

	moveq	#2,d0

	rts

; _ADPCMMOD 0: stops the effect.

audio_stop:
	tst.b	machine_has_ste_hardware
	beq		.ym

	clr.b	$ffff8901.w

	rts

.ym:
	sf		ym_playing
	st		ym_silence_pending

	rts

; ------------------------------------------------------------------------------
;
; ST: the effect whose sample this is (by its length and first long), from
; the next VBL on.

ym_play:
	movem.l	d0/d3/a0,-(sp)

	sf		ym_playing ; (The VBL leaves it alone meanwhile.)

	lea		ym_effects,a0
	moveq	#YM_EFFECTS-1,d3

.find:
	cmp.l	(a0),d2
	bne		.next

	move.l	(a1),d0
	cmp.l	4(a0),d0
	beq		.found

.next:
	lea		YM_EFFECT_SIZE(a0),a0

	dbf		d3,.find

	addq.l	#1,ym_effects_unknown
	st		ym_silence_pending

	bra		.done

.found:
	addq.l	#1,ym_effects_played
	move.l	8(a0),ym_frames
	move	12(a0),ym_frame_count
	clr		ym_position
	move	#POSITION_STEP,ym_step
	sf		ym_slow

	move	d1,d0
	lsr		#8,d0
	and		#7,d0
	cmp		#YM_SLOW_RATE,d0
	bne		.rate_known

	move	#POSITION_STEP_SLOW,ym_step
	st		ym_slow

.rate_known:
	st		ym_start_pending
	st		ym_playing

.done:
	movem.l	(sp)+,d0/d3/a0

	rts

; ------------------------------------------------------------------------------
;
; Every VBL, on an ST: the playing effect's frame into the YM. Preserves all
; registers.

; YM register \1 = \2 (a byte, not d7).

YM_WRITE macro
	move.b	#\1,YM_SELECT.w
	move.b	\2,YM_DATA.w
	endm

audio_tick:
	tst.b	machine_has_ste_hardware
	bne		.done

	tst.b	ym_playing
	bne		.playing

	tst.b	ym_silence_pending
	beq		.done

	sf		ym_silence_pending
	bra		audio_silence

.done:
	rts

.playing:
	movem.l	d0-d4/a0,-(sp)
	move	sr,-(sp)

	sf		ym_silence_pending

	moveq	#0,d0
	move	ym_position,d0
	lsr		#8,d0
	cmp		ym_frame_count,d0
	bcc		.end

	lsl		#3,d0 ; YM_FRAME_SIZE
	move.l	ym_frames,a0
	add		d0,a0

	move	4(a0),d1 ; Tone A period.
	move	6(a0),d2 ; Tone C period.
	moveq	#0,d3
	move.b	2(a0),d3 ; Noise period.
	tst.b	ym_slow
	beq		.periods_known

	; 10.4 kHz: 1.5 times lower.

	move	d1,d4
	lsr		#1,d4
	add		d4,d1
	move	d2,d4
	lsr		#1,d4
	add		d4,d2
	move	d3,d4
	lsr		#1,d4
	add		d4,d3
	cmp		#4095,d1
	bls		.a_ok

	move	#4095,d1

.a_ok:
	cmp		#4095,d2
	bls		.c_ok

	move	#4095,d2

.c_ok:
	cmp		#31,d3
	bls		.periods_known

	moveq	#31,d3

.periods_known:
	move	#$2700,sr ; (Select and write together.)

	tst.b	ym_start_pending
	beq		.mixer_set

	sf		ym_start_pending
	move.b	#YM_MIXER,YM_SELECT.w
	move.b	YM_SELECT.w,d4
	and.b	#$c0,d4 ; The I/O ports' directions.
	or.b	#YM_MIXER_EFFECT,d4
	YM_WRITE YM_MIXER,d4

.mixer_set:
	YM_WRITE 0,d1
	lsr		#8,d1
	YM_WRITE 1,d1
	YM_WRITE 4,d2
	lsr		#8,d2
	YM_WRITE 5,d2
	YM_WRITE 6,d3

	move.b	(a0),d4
	and.b	#$f,d4
	YM_WRITE 8,d4 ; Tone A.
	move.b	(a0),d4
	lsr.b	#4,d4
	YM_WRITE 9,d4 ; Noise B.
	move.b	1(a0),d4
	YM_WRITE 10,d4 ; Tone C.

	move	(sp)+,sr

	move	ym_step,d0
	add		d0,ym_position

	movem.l	(sp)+,d0-d4/a0

	rts

.end:
	move	(sp)+,sr
	sf		ym_playing
	movem.l	(sp)+,d0-d4/a0

	; Fall through: silence.

; The three channels silent and their tones and noise off (also at the
; take-over and the release, on an ST). Preserves all registers.

audio_silence:
	tst.b	machine_has_ste_hardware
	bne		.done

	move.l	d0,-(sp)
	move	sr,-(sp)
	move	#$2700,sr

	moveq	#0,d0
	YM_WRITE 8,d0
	YM_WRITE 9,d0
	YM_WRITE 10,d0
	move.b	#YM_MIXER,YM_SELECT.w
	move.b	YM_SELECT.w,d0
	and.b	#$c0,d0
	or.b	#YM_MIXER_OFF,d0
	YM_WRITE YM_MIXER,d0

	move	(sp)+,sr
	move.l	(sp)+,d0

.done:
	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

	include "ym_effects.i"

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

ym_frames: ; The playing effect's frames.
	ds.l	1
ym_effects_played:
	ds.l	1
ym_effects_unknown: ; Samples not in ym_effects (none expected).
	ds.l	1
ym_frame_count:
	ds.w	1
ym_position: ; Frames, in 1/256.
	ds.w	1
ym_step: ; Per VBL.
	ds.w	1
ym_playing:
	ds.b	1
ym_slow: ; A 10.4 kHz effect: 1.5 times slower and lower.
	ds.b	1
ym_start_pending: ; The mixer to set at the next VBL.
	ds.b	1
ym_silence_pending:
	ds.b	1

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
