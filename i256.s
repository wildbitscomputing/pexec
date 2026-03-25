;
; 65c02 Foenix I256 file format parser utils
; for F256 Jr
;
; https://docs.google.com/document/d/10ovgMClDAJVgbW0sOhUsBkVABKWhOPM5Au7vbHJymoA/edit?usp=sharing
;

DEBUG_F256 = 0

; error codes
		.virtual $0
i256_no_error         .fill 1   ; 0 = no error
i256_error_badheader  .fill 1   ; 1 = something is not good with the header
i256_error_noclut     .fill 1   ; 2 = There's no CLUT in this file
i256_error_nopixels   .fill 1   ; 3 = There are no PIXL in this file
		.endv

		.virtual $F0
i256_FileLength
i256_pChunk
i256_temp0      .fill 4

i256_blobCount
i256_colorCount
i256_temp1      .fill 2

i256_FileStart  .fill 3
i256_Width      .fill 2
i256_Height     .fill 2
i256_EOF        .fill 3
		.endv

;
; This works with the mmu utils, and the lzsa2 decompressor
; Addresses are in System Memory BUS space
;
; set_read_address  - the source address for the image.256 file
; set_write_address - the destination address of the clut data
;
; if c=0, then operation success
; if c=1, then operation fail, error code in A
;
decompress_clut
		jsr c256init
		bcs _error

		.if DEBUG_F256
		lda #<decompress_clut
		ldx #>decompress_clut
		jsr FindChunk

		sta i256_pChunk
		stx i256_pChunk+1
		sty i256_pChunk+2

		ora i256_pChunk+1
		ora i256_pChunk+2
		beq _pass
		lda #4
		sec
		rts
_pass
		.endif

		lda #<CHNK_CLUT
		ldx #>CHNK_CLUT
		jsr FindChunk

		sta i256_pChunk
		stx i256_pChunk+1
		sty i256_pChunk+2

		ora i256_pChunk+1
		ora i256_pChunk+2
		bne _hasClut

		lda #i256_error_noclut
		sec
_error
		rts

_hasClut
		; add 8 bytes, to skip up to color count
		clc
		lda i256_pChunk
		adc #8
		sta i256_pChunk
		lda i256_pChunk+1
		adc #0
		sta i256_pChunk+1
		lda i256_pChunk+2
		adc #0
		sta i256_pChunk+2

		lda i256_pChunk
		ldx i256_pChunk+1
		ldy i256_pChunk+2
		jsr set_read_address

		jsr readbyte
		sta i256_colorCount
		jsr readbyte
		sta i256_colorCount+1
		bit #$80
		bne _compressed

		ldx i256_colorCount
		tay  ; colorCount+1
_raw
		; copy 1 color
		jsr readbyte
		jsr writebyte
		jsr readbyte
		jsr writebyte
		jsr readbyte
		jsr writebyte
		jsr readbyte
		jsr writebyte
		txa
		bne _lo
		dey
		bmi _done
_lo 	dex
		bra _raw
_compressed
		and #$7F
		sta i256_colorCount+1

		jsr lzsa2_unpack
_done
		clc
		lda #0
		rts

;------------------------------------------------------------------------------
;
; This works with the mmu utils, and the lzsa2 decompressor
; Addresses are in System Memory BUS space
;
; set_read_address  - the source address for the image.256 file
; set_write_address - the destination address of the pixels data
;
; if c=0, then operation success
; if c=1, then operation fail, error code in A
;
decompress_pixels
		jsr c256init
		; bcs _error is a no-op (branches to next line) - original Merlin32 behavior
		lda #<CHNK_PIXL
		ldx #>CHNK_PIXL
		jsr FindChunk

		sta i256_pChunk
		stx i256_pChunk+1
		sty i256_pChunk+2

		ora i256_pChunk+1
		ora i256_pChunk+2
		bne _hasPixel

		lda #i256_error_nopixels
		sec
_error
		rts
_hasPixel
		; add 8 bytes, to skip up to color count
		clc
		lda i256_pChunk
		adc #8
		sta i256_pChunk
		lda i256_pChunk+1
		adc #0
		sta i256_pChunk+1
		lda i256_pChunk+2
		adc #0
		sta i256_pChunk+2

		lda i256_pChunk
		ldx i256_pChunk+1
		ldy i256_pChunk+2
		jsr set_read_address

		; realistically, blob count can't be bigger than 255
		jsr readbyte
		sta i256_blobCount
		jsr readbyte  	 		; really don't care about the high byte, it's there for 816
		sta i256_blobCount+1

_size = i256_temp0
_loop
		jsr readbyte
		sta _size
		jsr readbyte
		sta _size+1
		ora _size
		bne _compressed

		; Raw 64k Blob
		ldx #0
		ldy #0
_lp
		jsr readbyte
		jsr writebyte
		dex
		bne _lp
		dey
		bne _lp
		bra _blob

_compressed
		jsr lzsa2_unpack

_blob
		dec i256_blobCount
		bne _loop

		clc
		lda #0	; return no error

		rts

;
; set_read_address - the source address for the image.256 file
;
; Output in the Kernel Args at $F0
;
; $F0,$F1 - width     - 2 bytes
; $F2,$F3 - height    - 2 bytes
; $F4,$F5 - numcolors - 2 bytes
;
; if c=0, then operation success
; if c=1, then operation fail, error code in A
;
image_info
		rts

;------------------------------------------------------------------------------
;
; This verifies that the image is looking like it should
; c=0 all good
; c=1 not good, error code in A
;
c256init
		;jsr get_read_address

		jsr c256ParseHeader
		bcc _isGood

		sec
		lda #i256_error_badheader
		rts

_isGood
		lda #<CHNK_CLUT
		ldx #>CHNK_CLUT
		jsr FindChunk

		sta i256_pChunk
		stx i256_pChunk+1
		sty i256_pChunk+2

		ora i256_pChunk+1
		ora i256_pChunk+2
		bne _hasClut

		lda #i256_error_noclut
		sec
		rts

_hasClut
		lda #<CHNK_PIXL
		ldx #>CHNK_PIXL
		jsr FindChunk

		sta i256_pChunk
		stx i256_pChunk+1
		sty i256_pChunk+2

		ora i256_pChunk+1
		ora i256_pChunk+2
		bne _hasPixels

		lda #i256_error_nopixels
		sec
		rts

_hasPixels
		clc
		lda #i256_no_error
		rts

;------------------------------------------------------------------------------
;
; FindChunk
; mmu read address as the pointer to where to start searching
;
;  AX = pointer to the chunk name to be searching for
;
;  Return: AXY pointer to chunk on memory bus
;
FindChunk
_pTag = i256_temp1
_temp = i256_temp0
		sta _pTag
		stx _pTag+1
		.if DEBUG_F256
		lda #<txt_FindChunk
		ldx #>txt_FindChunk
		jsr TermPUTS
		.endif
		jsr get_read_address

		phy
		phx
		pha
_loop
		.if DEBUG_F256
		jsr DebugTag
		jsr DebugAXY
		.endif

		phy
		phx
		pha

		cpy i256_EOF+2
		bcc _continue
		bne _nullptr
        cpx i256_EOF+1
		bcc _continue
		bne _nullptr
        cmp i256_EOF
		bcs _nullptr

_continue
		jsr set_read_address

		jsr readbyte
		sta _temp
		jsr readbyte
		sta _temp+1
		jsr readbyte
		sta _temp+2
		jsr readbyte
		sta _temp+3

		ldy #3
_lp     lda (_pTag),y
		cmp _temp,y
		bne _nextChunk
		dey
		bpl _lp

		pla
		plx
		ply
		sta _temp
		stx _temp+1
		sty _temp+2

		pla
		plx
		ply
		jsr set_read_address

		lda _temp
		ldx _temp+1
		ldy _temp+2

		rts
_nextChunk

		pla
		plx
		ply
		sta _temp
		stx _temp+1
		sty _temp+2

		jsr readbyte
		clc
		adc _temp
		sta _temp
		php
		jsr readbyte
		plp
		adc _temp+1
		sta _temp+1
		php
		jsr readbyte
		plp
		adc _temp+2
		sta _temp+2
		jsr readbyte  ; if throw away 4th byte

		lda _temp
		ldx _temp+1
		ldy _temp+2
		;jsr set_read_address
		bra _loop


_nullptr
		pla
		plx
		ply

		pla
		plx
		ply

		jsr set_read_address

		lda #0
		tax
		tay

		rts

;------------------------------------------------------------------------------
;
;  mmu read address, should be set point at the header
;
;	char 			i,2,5,6;  // 'I','2','5','6'
;
;	unsigned int 	file_length;  // In bytes, including the 16 byte header
;
;	short			version;  // 0x0000 for now
;	short			width;	  // In pixels
;	short			height;	  // In pixels
;   short           reserved;
;
c256ParseHeader
		jsr get_read_address
		sta i256_FileStart
		stx i256_FileStart+1
		sty i256_FileStart+2

        ; Check for 'I256'
		lda #<CHNK_I256
		ldx #>CHNK_I256
		jsr IFF_Verify
		bcs _BadHeader

        ; Copy out FileLength
		ldx #0
_lp		jsr readbyte
		sta i256_FileLength,x
		inx
		cpx #4
		bcc _lp

        ; Compute the end of file address
        clc
        lda i256_FileStart
        adc i256_FileLength
        sta i256_EOF

        lda i256_FileStart+1
        adc i256_FileLength+1
        sta i256_EOF+1

        lda i256_FileStart+2
        adc i256_FileLength+2
        sta i256_EOF+2
        bcs _BadHeader          ; overflow on memory address

		lda i256_FileLength+3
		bne _BadHeader

        ; Look at the File Version
		jsr readbyte
		cmp #0  	    ; current
		bne _BadHeader
		jsr readbyte
		cmp #0
		bne _BadHeader  ; currently only supports version 0

        ; Get the width and height
		jsr readbyte
		sta i256_Width
		jsr readbyte
		sta i256_Width+1

		jsr readbyte
		sta i256_Height
		jsr readbyte
		sta i256_Height+1

        ; Reserved
        jsr readbyte
        jsr readbyte

        ; c=0 mean's there's no error
		clc
        rts

_BadHeader
		lda i256_FileStart
		ldx i256_FileStart+1
		ldy i256_FileStart+2
		jsr set_read_address

        sec     ; c=1 means there's an error
        rts

;------------------------------------------------------------------------------
; mmu read address is pointer to the source
;
; AX is pointer the IFF tag we want to compare
; Y is not preserved
IFF_Verify
_pIFF = i256_temp1
		ldy #0
		sta _pIFF
		stx _pIFF+1
_lp		jsr readbyte
		cmp (_pIFF),y
		bne _fail
		iny
		cpy #4
		bcc _lp
		clc
		rts

_fail
		sec
		rts

;------------------------------------------------------------------------------
		.if DEBUG_F256
DebugAXY
		pha
		phx
		phy

		phx
		pha
		tya
		jsr TermPrintAH
		pla
		plx
		jsr TermPrintAXH
		jsr TermCR

		ply
		plx
		pla

		rts
		.endif
;------------------------------------------------------------------------------
		.if DEBUG_F256
DebugTag
_pTag = i256_temp1
		pha
		phx
		phy
		lda #<txt_tag
		ldx #>txt_tag
		jsr TermPUTS
		lda _pTag
		ldx _pTag+1
		jsr TermPrintAXH
		jsr TermCR

		lda #<txt_eof
		ldx #>txt_eof
		jsr TermPUTS

		lda i256_EOF+2
		jsr TermPrintAH
		lda i256_EOF
		ldx i256_EOF+1
		jsr TermPrintAXH
		jsr TermCR

		ply
		plx
		pla
		rts
		.endif

;------------------------------------------------------------------------------


CHNK_CLUT .text "CLUT"
CHNK_PIXL .text "PIXL"
CHNK_I256 .text "I256"


		.if DEBUG_F256

txt_tag .text "tag="
			.byte 0
txt_FindChunk .text "FindChunk - "
			.byte 0

txt_eof .text "EOF="
			.byte 0
		.endif
