
; Settings: SZ2.CFG beside the program, or the file its command line names
; (test runs). One name=value a line, in any case; a line starting with #
; or ; is a comment. A setting it does not know, or a value it cannot
; read, is reported at start and ignored. binaries/st/SZ2.CFG lists them,
; commented out, each set to the opposite of its default:
;
;   preset=default       the settings as the file has them; performance or
;                        authentic: screen, hud, megaste_speedup and music
;                        set as the preset has them, whatever the file says
;                        (presets)
;   screen=crop          crop (200 lines, the window follows the ship) or
;                        full (both borders open: the whole picture)
;   hud=over             the score over the playfield (as on the X68000), or
;                        band: in a band of its own (faster)
;   megaste_speedup=true a Mega STE at 16 MHz with the cache; false: at
;                        8 MHz without it (for comparisons)
;   music=true           the songs on the YM2149 (MUS_DAT); false: none
;   lockstep=false       true: every frame shown from the start (as F1)
;   frames=0             a frame limit: the game exits after that many
;                        frames (test runs); 0: none

	xdef read_config
	xdef full_height
	xdef hud_band
	xdef megaste_speedup

	xref basepage
	xref heap_address
	xref frame_limit
	xref lockstep_mode
	xref music_enabled
	xref print_text
	xref print_number
	xref line_end_text

CONFIG_SIZE=4096 ; At most (the rest is ignored), read into the game's
                 ; process area (main.s clears it afterwards).
WORD_SIZE=32 ; A name or value, at most 31 characters (the rest ignored).

; The presets (preset=, 1-2; 0: default, none): name, then screen=full, hud=band,
; megaste_speedup, music.

PRESET_NAME=0
PRESET_FULL_HEIGHT=4
PRESET_HUD_BAND=5
PRESET_MEGASTE_SPEEDUP=6
PRESET_MUSIC=7
PRESET_SIZE=8
PRESET_COUNT=2

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Reads the settings (before the take-over: GEMDOS). Preserves all
; registers.

read_config:
	movem.l	d0-d7/a0-a6,-(sp)

	st		megaste_speedup ; (The other defaults are 0.)
	st		music_enabled

	; The file: the command line's first word, or SZ2.CFG.

	move.l	basepage,a0
	lea		128(a0),a0
	moveq	#0,d0
	move.b	(a0)+,d0
	lea		config_name,a1
	bra		.next_character

.name_character:
	move.b	(a0)+,d1
	cmp.b	#' ',d1
	bhi		.keep

	cmp.l	#config_name,a1
	beq		.next_character ; (A blank before it.)

	bra		.name_copied

.keep:
	move.b	d1,(a1)+

.next_character:
	dbf		d0,.name_character

.name_copied:
	clr.b	(a1)
	lea		config_name,a2
	cmp.l	a2,a1
	bne		.open

	lea		config_default_name,a2

.open:
	clr		-(sp)
	pea		(a2)
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi		.no_file

	move	d0,d3
	move.l	heap_address,-(sp)
	move.l	#CONFIG_SIZE-1,-(sp)
	move	d3,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp
	move.l	d0,d4
	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	tst.l	d4
	bpl		.file_read

	moveq	#0,d4

.file_read:
	move.l	heap_address,a0
	clr.b	(a0,d4.l)
	bsr		parse_config

	bra		.report

.no_file:
	lea		config_default_name,a0 ; (Only a file named must be there.)
	cmp.l	a0,a2
	beq		.report

	lea		no_config_text,a0
	jsr		print_text
	move.l	a2,a0
	jsr		print_text
	lea		line_end_text,a0
	jsr		print_text

.report:
	bsr		apply_preset

	tst.b	full_height
	beq		.no_full_height

	lea		full_height_text,a0
	jsr		print_text

.no_full_height:
	tst.b	hud_band
	beq		.no_hud_band

	lea		hud_band_text,a0
	jsr		print_text

.no_hud_band:
	move.l	frame_limit,d0
	beq		.no_frame_limit

	lea		frame_limit_text,a0
	jsr		print_text
	jsr		print_number
	lea		line_end_text,a0
	jsr		print_text

.no_frame_limit:
	tst.b	lockstep_mode
	beq		.done

	lea		lockstep_text,a0
	jsr		print_text

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; a0 = the settings' text (ended by a zero): each line's setting made.

parse_config:
	bsr		skip_blanks
	move.b	(a0),d0
	beq		.done

	cmp.b	#'#',d0
	beq		.next_line
	cmp.b	#';',d0
	beq		.next_line
	cmp.b	#13,d0
	beq		.next_line
	cmp.b	#10,d0
	beq		.next_line

	lea		name_word,a1
	bsr		read_word
	bsr		skip_blanks
	cmp.b	#'=',(a0)
	bne		.unknown

	addq.l	#1,a0
	bsr		skip_blanks
	lea		value_word,a1
	bsr		read_word

	lea		settings,a2

.find:
	move.l	(a2)+,d0
	beq		.unknown

	move.l	(a2)+,a3
	move.l	d0,a4
	lea		name_word,a1
	bsr		same_word
	bne		.find

	lea		value_word,a1
	jsr		(a3)
	tst.l	d1
	beq		.next_line

	lea		bad_value_text,a1 ; A value it cannot read.

	bra		.report

.unknown:
	lea		unknown_text,a1

.report:
	move.l	a0,-(sp)
	move.l	a1,a0
	jsr		print_text
	lea		name_word,a0
	jsr		print_text
	lea		line_end_text,a0
	jsr		print_text
	move.l	(sp)+,a0

.next_line:
	move.b	(a0)+,d0
	beq		.end

	cmp.b	#10,d0
	bne		.next_line

	bra		parse_config

.end:
	subq.l	#1,a0

.done:
	rts

; a0 past spaces and tabs.

skip_blanks:
	cmp.b	#' ',(a0)
	beq		.blank

	cmp.b	#9,(a0)
	bne		.done

.blank:
	addq.l	#1,a0

	bra		skip_blanks

.done:
	rts

; The word at a0 (letters, digits, '_') into a1 (WORD_SIZE bytes) in
; lower case, ended by a zero; a0 past it.

read_word:
	moveq	#WORD_SIZE-2,d1

.character:
	move.b	(a0),d0
	cmp.b	#'_',d0
	beq		.take

	cmp.b	#'0',d0
	bcs		.end

	cmp.b	#'9',d0
	bls		.take

	or.b	#$20,d0 ; Lower case.
	cmp.b	#'a',d0
	bcs		.end

	cmp.b	#'z',d0
	bhi		.end

.take:
	addq.l	#1,a0
	tst		d1
	bmi		.character ; (Too long: the rest dropped.)

	move.b	d0,(a1)+
	subq	#1,d1

	bra		.character

.end:
	clr.b	(a1)

	rts

; Z set if the words at a1 and a4 are the same. Preserves a1 and a4 (not
; d0).

same_word:
	movem.l	a1/a4,-(sp)

.character:
	move.b	(a1)+,d0
	cmp.b	(a4)+,d0
	bne		.done

	tst.b	d0
	bne		.character

.done:
	movem.l	(sp)+,a1/a4

	rts

; A preset: its settings over the file's (and reported). Uses d0/a0.

apply_preset:
	moveq	#0,d0
	move.b	preset,d0
	beq		.done

	lea		presets-PRESET_SIZE,a0
	mulu	#PRESET_SIZE,d0
	add.l	d0,a0
	move.b	PRESET_FULL_HEIGHT(a0),full_height
	move.b	PRESET_HUD_BAND(a0),hud_band
	move.b	PRESET_MEGASTE_SPEEDUP(a0),megaste_speedup
	move.b	PRESET_MUSIC(a0),music_enabled

	move.l	a0,-(sp)
	lea		preset_text,a0
	jsr		print_text
	move.l	(sp)+,a0
	move.l	PRESET_NAME(a0),a0
	jsr		print_text
	lea		preset_end_text,a0
	jsr		print_text

.done:
	rts

; The settings: a1 = the value word. Return d1.l = 0, or non-zero (Z
; clear; the setting unchanged) if the value cannot be read. Preserve a0.

set_preset:
	moveq	#0,d1
	lea		default_word,a4
	bsr		same_word
	bne		.not_default

	clr.b	preset ; The file's settings.

	rts

.not_default:
	lea		presets,a2
	moveq	#1,d2

.find:
	move.l	PRESET_NAME(a2),a4
	bsr		same_word
	beq		.found

	lea		PRESET_SIZE(a2),a2
	addq	#1,d2
	cmp		#PRESET_COUNT+1,d2
	bne		.find

	bra		bad_value

.found:
	move.b	d2,preset

	rts

set_screen:
	moveq	#0,d1
	lea		crop_word,a4
	bsr		same_word
	bne		.not_crop

	sf		full_height

	rts

.not_crop:
	lea		full_word,a4
	bsr		same_word
	bne		bad_value

	st		full_height

	rts

set_hud:
	moveq	#0,d1
	lea		over_word,a4
	bsr		same_word
	bne		.not_over

	sf		hud_band

	rts

.not_over:
	lea		band_word,a4
	bsr		same_word
	bne		bad_value

	st		hud_band

	rts

set_megaste_speedup:
	bsr		parse_bool
	bne		.done

	move.b	d0,megaste_speedup

.done:
	rts

set_music:
	bsr		parse_bool
	bne		.done

	move.b	d0,music_enabled

.done:
	rts

set_lockstep:
	bsr		parse_bool
	bne		.done

	move.b	d0,lockstep_mode

.done:
	rts

set_frames:
	bsr		parse_number
	bne		.done

	move.l	d0,frame_limit

.done:
	rts

bad_value:
	moveq	#1,d1

	rts

; a1 = true, 1, yes or on (d0.b = $FF), or false, 0, no or off (d0.b = 0):
; d1.l = 0 (Z set), or non-zero (Z clear) for anything else.

parse_bool:
	lea		bool_words,a2
	moveq	#-1,d2 ; (A true word first, then a false one.)

.word:
	move.l	(a2)+,d1
	beq		.bad

	move.l	d1,a4
	bsr		same_word
	beq		.found

	not.b	d2

	bra		.word

.found:
	move.b	d2,d0
	moveq	#0,d1

	rts

.bad:
	moveq	#0,d0

	bra		bad_value

; a1 = a decimal number: d0.l; d1.l = 0 (Z set), or non-zero (Z clear)
; if it is not one.

parse_number:
	moveq	#0,d0
	move.l	a1,a4
	tst.b	(a4)
	beq		.bad

.digit:
	moveq	#0,d2
	move.b	(a4)+,d2
	beq		.done

	sub.b	#'0',d2
	cmp.b	#9,d2
	bhi		.bad

	add.l	d0,d0 ; * 10
	move.l	d0,d3
	lsl.l	#2,d0
	add.l	d3,d0
	add.l	d2,d0

	bra		.digit

.done:
	moveq	#0,d1

	rts

.bad:
	moveq	#0,d0

	bra		bad_value

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

settings: ; Name, handler.
	dc.l	preset_name,set_preset
	dc.l	screen_name,set_screen
	dc.l	hud_name,set_hud
	dc.l	megaste_speedup_name,set_megaste_speedup
	dc.l	music_name,set_music
	dc.l	lockstep_name,set_lockstep
	dc.l	frames_name,set_frames
	dc.l	0

presets: ; The most pictures per second; the X68000's look.
	dc.l	performance_word
	dc.b	0,-1,-1,0 ; Crop, the HUD band, 16 MHz, no music.
	dc.l	authentic_word
	dc.b	-1,0,-1,-1 ; Full height, the score over the playfield, music.

bool_words:
	dc.l	true_word,false_word,one_word,zero_word
	dc.l	yes_word,no_word,on_word,off_word
	dc.l	0

config_default_name:
	dc.b	'SZ2.CFG',0
screen_name:
	dc.b	'screen',0
megaste_speedup_name:
	dc.b	'megaste_speedup',0
music_name:
	dc.b	'music',0
lockstep_name:
	dc.b	'lockstep',0
frames_name:
	dc.b	'frames',0
preset_name:
	dc.b	'preset',0
performance_word:
	dc.b	'performance',0
default_word:
	dc.b	'default',0
authentic_word:
	dc.b	'authentic',0
preset_text:
	dc.b	'Preset: ',0
preset_end_text:
	dc.b	' (its settings, not the file',39,'s).',13,10,0
hud_name:
	dc.b	'hud',0
over_word:
	dc.b	'over',0
band_word:
	dc.b	'band',0
crop_word:
	dc.b	'crop',0
full_word:
	dc.b	'full',0
true_word:
	dc.b	'true',0
false_word:
	dc.b	'false',0
one_word:
	dc.b	'1',0
zero_word:
	dc.b	'0',0
yes_word:
	dc.b	'yes',0
no_word:
	dc.b	'no',0
on_word:
	dc.b	'on',0
off_word:
	dc.b	'off',0
no_config_text:
	dc.b	'No settings file ',0
unknown_text:
	dc.b	'Settings: not known, ignored: ',0
bad_value_text:
	dc.b	'Settings: a value not understood, ignored: ',0
hud_band_text:
	dc.b	'Score: in a band of its own.',13,10,0
full_height_text:
	dc.b	'Screen: full height.',13,10,0
frame_limit_text:
	dc.b	'Frame limit: ',0
lockstep_text:
	dc.b	'Lockstep: every frame (F1 switches).',13,10,0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

config_name:
	ds.b	128
name_word:
	ds.b	WORD_SIZE
value_word:
	ds.b	WORD_SIZE
full_height: ; screen=full: both borders open (until they fail to).
	ds.b	1
hud_band: ; hud=band: the score in a band of its own, not over the playfield.
	ds.b	1
preset: ; preset= (1-2), applied after the file: 0 default (none).
	ds.b	1
megaste_speedup: ; A Mega STE at 16 MHz with the cache.
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
