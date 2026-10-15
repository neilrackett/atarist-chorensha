
; The STE's 16 colours (see tools/ste/palette_map.py): every X68000 palette
; entry is drawn in one ST colour (palette_map.i, baked into the background
; table and the sprites), and each ST colour shows the current value of one
; representative X68000 entry, read from the video controller shadow for
; every picture: the game's fades, colour cycling and flashes show without
; redrawing anything.
;
; Colour 0 is the backdrop (X68000 sprite/text entry 0). While the background
; shows it is black: on the X68000 the opaque background covers the backdrop
; then (its bomb-flash writes to it stay invisible), and on the ST colour 0
; is also the border and the HUD band's background.

	xdef make_hardware_palette
	xdef graphics_dither
	xdef sprite_colour_map

	xref L_00E82000
	xref background_visible

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; a0 = 16 words: the STE colour registers for the next picture. Preserves
; the other registers.

make_hardware_palette:
	movem.l	d0-d3/a0-a3,-(sp)

	lea		colour_representatives,a1
	lea		L_00E82000,a2
	lea		blue_levels(pc),a3
	moveq	#16-1,d3

.colour_loop:
	move	(a1)+,d0 ; Offset in the video controller shadow.
	move	(a2,d0.w),d0 ; GGGGG RRRRR BBBBB I

	moveq	#$1f<<1,d1 ; B: bits 5-1.
	and		d0,d1
	move	(a3,d1.w),d2

	move	d0,d1
	lsr		#5,d1
	and		#$1f<<1,d1 ; R: bits 10-6.
	or		red_levels-blue_levels(a3,d1.w),d2

	lsr		#8,d0
	lsr		#2,d0
	and		#$1f<<1,d0 ; G: bits 15-11.
	add		#green_levels-blue_levels,d0
	or		(a3,d0.w),d2

	move	d2,(a0)+

	dbf		d3,.colour_loop

	tst.b	background_visible
	beq		.done

	clr		-32(a0) ; Colour 0: black.

.done:
	movem.l	(sp)+,d0-d3/a0-a3

	rts

; 5-bit component -> STE 4-bit level (v >> 1), its low bit in bit 3 of the
; nibble, in the component's position.

COMPONENT macro
	dc.w	$0<<\1,$0<<\1,$8<<\1,$8<<\1,$1<<\1,$1<<\1,$9<<\1,$9<<\1
	dc.w	$2<<\1,$2<<\1,$a<<\1,$a<<\1,$3<<\1,$3<<\1,$b<<\1,$b<<\1
	dc.w	$4<<\1,$4<<\1,$c<<\1,$c<<\1,$5<<\1,$5<<\1,$d<<\1,$d<<\1
	dc.w	$6<<\1,$6<<\1,$e<<\1,$e<<\1,$7<<\1,$7<<\1,$f<<\1,$f<<\1
	endm

blue_levels:
	COMPONENT 0
red_levels:
	COMPONENT 8
green_levels:
	COMPONENT 4

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

	include	"palette_map.i"

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
