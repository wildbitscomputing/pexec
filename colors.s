;------------------------------------------------------------------------------
;
; Colors - Predefined Color Tables, and helper functions for dealing with color
;
;------------------------------------------------------------------------------

VKY_BKG_COL_B = $D00D           ; Vicky Graphics Background Color Blue Component
VKY_BRDR_COL_B = $D005          ; Vicky Border Color -- Blue

VKY_TXT_FGLUT = $D800           ; Text foreground CLUT
VKY_TXT_BGLUT = $D840           ; Text background CLUT

initColors
		php
		sei
		lda io_ctrl
		pha

		; Copy the colors up into the text luts

		stz io_ctrl

		ldx #16*4-1       ; 16 colors
_lp1
		lda gs_colors,x
		sta VKY_TXT_FGLUT,x
		sta VKY_TXT_BGLUT,x
		dex
		bpl _lp1

		; Set the background color, and the border color

		ldx #2
_lp2
		lda gs_colors+4*2,x ; Dark Blue index 2
		sta VKY_BKG_COL_B,x
		sta VKY_BRDR_COL_B,x
		dex
		bpl _lp2

		pla
		sta io_ctrl
		plp
		rts
;------------------------------------------------------------------------------
gs_colors
	.dword $ff000000  ;0 Black
	.dword $ffdd0033  ;1 Deep Red
	.dword $ff000099  ;2 Dark Blue
	.dword $ffdd22dd  ;3 Purple
	.dword $ff007722  ;4 Dark Green
	.dword $ff555555  ;5 Dark Gray
	.dword $ff2222ff  ;6 Medium Blue
	.dword $ff66aaff  ;7 Light Blue
	.dword $ff885500  ;8 Brown
	.dword $ffff6600  ;9 Orange
	.dword $ffaaaaaa  ;A Light Gray
	.dword $ffff9988  ;B Pink
	.dword $ff00dd00  ;C Light Green
	.dword $ffffff00  ;D Yellow
	.dword $ff55ff99  ;E Aquamarine
	.dword $ffffffff  ;F White

;------------------------------------------------------------------------------
;
; Micro Kernel uses these colors, but Super BASIC does not, and the
; DOS shell does not, so I'm not going to either
;
			.if 0
_palette
            .dword  $ff000000
			.dword  $ffffffff
			.dword  $ff880000
			.dword  $ffaaffee
			.dword  $ffcc44cc
			.dword  $ff00cc55
			.dword  $ff0000aa
			.dword  $ffdddd77
			.dword  $ffdd8855
			.dword  $ff664400
			.dword  $ffff7777
			.dword  $ff333333
			.dword  $ff777777
			.dword  $ffaaff66
			.dword  $ff0088ff
			.dword  $ffbbbbbb
			.endif

;------------------------------------------------------------------------------
