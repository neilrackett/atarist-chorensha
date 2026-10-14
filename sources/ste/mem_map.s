
; X68000 I/O regions the game core touches, as RAM shadow buffers (as in the
; Falcon port's mem_map.s), plus GVRAM: as on the Amiga, the game's own
; INITIALIZE_SPRITES_AND_GRAPHICS builds both 256-colour background pages
; here (2 pages * $80000). Only the left 256 pixels (bytes 0-511) of each
; 1024-byte line are written by the game; the renderer keeps its converted
; layers in the right halves of page 0 (see graphics.s).

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
L_00E00000:   ; TEXT PLANE 1
	ds.b    $20000
L_00E20000:   ; TEXT PLANE 2
	ds.b    $20000
L_00E40000:   ; TEXT PLANE 3
	ds.b    $20000
L_00E60000:   ; TEXT PLANE 4
	ds.b    $20000
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
