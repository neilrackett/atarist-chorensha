; LAUNCH.TOS: runs commands on a real ST for md-devops' Runner, which can
; only start programs from its own drive. The command line holds commands
; separated by ';':
;
;   run PATH [ARGUMENTS]   the drive and folder set from PATH, then Pexec
;   copy SOURCE TARGET     a file copied (from md-devops' drive to the hard
;                          disk, or back)
;   del PATH               a file deleted
;
; e.g. "copy D:\CRS\X.TOS C:\GAMES\CHORENSH\X.TOS;run C:\GAMES\CHORENSH\X.TOS".
; "@PATH" reads them from a file instead (one a line, or separated by ';'),
; past the command line's 127 characters.
; Each command's result goes to md-devops' debug stream as a line
; "[L] command ... result": a GEMDOS error (negative), the bytes copied or
; the program's exit code. The exit code is the last command's.
;
;   stcmd vasmm68k_mot /tmp/tests/st/hw/launch.s -quiet -Ftos -m68000 \
;       -o /tmp/binaries/st/LAUNCH.TOS

COPY_SIZE=32768
LINE_SIZE=1024

	section text

start:
	move.l	4(sp),a5 ; Basepage.
	lea		stack_top,sp

	move.l	12(a5),d0 ; Only the program kept: the rest for the programs run.
	add.l	20(a5),d0
	add.l	28(a5),d0
	add.l	#256,d0
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	clr		-(sp)
	move	#74,-(sp) ; Mshrink
	trap	#1
	lea		12(sp),sp

	; The command line, ended by a zero.

	lea		128(a5),a0
	moveq	#0,d0
	move.b	(a0)+,d0
	lea		line,a1
	bra		.next_character

.copy_character:
	move.b	(a0)+,d1
	beq		.line_copied
	cmp.b	#13,d1
	beq		.line_copied

	move.b	d1,(a1)+

.next_character:
	dbf		d0,.copy_character

.line_copied:
	clr.b	(a1)
	lea		line,a4
	moveq	#0,d7 ; The last result.

	cmp.b	#'@',(a4)
	bne		next_command

	; The commands from a file: its lines ended by ';'s.

	clr		-(sp) ; Read.
	pea		1(a4)
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	move.l	d0,d7
	bmi		.no_file

	move	d0,d5
	pea		line
	move.l	#LINE_SIZE-1,-(sp)
	move	d5,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp
	move.l	d0,d6
	move	d5,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

	moveq	#0,d7
	tst.l	d6
	bpl		.file_read

	moveq	#0,d6

.file_read:
	lea		line,a0
	clr.b	(a0,d6.l)

.line_ends:
	move.b	(a0)+,d0
	beq		next_command
	cmp.b	#13,d0
	beq		.line_end
	cmp.b	#10,d0
	bne		.line_ends

.line_end:
	move.b	#';',-1(a0)
	bra		.line_ends

.no_file:
	lea		no_file_text,a0
	bsr		emit_text
	lea		1(a4),a0
	bsr		emit_text
	bsr		emit_result
	bra		pterm

next_command:
	; This command: up to the next ';' (made a zero), the following one
	; after it.

	move.l	a4,a0

.find_end:
	move.b	(a0)+,d0
	beq		.last
	cmp.b	#';',d0
	bne		.find_end

	clr.b	-1(a0)
	move.l	a0,following
	bra		.parse

.last:
	clr.l	following

.parse:
	bsr		skip_spaces
	tst.b	(a4)
	beq		command_done ; (An empty command.)

	bsr		next_word
	move.l	a0,a3

	lea		run_word,a1
	bsr		same_words
	beq		run_command

	lea		copy_word,a1
	bsr		same_words
	beq		copy_command

	lea		del_word,a1
	bsr		same_words
	beq		del_command

	lea		unknown_text,a0
	bsr		emit_text
	move.l	a3,a0
	bsr		emit_text
	moveq	#-1,d7
	bsr		emit_result

command_done:
	move.l	following,a4
	move.l	a4,d0
	bne		next_command

pterm:
	move	d7,-(sp)
	move	#76,-(sp) ; Pterm
	trap	#1

; ------------------------------------------------------------------------------

; run PATH [ARGUMENTS]

run_command:
	bsr		skip_spaces
	bsr		next_word
	move.l	a0,a3 ; The path.

	; The arguments: the rest of the command, as a Pexec command tail.

	bsr		skip_spaces
	lea		tail+1,a1
	moveq	#0,d1

.copy_argument:
	move.b	(a4)+,d0
	beq		.arguments_copied

	move.b	d0,(a1)+
	addq	#1,d1
	bra		.copy_argument

.arguments_copied:
	clr.b	(a1)
	move.b	d1,tail

	; The drive (if the path names one) and the folder.

	cmp.b	#':',1(a3)
	bne		.folder

	moveq	#$df-256,d0
	and.b	(a3),d0
	sub.b	#'A',d0
	ext		d0
	move	d0,-(sp)
	move	#14,-(sp) ; Dsetdrv
	trap	#1
	addq.l	#4,sp

.folder:
	move.l	a3,a0
	cmp.b	#':',1(a0)
	bne		.copy_folder

	addq.l	#2,a0

.copy_folder:
	lea		folder,a1
	move.l	a1,a2 ; Just past the last '\'.

.folder_character:
	move.b	(a0)+,d0
	move.b	d0,(a1)+
	beq		.folder_copied
	cmp.b	#'\',d0
	bne		.folder_character

	move.l	a1,a2
	bra		.folder_character

.folder_copied:
	lea		folder,a1
	cmp.l	a1,a2
	beq		.pexec ; (No folder in the path.)

	clr.b	-(a2) ; The last '\' dropped,
	cmp.l	a1,a2
	bne		.set_folder

	move.b	#'\',(a2) ; but the root's kept.
	clr.b	1(a2)

.set_folder:
	pea		folder
	move	#59,-(sp) ; Dsetpath
	trap	#1
	addq.l	#6,sp

.pexec:
	lea		run_text,a0
	bsr		emit_text
	move.l	a3,a0
	bsr		emit_text

	clr.l	-(sp) ; The environment: the launcher's.
	pea		tail
	pea		(a3)
	clr		-(sp) ; Load and go.
	move	#75,-(sp) ; Pexec
	trap	#1
	lea		16(sp),sp
	move.l	d0,d7
	bsr		emit_result
	bra		command_done

; copy SOURCE TARGET

copy_command:
	bsr		skip_spaces
	bsr		next_word
	move.l	a0,a3 ; The source.
	bsr		skip_spaces
	bsr		next_word
	move.l	a0,a2 ; The target.

	lea		copy_text,a0
	bsr		emit_text
	move.l	a3,a0
	bsr		emit_text
	lea		space_text,a0
	bsr		emit_text
	move.l	a2,a0
	bsr		emit_text

	clr		-(sp) ; Read.
	pea		(a3)
	move	#61,-(sp) ; Fopen
	trap	#1
	addq.l	#8,sp
	move.l	d0,d7
	bmi		.result

	move	d0,d5 ; The source's handle.
	clr		-(sp)
	pea		(a2)
	move	#60,-(sp) ; Fcreate
	trap	#1
	addq.l	#8,sp
	move.l	d0,d7
	bmi		.close_source

	move	d0,d4 ; The target's handle.
	moveq	#0,d6 ; Bytes copied.

.copy_block:
	pea		copy_buffer
	move.l	#COPY_SIZE,-(sp)
	move	d5,-(sp)
	move	#63,-(sp) ; Fread
	trap	#1
	lea		12(sp),sp
	move.l	d0,d7
	ble		.copied

	move.l	d0,d3
	pea		copy_buffer
	move.l	d3,-(sp)
	move	d4,-(sp)
	move	#64,-(sp) ; Fwrite
	trap	#1
	lea		12(sp),sp
	move.l	d0,d7
	bmi		.copied

	add.l	d0,d6
	cmp.l	d3,d0
	beq		.copy_block

	moveq	#-1,d7 ; (A short write: the disk full.)

.copied:
	tst.l	d7
	bmi		.close_target

	move.l	d6,d7

.close_target:
	move	d4,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

.close_source:
	move	d5,-(sp)
	move	#62,-(sp) ; Fclose
	trap	#1
	addq.l	#4,sp

.result:
	bsr		emit_result
	bra		command_done

; del PATH

del_command:
	bsr		skip_spaces
	bsr		next_word
	move.l	a0,a3

	lea		del_text,a0
	bsr		emit_text
	move.l	a3,a0
	bsr		emit_text

	pea		(a3)
	move	#65,-(sp) ; Fdelete
	trap	#1
	addq.l	#6,sp
	move.l	d0,d7
	bsr		emit_result
	bra		command_done

; ------------------------------------------------------------------------------

; a4 = the parse position: past spaces.

skip_spaces:
	cmp.b	#' ',(a4)
	bne		.done

	addq.l	#1,a4
	bra		skip_spaces

.done:
	rts

; The word at a4 (up to a space or the command's end) ended by a zero in
; place: a0 = the word, a4 = past it (or at the end).

next_word:
	move.l	a4,a0

.character:
	move.b	(a4),d0
	beq		.done
	addq.l	#1,a4
	cmp.b	#' ',d0
	bne		.character

	clr.b	-1(a4)

.done:
	rts

; Z set if the words at a0 and a1 are the same (a0's in any case).

same_words:
	movem.l	a0-a1,-(sp)

.character:
	move.b	(a0)+,d0
	beq		.end

	or.b	#$20,d0
	cmp.b	(a1)+,d0
	beq		.character

	bra		.done

.end:
	tst.b	(a1)

.done:
	movem.l	(sp)+,a0-a1
	rts

; The debug stream: a read at $FBFF00 + c for each byte c.

emit_text:
	movem.l	d0/a0-a1,-(sp)
	lea		$fbff00,a1
	moveq	#0,d0

.character:
	move.b	(a0)+,d0
	beq		.done

	tst.b	(a1,d0.w)
	bra		.character

.done:
	movem.l	(sp)+,d0/a0-a1
	rts

; " = " d7 in hex, then the line's end.

emit_result:
	movem.l	d0-d2/a0,-(sp)
	lea		result_text,a0
	bsr		emit_text
	lea		hex_text,a0
	move.l	d7,d0
	moveq	#8-1,d2

.digit:
	rol.l	#4,d0
	moveq	#15,d1
	and		d0,d1
	move.b	.digits(pc,d1.w),(a0)+
	dbf		d2,.digit

	clr.b	(a0)
	lea		hex_text,a0
	bsr		emit_text
	lea		line_end_text,a0
	bsr		emit_text
	movem.l	(sp)+,d0-d2/a0
	rts

.digits:
	dc.b	'0123456789ABCDEF'

; ------------------------------------------------------------------------------

	section data

run_word:
	dc.b	'run',0
copy_word:
	dc.b	'copy',0
del_word:
	dc.b	'del',0
run_text:
	dc.b	'[L] run ',0
copy_text:
	dc.b	'[L] copy ',0
del_text:
	dc.b	'[L] del ',0
unknown_text:
	dc.b	'[L] unknown ',0
no_file_text:
	dc.b	'[L] no commands in ',0
space_text:
	dc.b	' ',0
result_text:
	dc.b	' = $',0
line_end_text:
	dc.b	13,10,0
	even

	section bss

following: ; The next command, 0 if none.
	ds.l	1
hex_text:
	ds.b	9
	even
line:
	ds.b	LINE_SIZE
tail:
	ds.b	130
folder:
	ds.b	130
	even
copy_buffer:
	ds.b	COPY_SIZE
	ds.l	1024
stack_top:
