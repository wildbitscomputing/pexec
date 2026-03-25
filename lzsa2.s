;
; 65c02 lzsa2 decompressor, for F256 Jr
;
;------------------------------------------------------------------------------

;
; ***************************************************************************
; ***************************************************************************
;
; It's been hacked up for 64tass and the Jr.
;
; lzsa2_6502.s
;
; NMOS 6502 decompressor for data stored in Emmanuel Marty's LZSA2 format.
;
; This code is written for the ACME assembler.
;
; The code is 240 bytes for the small version, and 255 bytes for the normal.
;
; Copyright John Brandwood 2021.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************


; ***************************************************************************
; ***************************************************************************
;
;

lzsa_cmdbuf     =       $E0                     ; 1 byte.
lzsa_nibflg     =       $E1                     ; 1 byte.
lzsa_nibble     =       $E2                     ; 1 byte.
lzsa_offset     =       $E3                     ; 1 word.
lzsa_winptr     =       $E5                     ; 3 byte
lzsa_srcptr     =       $E8                     ; 3 byte
lzsa_dstptr     =       $EB                     ; 3 byte

lzsa_length     =       lzsa_winptr             ; 1 word.


; ***************************************************************************
; ***************************************************************************
;
; lzsa2_unpack - Decompress data stored in Emmanuel Marty's LZSA2 format.
;
; args - set_read_address
; args - set_write_address
;
; Uses: lots!
;

DECOMPRESS_LZSA2_FAST
lzsa2_unpack    ldx     #$00                    ; Hi-byte of length or offset.
                ldy     #$00                    ; Initialize source index.
                sty     lzsa_nibflg             ; Initialize nibble buffer.

                ;
                ; Copy bytes from compressed source data.
                ;
                ; N.B. X=0 is expected and guaranteed when we get here.
                ;

_cp_length
                jsr     readbyte

_cp_skip0       sta     lzsa_cmdbuf             ; Preserve this for later.
                and     #$18                    ; Extract literal length.
                beq     _lz_offset              ; Skip directly to match?

                lsr                             ; Get 2-bit literal length.
                lsr
                lsr
                cmp     #$03                    ; Extended length?
                bcc     _inc_cp_len

                inx
                jsr     _get_length             ; X=1 for literals, returns CC.

                ora     #0                      ; Check the lo-byte of length
                beq     _put_cp_len             ; without effecting CC.

_inc_cp_len     inx                             ; Increment # of pages to copy.

_put_cp_len     stx     lzsa_length
                tax

_cp_page        jsr	readbyte
				jsr writebyte

_cp_skip2       dex
                bne     _cp_page
                dec     lzsa_length             ; Any full pages left to copy?
                bne     _cp_page

                ;
                ; Copy bytes from decompressed window.
                ;
                ; N.B. X=0 is expected and guaranteed when we get here.
                ;
                ; xyz
                ; ===========================
                ; 00z  5-bit offset
                ; 01z  9-bit offset
                ; 10z  13-bit offset
                ; 110  16-bit offset
                ; 111  repeat offset
                ;

_lz_offset      lda     lzsa_cmdbuf
                asl
                bcs     _get_13_16_rep
                asl
                bcs     _get_9_bits

_get_5_bits     dex                             ; X=$FF
_get_13_bits    asl
                php
                jsr     _get_nibble
                plp
                rol                             ; Shift into position, clr C.
                eor     #$E1
                cpx     #$00                    ; X=$FF for a 5-bit offset.
                bne     _set_offset
                sbc     #2                      ; 13-bit offset from $FE00.
                bne     _set_hi_8               ; Always NZ from previous SBC.

_get_9_bits     dex                             ; X=$FF if CS, X=$FE if CC.
                asl
                bcc     _get_lo_8
                dex
                bcs     _get_lo_8               ; Always VS from previous BIT.

_get_13_16_rep  asl
                bcc     _get_13_bits            ; Shares code with 5-bit path.

_get_16_rep     bmi     _lz_length              ; Repeat previous offset.

_get_16_bits    jsr     readbyte                ; Get hi-byte of offset.

_set_hi_8       tax

_get_lo_8
                jsr     readbyte                ; Get lo-byte of offset.

_set_offset     stx     lzsa_offset+1           ; Save new offset.
                sta     lzsa_offset+0

_lz_length      ldx     #$00                    ; Hi-byte of length.

                lda     lzsa_cmdbuf
                and     #$07
                clc
                adc     #$02
                cmp     #$09                    ; Extended length?
                bcc     _got_lz_len

                jsr     _get_length             ; X=0 for match, returns CC.

_got_lz_len     eor     #$FF                    ; Negate the lo-byte of length
                tay                             ; and check for zero.
                iny
                beq     _get_lz_win
                inx                             ; Increment # of pages to copy.
_get_lz_win
				phx
				phy
				jsr 	get_write_address
				sta     lzsa_dstptr
				stx     lzsa_dstptr+1
				sty     lzsa_dstptr+2
				; saved the read address
				jsr     get_read_address
				sta     lzsa_srcptr
				stx     lzsa_srcptr+1
				sty     lzsa_srcptr+2

				clc                          ; Calc address of match.
                lda     lzsa_dstptr+0        ; N.B. Offset is negative!
                adc     lzsa_offset+0
                sta     lzsa_winptr+0
                lda     lzsa_dstptr+1
                adc     lzsa_offset+1
                sta     lzsa_winptr+1
				lda		lzsa_dstptr+2
				adc     #$FF 			     ; assuming negative offset
				sta     lzsa_winptr+2

				; read address is now the window pointer
				lda     lzsa_winptr
				ldx     lzsa_winptr+1
				ldy     lzsa_winptr+2
				jsr     set_read_address

				ply
				plx
_lz_page
				jsr 	readbyte
				jsr		writebyte
                iny
                bne     _lz_page
                dex                             ; Any full pages left to copy?
                bne     _lz_page

				lda lzsa_srcptr
				ldx lzsa_srcptr+1
				ldy lzsa_srcptr+2
				jsr set_read_address

				ldy #0
				ldx #0

                jmp     _cp_length              ; Loop around to the beginning.

                ;
                ; Lookup tables to differentiate literal and match lengths.
                ;

_nibl_len_tbl   .byte   9                       ; 2+7 (for match).
                .byte   3                       ; 0+3 (for literal).

_byte_len_tbl   .byte   24-1                    ; 2+7+15 - CS (for match).
                .byte   18-1                    ; 0+3+15 - CS (for literal).

                ;
                ; Get 16-bit length in X:A register pair, return with CC.
                ;

_get_length     jsr     _get_nibble
                cmp     #$0F                    ; Extended length?
                bcs     _byte_length
                adc     _nibl_len_tbl,x         ; Always CC from previous CMP.

_got_length     ldx     #$00                    ; Set hi-byte of 4 & 8 bit
                rts                             ; lengths.

_byte_length    php
				jsr     readbyte                ; So rare, this can be slow!
				plp
                adc     _byte_len_tbl,x         ; Always CS from previous CMP.
                bcc     _got_length
                beq     _finished

_word_length    jsr     readbyte                ; So rare, this can be slow!
                pha
                jsr     readbyte                ; So rare, this can be slow!
                tax
                pla
                clc                             ; MUST return CC!
                rts

_finished       pla                             ; Decompression completed, pop
                pla                             ; return address.
                rts

                ;
                ; Get a nibble value from compressed data in A.
                ;

_get_nibble     lsr     lzsa_nibflg             ; Is there a nibble waiting?
                lda     lzsa_nibble             ; Extract the lo-nibble.
                bcs     _got_nibble

                inc     lzsa_nibflg             ; Reset the flag.

                jsr     readbyte

_set_nibble     sta     lzsa_nibble             ; Preserve for next time.
                lsr                             ; Extract the hi-nibble.
                lsr
                lsr
                lsr

_got_nibble     and     #$0F
                rts

