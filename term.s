;
; Terminal Module for Jr
;

TextBuffer = $C000

; Terminal Variables
	.virtual $C0
term_width  .fill 1
term_height .fill 1
term_x      .fill 1
term_y      .fill 1
term_ptr    .fill 2
term_temp0  .fill 4
term_temp1  .fill 4
term_temp2  .fill 2
	.endv

;TermCOUT       - COUT, prints character in A, right now only special character code #13 is supported <cr>
;TermPUTS       - AX is a pointer to a 0 terminated string, this function will send the characters into COUT
;TermPrintAN    - print nybble value in A
;TermPrintAH    - print value in A, as HEX
;TermPrintAI    - print value in A, as DEC
;TermPrintAXH   - print value in AX, as HEX  (it will end up XA, because high, then low)
;TermPrintAXI   - print value in AX, as DEC
;TermPrintAXYH  - print values in AXY, as HEX
;TermSetXY      - cursor position X in X, Y in Y

;------------------------------------------------------------------------------
TermInit
		jsr TermClearTextBuffer

		stz term_x
		stz term_y
		lda #80
		sta term_width
		lda #60
		sta term_height

		lda #<TextBuffer
		sta term_ptr
		lda #>TextBuffer
		sta term_ptr+1

		rts

;------------------------------------------------------------------------------
; ldx #XX
; ldy #YY
TermSetXY
		stx term_x
		sty term_y

		txa
		clc
		adc Term80Table_lo,y
		sta term_ptr
		lda #0
		adc Term80Table_hi,y
		sta term_ptr+1
		rts

;------------------------------------------------------------------------------
TermCR  lda #13
;------------------------------------------------------------------------------
TermCOUT
		cmp #13
		beq _cr

		sta (term_ptr)
		inc term_ptr
		bne _skiphi
		inc term_ptr+1
_skiphi
		lda term_x
		inc a
		cmp term_width
		bcc _x
_incy
		lda term_y
		inc a
		cmp term_height
		bcs _scroll_savexy
_y      sta term_y

		lda #0
_x		sta term_x
		rts

_cr
		phy
		phx
		lda term_y
		inc a
		cmp term_height
		bcs _scroll
		tay
		ldx #0
		jsr TermSetXY
		plx
		ply
		rts
_scroll_savexy
		phy
		phx
_scroll
_pSrc = term_temp0
_pDst = term_temp0+2

		stz _pDst
		lda #80
		sta _pSrc
		lda #>TextBuffer
		sta _pDst+1
		sta _pSrc+1

		ldx term_height
		dex
_lp
		ldy #0
_inlp
		lda (_pSrc),y
		sta (_pDst),y
		iny
		cpy term_width
		bcc _inlp

		clc
		lda _pSrc
		sta _pDst
		adc term_width
		sta _pSrc
		lda _pSrc+1
		sta _pDst+1
		adc #0
		sta _pSrc+1

		dex
		bne _lp

; clear line
		ldy #0
		lda #' '
_lclrp  sta (_pDst),y
		iny
		cpy term_width
		bcc _lclrp

		ldx #0
		ldy term_height
		dey
		jsr TermSetXY
		plx
		ply
		rts

;------------------------------------------------------------------------------
; Fill Text Buffer with spaces

TermClearTextBuffer
		stz	io_ctrl
		stz	$D010			; disable cursor

		lda #3
		sta io_ctrl         ; swap in the color memory
		;lda $C000			; get current color attribute
		lda #$F2	; white on blue
		jsr	_clear

; We need a rainbow up top

		ldx #79
_cloop  lda #$12  			; red
		sta $C000+80*1,x
		sta $C000+80*51,x
		lda #$92			; orange
		sta $C000+80*2,x
		sta $C000+80*52,x
		lda #$D2			; yello
		sta $C000+80*3,x
		sta $C000+80*53,x
		lda #$C2			; green
		sta $C000+80*4,x
		sta $C000+80*54,x
		lda #$72			; bright blue
		sta $C000+80*5,x
		sta $C000+80*55,x
		lda #$32		   	; purple
		sta $C000+80*6,x
		sta $C000+80*56,x
		lda #$B2		  	; pink
		sta $C000+80*7,x
		sta $C000+80*57,x
		lda #$A2		  	; grey
		sta $C000+80*8,x
		sta $C000+80*58,x
		dex
		bpl _cloop

		lda #2
		sta io_ctrl         ; swap in the text memory
		lda #' '

_clear
		ldx #0

_lp
		sta $C000,x
		sta $C100,x
		sta $C200,x
		sta $C300,x
		sta $C400,x
		sta $C500,x
		sta $C600,x
		sta $C700,x
		sta $C800,x
		sta $C900,x
		sta $CA00,x
		sta $CB00,x
		sta $CC00,x
		sta $CD00,x
		sta $CE00,x
		sta $CF00,x
		sta $D000,x
		sta $D100,x
		sta $D200,x
		dex
		bne _lp

		rts

;------------------------------------------------------------------------------

Term80Table_lo
	.for _n := 0, _n < 60, _n += 1
	.byte <(TextBuffer + _n * 80)
	.next

Term80Table_hi
	.for _n := 0, _n < 60, _n += 1
	.byte >(TextBuffer + _n * 80)
	.next

;------------------------------------------------------------------------------
TermPUTS
_pString = term_temp2
		sta _pString
		stx _pString+1

_lp		lda (_pString)
		beq _done
		jsr TermCOUT
		inc _pString
		bne _lp
		inc _pString+1
		bra _lp
_done
		rts

;------------------------------------------------------------------------------
;TermPrintAXH   - print value in AX, as HEX  (it will end up XA, because high, then low)
TermPrintAXYH
		pha
		phx
		tya
		jsr TermPrintAH
		pla
		jsr TermPrintAH
		pla
;		bra TermPrintAH

;------------------------------------------------------------------------------
;TermPrintAH    - print value in A, as HEX
TermPrintAH
		pha
		lsr
		lsr
		lsr
		lsr
		tax
		lda Term_chars,x
		jsr TermCOUT
		pla
		and #$0F
		tax
		lda Term_chars,x
		jmp TermCOUT

Term_chars  .text "0123456789ABCDEF"

;TermPrintAN    - print nybble value in A
TermPrintAN
		and #$0F
		tax
		lda Term_chars,x
		jmp TermCOUT

;------------------------------------------------------------------------------
;TermPrintAXH   - print value in AX, as HEX  (it will end up XA, because high, then low)
TermPrintAXH
		pha
		txa
		jsr TermPrintAH
		pla
		bra TermPrintAH

;------------------------------------------------------------------------------
;TermPrintAI    - print value in A, as DEC
TermPrintAI
_bcd = term_temp1
		jsr BINBCD8
		lda _bcd+1
		and #$0F
		beq _skip
		jsr TermPrintAN
		lda _bcd
		bra TermPrintAH
_skip
		lda _bcd
		and #$F0
		beq _single_digit
		lda _bcd
		bra TermPrintAH

_single_digit
		lda _bcd
		bra TermPrintAN
		rts
;------------------------------------------------------------------------------
;TermPrintAXI   - print value in AX, as DEC
TermPrintAXI
_bcd = term_temp1
		jsr BINBCD16

		lda _bcd+2
		and #$0F
		beq _skip1

		; 5 digits
		jsr TermPrintAN
_digit4
		lda _bcd
		ldx _bcd+1
		bra TermPrintAXH
_skip1
		lda _bcd+1
		beq _skip2

		and #$F0
		bne _digit4

		lda _bcd+1
		jsr TermPrintAN  ; just the nybble
		lda _bcd
		bra TermPrintAH

_skip2
		lda _bcd
		and #$F0
		beq _single_digit
		lda _bcd
		jmp TermPrintAH

_single_digit
		lda _bcd
		bra TermPrintAN
		rts
;------------------------------------------------------------------------------
; Andrew Jacobs, 28-Feb-2004
BINBCD8
_bin = term_temp0
_bcd = term_temp1
		sta _bin
		sed		; Switch to decimal mode
		stz _bcd+0
		stz _bcd+1
		ldx #8		; The number of source bits

_CNVBIT	asl _bin	; Shift out one bit
		lda _bcd+0	; And add into result
		adc _bcd+0
		sta _bcd+0
		lda _bcd+1	; propagating any carry
		adc _bcd+1
		sta _bcd+1
		dex		; And repeat for next bit
		bne _CNVBIT
		cld		; Back to binary
		rts

; Convert an 16 bit binary value to BCD
;
; This function converts a 16 bit binary value into a 24 bit BCD. It
; works by transferring one bit a time from the source and adding it
; into a BCD value that is being doubled on each iteration. As all the
; arithmetic is being done in BCD the result is a binary to decimal
; conversion. All conversions take 915 clock cycles.
;
; See BINBCD8 for more details of its operation.
;
; Andrew Jacobs, 28-Feb-2004

BINBCD16
_bin = term_temp0
_bcd = term_temp1
		sta _bin
		stx _bin+1

		sed		; Switch to decimal mode
		stz _bcd+0
		stz _bcd+1
		stz _bcd+2
		ldx #16		; The number of source bits

_CNVBIT	asl _bin+0	; Shift out one bit
		rol _bin+1
		lda _bcd+0	; And add into result
		adc _bcd+0
		sta _bcd+0
		lda _bcd+1	; propagating any carry
		adc _bcd+1
		sta _bcd+1
		lda _bcd+2	; ... thru whole result
		adc _bcd+2
		sta _bcd+2
		dex		; And repeat for next bit
		bne _CNVBIT
		cld		; Back to binary

		rts
