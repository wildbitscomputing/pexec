;
; Glyphs, custom glyphs to make pexec pretty
;
;------------------------------------------------------------------------------

	.virtual 1

G_SPACE .fill 1

GC .fill 1
GE .fill 1
GO .fill 1
GP .fill 1
GR .fill 1
GX .fill 1

GRUN0 .fill 1
GRUN1 .fill 1
GRUN2 .fill 1
GRUN3 .fill 1
	.endv

;------------------------------------------------------------------------------
glyph_puts

_pString = term_temp2

	sta _pString
	stx _pString+1

_lp	lda (_pString)
	beq _done
	jsr glyph_draw
	inc _pString
	bne _lp
	inc _pString+1
	bra _lp
_done
	rts

;------------------------------------------------------------------------------

glyph_draw
	ldx term_ptr
	phx
	ldx term_ptr+1
	phx

	ldx term_x
	phx
	ldx term_y
	phx

	asl
	asl
	asl
	tax

	; c = 0
	ldy #7

_lp lda glyphs-8,x ;-8 because 0 is terminator
	phy
	phx
	jsr _emit_line
	plx
	ply

	; c=1
	lda term_ptr
	adc #80-1
	sta term_ptr
	lda term_ptr+1
	adc #0
	sta term_ptr+1

	inx
	dey
	bpl _lp

	plx
	stx term_y
	ply
	sty term_x

	pla
	sta term_ptr+1

	pla
	sta term_ptr

	lda term_ptr
	adc #9 			; c=0
	sta term_ptr
	lda term_ptr+1
	adc #0
	sta term_ptr+1

	rts

_emit_line
	ldy #0
_lp2
	asl
	tax
	lda #' '    ; space
	bcc _write

	lda #$B5    ; square

_write
	sta (term_ptr),y
	iny
	cpy #8
	txa
	bcc _lp2

	rts

;------------------------------------------------------------------------------

glyphs

space_glyph			; useful for "erase"
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000


c_glyph
	.byte %01111100
	.byte %11000110
	.byte %11000000
	.byte %11000000
	.byte %11000000
	.byte %11000110
	.byte %01111100
	.byte %00000000


e_glyph
	.byte %11111110
	.byte %11000000
	.byte %11000000
	.byte %11111000
	.byte %11000000
	.byte %11000000
	.byte %11111110
	.byte %00000000

o_glyph
	.byte %01111100
	.byte %11000110
	.byte %11000110
	.byte %11000110
	.byte %11000110
	.byte %11000110
	.byte %01111100
	.byte %00000000


p_glyph
	.byte %11111100
	.byte %11000110
	.byte %11000110
	.byte %11111100
	.byte %11000000
	.byte %11000000
	.byte %11000000
	.byte %00000000

r_glyph
	.byte %11111100
	.byte %11000110
	.byte %11000110
	.byte %11111100
	.byte %11011000
	.byte %11001100
	.byte %11000110
	.byte %00000000


x_glyph
	.byte %11000110
	.byte %01101100
	.byte %00111000
	.byte %00010000
	.byte %00111000
	.byte %01101100
	.byte %11000110
	.byte %00000000


run0
	.byte %00011000
	.byte %00011000
	.byte %00110000
	.byte %00110000
	.byte %00111000
	.byte %01110000
	.byte %00110000
	.byte %00100000

run1
	.byte %00011000
	.byte %00011000
	.byte %00110000
	.byte %00110000
	.byte %00110000
	.byte %00110000
	.byte %00110000
	.byte %00100000

run2
	.byte %00001100
	.byte %00001100
	.byte %00011000
	.byte %00111000
	.byte %00111100
	.byte %00011100
	.byte %00100100
	.byte %00100000

run3
	.byte %00001100
	.byte %00001100
	.byte %00111000
	.byte %01011110
	.byte %00011000
	.byte %00100100
	.byte %01000100
	.byte %00000100

;------------------------------------------------------------------------------
