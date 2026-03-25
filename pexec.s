;
; 64tass Cross Dev Stub for the Jr Micro Kernel
;
; To Assemble "64tass pexec.s -b -o pexec.bin"
;

		.cpu "65c02"

; Platform-Exec
;
;         Load->Run PGX files
;         Load->Run PGZ files
;         Load->Run KUP files
;         Load-Display 256 Picture files
;         Load-Display LBM Picture files
;

; some Kernel Stuff
		.include "kernel_api.s"

; Kernel uses MMU configurations 0 and 1
; User programs default to # 3
; I'm going to need 2 & 3, so that I can launch the PGX/PGZ with config #3
;
; and 0-BFFF mapped into 1:1
;

; Picture Viewer Stuff
PIXEL_DATA = $010000	; 320x240 pixels
CLUT_DATA  = $005C00	; 1k color buffer
IMAGE_FILE = $022C00	; try to allow for large files
VKY_GR_CLUT_0 = $D000
VKY_GR_CLUT_1 = $D400

; PGX/PGZ Loaders restrict memory usage to the DirectPage, and Stack
; It would be possible to stuff some code into text buffer, but unsure I need
; that

; Some Global Direct page stuff

; MMU modules needs 0-1F

	.virtual $20
temp0 .fill 4
temp1 .fill 4
temp2 .fill 4
temp3 .fill 4
	.endv

	.virtual $20
PGz_z .fill 1
PGz_addr .fill 4
PGz_size .fill 4
	.endv

; Event Buffer at $30
event_type = $30
event_buf  = $31
event_ext  = $32

event_file_data_read  = event_type+kernel_event_event_t_file_data_read
event_file_data_wrote = event_type+kernel_event_event_t_file_wrote_wrote

; arguments
args_buf = $40
args_buflen = $42

	.virtual $60
temp7 .fill 4
temp8 .fill 4
temp9 .fill 4
temp10 .fill 4

progress .fill 2     ; progress counter
show_prompt .fill 1  ; picture viewer can hide the press key prompt

pArg .fill 2
pExt .fill 2		  ; used by the alternate_open
	.endv


	.virtual $400
scratch_path .fill 256
try_count .fill 1
	.endv

; copy of the mmu_lock function, down to zero page

mmu_lock_springboard = $80

; File uses $B0-$BF
; Term uses $C0-$CF
; LZSA uses $E0-$EF
; Kernel uses $F0-FF
; I256 uses $F0-FF
; LBM uses $F0-FF

; 8k Kernel Program, so it can live anywhere

		* = $A000
sig		.byte $f2,$56		; signature
		.byte 1            ; 1 8k block
		.byte 5            ; mount at $a000
		.word start		; start here
		.byte 1			; version
		.byte 0			; reserved
		.byte 0			; reserved
		.byte 0			; reserved
		.text "-" 		; This will require some discussion with Gadget
		.byte 0
		.text "<file>"	; argument list
		.byte 0
		.text '"pexec", load and execute file.'	; description
		.byte 0

start
		; store argument list, but skip over first argument (us)
		lda	kernel_args_ext
		clc
		adc	#2
		sta	args_buf
		lda	kernel_args_ext+1
		adc #0
		sta	args_buf+1

		lda	kernel_args_extlen
		beq _zero_args				; validation, this should not be zero, but we'll accept it
		dec a
		dec a						; subtract 2 - we get rid of "pexec" from the args list
		bmi _zero_args              ; this is supposed to be positive
		bit #1
		bne _zero_args				; this is expected to be even

		sta	args_buflen 			; we've done some reasonable validation here
		bra _seems_good_args

_zero_args
		stz args_buflen
		stz kernel_args_extlen

_seems_good_args

		; Some variable initialization
		stz progress
		stz progress+1
		stz show_prompt  ; default to show the press key prompt
		stz chooser_chdir
		stz chooser_chdir+1

		; Terminal Init
		jsr initColors	; default the color palette
		jsr TermInit

		; mmu help functions are alive
		jsr mmu_unlock

		; Ensure 80x60 text mode
		php
		sei
		stz io_ctrl
		stz $D001		; 80 column mode
		lda #2
		sta io_ctrl
		plp

		; Program Version
		lda #<txt_version
		ldx #>txt_version
		jsr TermPUTS


		; giant text test

		ldx #18
		ldy #1
		jsr TermSetXY

		lda #<txt_glyph_pexec
		ldx #>txt_glyph_pexec
		jsr glyph_puts

		; load stuff banner
		ldx #17
		ldy #8
		jsr TermSetXY

		lda #<txt_load_stuff
		ldx #>txt_load_stuff
		jsr TermPUTS


		lda	args_buflen
		bne	_has_argument

		jmp	chooser_init

_has_argument
		; Display what we're trying to do
		ldx #0
		ldy #10
		jsr TermSetXY

		lda #<txt_launch
		ldx #>txt_launch
		jsr TermPUTS

		; Display the arguments, hopefully there are some
		lda	#'"'
		jsr	TermCOUT
		ldy	#3
		lda (kernel_args_ext),y
		tax
		dey
		lda (kernel_args_ext),y
		jsr TermPUTS
		lda	#'"'
		jsr	TermCOUT
		jsr TermCR

;------------------------------------------------------------------------------
		; Before receiving any Kernel events, we need to have a location
		; to receive them defined
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1

		; Set the drive
		; currently hard-coded to drive 0, since drive not passed
		stz file_open_drive

		; Set the Filename
		lda	#1
		jsr	get_arg

		; we have a chance here to change the drive
		sta pArg
		stx pArg+1

		ldy #1
		lda (pArg),y
		cmp #':'
		bne _no_device_passed_in

		; OMG there's a device!
		; if it's valid, maybe it can overide the device 0

		lda (pArg)

		inc pArg
		inc pArg 		; fuck you if we need to wrap a page

		sec
		sbc #'0'
		cmp #10
		bcs _no_device_passed_in ; fucked up, so just use device 0

		sta file_open_drive

_no_device_passed_in
		lda pArg
		ldx pArg+1

		jsr fopen
		bcc _opened
		; failed

		; Micah suggested we make life easier, so we don't require the extension
		; sounds good to me
		jsr alternate_open
		bcc _opened

		pha
		lda #<txt_error_open
		ldx #>txt_error_open
		jsr TermPUTS
		pla

		jsr TermPrintAH
		jsr TermCR

		bra wait_for_key
_opened

		; set address, system memory, to read
		lda #<temp0
		ldx #>temp0
		ldy #`temp0
		jsr set_write_address

		; request 4 bytes
		lda #4
		ldx #0
		ldy #0
		jsr fread

		pha

		jsr fclose

		pla

		cmp #4
		beq _got4

		pha

		lda #<txt_error_reading
		ldx #>txt_error_reading
		jsr TermPUTS

		pla

		jsr TermPrintAH
		jsr TermCR

		bra wait_for_key
_got4
		jsr execute_file

wait_for_key

		lda show_prompt
		bne _skip_prompt

		lda #<txt_press_key
		ldx #>txt_press_key
		jsr TermPUTS

_skip_prompt

_loop
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1
_wait
		jsr kernel_NextEvent
		bcs _wait

		lda event_type
		cmp #kernel_event_key_PRESSED
		beq _done

		;jsr TermPrintAH
		bra _loop
_done
		jmp mmu_lock   ; jsr+rts

;------------------------------------------------------------------------------
;
execute_file

; we have the first 4 bytes, let's see if we can
; identify the file
		lda temp0
		cmp #'Z'
		beq _pgZ
		cmp #'z'
		beq _pgz
		cmp #'P'
		beq _pgx
		cmp #'I'
		beq _256
		cmp #'F'
		beq _lbm
		cmp #$F2
		beq _kup
_done
		lda #<txt_unknown
		ldx #>txt_unknown
		jsr TermPUTS

		rts

;------------------------------------------------------------------------------
; Load /run KUP (Kernel User Program)
_kup
		lda temp0+1
		cmp #$56
		bne _done
		lda temp0+2 	; size in blocks
		beq _done   	; size 0, invalid
		cmp #6
		bcs _done       ; size larger than 40k, invalid
		lda temp0+3		; address mapping of block
		beq	_done       ; can't map you in at block 0
		cmp #6
		bcs _done		; can't map you in at block 6 or higher
		jmp LoadKUP

;------------------------------------------------------------------------------
; Load / run pgZ Program
_pgZ
		jmp LoadPGZ
_pgz
		jmp LoadPGz
_pgx
		lda temp0+1
		cmp #'G'
		bne _done
		lda temp0+2
		cmp #'X'
		bne _done
		lda temp0+3
		cmp #3
		bne _done
;------------------------------------------------------------------------------
; Load / Run PGX Program
		jmp LoadPGX

_256
		lda temp0+1
		cmp #'2'
		bne _done
		lda temp0+2
		cmp #'5'
		bne _done
		lda temp0+3
		cmp #'6'
		bne _done
;------------------------------------------------------------------------------
; Load / Display 256 Image
		jsr load_image
		jsr set_srcdest_clut
		jsr decompress_clut
		jsr copy_clut
		jsr init320x240
		jsr set_srcdest_pixels
		jsr decompress_pixels

		inc show_prompt   ; don't show prompt

		jmp TermClearTextBuffer  ; jsr+rts
;
_lbm
		lda temp0+1
		cmp #'O'
		bne _done
		lda temp0+2
		cmp #'R'
		bne _done
		lda temp0+3
		cmp #'M'
		bne _done
;------------------------------------------------------------------------------
; Load / Display LBM Image

		; get the compressed binary into memory
		jsr load_image

		; Now the LBM is in memory, let's try to decode and show it
		; set src to loaded image file, and dest to clut
		jsr set_srcdest_clut

		jsr lbm_decompress_clut
		jsr copy_clut

		; turn on graphics mode, so we can see the glory
		jsr init320x240

		; get the pixels
		; set src to loaded image file, dest to output pixels
		jsr set_srcdest_pixels
		jsr lbm_decompress_pixels

		inc show_prompt   ; don't show prompt

		jmp TermClearTextBuffer  ; jsr+rts
;-----------------------------------------------------------------------------
LoadPGX
		lda #<temp0
		ldx #>temp0
		ldy #`temp0
		jsr set_write_address

		lda	pArg
		ldx pArg+1

		jsr fopen

		lda #8
		ldx #0
		ldy #0
		jsr fread

		lda temp1
		ldx temp1+1
		ldy temp1+2
		jsr set_write_address

		; Try to read 64k, which should load the whole file
		lda #0
		tax
		ldy #1
		jsr fread

launchProgram
		jsr fclose	; close PGX or PGZ

		; Deferred chdir from chooser (after file is fully loaded/closed)
		lda chooser_chdir
		ora chooser_chdir+1
		beq _no_chdir
		lda chooser_chdir
		sta kernel_args_buf
		lda chooser_chdir+1
		sta kernel_args_buf+1
		; Calculate path length
		ldy #0
		lda (chooser_chdir),y
_chdir_len
		beq _chdir_go
		iny
		lda (chooser_chdir),y
		bra _chdir_len
_chdir_go
		sty kernel_args_buflen
		lda chooser_drive
		sta kernel_args_directory_open_drive
		jsr kernel_Chdir
		stz chooser_chdir		; clear so it doesn't fire again
		stz chooser_chdir+1
_no_chdir

		lda #5
		sta old_mmu0+5	; when lock is called it will map $A000 to physcial $A000

		; need to place a copy of mmu_lock, where it won't be unmapped
		ldx #mmu_lock_end-mmu_lock
_lp		lda mmu_lock,x
		sta mmu_lock_springboard,x
		dex
		bpl _lp

		; construct more stub code
		lda #$20   ; jsr mmu_lock_springboard
		sta temp0
		lda #<mmu_lock_springboard
		sta temp0+1
		lda #>mmu_lock_springboard
		sta temp0+2

		lda #$4c
		sta temp1-1  ; same as temp0+3

		; temp1, and temp1+1 contain the start address

		lda args_buf
		sta kernel_args_ext
		lda args_buf+1
		sta kernel_args_ext+1
		lda args_buflen
		sta kernel_args_extlen

		jmp temp0	; will jsr mmu_lock, then jmp to the start

;-----------------------------------------------------------------------------
LoadPGz
		; Open the File again (seek back to 0)
		lda	#1
		jsr	get_arg
		jsr TermPUTS

		lda pArg
		ldx pArg+1

		jsr fopen

		lda #<PGz_z
		ldx #>PGz_z
		ldy #`PGz_z
		jsr set_write_address

		lda #9
_loop
		ldx #0
		ldy #0
		jsr fread

		lda PGz_size
		ora PGz_size+1
		ora PGz_size+2
		ora PGz_size+3
		beq pgzDoneLoad

		lda PGz_addr
		ldx PGz_addr+1
		ldy PGz_addr+2
		jsr set_write_address

		lda PGz_size
		ldx PGz_size+1
		ldy PGz_size+2
		jsr fread

		lda #<PGz_addr
		ldx #>PGz_addr
		ldy #`PGz_addr
		jsr set_write_address
		lda #8
		bra _loop

;-----------------------------------------------------------------------------
LoadPGZ
		; Open the File again (seek back to 0)
		lda	#1
		jsr	get_arg
		jsr TermPUTS

		lda pArg
		ldx pArg+1

		jsr fopen

		lda #<temp0
		ldx #>temp0
		ldy #`temp0
		jsr set_write_address

		lda #7
_loop
		ldx #0
		ldy #0
		jsr fread

		lda temp1
		ora temp1+1
		ora temp1+2
		beq pgzDoneLoad

		lda temp0+1
		ldx temp0+2
		ldy temp0+3
		jsr set_write_address

		lda temp1
		ldx temp1+1
		ldy temp1+2
		jsr fread

		lda #<(temp0+1)
		ldx #>(temp0+1)
		ldy #`(temp0+1)
		jsr set_write_address
		lda #6
		bra _loop

pgzDoneLoad

		; copy the start location, for the launch code fragment
		lda temp0+1
		sta temp1
		lda temp0+2
		sta temp1+1

		jmp launchProgram  ; share cleanup with PGX launcher

;-----------------------------------------------------------------------------
; Load /run KUP (Kernel User Program)
LoadKUP
		; Open the File again (seek back to 0)
		lda	#1
		jsr	get_arg
		jsr TermPUTS

		lda pArg
		ldx pArg+1

		jsr fopen

; Set the address where we read data

		lda temp0+3 ; mount address
		clc
		ror
		ror
		ror
		ror
		tax
		lda #0
		tay

		sta temp0		; start address of where we're loading
		stx temp0+1

		jsr set_write_address

; Now ask for data from the file, let's be smart here, and ask for the
; max conceivable size that will fit.

		sec
		lda #$C0
		sbc temp0+1
		tax			; Should yield $A000 as largest possible address
		lda #0      ;
		tay
		jsr fread

		ldy #4
		lda (temp0),y
		sta temp1
		iny
		lda (temp0),y
		sta temp1+2

		jmp launchProgram	; close, fix mmu, start


;-----------------------------------------------------------------------------
load_image
; $10000, for the bitmap

		; Open the File again (seek back to 0)
		lda	#1
		jsr	get_arg
		jsr TermPUTS

		lda pArg
		ldx pArg+1

		jsr fopen

		; Address where we're going to load the file
		lda #<IMAGE_FILE
		ldx #>IMAGE_FILE
		ldy #`IMAGE_FILE
		jsr set_write_address

		; Request as many bytes as we can, and hope we hit the EOF
READ_BUFFER_SIZE = $080000-IMAGE_FILE

		lda #<READ_BUFFER_SIZE
		ldx #>READ_BUFFER_SIZE
		ldy #`READ_BUFFER_SIZE
		jsr fread
		; length read is in AXY, if we need it
		jsr fclose

		rts
;-----------------------------------------------------------------------------
set_srcdest_clut
		; Address where we're going to load the file
		lda #<IMAGE_FILE
		ldx #>IMAGE_FILE
		ldy #`IMAGE_FILE
		jsr set_read_address

		lda #<CLUT_DATA
		ldx #>CLUT_DATA
		ldy #`CLUT_DATA
		jsr set_write_address
		rts
;-----------------------------------------------------------------------------
set_srcdest_pixels
		lda #<IMAGE_FILE
		ldx #>IMAGE_FILE
		ldy #`IMAGE_FILE
		jsr set_read_address

		lda #<PIXEL_DATA
		ldx #>PIXEL_DATA
		ldy #`PIXEL_DATA
		jsr set_write_address
		rts
;-----------------------------------------------------------------------------

copy_clut
		php
		sei

		; set access to vicky CLUTs
		lda #1
		sta io_ctrl
		; copy the clut up there
		ldx #0
_lp		lda CLUT_DATA,x
		sta VKY_GR_CLUT_0,x
		lda CLUT_DATA+$100,x
		sta VKY_GR_CLUT_0+$100,x
		lda CLUT_DATA+$200,x
		sta VKY_GR_CLUT_0+$200,x
		lda CLUT_DATA+$300,x
		sta VKY_GR_CLUT_0+$300,x
		dex
		bne _lp

		; set access back to text buffer, for the text stuff
		lda #2
		sta io_ctrl

		plp
		rts

;-----------------------------------------------------------------------------
; Setup 320x240 mode
init320x240
		php
		sei

		; Access to vicky generate registers
		stz io_ctrl

		; enable the graphics mode
		lda #%01001111	; gamma + bitmap + graphics + overlay + text
;		lda #%00000001	; text
		sta $D000
		;lda #%110       ; text in 40 column when it's enabled
		;sta $D001
		stz $D001

		; layer stuff - take from Jr manual
		stz $D002  ; layer ctrl 0
		stz $D003  ; layer ctrl 3

		; set address of image, since image uncompressed, we just display it
		; where we loaded it.
		lda #<PIXEL_DATA
		sta $D101
		lda #>PIXEL_DATA
		sta $D102
		lda #`PIXEL_DATA
		sta $D103

		lda #1
		sta $D100  ; bitmap enable, use clut 0
		stz $D108  ; disable
		stz $D110  ; disable

		lda #2
		sta io_ctrl
		plp

		rts

;------------------------------------------------------------------------------
; Get argument
; A - argument number
;
; Returns string in AX

get_arg
		asl
		tay
		iny
		lda (kernel_args_ext),y
		tax
		dey
		lda (kernel_args_ext),y
		rts

;------------------------------------------------------------------------------
;
;
ProgressIndicator

		lda #'.'
		jsr TermCOUT

		dec progress+1
		bpl _return

		lda #16
		sta progress+1

		ldx term_x
		phx
		ldy term_y
		phy

		clc
		lda progress
		inc a
		cmp #64
		bcc _no_wrap

		dec a
		adc #4
		tax

		ldy #51
		jsr TermSetXY

		lda #G_SPACE 	 ; erase the dude
		jsr glyph_draw

		clc
		lda #0     		 ; wrap to left
_no_wrap
		sta progress
		adc #5
		tax

		ldy #51
		jsr TermSetXY

		clc
		lda progress
		and #$3
		adc #GRUN0

		jsr glyph_draw   	; running man

		ply
		plx
		jsr TermSetXY

_return
		rts

;------------------------------------------------------------------------------
;
; We get here, because we got a kernel error when trying to open
; this could mean file is not found, so let's try to find the file
; to make life easier
;
; return c=0 if no error
;
alternate_open
		pha				; preserve the initial error
		stz try_count
_try
		jsr _copy_to_scratch
		jsr _append_ext

		lda #<scratch_path
		ldx #>scratch_path
		jsr fopen
		bcc _opened

		; this path didn't work
		inc try_count
		lda try_count
		cmp #5 				; there are 5 extensions
		bcc _try
; we failed 5 more times :-(
		pla
		rts

_opened
		lda #<scratch_path
		ldx #>scratch_path
		sta pArg  			; make sure when the file is re-opened it uses this working path
		stx pArg+1

		pla				; restore original error
_rts
		rts

_append_ext
		; at this point y points at the 0 terminator in the scratch path
		lda try_count
		asl
		asl
		tax
_ext_loop
		lda ext_table,x
		sta scratch_path,y
		beq _rts
		inx
		iny
		bra _ext_loop

_copy_to_scratch
		ldy #0
_lp		lda (pArg),y
		sta scratch_path,y
		beq _done_copy
		iny
		bne _lp
		; if we get here, things are fubar
		dey
		lda #0
		sta scratch_path,y
		rts

_done_copy
		lda #'.'
		sta scratch_path,y  ; replace the 0 terminator
		iny

		lda #0
		sta scratch_path,y  ; zero terminate
		rts


;------------------------------------------------------------------------------
; Strings and other includes
txt_version .text "Pexec 0.70"
		.byte 13,13,0

txt_press_key .byte 13
		.text "--- Press >ENTER< to continue ---"
		.byte 13,0

txt_unknown
		.text "Unknown application type"
		.byte 13,13,0

txt_launch .text "launch: "
		.byte 0

txt_error_open .text "ERROR: file open $"
		.byte 0
txt_error_notfound .text "ERROR: file not found: "
		.byte 0
txt_error_reading .text "ERROR: reading $"
		.byte 0
txt_error .text "ERROR!"
		.byte 13
		.byte 0
txt_open .text "Open Success!"
		.byte 13
		.byte 0
txt_no_argument .text "Missing file argument"
		.byte 13
		.byte 0
;------------------------------
ext_table
txt_pgz .text "pgz",0
txt_pgx .text "pgx",0
txt_kup .text "kup",0
txt_256 .text "256",0
txt_lbm .text "lbm",0
;------------------------------

txt_load_stuff .text "Load your stuff: .pgx, .pgz, .kup, .lbm, .256",0


txt_glyph_pexec
		.byte GP,GE,GX,GE,GC,0

;------------------------------------------------------------------------------
		.include "chooser.s"
		.include "mmu.s"
		.include "term.s"
		.include "lbm.s"
		.include "i256.s"
		.include "lzsa2.s"
		.include "file.s"
		.include "glyphs.s"
		.include "colors.s"
		.include "logo.s"

; pad to the end
		.fill $C000-*, $EA
