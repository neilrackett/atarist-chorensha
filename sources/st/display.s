
; Atari ST display: low resolution (320 x 200, 16 colours, or 273 lines
; at full height), triple-buffered, drawn in bitplanes:
;
;   lines 0-199   the playfield: 200 of the X68000's 256 lines, 1:1, 32
;                 pixels from the left edge, with the text layer's score
;                 (row 0) over its top, as on the X68000. The window follows
;                 the ship in a stage (the ship two thirds down; at most 2
;                 lines per frame), elsewhere it shows lines 24-223; F2
;                 keeps it there. At full height (SZ2.CFG's screen=full:
;                 both borders open, STDL's code) all 256, and no window.
;
; With hud=band the score has lines 0-7 to itself instead, the HUD band,
; drawn into all three screens by text.s when the game writes it, never
; touched here: the playfield is lines 8-199 (X68000 lines 8 + the window
; offset on), or 8-255 at full height. A picture then draws 8 lines less,
; and the score only when it changes.
;
; A picture: the background (background.s: a copy from the composed table)
; or colour 0 while the game hides it; sprites and the text layer's other
; rows in the order of the X68000's priority register R1; the borders where
; sprites reached into them cleared; the 16 colours (palette.s). The VBL
; shows it: the screen address at the next VBL (the shifter takes it a frame
; later), the colours one VBL after that, together with the new screen.
; Three screens: the one shown, the one presented (shown after those VBLs)
; and the one drawn into, so drawing never waits for the VBLs; presenting
; waits only if the picture before is not on screen yet (wait_for_flip).

	xdef initialize_display
	xdef use_crop_layout
	xdef show_display_page
	xdef screen_top_offset
	xdef playfield_top
	xdef playfield_lines
	xdef playfield_bottom
	xdef render_frame
	xdef present_frame
	xdef display_vbl
	xdef display_screen_address
	xdef screen_buffers
	xdef st_palette
	xdef write_screenshot
	xdef crop_mode
	xdef st_hidden_menu
	xdef st_name_entry_window
	xdef st_scores_window
	xdef text_window
	xdef text_unpinned

	xref L_00E82000
	xref WORD_00098864
	xref background_visible
	xref copy_background
	xref draw_sprites
	xref margin_top
	xref margin_bottom
	xref draw_text_rows
	xref make_hardware_palette
	xref in_stage
	xref frame_count
	xref divide_unsigned
	xref create_and_write
	xref write_more
	xref close_file
	xref start_render_parts
	xref mark_render_part
	xref full_height
	xref hud_band

	xref _stdl_ovsc_bhi ; (stdl_glue.c, lib/stdl/src/overscan.c)
	xref _stdl_ovsc_bmid
	xref _stdl_ovsc_bhi2
	xref _stdl_ovsc_bmid2
	xref _stdl_ovsc_l262mid

	ifd __ORACLE__
	xref L_00E80000
	xref character_map
	xref sprite_list
	xref render_sprite_count
	endif

	include "st.i"

MAXIMUM_WINDOW=256-CROP_SCREEN_LINES ; 56: the window shows X68000 lines w..199+w.
DEFAULT_WINDOW=24 ; Lines 24-223.
HIDDEN_MENU_WINDOW=40 ; Lines 40-239: the hidden menu's rows 6-29.
NAME_ENTRY_WINDOW=48 ; Lines 48-247: the name entry's rows 6-30.
SCORES_WINDOW=40 ; Lines 40-239: the title's high score table, rows 5-28.
SHIP_LINE=138 ; The ship's line on the screen.
WINDOW_STEP=2 ; Lines per frame.
PI1_SIZE=CROP_SCREEN_LINES*SCREEN_LINE ; A screenshot's picture: 200 lines,
FULL_PI1_SIZE=256*SCREEN_LINE ; or the whole 256 at full height (a longer
                              ; PI1 than Degas's).
OVERSCAN_LINE_262=228 ; The page's row on the frame's line 262 (STDL's).

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; The screens for the layout chosen (full_height: both borders open, else
; crop): three pages, allocated (the sprite arena then takes what is
; left), cleared. Returns d0.l negative (N set) if there is no memory for
; them.

initialize_display:
	movem.l	d1-d2/a0-a2,-(sp)

	move.l	#CROP_PAGE_SIZE*SCREENS+256,d0
	tst.b	full_height
	beq		.size_known

	move.l	#FULL_PAGE_SIZE*SCREENS+256,d0

.size_known:
	move.l	d0,-(sp)
	move	#72,-(sp) ; Malloc
	trap	#1
	addq.l	#6,sp
	move.l	d0,screen_memory
	beq		.no_memory

	bsr		set_layout
	moveq	#0,d0

.done:
	movem.l	(sp)+,d1-d2/a0-a2

	rts

.no_memory:
	moveq	#-1,d0

	bra		.done

; The borders did not open: crop instead, in the same memory (more than
; crop needs), before the game starts. Preserves all registers.

use_crop_layout:
	sf		full_height
	bsr		set_layout

	; (Falls through.)

; The shown screen's page to the shifter. Preserves all registers.

show_display_page:
	move.l	d0,-(sp)
	move.l	display_screen_address,d0
	sub.l	screen_top_offset,d0
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w
	move.l	(sp)+,d0

	rts

; The layout's values, the screens in their pages (256-aligned, cleared)
; and the window. Preserves all registers.

set_layout:
	movem.l	d0-d1/a0,-(sp)

	tst.b	full_height
	bne		.full_height

	clr.l	screen_top_offset
	move.l	#CROP_PAGE_SIZE,d1
	move	#CROP_SCREEN_LINES,d0
	move	#DEFAULT_WINDOW,window_offset

	bra		.values_set

.full_height:
	move.l	#FULL_SCREEN_TOP*SCREEN_LINE,screen_top_offset
	move.l	#FULL_PAGE_SIZE,d1
	move	#FULL_SCREEN_LINES,d0
	clr		window_offset

.values_set:
	; d0 = the picture's lines: the playfield's, but for the HUD band's.

	clr		playfield_top
	tst.b	hud_band
	beq		.top_set

	move	#HUD_BAND_LINES,playfield_top

.top_set:
	move	d0,playfield_bottom
	subq	#1,playfield_bottom
	sub		playfield_top,d0
	move	d0,playfield_lines

	move.l	screen_memory,d0
	add.l	#255,d0
	clr.b	d0
	move.l	d0,a0 ; The first page.
	add.l	screen_top_offset,d0 ; Its screen's origin.
	move.l	d0,display_screen_address
	move.l	d0,screen_buffers
	add.l	d1,d0
	move.l	d0,work_screen_address
	move.l	d0,screen_buffers+4
	add.l	d1,d0
	move.l	d0,spare_screen_address
	move.l	d0,screen_buffers+8

	move.l	d1,d0 ; The three pages cleared, 16 bytes a pass.
	add.l	d0,d0
	add.l	d1,d0
	lsr.l	#4,d0
	subq.l	#1,d0
	moveq	#0,d1

.clear:
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	move.l	d1,(a0)+
	subq.l	#1,d0
	bpl		.clear

	movem.l	(sp)+,d0-d1/a0

	rts

; ------------------------------------------------------------------------------
;
; Screens of the game whose text does not fit crop's default window (sz2.s,
; ifd __ST__, after their CLEAR_TEXT_PLANE; the next one ends it, text.s).
; The name entry: its table's ten scores and keyboard, rows 6-30, its title
; and heading (rows 1 and 4) left out, and its rows 1-3 not pinned to the
; top as the HUD's are (they are its title's). The title's high score
; table: rows 5-28, all of it. Preserve all registers.

st_name_entry_window:
	move	#NAME_ENTRY_WINDOW,text_window
	st		text_unpinned

	rts

st_scores_window:
	move	#SCORES_WINDOW,text_window

	rts

; ------------------------------------------------------------------------------
;
; VBL: a presented picture's screen address now (the shifter takes it at the
; end of the next frame), its colours a VBL later, with it. The buffer it
; replaces is free after that. Preserves all registers.

display_vbl:
	tst.b	flip_pending
	beq		.done

	cmp.b	#2,flip_pending
	bne		.colours

	; Its page (256-aligned: an STE's low byte stays 0). At full height,
	; the borders' top interrupt accepts it too (bhi2, bmid2) from now on:
	; next frame shows it, this one still the page before. (Their values
	; are kept in crop too, unused.)

	move.l	d0,-(sp)
	move.l	display_screen_address,d0
	sub.l	screen_top_offset,d0
	move.l	d0,flip_page
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	move.b	d0,_stdl_ovsc_bmid2
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w
	move.b	d0,_stdl_ovsc_bhi2
	move.l	(sp)+,d0

	bra		.flipped

.colours:
	movem.l	d0-d7,-(sp)
	movem.l	flip_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w

	; The page is shown from this frame: at full height the borders'
	; interrupts compare the video counter with it (the bottom one at its
	; line 262).

	move.b	_stdl_ovsc_bhi2,_stdl_ovsc_bhi
	move.b	_stdl_ovsc_bmid2,_stdl_ovsc_bmid
	move.l	flip_page,d0
	add.l	#OVERSCAN_LINE_262*SCREEN_LINE,d0
	lsr.w	#8,d0
	move.b	d0,_stdl_ovsc_l262mid
	movem.l	(sp)+,d0-d7

.flipped:
	subq.b	#1,flip_pending

.done:
	rts

; ------------------------------------------------------------------------------
;
; Draws the current X68000 screen into the hidden screen.

; Measurement builds: the render's part \1 has ended (its time added up).

RENDER_PART macro
	ifnd __RELEASE__
	moveq	#\1,d0
	jsr		mark_render_part
	endif
	endm

render_frame:
	movem.l	d0-d7/a0-a6,-(sp)

	ifnd __RELEASE__
	jsr		start_render_parts
	endif

	bsr		update_window

	; Background, or colour 0.

	move.l	work_screen_address,a1
	tst.b	background_visible
	beq		.no_background

	move	playfield_top,d0
	mulu	#SCREEN_LINE,d0
	lea		PICTURE_X_BYTES(a1,d0.l),a1
	move	window_offset,d0
	add		playfield_top,d0 ; The playfield's first X68000 line.
	jsr		copy_background

	bra		.layers

.no_background:
	bsr		clear_playfield

.layers:
	RENDER_PART 0 ; Background.

	; R1 bits 13-12 = sprite priority, 11-10 = text priority (0 = front).

	move	L_00E82000+VC_PRIORITY,d0
	move	d0,d1
	lsr		#8,d0
	lsr		#4,d0
	and		#3,d0 ; Sprites.
	lsr		#8,d1
	lsr		#2,d1
	and		#3,d1 ; Text.
	cmp		d1,d0
	bhi		.text_in_front

	bsr		.text
	bsr		.sprites

	bra		.borders

.text_in_front:
	bsr		.sprites
	bsr		.text

.borders:
	bsr		clear_margins

	lea		picture_palette,a0
	jsr		make_hardware_palette

	RENDER_PART 3 ; Borders and colours.

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.sprites:
	move.l	work_screen_address,a1
	move	window_offset,d0
	jsr		draw_sprites
	RENDER_PART 1

	rts

.text:
	move.l	work_screen_address,a1
	move	window_offset,d0
	jsr		draw_text_rows
	RENDER_PART 2

	rts

; The window: in a stage, toward the ship (two thirds down the playfield),
; else (or with F2) the default, or lower for the game's hidden menu (its
; title to its EXIT) and the screens that ask for a window of their own
; (text_window). At full height none: the whole playfield.

update_window:
	tst.b	full_height
	bne		.done

	move	#DEFAULT_WINDOW,d0
	tst.b	st_hidden_menu
	beq		.not_hidden_menu

	moveq	#HIDDEN_MENU_WINDOW,d0

	bra		.target

.not_hidden_menu:
	tst.b	in_stage
	bne		.stage

	move	text_window,d1
	bmi		.target

	move	d1,d0

	bra		.target

.stage:
	tst.b	crop_mode
	bne		.target

	move	WORD_00098864+2,d0 ; Ship y, 1/64 pixel, sprite coordinates.
	asr		#6,d0
	sub		#16+SHIP_LINE,d0
	bpl		.not_above

	moveq	#0,d0

.not_above:
	cmp		#MAXIMUM_WINDOW,d0
	ble		.target

	moveq	#MAXIMUM_WINDOW,d0

.target:
	; At most WINDOW_STEP lines per frame since the last picture.

	move.l	frame_count,d1
	sub.l	window_frame,d1
	move.l	frame_count,window_frame
	cmp.l	#MAXIMUM_WINDOW,d1
	bls		.frames_ok

	moveq	#MAXIMUM_WINDOW,d1

.frames_ok:
	add		d1,d1 ; WINDOW_STEP
	bne		.step_ok

	moveq	#WINDOW_STEP,d1

.step_ok:
	sub		window_offset,d0 ; Distance.
	cmp		d1,d0
	ble		.not_too_low

	move	d1,d0

.not_too_low:
	neg		d1
	cmp		d1,d0
	bge		.not_too_high

	move	d1,d0

.not_too_high:
	add		d0,window_offset

.done:
	rts

; The playfield in colour 0 (no background).

clear_playfield:
	move	playfield_lines,d7
	move	playfield_top,d0
	add		d7,d0
	mulu	#SCREEN_LINE,d0
	move.l	work_screen_address,a0
	add.l	d0,a0 ; Its end.
	mulu	#SCREEN_LINE/40,d7
	subq	#1,d7
	bsr		zero_registers

.loop:
	movem.l	d0-d6/a1-a3,-(a0) ; 10 longs.
	dbf		d7,.loop

	rts

; The borders (16 bytes either side) of the lines sprites reached.

clear_margins:
	move	margin_top,d6
	move	margin_bottom,d7
	sub		d6,d7
	bmi		.done

	move.l	work_screen_address,a0
	mulu	#SCREEN_LINE,d6
	add.l	d6,a0
	bsr		zero_registers

.loop:
	movem.l	d0-d3,(a0)
	movem.l	d0-d3,SCREEN_LINE-PICTURE_X_BYTES(a0)
	lea		SCREEN_LINE(a0),a0

	dbf		d7,.loop

.done:
	rts

zero_registers:
	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	move.l	d0,a1
	move.l	d0,a2
	move.l	d0,a3

	rts

; ------------------------------------------------------------------------------
;
; Shows the picture drawn by render_frame.

present_frame:
	bsr		wait_for_flip ; The picture before on screen (usually long since).

	movem.l	d0-d7/a0,-(sp)

	movem.l	picture_palette,d0-d7
	movem.l	d0-d7,flip_palette

	; The picture drawn is presented; the next one goes into the spare
	; screen; the one shown until now becomes the spare (once the VBLs
	; have shown the new one, before the next presentation).

	move.l	display_screen_address,d0
	move.l	work_screen_address,display_screen_address
	move.l	spare_screen_address,work_screen_address
	move.l	d0,spare_screen_address
	move.b	#2,flip_pending

	movem.l	(sp)+,d0-d7/a0

	rts

; Waits until the picture last presented is on screen (its address and
; colours taken at the VBLs): only then has the shifter left the screen
; shown before it. Preserves all registers.

wait_for_flip:
	tst.b	flip_pending
	beq		.done

	move	sr,-(sp)
	stop	#$2300
	move	(sp)+,sr

	bra		wait_for_flip

.done:
	rts

; ------------------------------------------------------------------------------
;
; Measurement runs: d0.l = frame; the picture just presented as a Degas
; file, Snnnnnnn.PI1, with its colours (tools/st/pi1_png.py converts it).
; GEMDOS, from the game's frame wait.

write_screenshot:
	movem.l	d0-d3/a0-a2,-(sp)

	lea		screenshot_name+8,a0 ; 'S', seven digits, '.PI1'.
	moveq	#7-1,d3

.digit_loop:
	moveq	#10,d1
	jsr		divide_unsigned
	add.b	#'0',d1
	move.b	d1,-(a0)
	dbf		d3,.digit_loop

	lea		screenshot_name,a0
	lea		screenshot_header,a1
	moveq	#2+16*2,d1 ; Resolution, palette.
	jsr		create_and_write
	bmi		.done

	move.l	display_screen_address,a1
	move.l	#PI1_SIZE,d1
	tst.b	full_height
	beq		.size_known

	move.l	#FULL_PI1_SIZE,d1

.size_known:
	jsr		write_more
	jsr		close_file

	ifd __ORACLE__
	bsr		write_frame_dump
	endif

.done:
	movem.l	(sp)+,d0-d3/a0-a2

	rts

	ifd __ORACLE__

; Oracle builds (lockstep runs): with each screenshot, Fnnnnnnn.BIN, what
; the picture was drawn from, for tools/st/refrender.py: 'CRSF', the
; window offset (word), background shown (byte), the HUD band (byte: 1 with
; hud=band, else the score is over the playfield), the pages'
; scroll Y0, Y1 and R1 (words), the sprites (word), the video controller
; shadow ($400 bytes), the text layer's character map (32 x 32 bytes), the
; sprite list (8 bytes each).

write_frame_dump:
	lea		screenshot_name,a0
	move.b	#'F',(a0)
	move.b	#'B',9(a0)
	move.b	#'I',10(a0)
	move.b	#'N',11(a0)

	lea		frame_header,a1
	move.l	#'CRSF',(a1)+
	move	window_offset,(a1)+
	move.b	background_visible,(a1)+
	move.b	hud_band,(a1)
	and.b	#1,(a1)+
	move	L_00E80000+CRTC_PAGE0_Y,(a1)+
	move	L_00E80000+CRTC_PAGE1_Y,(a1)+
	move	L_00E82000+VC_PRIORITY,(a1)+
	move	render_sprite_count,(a1)+

	lea		screenshot_name,a0
	lea		frame_header,a1
	moveq	#16,d1
	jsr		create_and_write
	bmi		.restore

	lea		L_00E82000,a1
	move.l	#$400,d1
	jsr		write_more
	lea		character_map,a1
	move.l	#32*32,d1
	jsr		write_more
	move.l	sprite_list,a1
	moveq	#0,d1
	move	render_sprite_count,d1
	lsl.l	#3,d1
	jsr		write_more
	jsr		close_file

.restore:
	lea		screenshot_name,a0
	move.b	#'S',(a0)
	move.b	#'P',9(a0)
	move.b	#'I',10(a0)
	move.b	#'1',11(a0)

	rts

	endif

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

screenshot_name:
	dc.b	'S0000000.PI1',0

	even

screenshot_header: ; Degas: low resolution, then the picture's colours.
	dc.w	0
flip_palette: ; The presented picture's colours.
	dcb.w	16,0

st_palette: ; At the take-over: all black.
	dcb.w	16,0

text_window: ; A screen's own window (st_name_entry_window), or -1: none.
	dc.w	-1

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

display_screen_address: ; Shown (or about to be).
	ds.l	1
work_screen_address: ; Hidden: the next picture is drawn here.
	ds.l	1
spare_screen_address: ; Shown before the last presentation; drawn into next.
	ds.l	1
screen_buffers: ; The three screens (a HUD band is drawn into all of them).
	ds.l	SCREENS
window_frame:
	ds.l	1
picture_palette: ; The colours of the picture being drawn.
	ds.w	16
window_offset:
	ds.w	1

	ifd __ORACLE__
frame_header:
	ds.b	16
	endif

flip_page: ; The presented picture's page.
	ds.l	1
screen_memory: ; The screens' allocation.
	ds.l	1
screen_top_offset: ; Bytes from a page's start to its screen's origin.
	ds.l	1
playfield_top: ; The playfield's first line: 0, or below a HUD band.
	ds.w	1
playfield_lines: ; Shown: 200 in crop, 256 at full height (8 fewer below a
	ds.w	1         ; HUD band).
playfield_bottom: ; Its last line: 199, or 255.
	ds.w	1

flip_pending: ; 2: a new picture to show at the next VBL, 1: its colours next.
	ds.b	1
crop_mode: ; F2: the window does not follow the ship.
	ds.b	1
st_hidden_menu: ; The game's hidden menu is open (sz2.s).
	ds.b	1
text_unpinned: ; The text's rows 1-3 follow the window (st_name_entry_window).
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
