
; Atari STE / Mega STE sound effects, from the Falcon port: the game plays one
; effect at a time with IOCS _ADPCMOUT (keeping its own priorities) and asks
; _ADPCMSNS whether one still plays. The effects are the Falcon port's
; PCM_DAT/*.sam files (signed 8-bit mono, 12517 Hz), which the game loads
; into its heap itself; STE DMA sound plays them once each. No music (MCDRV
; is not emulated).

	xdef audio_play
	xdef audio_status
	xdef audio_stop

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; _ADPCMOUT: a1 = sample, d2.l = length (d1 = the X68000 rate and output,
; ignored). Preserves all registers.

audio_play:
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

	btst	#0,$ffff8901.w
	beq		.idle

	moveq	#2,d0

.idle:
	rts

audio_stop:
	clr.b	$ffff8901.w

	rts

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
