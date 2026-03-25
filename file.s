;
;  File Abstraction Routines, since Kernel level stuff is all async
;

DEBUG_FILE = 0

		.virtual $B0
file_handle     .fill 1
file_bytes_req  .fill 3

file_bytes_wrote
file_bytes_read .fill 3

file_to_read .fill 1
file_open_drive .fill 1
		.endv

;
; AX = pFileName (CString)
;
; c = 0 - no error
;		A = filehandle
; c = 1 - error
;		A = error #
fcreate
		ldy #kernel_args_file_open_WRITE
		bra fcreate_open

;
; AX = pFileName (CString)
;
; c = 0 - no error
;		A = filehandle
; c = 1 - error
;		A = error #
;
fopen
		; Set the mode, and open
		ldy #kernel_args_file_open_READ
fcreate_open
		sty kernel_args_file_open_mode

		ldy file_open_drive
		sty kernel_args_file_open_drive

		sta kernel_args_file_open_fname
		stx kernel_args_file_open_fname+1

		; Set the Filename length (why?)
		ldy #0
_len    lda (kernel_args_file_open_fname),y
		beq _got_len
		iny
		bne _len
_got_len
		sty kernel_args_file_open_fname_len

_try_again
		jsr kernel_File_Open
		sta file_handle
		bcc _it_opened
_error
		sec
		rts

_it_opened
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1

_loop
        jsr kernel_Yield    ; Not required; but good while waiting.
        jsr kernel_NextEvent
        bcs _loop

		lda event_type

		.if DEBUG_FILE
		pha
		jsr TermPrintAH
		lda #'y'
		jsr TermCOUT
		pla
		.endif

		;cmp #kernel_event_file_CLOSED  ; skip this event
		;beq _error
        cmp #kernel_event_file_NOT_FOUND
        beq _error
		cmp #kernel_event_file_OPENED
		beq _success
		cmp #kernel_event_file_ERROR
		beq _error
		bra _loop

_success
		lda file_handle
		clc
		rts

;
; mmu write address is the address
; AXY - Num Bytes to Read
;
; Return
; AXY - num Bytes actually read in
;
fread
		sta file_bytes_req
		stx file_bytes_req+1
		sty file_bytes_req+2

		.if DEBUG_FILE
		jsr TermCR
		lda file_bytes_req+2
		jsr TermPrintAH
		lda file_bytes_req
		ldx file_bytes_req+1
		jsr TermPrintAXH
		jsr TermCR
		.endif

		stz file_bytes_read
		stz file_bytes_read+1
		stz file_bytes_read+2

		; Set the stream
		lda file_handle
		sta kernel_args_file_read_stream

		; make sure event output is still set
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1

_loop
		lda file_bytes_req+2
		bne _do128  			  ; a lot of data left to read
		lda file_bytes_req+1
		bne _do128
		lda file_bytes_req
		bne	_not_done
		jmp	_done_done
_not_done
		bpl _small_read
_do128
		lda	#128
_small_read
		sta	file_to_read
		jsr	bytes_can_write
		cmp file_to_read
		bcc _read_len_ok
		lda file_to_read
_read_len_ok
		sta kernel_args_file_read_buflen

		.if DEBUG_FILE
		jsr TermCR
		ldx #$EA
		lda kernel_args_file_read_buflen
		jsr TermPrintAXH
		jsr TermCR
		.endif

		; Set the stream
		lda file_handle
		sta kernel_args_file_read_stream

		jsr kernel_File_Read

	    ; wait for data to appear, or error, or EOF
_event_loop
		.if DEBUG_FILE
		; make sure event output is still set
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1
		.endif

        ;jsr kernel_Yield    ; Not required; but good while waiting.
        jsr kernel_NextEvent
        bcs _event_loop

		lda event_type

		.if DEBUG_FILE
		pha
		jsr TermPrintAH
		lda #'x'
		jsr TermCOUT
		pla
		.endif

        cmp #kernel_event_file_EOF
		beq _done_done
        cmp #kernel_event_file_ERROR
		beq _done_done
		cmp #kernel_event_file_DATA
		bne _event_loop

		.if DEBUG_FILE
		jsr TermCR
		lda event_file_data_read
		jsr TermPrintAH
		jsr TermCR
		.endif

		; subtract bytes read from the total request
		sec
		lda file_bytes_req
		sbc event_file_data_read
		sta file_bytes_req
		lda file_bytes_req+1
		sbc #0
		sta file_bytes_req+1
		lda file_bytes_req+2
		sbc #0
		sta file_bytes_req+2

		clc
		lda file_bytes_read
		adc event_file_data_read
		sta file_bytes_read
		bcc _get_data
;-----------------------------------------------------------------------------
; LAME PROGRESS INDICATOR
;-----------------------------------------------------------------------------

		jsr ProgressIndicator

;-----------------------------------------------------------------------------
		inc file_bytes_read+1
		bne _get_data
		inc file_bytes_read+2

_get_data
		lda event_file_data_read
		sta kernel_args_recv_buflen

		.if DEBUG_FILE
		lda #<txt_data_read
		ldx #>txt_data_read
		jsr TermPUTS
		lda event_file_data_read
		jsr TermPrintAH
		jsr TermCR
		.endif

		lda	pDest
		sta kernel_args_recv_buf
		lda	pDest+1
		sta kernel_args_recv_buf+1

		jsr kernel_ReadData

		lda kernel_args_recv_buflen
		jsr increment_dest

		.if DEBUG_FILE
		jmp _loop
		.else
		bra _loop
		.endif


_done_done
		lda file_bytes_read
		ldx file_bytes_read+1
		ldy file_bytes_read+2

		rts

fclose
		lda file_handle
		sta kernel_args_file_close_stream
		jmp kernel_File_Close

txt_data_read .text "Data Read:"
		.byte 0

	.if 0
;
; mmu read address is the address
; AXY - Num Bytes to write
;
; Return
; AXY - num Bytes actually wrote
;
fwrite
		sta file_bytes_req
		stx file_bytes_req+1
		sty file_bytes_req+2

		stz file_bytes_wrote
		stz file_bytes_wrote+1
		stz file_bytes_wrote+2

		; make sure event output is still set
		lda #<event_type
		sta kernel_args_events
		lda #>event_type
		sta kernel_args_events+1

_loop
		lda file_bytes_req+2
		bne _do128  			  ; a lot of data left to write
		lda file_bytes_req+1
		bne _do128
		lda file_bytes_req
		cmp #128
		bcc _small_read
_do128	lda #128
		bra _try128
_small_read
		lda file_bytes_req
		beq _done_done  	   	; zero bytes left
_try128
		sta kernel_args_file_write_buflen

		; subtract request from the total request
		sec
		lda file_bytes_req
		sbc kernel_args_file_write_buflen
		sta file_bytes_req
		lda file_bytes_req+1
		sbc #0
		sta file_bytes_req+1
		lda file_bytes_req+2
		sbc #0
		sta file_bytes_req+2

		jsr _bytes_to_buffer

		; Set the stream
		lda file_handle
		sta kernel_args_file_write_stream

		lda #<file_buffer
		sta kernel_args_file_write_buf
		lda #>file_buffer
		sta kernel_args_file_write_buf+1

		jsr kernel_File_Write

	    ; wait for data to appear, or error, or EOF
_event_loop
        jsr kernel_Yield    ; Not required; but good while waiting.
        jsr kernel_NextEvent
        bcs _event_loop

		.if 0
		lda event_type
		jsr TermPrintAH
		.endif

		lda event_type

        cmp #kernel_event_file_EOF
		beq _done_done
        cmp #kernel_event_file_ERROR
		beq _done_done
		cmp #kernel_event_file_WROTE
		bne _event_loop

		.if 0
		lda event_file_data_wrote
		jsr TermPrintAH
		.endif

		clc
		lda file_bytes_wrote
		adc event_file_data_wrote
		sta file_bytes_wrote
		bcc _show
		inc file_bytes_wrote+1
		bne _show
		inc file_bytes_wrote+2
_show
		ldx #0
		ldy term_y
		jsr TermSetXY

		lda file_bytes_wrote+2
		jsr TermPrintAH
		lda file_bytes_wrote+0
		ldx file_bytes_wrote+1
		jsr TermPrintAXH

		bra _loop


_done_done
		lda file_bytes_wrote
		ldx file_bytes_wrote+1
		ldy file_bytes_wrote+2

		rts
;
; Copy bytes from the file, into the io buffer
; before they are written out to disk
;
_bytes_to_buffer
		ldx #0
_lp		jsr readbyte

		;pha
		;phx
		;jsr TermPrintAH
		;plx
		;pla

		sta file_buffer,x
		inx
		cpx kernel_args_file_write_buflen
		bne _lp
		rts

	.endif
