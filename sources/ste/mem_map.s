
; X68000 I/O regions the game core touches, as RAM shadow buffers (as in the
; Falcon port's mem_map.s), plus GVRAM: the game's own INITIALIZE_SPRITES_
; AND_GRAPHICS builds both 256-colour background pages here once (2 pages *
; $80000); background.s then converts them and composes its 1 MB table of
; background lines over them.
;
; No text planes: the game's text drawing is redirected to a character map
; (text.s); L_00E00000 and L_00E20000 only label its unused original code.

	xdef L_00C00000,L_00E00000,L_00E20000,L_00E80000,L_00E82000,L_00E88000
	xdef L_00E8E000,L_00EB0000,L_00EB8000

	xdef L_00000118,L_00000138

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

dummy_interrupt_handler:
	rte

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

	even

L_00000118:   ; MFP V-DISP vector (game VBL handler).
	dc.l	dummy_interrupt_handler

L_00000138:   ; MFP CRTC IRQ vector (game raster handler).
	dc.l	dummy_interrupt_handler

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

	align 4

L_00C00000:   ; GVRAM, pages 0 and 1 (512 * 512 * 2 bytes each).
	ds.b    $100000
L_00E00000:   ; TEXT PLANES (not used)
L_00E20000:
	ds.l    1
L_00E80000:   ; CRTC
	ds.b    $2000
L_00E82000:   ; VIDEO CONTROLLER
	ds.b    $2000
L_00E88000:   ; MFP
	ds.b    $2000
L_00E8E000:   ; SYSTEM PORT
	ds.b    $2000
L_00EB0000:   ; SPRITE REGISTERS
	ds.b    $8000
L_00EB8000:   ; SPRITE VRAM
	ds.b    $8000

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
