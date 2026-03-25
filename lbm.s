;
; 65c02 Foenix LBM file format parser utils
; for F256 Jr
;

; error codes
		.virtual $0
lbm_no_error         .fill 1   ; 0 = no error
lbm_error_notlbm     .fill 1   ; 1 = not an LBM file
lbm_error_notpbm     .fill 1   ; 2 = not an LBM with 8 bit packed pixels
lbm_error_noclut     .fill 1   ; 3 = There's no CLUT in this file
lbm_error_nopixels   .fill 1   ; 4 = There are no PIXL in this file
		.endv


		.virtual $F0
lbm_ChunkLength
lbm_FileLength
lbm_pChunk
lbm_temp0      .fill 4

lbm_pTag
lbm_temp1      .fill 2

lbm_FileStart  .fill 3
lbm_Width      .fill 2
lbm_Height     .fill 2
lbm_EOF        .fill 3
		.endv

;------------------------------------------------------------------------------
;
; This works with the mmu utils
; Addresses are in System Memory BUS space
;
; set_read_address  - the source address for the image.lbm
; set_write_address - the destination address of the clut data
;
;  This will massage the LBM clut data into something that works on Jr
;
; if c=0, then operation success
; if c=1, then operation fail, error code in A
;
lbm_decompress_clut
		jsr lbm_init
		bcc _good
		rts				; error, error code in A
_good
		lda #<CHNK_CMAP
		ldx #>CHNK_CMAP
		jsr lbm_FindChunk

		sta lbm_pChunk
		stx lbm_pChunk+1
		sty lbm_pChunk+2

		; Check for nullptr
		ora lbm_pChunk+1
		ora lbm_pChunk+2
		bne _got_pal

		sec
		lda #lbm_error_noclut
		rts

_got_pal

		ldx #0
_lp		jsr readbyte  ; r
		sta lbm_temp0
		jsr readbyte  ; g
		sta lbm_temp0+1
		jsr readbyte  ; b
		sta lbm_temp0+2

		jsr writebyte  ; b
		lda lbm_temp0+1
		jsr writebyte  ; g
		lda lbm_temp0
		jsr writebyte  ; r
		lda #$FF
		jsr writebyte  ; a
		dex
		bne _lp

		clc
		lda #lbm_no_error
		rts

;------------------------------------------------------------------------------
;
; This works with the mmu utils
; Addresses are in System Memory BUS space
;
; set_read_address  - the source address for the image.lbm
; set_write_address - the destination address of the pixel data
;
; if c=0, then operation success
; if c=1, then operation fail, error code in A
;
lbm_decompress_pixels
		jsr lbm_init
		bcc _good
		rts				; error, error code in A
_good
		lda #<CHNK_BODY
		ldx #>CHNK_BODY
		jsr lbm_FindChunk

		sta lbm_pChunk
		stx lbm_pChunk+1
		sty lbm_pChunk+2

		; Check for nullptr
		ora lbm_pChunk+1
		ora lbm_pChunk+2
		bne _got_body

		sec
		lda #lbm_error_nopixels
		rts

_got_body

_width = lbm_temp0
_height = lbm_temp0+2

		stz _height
		stz _height+1

_height_loop
		stz _width
		stz _width+1

_width_loop

		jsr readbyte
		tax
		bpl _copy
		; rle
		eor #$FF
		inc a
		tax
		jsr readbyte
_rle	jsr writebyte
		inc _width
		bne _nx
		inc _width+1
_nx
		dex
		bpl _rle

_wid_height
		lda _width+1
		cmp lbm_Width+1
		bne _width_loop
		lda _width
		cmp lbm_Width
		bne _width_loop

		inc _height
		bne _nh
		inc _height+1
_nh

		lda _height+1
		cmp lbm_Height+1
		bne _height_loop
		lda _height
		cmp lbm_Height
		bne _height_loop

		clc
		lda #0
		rts

_copy
		jsr readbyte
		jsr writebyte

		inc _width
		bne _nx2
		inc _width+1
_nx2
		dex
		bpl _copy

		bra _wid_height

;------------------------------------------------------------------------------


CHNK_FORM .text "FORM"
CHNK_PBM  .text "PBM "
CHNK_BMHD .text "BMHD"
CHNK_CMAP .text "CMAP"
CHNK_BODY .text "BODY"

;------------------------------------------------------------------------------

;
; This works with the mmu utils
; Addresses are in System Memory BUS space
;
; set_read_address  - the source address for the image.lbm
; set_write_address - the destination address of the pixel data
;
lbm_init
		lda #<CHNK_FORM
		ldx #>CHNK_FORM
		jsr lbm_CheckTag
		bcc _good
		lda #lbm_error_notlbm
		rts
_good
		jsr lbm_chnklen

		jsr get_read_address

		; Need to set EOF, so FindChunk knows where to stop
		clc
		adc lbm_ChunkLength
		sta lbm_EOF+0
		txa
		adc lbm_ChunkLength+1
		sta lbm_EOF+1
		tya
		adc lbm_ChunkLength+2
		sta lbm_EOF+2

		lda #<CHNK_PBM
		ldx #>CHNK_PBM
		jsr lbm_CheckTag
		bcc _pbm
_not_pbm
		lda #lbm_error_notpbm
		rts
_pbm
		lda #<CHNK_BMHD
		ldx #>CHNK_BMHD
		jsr lbm_CheckTag
		bcs _not_pbm

		jsr lbm_chnklen
		jsr lbm_nextchunk_address ; pChunk will hold next chunk address


		; Width
		jsr readbyte
		sta lbm_Width+1
		jsr readbyte
		sta lbm_Width

		;Height
		jsr readbyte
		sta lbm_Height+1
		jsr readbyte
		sta lbm_Height


		lda lbm_pChunk
		ldx lbm_pChunk+1
		ldy lbm_pChunk+2

		jsr set_read_address

		clc
		rts
;------------------------------------------------------------------------------
;
; AX = address of tag to check
;
; c=0 match
; c=1 does not match
;
lbm_CheckTag
		sta lbm_pTag
		stx lbm_pTag+1
lbm_CheckTag2
		jsr readbyte
		sta lbm_temp0

;		jsr TermCOUT

		jsr readbyte
		sta lbm_temp0+1

;		jsr TermCOUT

		jsr readbyte
		sta lbm_temp0+2

;		jsr TermCOUT

		jsr readbyte
		sta lbm_temp0+3

;		jsr TermCOUT
;		jsr TermCR

		ldy #3
_lp		lda (lbm_pTag),y
		cmp lbm_temp0,y
		bne _error
		dey
		bpl _lp
		clc
		rts

_error
		sec
		rts

;------------------------------------------------------------------------------
lbm_chnklen
		jsr readbyte
		sta lbm_ChunkLength+3
		jsr readbyte
		sta lbm_ChunkLength+2
		jsr readbyte
		sta lbm_ChunkLength+1
		jsr readbyte
		sta lbm_ChunkLength+0

		bit #1
		beq _even

		; EA I hate you
		inc lbm_ChunkLength+0
		bne _done
		inc lbm_ChunkLength+1
		bne _done
		inc lbm_ChunkLength+2
_even
_done
		rts

;------------------------------------------------------------------------------
lbm_nextchunk_address
		jsr get_read_address
		clc
		adc lbm_pChunk
		sta lbm_pChunk
		txa
		adc lbm_pChunk+1
		sta lbm_pChunk+1
		tya
		adc lbm_pChunk+2
		sta lbm_pChunk+2

;		jsr TermPrintAH
;		lda lbm_pChunk+0
;		ldx lbm_pChunk+1
;		jsr TermPrintAXH
;		jsr TermCR

		rts
;------------------------------------------------------------------------------
lbm_FindChunk
		sta lbm_pTag
		stx lbm_pTag+1

_loop
		jsr get_read_address

		cpy lbm_EOF+2
		bcc _continue
		bne _nullptr
        cpx lbm_EOF+1
		bcc _continue
		bne _nullptr
        cmp lbm_EOF
		bcs _nullptr
_continue
		jsr lbm_CheckTag2
		php
		jsr lbm_chnklen
		plp
		bcs _not_found

		jsr get_read_address
		rts				 ; found it
_not_found
		jsr lbm_nextchunk_address

		;jsr get_read_address
		;clc
		;adc lbm_ChunkLength
		;sta lbm_ChunkLength

		;txa
		;adc lbm_ChunkLength+1
		;sta lbm_ChunkLength+1

		;tya
		;adc lbm_ChunkLength+2
		;sta lbm_ChunkLength+2

		lda lbm_ChunkLength
		ldx lbm_ChunkLength+1
		ldy lbm_ChunkLength+2

		jsr set_read_address

		bra _loop

_nullptr
		lda #0
		tax
		tay
		rts
;------------------------------------------------------------------------------
