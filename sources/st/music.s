; Music: the game's songs on the YM2149. The game plays its songs
; (BGM_DAT/*.MDC, for the X68000's YM2151 FM chip) through the MCDRV driver
; (trap #4). Each song is reduced beforehand (tools/music/make_st_music.py:
; the original driver's YM2151 writes, through STDL's stdlconv opm) to the
; YM2149's three voices and noise, a register stream in STDL's STM format
; (lib/stdl/docs/format.md), MUSIC_DAT\NAME.STM:
;
;   'STM1', tick rate.w (50), frames.w, loop frame.w, reserved.w, then per
;   frame a mask word (bit r: register r's byte follows) and the bytes of
;   the registers set, in ascending order; byte-packed. The first frame
;   and the loop's set registers 0-12.
;
; - At start (initialize_music, GEMDOS): with music=true (SZ2.CFG) and
;   streams in MUSIC_DAT, a buffer the size of the largest. The MCDRV probe
;   (sz2.s) then reports the driver, and the game loads the songs named in
;   SZ2_BGM.CNF as on the X68000: amiga_music_loaded keeps each song's base
;   name and its fade unit (music_fades.i).
; - _TRANSMDC names the song to play; _PLAYMUSIC loads its stream (GEMDOS,
;   from the trap: the game runs in supervisor mode, as for its own file
;   calls) and plays it from the next VBL; _STOPMUSIC silences it;
;   _FADEOUT fades it out: MCDRV lowers the level 0.75 dB every speed
;   ticks of the song's timer, 64 steps, then the song is silent and stops.
;   Here the length is speed times the song's measured unit, the levels go
;   down 3 dB (one YM level) a quarter of the way.
; - music_tick (the VBL): the frame's registers into the YM as STDL's
;   player writes them: never registers 14 and 15 (TOS's floppy select),
;   the mixer keeping the port direction bits, interrupts masked between
;   selecting a register and writing it (only then: a border interrupt at
;   full height must not wait for the whole frame's writes).
; - An ST (no DMA sound) plays the effects on the YM too. While the music
;   plays, an effect has voice C (audio.s mixes it down to one voice) and
;   the noise period: the music keeps voices A and B, which stdlconv gives
;   a song's two most important parts (C has the third, and the drums).
;   Once the effect is over, the music's registers are all written again.

	xdef initialize_music
	xdef music_call
	xdef music_tick
	xdef music_release
	xdef amiga_music_loaded
	xdef amiga_mcdrv_probe
	xdef music_enabled
	xdef music_available
	xdef music_song_count
	xdef music_songs_played
	xdef music_load_failures
	xdef music_ticks
	xdef music_ticks_shared
	xdef music_playing

	xref machine_has_ste_hardware
	xref ym_playing

MCDRV_VERSION=$69 ; Reported by the probe (MCDRV 0.69 made the streams).

MCDRV_TRANSMDC=$01 ; a0 = the song data, d1 = its size.
MCDRV_PLAYMUSIC=$02
MCDRV_STOPMUSIC=$05
MCDRV_FADEOUT=$14 ; d1 = speed.

MAXIMUM_SONGS=16
SONG_NAME_SIZE=8 ; The base name (8.3), zero-padded.
SONG_DATA=0 ; The game's copy of the song (_TRANSMDC names it by this).
SONG_NAME=4
SONG_FADE_UNIT=SONG_NAME+SONG_NAME_SIZE ; 1/10000 s per unit of speed.
SONG_ENTRY_SIZE=SONG_FADE_UNIT+2
DEFAULT_FADE_UNIT=5400

STM_HEADER_SIZE=12
STM_TICK_RATE=50
REGISTERS=14 ; 0-13: the stream never sets 14 and 15.
ALL_REGISTERS=%1111111111111 ; 0-12: the envelope shape (13) restarts it.
VOLUME_REGISTERS=%11100000000
SHARED_REGISTERS=%1110001111 ; With an ST's effect: voices A and B, mixer.
PORT_BITS=%11000000 ; The mixer's I/O port directions.
SHARED_MIXER_BITS=%11100100 ; With an effect: those and voice C's.
FADE_LEVELS=16 ; The YM's 3 dB levels: 48 dB, MCDRV's 64 steps.

YM_SELECT=$ffff8800 ; (Reads the selected register.)
YM_DATA=$ffff8802
YM_MIXER=7
YM_MIXER_OFF=%111111

DTA_LENGTH=26
DTA_SIZE=44

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; At start (GEMDOS, before the sprite arena takes the rest of the memory):
; with music=true, a buffer the size of the largest stream in MUSIC_DAT.
; music_available is set if there is one. Preserves all registers.

initialize_music:
	movem.l	d0-d4/a0-a2,-(sp)

	sf		music_available
	move	#-1,loaded_song
	move	#-1,transferred_song
	tst.b	music_enabled
	beq		.done

	; The bits set in each byte (a frame's mask: the bytes that follow).

	lea		bit_counts,a0
	moveq	#0,d0

.count_byte:
	move	d0,d1
	moveq	#0,d2

.count_bit:
	lsr		#1,d1
	bcc		.no_bit

	addq.b	#1,d2

.no_bit:
	tst		d1
	bne		.count_bit

	move.b	d2,(a0)+
	addq	#1,d0
	cmp		#256,d0
	bne		.count_byte

	move	#47,-(sp) ; Fgetdta
	trap	#1
	addq.l	#2,sp
	move.l	d0,a2

	pea		music_dta
	move	#26,-(sp) ; Fsetdta
	trap	#1
	addq.l	#6,sp

	moveq	#0,d3 ; The largest.
	clr		-(sp)
	pea		music_pattern
	move	#78,-(sp) ; Fsfirst
	trap	#1
	addq.l	#8,sp

.file:
	tst.l	d0
	bmi		.listed

	move.l	music_dta+DTA_LENGTH,d0
	cmp.l	d3,d0
	bls		.not_larger

	move.l	d0,d3

.not_larger:
	move	#79,-(sp) ; Fsnext
	trap	#1
	addq.l	#2,sp

	bra		.file

.listed:
	move.l	a2,-(sp)
	move	#26,-(sp) ; Fsetdta: TOS's again.
	trap	#1
	addq.l	#6,sp

	cmp.l	#STM_HEADER_SIZE,d3
	bls		.done

	move.l	d3,-(sp)
	move	#72,-(sp) ; Malloc
	trap	#1
	addq.l	#6,sp
	tst.l	d0
	ble		.done

	move.l	d0,music_buffer
	move.l	d3,music_buffer_size
	st		music_available

.done:
	movem.l	(sp)+,d0-d4/a0-a2

	rts

; ------------------------------------------------------------------------------
;
; MCDRV probe (sz2.s): returns d0.l = the driver version if the music can
; play, else -1.

amiga_mcdrv_probe:
	moveq	#-1,d0
	tst.b	music_available
	beq		.done

	moveq	#MCDRV_VERSION,d0

.done:
	rts

; ------------------------------------------------------------------------------
;
; After the game loaded a song (INITIALIZE_SOUND): a0 = the song data, a1 =
; its file name from SZ2_BGM.CNF ("BGM_DAT\SZ2_S1.mdc"). Keeps the data
; address with the base name and its fade unit. Preserves all registers.

amiga_music_loaded:
	movem.l	d0-d2/a0-a3,-(sp)

	move	music_song_count,d0
	cmp		#MAXIMUM_SONGS,d0
	bcc		.done

	mulu	#SONG_ENTRY_SIZE,d0
	lea		music_songs,a2
	add.l	d0,a2
	move.l	a0,SONG_DATA(a2)

	; The base name: after the last '\', '/' or ':', up to the '.'.

	move.l	a1,a3

.scan:
	move.b	(a1)+,d0
	beq		.scanned

	cmp.b	#92,d0 ; Backslash.
	beq		.separator

	cmp.b	#'/',d0
	beq		.separator

	cmp.b	#':',d0
	bne		.scan

.separator:
	move.l	a1,a3

	bra		.scan

.scanned:
	lea		SONG_NAME(a2),a0
	moveq	#SONG_NAME_SIZE-1,d1

.clear:
	clr.b	(a0)+
	dbf		d1,.clear

	lea		SONG_NAME(a2),a0
	moveq	#SONG_NAME_SIZE-1,d1

.base:
	move.b	(a3)+,d0
	cmp.b	#'.',d0
	beq		.named

	cmp.b	#' ',d0
	bls		.named ; The end, a line end or a space.

	cmp.b	#'a',d0
	bcs		.upper

	cmp.b	#'z',d0
	bhi		.upper

	sub.b	#'a'-'A',d0

.upper:
	move.b	d0,(a0)+
	dbf		d1,.base

.named:
	; Its fade unit (the table's names are upper case, zero-padded).

	move	#DEFAULT_FADE_UNIT,SONG_FADE_UNIT(a2)
	lea		music_fades,a0

.fade_entry:
	tst.b	(a0)
	beq		.fade_known

	moveq	#SONG_NAME_SIZE/4-1,d1
	lea		SONG_NAME(a2),a1
	move.l	a0,a3

.fade_compare:
	cmpm.l	(a1)+,(a3)+
	bne		.fade_next

	dbf		d1,.fade_compare

	move	(a3),SONG_FADE_UNIT(a2)

	bra		.fade_known

.fade_next:
	lea		SONG_NAME_SIZE+2(a0),a0

	bra		.fade_entry

.fade_known:
	addq	#1,music_song_count

.done:
	movem.l	(sp)+,d0-d2/a0-a3

	rts

; ------------------------------------------------------------------------------
;
; MCDRV call (trap #4, supervisor mode): d0.l = function, d1.l, a0.
; Returns d0.l = 0. Preserves the other registers.

music_call:
	movem.l	d1-d4/a0-a2,-(sp)

	tst.b	music_available
	beq		.return

	cmp.l	#MCDRV_TRANSMDC,d0
	beq		.transfer

	cmp.l	#MCDRV_PLAYMUSIC,d0
	beq		.play

	cmp.l	#MCDRV_STOPMUSIC,d0
	beq		.stop

	cmp.l	#MCDRV_FADEOUT,d0
	beq		.fade

	bra		.return

.transfer:
	; The song to play next: the entry with this data.

	move	#-1,transferred_song
	lea		music_songs,a1
	moveq	#0,d2

.find:
	cmp		music_song_count,d2
	beq		.return

	cmp.l	SONG_DATA(a1),a0
	beq		.found

	lea		SONG_ENTRY_SIZE(a1),a1
	addq	#1,d2

	bra		.find

.found:
	move	d2,transferred_song

	bra		.return

.play:
	bsr		stop_music

	move	transferred_song,d2
	bmi		.return

	bsr		load_song
	bne		.return

	; From the first frame, at the next VBL.

	move.l	music_buffer,a0
	move	6(a0),music_frames
	move	8(a0),music_loop_frame
	lea		STM_HEADER_SIZE(a0),a0
	move.l	a0,music_position
	clr		music_frame
	sf		fade_active
	clr.b	fade_level
	addq.l	#1,music_songs_played
	st		music_playing

	bra		.return

.stop:
	bsr		stop_music

	bra		.return

.fade:
	tst.b	music_playing
	beq		.return

	tst.b	fade_active
	bne		.return ; (MCDRV keeps the first.)

	; The length in VBLs: speed * unit * 50 / 10000, 1 to 65535.

	and.l	#$ffff,d1
	bne		.speed_set

	moveq	#1,d1

.speed_set:
	move	music_playing_song,d2
	mulu	#SONG_ENTRY_SIZE,d2
	lea		music_songs,a1
	move	SONG_FADE_UNIT(a1,d2.l),d2
	mulu	d2,d1
	divu	#200,d1
	bvc		.length

	moveq	#-1,d1

.length:
	and.l	#$ffff,d1
	bne		.length_set

	moveq	#1,d1

.length_set:
	move.l	d1,fade_length
	clr.l	fade_elapsed
	st		fade_active

.return:
	moveq	#0,d0
	movem.l	(sp)+,d1-d4/a0-a2

	rts

; d2 = the song: its stream into the buffer, unless it is there already.
; The header and every frame's mask are checked, the loop's position found.
; Returns Z set if the stream is ready. GEMDOS. Uses d0-d4/a0-a2.

load_song:
	cmp		loaded_song,d2
	beq		.ready

	move	#-1,loaded_song
	move	d2,music_playing_song

	; "MUSIC_DAT\" + the base name + ".STM"

	lea		music_path,a0
	lea		music_directory,a1

.directory:
	move.b	(a1)+,(a0)+
	bne		.directory

	subq.l	#1,a0
	move	d2,d0
	mulu	#SONG_ENTRY_SIZE,d0
	lea		music_songs+SONG_NAME,a1
	add.l	d0,a1
	moveq	#SONG_NAME_SIZE-1,d0

.name:
	move.b	(a1)+,d1
	beq		.named

	move.b	d1,(a0)+
	dbf		d0,.name

.named:
	lea		music_extension,a1

.extension:
	move.b	(a1)+,(a0)+
	bne		.extension

	clr		-(sp)
	pea		music_path
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	move.l	d0,d3
	bmi		.failed

	move.l	music_buffer,-(sp)
	move.l	music_buffer_size,-(sp)
	move	d3,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp
	move.l	d0,d1

	move	d3,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	; d1.l = the size read: the header, then every frame within it.

	cmp.l	#STM_HEADER_SIZE,d1
	ble		.failed

	move.l	music_buffer,a0
	lea		(a0,d1.l),a2 ; The end.
	cmp.l	#'STM1',(a0)
	bne		.failed

	cmp		#STM_TICK_RATE,4(a0)
	bne		.failed

	move	6(a0),d0 ; Frames.
	beq		.failed

	cmp		8(a0),d0
	bls		.failed ; (The loop frame is one of them.)

	move	8(a0),d3
	lea		STM_HEADER_SIZE(a0),a0
	moveq	#0,d2 ; Frame.
	lea		bit_counts,a1

.frame:
	cmp		d3,d2
	bne		.not_loop

	move.l	a0,music_loop_position

.not_loop:
	; The mask's bits: its bytes follow.

	moveq	#0,d1
	move.b	(a0)+,d1
	and.b	#$3f,d1 ; (Registers 14 and 15 are never set.)
	move.b	(a1,d1.w),d1
	moveq	#0,d4
	move.b	(a0)+,d4
	add.b	(a1,d4.w),d1
	add		d1,a0

	cmp.l	a2,a0
	bhi		.failed

	addq	#1,d2
	cmp		d0,d2
	bne		.frame

	move	music_playing_song,loaded_song

.ready:
	moveq	#0,d0 ; Z set.

	rts

.failed:
	addq.l	#1,music_load_failures
	moveq	#-1,d0 ; Z clear.

	rts

; Stops the music: the voices silent and their tones and noises off (unless
; an ST's effect has the chip). Any context. Preserves all registers.

stop_music:
	sf		music_playing
	sf		fade_active
	sf		music_restore

music_silence:
	tst.b	machine_has_ste_hardware
	bne		silence_ym

	tst.b	ym_playing
	beq		silence_ym

	rts ; The effect's: it silences the YM when it ends.

; The voices silent, their tones and noises off. Preserves all registers.

silence_ym:
	movem.l	d0-d1,-(sp)
	move	sr,-(sp)

	moveq	#0,d0
	move	#$2700,sr
	move.b	#8,YM_SELECT.w
	move.b	d0,YM_DATA.w
	move	(sp),sr
	move	#$2700,sr
	move.b	#9,YM_SELECT.w
	move.b	d0,YM_DATA.w
	move	(sp),sr
	move	#$2700,sr
	move.b	#10,YM_SELECT.w
	move.b	d0,YM_DATA.w
	move	(sp),sr
	move	#$2700,sr
	move.b	#YM_MIXER,YM_SELECT.w
	move.b	YM_SELECT.w,d1
	and.b	#$c0,d1
	or.b	#YM_MIXER_OFF,d1
	move.b	d1,YM_DATA.w

	move	(sp)+,sr
	movem.l	(sp)+,d0-d1

	rts

; At the release (any context): the music stopped and the YM silent.
; Preserves all registers.

music_release:
	tst.b	music_available
	beq		.done

	sf		music_playing
	sf		fade_active
	bra		silence_ym

.done:
	rts

; ------------------------------------------------------------------------------
;
; Every VBL: the next frame's registers into the YM. Preserves all
; registers.

music_tick:
	tst.b	music_playing
	beq		.idle

	movem.l	d0-d5/a0-a1,-(sp)
	addq.l	#1,music_ticks

	; The frame's registers into the shadow, d3 = their mask.

	move.l	music_position,a0
	moveq	#0,d3
	move.b	(a0)+,d3
	lsl		#8,d3
	move.b	(a0)+,d3
	and		#$3fff,d3

	lea		music_shadow,a1
	move	d3,d1

.read:
	lsr		#1,d1
	bcc		.read_next

	move.b	(a0)+,(a1)

.read_next:
	addq.l	#1,a1
	tst		d1
	bne		.read

	addq	#1,music_frame
	move	music_frame,d0
	cmp		music_frames,d0
	bcs		.positioned

	move	music_loop_frame,music_frame
	move.l	music_loop_position,a0

.positioned:
	move.l	a0,music_position

	; The fade: the level it takes off the volumes now (a change writes
	; them all again), and the end.

	tst.b	fade_active
	beq		.faded

	addq.l	#1,fade_elapsed
	move.l	fade_elapsed,d0
	cmp.l	fade_length,d0
	bcc		.fade_over

	lsl.l	#4,d0 ; FADE_LEVELS
	divu	fade_length+2,d0
	cmp.b	fade_level,d0
	beq		.faded

	move.b	d0,fade_level
	or		#VOLUME_REGISTERS,d3

.faded:
	; An ST's effect has voice C: voices A and B, then everything once
	; it is over.

	move.b	#PORT_BITS,d4
	tst.b	machine_has_ste_hardware
	bne		.write

	tst.b	ym_playing
	beq		.chip_free

	addq.l	#1,music_ticks_shared
	st		music_restore
	and		#SHARED_REGISTERS,d3
	move.b	#SHARED_MIXER_BITS,d4

	bra		.write

.chip_free:
	tst.b	music_restore
	beq		.write

	sf		music_restore
	move	#ALL_REGISTERS,d3

.write:
	bsr		write_registers

	movem.l	(sp)+,d0-d5/a0-a1

.idle:
	rts

.fade_over:
	movem.l	(sp)+,d0-d5/a0-a1

	bra		stop_music

; d3 = mask: those registers from the shadow into the YM, the volumes
; lowered by the fade; d4 = the mixer's bits kept from the chip (the port
; directions, and voice C's while an ST's effect has it). Uses d0-d3/d5/a1.

write_registers:
	move	sr,d5
	lea		music_shadow,a1
	moveq	#0,d0 ; Register.

.register:
	lsr		#1,d3
	bcc		.next

	move.b	(a1,d0.w),d1
	move	#$2700,sr
	cmp.b	#YM_MIXER,d0
	bne		.not_mixer

	move.b	#YM_MIXER,YM_SELECT.w
	move.b	YM_SELECT.w,d2
	and.b	d4,d2
	not.b	d4
	and.b	d4,d1
	not.b	d4
	or.b	d2,d1

	bra		.put

.not_mixer:
	cmp.b	#8,d0
	bcs		.put

	cmp.b	#10,d0
	bhi		.put

	btst	#4,d1
	bne		.put ; The envelope's level: as it is.

	sub.b	fade_level,d1
	bcc		.put

	moveq	#0,d1

.put:
	move.b	d0,YM_SELECT.w
	move.b	d1,YM_DATA.w
	move	d5,sr

.next:
	addq	#1,d0
	tst		d3
	bne		.register

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

music_pattern:
	dc.b	'MUSIC_DAT\*.STM',0
music_directory:
	dc.b	'MUSIC_DAT\',0
music_extension:
	dc.b	'.STM',0

	even

; The songs' fade units (tools/music/make_st_music.py): name (8 bytes,
; zero-padded), unit (word, 1/10000 s per unit of _FADEOUT's speed); a
; zero name ends the table.

music_fades:
	include	"music_fades.i"
	dc.b	0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

music_buffer: ; The loaded song's stream.
	ds.l	1
music_buffer_size:
	ds.l	1
music_position: ; The next frame.
	ds.l	1
music_loop_position:
	ds.l	1
fade_length: ; VBLs.
	ds.l	1
fade_elapsed:
	ds.l	1
music_songs_played:
	ds.l	1
music_load_failures:
	ds.l	1
music_ticks: ; VBLs that played a frame.
	ds.l	1
music_ticks_shared: ; Of them, those an ST's effect had voice C in.
	ds.l	1
music_songs:
	ds.b	MAXIMUM_SONGS*SONG_ENTRY_SIZE
music_song_count:
	ds.w	1
transferred_song: ; _TRANSMDC's (-1: none).
	ds.w	1
loaded_song: ; The buffer's (-1: none).
	ds.w	1
music_playing_song:
	ds.w	1
music_frame:
	ds.w	1
music_frames:
	ds.w	1
music_loop_frame:
	ds.w	1
music_dta:
	ds.b	DTA_SIZE
music_path:
	ds.b	32
music_shadow: ; The stream's registers.
	ds.b	REGISTERS
bit_counts: ; Per byte value, its bits set.
	ds.b	256
music_enabled: ; SZ2.CFG's music (true by default).
	ds.b	1
music_available:
	ds.b	1
music_playing:
	ds.b	1
music_restore: ; All the registers into the YM at the next tick.
	ds.b	1
fade_active:
	ds.b	1
fade_level: ; Levels off the volumes (0-16).
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
