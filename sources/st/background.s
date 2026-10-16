
; The background on the Atari ST: the game's two GVRAM pages,
; composed in advance.
;
; The game builds one background for the whole game (INITIALIZE_SPRITES_AND_
; GRAPHICS, from data loaded at start). Page 0 (in front; colour 0 is
; transparent) repeats every 256 lines and scrolls 4 lines per frame, page 1
; (opaque) repeats every 32 lines and scrolls 1 line per frame. So a line of
; the picture is page 0's line a over page 1's line b, and there are only
; 256 x 32 different ones: all of them are composed once, in ST colours and
; bitplanes (128 bytes each), into a 1 MB table that replaces GVRAM:
;
;   T[s][a] = page 0 line a over page 1 line (a + s) & 31, at
;   L_00C00000 + s * 32768 + a * 128.
;
; For playfield line g, a = (g + Y0) & 255 and b = (g + Y1) & 31 (Y0, Y1:
; the pages' scroll registers): s = (b - a) & 31 is the same all the way
; down, so a picture's background is one block of the table (wrapping once
; at a = 256), copied with movem.
;
; The first time the game builds GVRAM (its first game), it is converted into
; planar layers in ST colours (palette_map.i: each graphics index a 2x2
; ordered dither of two colours, anchored to its layer, so the pattern
; scrolls with it), and the table is composed over it. Later games skip the
; game's builder (sz2.s, st_table_ready). The background shows from the
; game's start (the builder's hook) until _VPAGE hides the graphics pages
; or _WIPE clears them (menus, name entry).

	xdef amiga_graphics_changed
	xdef st_table_ready
	xdef background_visible
	xdef copy_background
	xdef hide_background

	xref L_00C00000
	xref L_00E80000
	xref graphics_dither

	ifd __DUMP__
	xref write_graphics_dump
	endif

GVRAM_LINE=1024
GVRAM_PAGE_SIZE=$80000

PAGE0_LINES=256
PAGE1_LINES=32
GROUPS=16 ; 16-pixel groups in the 256-pixel picture.
PAGE0_LINE=GROUPS*10 ; Mask and four plane words per group.
PAGE1_LINE=GROUPS*8
TABLE_LINE=GROUPS*8
TABLE_STRIP=PAGE0_LINES*TABLE_LINE ; 32 KB.

PLAYFIELD_LINES=192
SCREEN_LINE=160

CRTC_PAGE0_Y=$1a
CRTC_PAGE1_Y=$22

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Called after the game has built (or would build) GVRAM, at the start of
; every game. Preserves all registers.

amiga_graphics_changed:
	st		background_visible

	tst.b	st_table_ready
	bne		.done

	movem.l	d0-d7/a0-a6,-(sp)

	ifd __DUMP__
	jsr		write_graphics_dump ; GVRAM as the game built it.
	endif

	bsr		convert_layers
	bsr		compose_table

	st		st_table_ready

	movem.l	(sp)+,d0-d7/a0-a6

.done:
	rts

; _VPAGE with no page shown, _WIPE: no background. Preserves all registers.

hide_background:
	sf		background_visible

	rts

; ------------------------------------------------------------------------------
;
; GVRAM pages -> planar layers: page 0's 256 lines (per group a mask word,
; 1 = transparent, then four plane words), page 1's 32 lines (four plane
; words per group).

convert_layers:
	; The dithered colour of every graphics index at each 2x2 threshold:
	; dither_colours[index * 4 + t] = b if level > t, else a.

	lea		graphics_dither,a0
	lea		dither_colours,a1
	move	#256-1,d7

.entry_loop:
	move.b	(a0)+,d0 ; a
	move.b	(a0)+,d1 ; b
	move.b	(a0)+,d2 ; Level.
	addq.l	#1,a0
	moveq	#0,d6 ; t

.threshold_loop:
	move.b	d0,d3
	cmp.b	d6,d2
	bls		.colour_a

	move.b	d1,d3

.colour_a:
	move.b	d3,(a1)+
	addq	#1,d6
	cmp		#4,d6
	bne		.threshold_loop

	dbf		d7,.entry_loop

	lea		dither_colours,a5

	lea		layer0,a2
	lea		L_00C00000,a3
	moveq	#0,d6 ; Line.

.page0_line:
	bsr		line_thresholds
	move.l	a3,a4
	addq.l	#1,a4 ; Low bytes of the words.
	moveq	#GROUPS-1,d7

.page0_group:
	bsr		convert_group
	move	d4,(a2)+ ; Mask.
	move	d0,(a2)+
	move	d1,(a2)+
	move	d2,(a2)+
	move	d3,(a2)+

	dbf		d7,.page0_group

	lea		GVRAM_LINE(a3),a3
	addq	#1,d6
	cmp		#PAGE0_LINES,d6
	bne		.page0_line

	lea		layer1,a2
	lea		L_00C00000+GVRAM_PAGE_SIZE,a3
	moveq	#0,d6

.page1_line:
	bsr		line_thresholds
	move.l	a3,a4
	addq.l	#1,a4
	moveq	#GROUPS-1,d7

.page1_group:
	bsr		convert_group
	move	d0,(a2)+
	move	d1,(a2)+
	move	d2,(a2)+
	move	d3,(a2)+

	dbf		d7,.page1_group

	lea		GVRAM_LINE(a3),a3
	addq	#1,d6
	cmp		#PAGE1_LINES,d6
	bne		.page1_line

	rts

; d6 = layer line: a1 = its two thresholds (even x, odd x).

line_thresholds:
	moveq	#1,d0
	and		d6,d0
	add		d0,d0
	lea		bayer(pc),a1
	add		d0,a1

	rts

bayer: ; 2x2 thresholds, (y & 1) * 2 + (x & 1): colour b if level > it.
	dc.b	0,2,3,1

; One pixel: \1 = 0 (even x) or 1 (odd x).

CONVERT_PIXEL macro
	moveq	#0,d5
	move.b	(a4),d5
	addq.l	#2,a4
	add		d0,d0
	add		d1,d1
	add		d2,d2
	add		d3,d3
	add		d4,d4
	tst.b	d5
	bne.s	.opaque\@

	addq	#1,d4 ; Transparent.

	bra.s	.done\@

.opaque\@:
	lsl		#2,d5
	or.b	\1(a1),d5
	move.b	(a5,d5.w),d5 ; ST colour.
	lsr.b	#1,d5
	bcc.s	.plane1\@
	addq	#1,d0
.plane1\@:
	lsr.b	#1,d5
	bcc.s	.plane2\@
	addq	#1,d1
.plane2\@:
	lsr.b	#1,d5
	bcc.s	.plane3\@
	addq	#1,d2
.plane3\@:
	lsr.b	#1,d5
	bcc.s	.done\@
	addq	#1,d3
.done\@:
	endm

; a4 = the group's first GVRAM index (stride 2), a1 = the line's thresholds,
; a5 = dither_colours: d0-d3 = plane words, d4 = mask (1 = transparent,
; index 0). a4 advanced; uses d5.

convert_group:
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4

	rept	8
	CONVERT_PIXEL 0
	CONVERT_PIXEL 1
	endr

	rts

; ------------------------------------------------------------------------------
;
; The table: for every s (0-31) and a (0-255), page 0's line a over page 1's
; line (a + s) & 31.

compose_table:
	lea		L_00C00000,a1 ; Destination: T[0][0].
	moveq	#0,d6 ; s

.strip_loop:
	lea		layer0,a0
	moveq	#0,d5 ; a

.line_loop:
	move	d5,d0
	add		d6,d0
	and		#PAGE1_LINES-1,d0
	lsl		#7,d0 ; * PAGE1_LINE (128)
	lea		layer1,a2
	add		d0,a2

	moveq	#GROUPS-1,d7

.group_loop:
	move	(a0)+,d4 ; Mask.
	beq		.opaque_group

	cmp		#$ffff,d4
	beq		.transparent_group

	; Mixed: page 1 & mask | page 0 (page 0's planes are 0 where
	; transparent).

	rept	4
	move	(a2)+,d0
	and		d4,d0
	or		(a0)+,d0
	move	d0,(a1)+
	endr

	dbf		d7,.group_loop

	bra		.line_done

.opaque_group:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	addq.l	#8,a2

	dbf		d7,.group_loop

	bra		.line_done

.transparent_group:
	addq.l	#8,a0
	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+

	dbf		d7,.group_loop

.line_done:
	addq	#1,d5
	cmp		#PAGE0_LINES,d5
	bne		.line_loop

	addq	#1,d6
	cmp		#PAGE1_LINES,d6
	bne		.strip_loop

	rts

; ------------------------------------------------------------------------------
;
; a1 = the picture's first playfield line (its first pixel, 32 pixels into
; the screen line), d0.w = the first playfield line's X68000 line (8 + the
; window offset): copies the PLAYFIELD_LINES lines of the background there.
; Uses all registers but a7.

copy_background:
	move	d0,d1
	add		L_00E80000+CRTC_PAGE0_Y,d1
	and		#PAGE0_LINES-1,d1 ; a
	move	d0,d2
	add		L_00E80000+CRTC_PAGE1_Y,d2
	sub		d1,d2
	and		#PAGE1_LINES-1,d2 ; s

	moveq	#0,d3
	move	d2,d3
	swap	d3
	lsr.l	#1,d3 ; s * 32768
	lea		L_00C00000,a0
	add.l	d3,a0
	move.l	a0,a6 ; T[s][0], for the wrap.
	moveq	#0,d3
	move	d1,d3
	lsl.l	#7,d3
	add.l	d3,a0 ; T[s][a]

	move	#PAGE0_LINES,d7
	sub		d1,d7 ; Lines before the wrap.
	cmp		#PLAYFIELD_LINES,d7
	bls		.first_count

	move	#PLAYFIELD_LINES,d7

.first_count:
	move	#PLAYFIELD_LINES,d6
	sub		d7,d6 ; Lines after it.

	subq	#1,d7
	bsr		.copy_lines

	subq	#1,d6
	bmi		.done

	move.l	a6,a0
	move	d6,d7
	bsr		.copy_lines

.done:
	rts

; d7 = lines - 1: copies 128 bytes per line from (a0)+ to (a1), next line.

.copy_lines:
	movem.l	(a0)+,d0-d5/a2-a5 ; 40 bytes.
	movem.l	d0-d5/a2-a5,(a1)
	movem.l	(a0)+,d0-d5/a2-a5
	movem.l	d0-d5/a2-a5,40(a1)
	movem.l	(a0)+,d0-d5/a2-a5
	movem.l	d0-d5/a2-a5,80(a1)
	movem.l	(a0)+,d0-d1
	movem.l	d0-d1,120(a1)
	lea		SCREEN_LINE(a1),a1

	dbf		d7,.copy_lines

	rts

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

st_table_ready:
	ds.b	1
background_visible:
	ds.b	1

	even

dither_colours:
	ds.b	256*4
layer0:
	ds.b	PAGE0_LINES*PAGE0_LINE
layer1:
	ds.b	PAGE1_LINES*PAGE1_LINE

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
