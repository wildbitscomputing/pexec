;
; File Chooser - interactive file browser
;

; Screen layout constants
CHOOSER_PATH_LINE = 10
CHOOSER_LIST_LINE = 11
CHOOSER_MAX_LINES = 38    ; lines 11-48
CHOOSER_BOTTOM    = 49    ; bottom border line

; Box drawing
BOX_LEFT  = 5
BOX_RIGHT = 74
BOX_WIDTH = 70             ; total including borders
BOX_INNER = 68             ; content area between │'s

; Box-drawing characters (from F256K font)
BOX_TL = 169               ; ┌
BOX_TR = 170               ; ┐
BOX_BL = 171               ; └
BOX_BR = 172               ; ┘
BOX_H  = 173               ; ─
BOX_V  = 174               ; │

; Entry buffer at $2000, 33 bytes per entry (32 name + 1 flags)
ENTRY_SIZE = 33
ENTRY_NAME_MAX = 32
ENTRY_BUF = $2000
MAX_ENTRIES = 128

; Flags byte
FLAG_DIR = $01
FLAG_LAUNCHABLE = $02

; Key codes
KEY_UP    = $B6
KEY_DOWN  = $B7
KEY_LEFT  = $B8
KEY_RIGHT = $B9
KEY_ENTER = 13
KEY_ESC   = 27
KEY_BKSP  = $92
KEY_DEL   = $91
KEY_BREAK = $BC            ; RUN/STOP key

PAGE_JUMP = 10             ; entries to skip with left/right

; Attribute flags from kernel directory events
ATTR_HIDDEN = $02
ATTR_DIR    = $10

; Zero page variables
chooser_sel    = $90
chooser_top    = $91
chooser_count  = $92
chooser_drive  = $93
chooser_stream = $94
chooser_tmp    = $95   ; 2 bytes
chooser_path   = $97   ; 2 bytes
chooser_idx    = $99   ; 1 byte - temp entry index for drawing
chooser_flags  = $9A   ; 1 byte - temp entry flags for drawing
chooser_oldos  = $9B   ; 1 byte - OLD-OS mode flag (nonzero = enabled)
chooser_chdir  = $9C   ; 2 bytes - pointer to chdir path (0=none)
repeat_key     = $9E   ; 1 byte - raw key code being repeated (0=none)
repeat_delay   = $9F   ; 1 byte - frames to wait before next repeat
repeat_start   = $A0   ; 1 byte - frame counter snapshot at start of wait

; Repeat timing (via hardware frame counter at $D659)
REPEAT_INITIAL = 15    ; ~250ms at 60Hz
REPEAT_RATE    = 3     ; ~50ms = 20/sec
FRAME_COUNTER  = $D659 ; F256K hardware frame counter (low byte, I/O page)

; Trash buffer for consuming data we don't need
TRASH_BUF = scratch_path+128

; Colors
COLOR_NORMAL   = $F2   ; white on blue (matches existing)
COLOR_HIGHLIGHT = $2F  ; blue on white (inverted)
COLOR_GREYED   = $A2   ; light grey on blue

;------------------------------------------------------------------------------
; chooser_init - entry point from pexec when no argument given
;
chooser_init
        ; Set initial drive to 0
        stz chooser_drive
        stz chooser_oldos
        stz repeat_key

        ; Set initial path to "/"
        lda #'/'
        sta scratch_path
        stz scratch_path+1

        ; Fall through to read directory and start chooser
        jsr chooser_read_dir
        jsr chooser_draw
        jmp chooser_loop

;------------------------------------------------------------------------------
; chooser_read_dir - Read directory entries from kernel into ENTRY_BUF
;
chooser_read_dir
        ; Reset state
        stz chooser_count
        stz chooser_sel
        stz chooser_top

        ; Set up kernel event destination
        lda #<event_type
        sta kernel_args_events
        lda #>event_type
        sta kernel_args_events+1

        ; Set drive
        lda chooser_drive
        sta kernel_args_directory_open_drive

        ; Set path pointer to scratch_path
        lda #<scratch_path
        sta kernel_args_directory_open_path
        lda #>scratch_path
        sta kernel_args_directory_open_path+1

        ; Calculate path length
        ldy #0
_path_len
        lda scratch_path,y
        beq _got_path_len
        iny
        bne _path_len
_got_path_len
        sty kernel_args_directory_open_path_len

        ; Open directory
        jsr kernel_Directory_Open
        bcs _on_closed          ; open failed, nothing to read

        ; --- Event loop ---
_event_loop
        jsr kernel_NextEvent
        bcs _event_loop

        lda event_type
        cmp #kernel_event_directory_OPENED
        beq _on_opened
        cmp #kernel_event_directory_VOLUME
        beq _on_volume
        cmp #kernel_event_directory_FILE
        beq _on_file
        cmp #kernel_event_directory_FREE
        beq _on_free
        cmp #kernel_event_directory_EOF
        beq _on_eof
        cmp #kernel_event_directory_ERROR
        beq _on_eof
        cmp #kernel_event_directory_CLOSED
        beq _on_closed
        bra _event_loop

_on_volume
        ; Consume volume name data then request next entry
        lda event_type+kernel_event_event_t_directory_volume_len
        sta kernel_args_recv_buflen
        lda #<TRASH_BUF
        sta kernel_args_recv_buf
        lda #>TRASH_BUF
        sta kernel_args_recv_buf+1
        jsr kernel_ReadData
        ; Request next entry
        lda chooser_stream
        sta kernel_args_directory_read_stream
        jsr kernel_Directory_Read
        jmp _event_loop

_on_free
        ; Consume extended data then close
        jsr _read_ext
        jmp _on_eof

_on_opened
        ; Save stream handle from event
        lda event_type+kernel_event_event_t_directory_stream
        sta chooser_stream

        ; Request first directory entry
        sta kernel_args_directory_read_stream
        jsr kernel_Directory_Read
        jmp _event_loop

_on_eof
        ; Close the directory stream
        lda chooser_stream
        sta kernel_args_directory_close_stream
        jsr kernel_Directory_Close
        jmp _event_loop

_on_closed
        rts

_on_file
        ; Check ATTR_HIDDEN flag - skip hidden files
        lda event_type+kernel_event_event_t_directory_file_flags
        and #ATTR_HIDDEN
        bne _skip_entry

        ; Check if buffer is full
        lda chooser_count
        cmp #MAX_ENTRIES
        bcs _skip_entry

        ; Calculate entry pointer into chooser_tmp
        jsr _calc_entry_ptr

        ; Read filename into entry buffer via kernel_ReadData
        lda chooser_tmp
        sta kernel_args_recv_buf
        lda chooser_tmp+1
        sta kernel_args_recv_buf+1
        lda event_type+kernel_event_event_t_directory_file_len
        sta kernel_args_recv_buflen
        jsr kernel_ReadData

        ; Null-terminate the filename at the length position
        lda kernel_args_recv_buflen
        tay
        lda #0
        sta (chooser_tmp),y

        ; Skip "." and ".." entries
        ldy #0
        lda (chooser_tmp),y
        cmp #'.'
        bne _not_dot_entry
        iny
        lda (chooser_tmp),y
        beq _discard_entry      ; name is "."
        cmp #'.'
        bne _not_dot_entry
        iny
        lda (chooser_tmp),y
        beq _discard_entry      ; name is ".."
_not_dot_entry

        ; Consume 2 bytes of extended data
        jsr _read_ext

        ; --- Build flags byte ---
        ; Check ATTR_DIR flag from kernel event
        lda event_type+kernel_event_event_t_directory_file_flags
        and #ATTR_DIR
        beq _no_dir_flag
        lda #FLAG_DIR
        bra _have_dir_flag
_no_dir_flag
        lda #0
_have_dir_flag
        pha                     ; save DIR flag on stack

        ; Check if file extension is launchable
        ; _check_launchable needs chooser_tmp to point at the entry
        ; chooser_tmp is still valid here (not clobbered)
        jsr _check_launchable   ; returns FLAG_LAUNCHABLE or 0 in A

        ; Combine with DIR flag from stack
        tax                     ; save launchable result in X
        pla                     ; get DIR flag
        stx chooser_tmp        ; temporarily stash launchable in low byte (will clobber ptr)
        ora chooser_tmp         ; A = DIR | LAUNCHABLE
        pha                     ; save combined flags

        ; Recalculate entry pointer (chooser_tmp was clobbered)
        jsr _calc_entry_ptr

        ; Store combined flags at entry + ENTRY_NAME_MAX (offset 32)
        pla
        ldy #ENTRY_NAME_MAX
        sta (chooser_tmp),y

        ; Increment entry count
        inc chooser_count

        ; Request next directory entry
        lda chooser_stream
        sta kernel_args_directory_read_stream
        jsr kernel_Directory_Read
        jmp _event_loop

_discard_entry
        ; Entry was already read but we don't want it - consume ext and skip
        jsr _read_ext
        lda chooser_stream
        sta kernel_args_directory_read_stream
        jsr kernel_Directory_Read
        jmp _event_loop

_skip_entry
        ; Must still consume ReadData and ReadExt even for skipped entries
        lda #<TRASH_BUF
        sta kernel_args_recv_buf
        lda #>TRASH_BUF
        sta kernel_args_recv_buf+1
        lda event_type+kernel_event_event_t_directory_file_len
        sta kernel_args_recv_buflen
        jsr kernel_ReadData

        jsr _read_ext

        ; Request next directory entry
        lda chooser_stream
        sta kernel_args_directory_read_stream
        jsr kernel_Directory_Read
        jmp _event_loop

;--------------------------------------
; _calc_entry_ptr
; Calculate pointer: ENTRY_BUF + chooser_count * 33
; Result stored in chooser_tmp (2 bytes)
;
_calc_entry_ptr
        lda chooser_count
        sta chooser_tmp
        stz chooser_tmp+1

        ; Multiply by 32 (shift left 5 times)
        .for i := 0, i < 5, i += 1
        asl chooser_tmp
        rol chooser_tmp+1
        .next

        ; Add count once more: count*32 + count = count*33
        clc
        lda chooser_tmp
        adc chooser_count
        sta chooser_tmp
        lda chooser_tmp+1
        adc #0
        sta chooser_tmp+1

        ; Add ENTRY_BUF base address
        clc
        lda chooser_tmp
        adc #<ENTRY_BUF
        sta chooser_tmp
        lda chooser_tmp+1
        adc #>ENTRY_BUF
        sta chooser_tmp+1
        rts

;--------------------------------------
; _read_ext
; Consume 2 bytes of extended directory data into trash buffer
;
_read_ext
        lda #<TRASH_BUF
        sta kernel_args_recv_buf
        lda #>TRASH_BUF
        sta kernel_args_recv_buf+1
        lda #2
        sta kernel_args_recv_buflen
        jmp kernel_ReadExt      ; tail call

;--------------------------------------
; _check_launchable
; Scan filename at (chooser_tmp) for the LAST dot, then compare
; the 3-char extension case-insensitively against the known table.
; Returns FLAG_LAUNCHABLE ($02) in A if match, 0 otherwise.
;
_check_launchable
        ; Find the last dot in the filename
        ldy #0
        ldx #$ff                ; X = position of last dot ($ff = none)
_find_dot
        lda (chooser_tmp),y
        beq _done_scan
        cmp #'.'
        bne _no_dot
        tya
        tax                     ; X = index of this dot
_no_dot
        iny
        cpy #ENTRY_NAME_MAX
        bcc _find_dot
_done_scan
        cpx #$ff
        beq _not_launchable     ; no dot found at all

        ; X = index of last dot; extension starts at X+1
        inx
        txa
        tay                     ; Y = index of first char of extension
        sty chooser_path        ; save extension start index

        ; Check that the extension is exactly 3 characters long
        ; i.e. char at Y+3 must be the null terminator
        iny
        iny
        iny                     ; Y = ext_start + 3
        lda (chooser_tmp),y
        bne _not_launchable     ; not null -> extension length != 3

        ; Restore Y to start of extension
        ldy chooser_path

        ; Now compare against each 3-byte entry in the extension table
        ldx #0                  ; X = offset into _ext_tbl
_cmp_next_ext
        lda _ext_tbl,x
        beq _not_launchable     ; hit the sentinel -> no match

        ; Save table base offset and extension start index
        stx chooser_path+1     ; save table base offset

        ; Compare char 0
        lda (chooser_tmp),y
        ora #$20                ; to lowercase
        cmp _ext_tbl,x
        bne _ext_mismatch

        ; Compare char 1
        iny
        inx
        lda (chooser_tmp),y
        ora #$20
        cmp _ext_tbl,x
        bne _ext_mismatch

        ; Compare char 2
        iny
        inx
        lda (chooser_tmp),y
        ora #$20
        cmp _ext_tbl,x
        bne _ext_mismatch

        ; All 3 characters matched
        lda #FLAG_LAUNCHABLE
        rts

_ext_mismatch
        ; Advance to next table entry: base + 3
        lda chooser_path+1     ; recover saved table base offset
        clc
        adc #3
        tax                     ; X = next table entry offset

        ; Restore Y to start of extension
        ldy chooser_path
        bra _cmp_next_ext

_not_launchable
        lda #0
        rts

; Extension table: 3-byte entries, terminated by a zero byte
_ext_tbl
        .text "pgz"
        .text "pgx"
        .text "kup"
        .text "256"
        .text "lbm"
        .byte 0

;------------------------------------------------------------------------------
; chooser_draw - render box, path, entries, bottom border
;
chooser_draw
        jsr _draw_top_border
        jsr draw_entries
        jsr _draw_bottom_border

        ; Show "(empty)" if directory has no entries
        lda chooser_count
        bne _cd_done
        ldx #BOX_LEFT+2
        ldy #CHOOSER_LIST_LINE
        jsr TermSetXY
        lda #<_txt_empty
        ldx #>_txt_empty
        jsr TermPUTS
_cd_done
        rts

_txt_empty .text "(empty)",0
_txt_cdroot .text " CD / ",0

;------------------------------------------------------------------------------
; _draw_top_border - draw ┌── N:path ──...──┐ on path line
;
_draw_top_border
        ; Set normal color for the border line
        ldy #CHOOSER_PATH_LINE
        sty term_y
        lda #COLOR_NORMAL
        jsr set_line_color

        ldx #BOX_LEFT
        ldy #CHOOSER_PATH_LINE
        jsr TermSetXY

        ; ┌──
        lda #BOX_TL
        jsr TermCOUT
        lda #BOX_H
        jsr TermCOUT
        lda #' '
        jsr TermCOUT

        ; "N:path"
        lda chooser_drive
        clc
        adc #'0'
        jsr TermCOUT
        lda #':'
        jsr TermCOUT
        lda #<scratch_path
        ldx #>scratch_path
        jsr TermPUTS

_tb_pad
        lda #' '
        jsr TermCOUT

        ; Fill with ─ until one before BOX_RIGHT
_tb_fill
        lda term_x
        cmp #BOX_RIGHT
        bcs _tb_corner
        lda #BOX_H
        jsr TermCOUT
        bra _tb_fill

_tb_corner
        lda #BOX_TR
        jsr TermCOUT
        rts

;------------------------------------------------------------------------------
; _draw_bottom_border - draw └──...──┘ on bottom line
;
_draw_bottom_border
        ldy #CHOOSER_BOTTOM
        sty term_y
        lda #COLOR_NORMAL
        jsr set_line_color

        ldx #BOX_LEFT
        ldy #CHOOSER_BOTTOM
        jsr TermSetXY

        lda #BOX_BL
        jsr TermCOUT

        ; If CD/ enabled, stop fill early to fit indicator before corner
        ; " CD / " = 6 chars, so stop at BOX_RIGHT - 6
        lda chooser_oldos
        beq _bb_fill_full

_bb_fill_short
        lda term_x
        cmp #BOX_RIGHT-6
        bcs _bb_cdroot
        lda #BOX_H
        jsr TermCOUT
        bra _bb_fill_short

_bb_cdroot
        lda #<_txt_cdroot
        ldx #>_txt_cdroot
        jsr TermPUTS
        bra _bb_corner

_bb_fill_full
        lda term_x
        cmp #BOX_RIGHT
        bcs _bb_corner
        lda #BOX_H
        jsr TermCOUT
        bra _bb_fill_full

_bb_corner
        lda #BOX_BR
        jsr TermCOUT
        rts

;------------------------------------------------------------------------------
; clear_chooser_area - clear lines 10 through CHOOSER_BOTTOM, full width
; Resets both text (spaces) and colors (COLOR_NORMAL) for all 80 columns.
;
clear_chooser_area
        ldy #CHOOSER_PATH_LINE
_cca_loop
        cpy #CHOOSER_BOTTOM+1
        bcs _cca_done
        sty term_y

        ; Set full-width color to normal
        pha
        lda #3
        sta io_ctrl
        lda Term80Table_lo,y
        sta chooser_tmp
        lda Term80Table_hi,y
        sta chooser_tmp+1
        lda #COLOR_NORMAL
        ldy #79
_cca_col
        sta (chooser_tmp),y
        dey
        bpl _cca_col
        lda #2
        sta io_ctrl
        pla

        ; Fill text with spaces
        ldx #0
        ldy term_y
        jsr TermSetXY
        ldx #79
_cca_sp lda #' '
        jsr TermCOUT
        dex
        bne _cca_sp

        ldy term_y
        iny
        bra _cca_loop
_cca_done
        rts

;------------------------------------------------------------------------------
; draw_entries - draw visible file entries from chooser_top
;
draw_entries
        ldx chooser_top        ; entry index
        ldy #CHOOSER_LIST_LINE ; screen line

_de_loop
        ; Are we past the visible area?
        cpy #CHOOSER_LIST_LINE+CHOOSER_MAX_LINES
        bcs _de_done

        ; Are there more entries to show?
        cpx chooser_count
        bcs _de_clear_rest

        ; Draw this entry
        phx
        phy
        jsr _draw_one_entry     ; X=entry index, Y=screen line
        ply
        plx

        inx
        iny
        bra _de_loop

_de_clear_rest
        ; Clear remaining lines: │ + spaces + │
        cpy #CHOOSER_LIST_LINE+CHOOSER_MAX_LINES
        bcs _de_done
        phy
        sty term_y              ; set term_y for set_line_color

        ; Set normal color for the whole line
        lda #COLOR_NORMAL
        jsr set_line_color

        ldx #BOX_LEFT
        ldy term_y
        jsr TermSetXY

        lda #BOX_V
        jsr TermCOUT
_clr    lda term_x
        cmp #BOX_RIGHT
        bcs _clr_end
        lda #' '
        jsr TermCOUT
        bra _clr
_clr_end
        lda #BOX_V
        jsr TermCOUT

        ply
        iny
        bra _de_clear_rest

_de_done
        rts

;------------------------------------------------------------------------------
; _draw_one_entry - draw a single entry line
;
; X = entry index, Y = screen line
;
_draw_one_entry
        ; Save entry index and screen line
        stx chooser_idx
        sty term_y              ; set term_y for set_line_color

        ; Calculate entry pointer
        lda chooser_idx
        jsr get_entry_ptr_a     ; chooser_tmp = pointer to entry

        ; Get flags
        ldy #ENTRY_NAME_MAX
        lda (chooser_tmp),y
        sta chooser_flags

        ; Determine color for this entry
        lda chooser_idx
        cmp chooser_sel
        bne _doe_not_sel
        lda #COLOR_HIGHLIGHT
        bra _doe_set_color
_doe_not_sel
        lda chooser_flags
        and #FLAG_DIR | FLAG_LAUNCHABLE
        bne _doe_normal
        lda #COLOR_GREYED
        bra _doe_set_color
_doe_normal
        lda #COLOR_NORMAL
_doe_set_color
        ; Set color for this line (clobbers chooser_tmp)
        jsr set_line_color

        ; Position cursor at left border
        ldx #BOX_LEFT
        ldy term_y
        jsr TermSetXY

        ; Draw left border │ in normal color
        lda #BOX_V
        jsr TermCOUT
        lda #' '
        jsr TermCOUT

        ; Recalculate entry pointer (was clobbered by set_line_color)
        lda chooser_idx
        jsr get_entry_ptr_a

        ; If directory, print "/" prefix
        lda chooser_flags
        and #FLAG_DIR
        beq _doe_name
        lda #'/'
        jsr TermCOUT
_doe_name
        ; Print filename
        lda chooser_tmp
        ldx chooser_tmp+1
        jsr TermPUTS

_doe_pad
        ; Pad with spaces until one before BOX_RIGHT
        lda term_x
        cmp #BOX_RIGHT
        bcs _doe_rborder
        lda #' '
        jsr TermCOUT
        bra _doe_pad

_doe_rborder
        ; Draw right border │
        lda #BOX_V
        jsr TermCOUT
        rts

;------------------------------------------------------------------------------
; set_line_color - set color for box area of current line
;
; A = color attribute, uses term_y for the line
; Colors columns BOX_LEFT to BOX_RIGHT inclusive
;
set_line_color
        pha
        ; Switch to color memory
        lda #3
        sta io_ctrl

        ; Calculate line address
        ldy term_y
        lda Term80Table_lo,y
        sta chooser_tmp
        lda Term80Table_hi,y
        sta chooser_tmp+1

        ; Fill inner content only (BOX_LEFT+1 to BOX_RIGHT-1)
        ; Borders keep COLOR_NORMAL from initial clear
        pla
        ldy #BOX_RIGHT-1
_slc_lp sta (chooser_tmp),y
        dey
        cpy #BOX_LEFT
        bne _slc_lp

        ; Switch back to text memory
        lda #2
        sta io_ctrl
        rts

;------------------------------------------------------------------------------
; get_entry_ptr_a - get pointer to entry A
;
; A = entry index
; Sets chooser_tmp to entry base address
;
get_entry_ptr_a
        ; Multiply A by ENTRY_SIZE (33 = 32+1)
        sta chooser_idx
        stz chooser_tmp+1

        ; A * 32
        asl
        rol chooser_tmp+1
        asl
        rol chooser_tmp+1
        asl
        rol chooser_tmp+1
        asl
        rol chooser_tmp+1
        asl
        rol chooser_tmp+1
        sta chooser_tmp

        ; + original A
        clc
        lda chooser_tmp
        adc chooser_idx
        sta chooser_tmp
        lda chooser_tmp+1
        adc #0
        sta chooser_tmp+1

        ; + ENTRY_BUF
        clc
        lda chooser_tmp
        adc #<ENTRY_BUF
        sta chooser_tmp
        lda chooser_tmp+1
        adc #>ENTRY_BUF
        sta chooser_tmp+1
        rts


;------------------------------------------------------------------------------
; chooser_loop - keyboard event loop for file chooser navigation
;
; Key repeat reads hardware frame counter ($D659) directly.
; Subtraction handles 8-bit wrap correctly: (current - start) gives
; true elapsed frames even across the 255→0 boundary.
;
chooser_loop
_cl_poll
        lda #<event_type
        sta kernel_args_events
        lda #>event_type
        sta kernel_args_events+1

        jsr kernel_NextEvent
        bcs _cl_no_event

        ; Got an event - dispatch by type
        lda event_type

        cmp #kernel_event_key_PRESSED
        beq _cl_key_pressed

        cmp #kernel_event_key_RELEASED
        beq _cl_key_released

        bra _cl_poll

_cl_no_event
        ; No event - check if repeat timer has elapsed
        lda repeat_key
        beq _cl_poll            ; no repeat active

        ; Read hardware frame counter (need I/O page)
        stz io_ctrl             ; switch to I/O
        lda FRAME_COUNTER       ; read low byte
        ldx #2
        stx io_ctrl             ; back to text mode

        ; Elapsed = current - start (wrap-safe unsigned subtraction)
        sec
        sbc repeat_start
        cmp repeat_delay
        bcc _cl_poll            ; not enough time yet

        ; Time to repeat! Snapshot new start frame
        stz io_ctrl
        lda FRAME_COUNTER
        ldx #2
        stx io_ctrl
        sta repeat_start
        lda #REPEAT_RATE
        sta repeat_delay        ; subsequent repeats are fast

        ; Dispatch the repeated key via jump table
        lda repeat_key
        cmp #KEY_UP
        bne _rpt_not_up
        jmp _cl_move_up
_rpt_not_up
        cmp #KEY_DOWN
        bne _rpt_not_down
        jmp _cl_move_down
_rpt_not_down
        cmp #KEY_LEFT
        bne _rpt_not_left
        jmp _cl_move_pgup
_rpt_not_left
        cmp #KEY_RIGHT
        bne _rpt_done
        jmp _cl_move_pgdn
_rpt_done
        jmp _cl_poll

_cl_key_released
        stz repeat_key
        jmp _cl_poll

_cl_key_pressed
        lda event_type+kernel_event_event_t_key_raw

        cmp #KEY_UP
        bne _kp_not_up
        jmp _cl_start_up
_kp_not_up
        cmp #KEY_DOWN
        bne _kp_not_down
        jmp _cl_start_down
_kp_not_down
        cmp #KEY_LEFT
        bne _kp_not_left
        jmp _cl_start_pgup
_kp_not_left
        cmp #KEY_RIGHT
        bne _kp_not_right
        jmp _cl_start_pgdn
_kp_not_right

        ; Other keys stop repeat
        stz repeat_key

        cmp #KEY_BKSP
        bne _cl_not_bksp
        jmp _chooser_parent_dir
_cl_not_bksp
        cmp #KEY_DEL
        bne _cl_not_del
        jmp _chooser_parent_dir
_cl_not_del
        cmp #KEY_BREAK
        bne _cl_not_break
        jmp mmu_lock
_cl_not_break

        ; Check ASCII
        lda event_type+kernel_event_event_t_key_ascii
        cmp #KEY_ENTER
        beq _cl_select
        cmp #' '
        beq _cl_select
        bra _cl_not_select
_cl_select
        jmp _chooser_select
_cl_not_select
        cmp #'o'
        beq _cl_toggle_oldos
        cmp #'O'
        beq _cl_toggle_oldos
        jmp _cl_poll

_cl_toggle_oldos
        ; Only allow if kernel supports Chdir
        lda kernel_Chdir
        cmp #$4C
        bne _cl_toggle_skip
        lda chooser_oldos
        eor #$01
        sta chooser_oldos
        jsr chooser_draw
        jmp chooser_loop
_cl_toggle_skip
        jmp _cl_poll

;--------------------------------------
; _snapshot_frame - read frame counter into repeat_start
;
_snapshot_frame
        stz io_ctrl
        lda FRAME_COUNTER
        sta repeat_start
        ldx #2
        stx io_ctrl
        rts

;--------------------------------------
; Start repeat for UP, then move
;
_cl_start_up
        lda #KEY_UP
        sta repeat_key
        lda #REPEAT_INITIAL
        sta repeat_delay
        jsr _snapshot_frame
        ; fall through to movement

_cl_move_up
        lda chooser_sel
        bne _cl_do_up
        jmp _cl_poll
_cl_do_up
        dec chooser_sel

        lda chooser_sel
        cmp chooser_top
        bcs _cl_up_draw
        dec chooser_top

_cl_up_draw
        jsr draw_entries
        jmp chooser_loop

;--------------------------------------
; Start repeat for DOWN, then move
;
_cl_start_down
        lda #KEY_DOWN
        sta repeat_key
        lda #REPEAT_INITIAL
        sta repeat_delay
        jsr _snapshot_frame
        ; fall through to movement

_cl_move_down
        lda chooser_sel
        clc
        adc #1
        cmp chooser_count
        bcs _cl_down_done

        inc chooser_sel

        lda chooser_sel
        sec
        sbc chooser_top
        cmp #CHOOSER_MAX_LINES
        bcc _cl_down_draw
        inc chooser_top

_cl_down_draw
        jsr draw_entries
        jmp chooser_loop

_cl_down_done
        jmp _cl_poll

;--------------------------------------
; Page up (left arrow) - start repeat, then jump up
;
_cl_start_pgup
        lda #KEY_LEFT
        sta repeat_key
        lda #REPEAT_INITIAL
        sta repeat_delay
        jsr _snapshot_frame

_cl_move_pgup
        ; Subtract PAGE_JUMP from selection, clamp to 0
        lda chooser_sel
        sec
        sbc #PAGE_JUMP
        bcs _pgup_ok
        lda #0                  ; clamped to top
_pgup_ok
        sta chooser_sel

        ; Adjust scroll if needed
        cmp chooser_top
        bcs _pgup_draw
        sta chooser_top         ; scroll to show selection
_pgup_draw
        jsr draw_entries
        jmp chooser_loop

;--------------------------------------
; Page down (right arrow) - start repeat, then jump down
;
_cl_start_pgdn
        lda #KEY_RIGHT
        sta repeat_key
        lda #REPEAT_INITIAL
        sta repeat_delay
        jsr _snapshot_frame

_cl_move_pgdn
        ; Add PAGE_JUMP to selection, clamp to count-1
        lda chooser_sel
        clc
        adc #PAGE_JUMP
        cmp chooser_count
        bcc _pgdn_ok
        lda chooser_count
        beq _pgdn_done          ; empty directory
        sec
        sbc #1                  ; clamp to last entry
_pgdn_ok
        sta chooser_sel

        ; Adjust scroll if needed
        sec
        sbc chooser_top
        cmp #CHOOSER_MAX_LINES
        bcc _pgdn_draw
        ; Selection is past visible area, adjust top
        lda chooser_sel
        sec
        sbc #CHOOSER_MAX_LINES-1
        sta chooser_top
_pgdn_draw
        jsr draw_entries
        jmp chooser_loop

_pgdn_done
        jmp _cl_poll

;--------------------------------------
; Enter - select the highlighted entry
;
_chooser_select
        ; Do nothing if directory is empty
        lda chooser_count
        beq _cs_nothing

        ; Get pointer to the selected entry
        lda chooser_sel
        jsr get_entry_ptr_a         ; chooser_tmp -> entry

        ; Read flags byte
        ldy #ENTRY_NAME_MAX
        lda (chooser_tmp),y

        ; Check if directory
        bit #FLAG_DIR
        bne _cs_enter_dir

        ; Check if launchable
        bit #FLAG_LAUNCHABLE
        bne _cs_launch

        ; Neither - do nothing
_cs_nothing
        jmp chooser_loop

;- - - - - - - - - - - - - - - - - - -
; Enter a subdirectory
;
_cs_enter_dir
        ; Find end of scratch_path (null terminator)
        ldx #0
_cs_find_end
        lda scratch_path,x
        beq _cs_at_end
        inx
        bne _cs_find_end
_cs_at_end
        ; X = index of null terminator in scratch_path
        ; Copy entry name from (chooser_tmp),y to scratch_path+X
        ldy #0
_cs_copy_name
        lda (chooser_tmp),y
        beq _cs_name_done
        sta scratch_path,x
        inx
        iny
        cpy #ENTRY_NAME_MAX
        bcc _cs_copy_name
_cs_name_done
        ; Append '/' and null terminator
        lda #'/'
        sta scratch_path,x
        inx
        stz scratch_path,x

        ; Re-read directory with new path
        jsr chooser_read_dir
        jsr chooser_draw
        jmp chooser_loop

;- - - - - - - - - - - - - - - - - - -
; Launch a file
;
_cs_launch
        ; Build full path in scratch_path+128 ($480)
        ; First copy scratch_path until null
        ldx #0
_cs_cp_path
        lda scratch_path,x
        beq _cs_cp_path_done
        sta scratch_path+128,x
        inx
        bne _cs_cp_path
_cs_cp_path_done
        ; X = index into destination (after path)
        ; Now append the filename from the selected entry
        lda chooser_sel
        jsr get_entry_ptr_a         ; chooser_tmp -> entry

        ldy #0
_cs_cp_fname
        lda (chooser_tmp),y
        beq _cs_fname_done
        sta scratch_path+128,x
        inx
        iny
        cpy #ENTRY_NAME_MAX
        bcc _cs_cp_fname
_cs_fname_done
        stz scratch_path+128,x     ; null terminate

        ; Set pArg to scratch_path+128
        lda #<(scratch_path+128)
        sta pArg
        lda #>(scratch_path+128)
        sta pArg+1

        ; Set drive
        lda chooser_drive
        sta file_open_drive

        ; Clear entire chooser area (lines 10-49, full width, reset colors)
        jsr clear_chooser_area

        ; Position cursor and print launch message
        ldx #0
        ldy #CHOOSER_PATH_LINE
        jsr TermSetXY

        lda #<txt_launch
        ldx #>txt_launch
        jsr TermPUTS

        lda pArg
        ldx pArg+1
        jsr TermPUTS
        jsr TermCR

_cs_no_chdir
        ; Set up kernel events
        lda #<event_type
        sta kernel_args_events
        lda #>event_type
        sta kernel_args_events+1

        ; Try to open the file
        lda pArg
        ldx pArg+1
        jsr fopen
        bcc _cs_opened

        ; Primary open failed - try alternate extensions
        jsr alternate_open
        bcc _cs_opened

        ; Both failed - show error
        pha
        lda #<txt_error_open
        ldx #>txt_error_open
        jsr TermPUTS
        pla
        jsr TermPrintAH
        jsr TermCR
        jmp wait_for_key

_cs_opened
        ; Read first 4 bytes to identify file type
        lda #<temp0
        ldx #>temp0
        ldy #`temp0
        jsr set_write_address

        lda #4
        ldx #0
        ldy #0
        jsr fread

        pha
        jsr fclose
        pla

        cmp #4
        beq _cs_got4

        ; Read error
        pha
        lda #<txt_error_reading
        ldx #>txt_error_reading
        jsr TermPUTS
        pla
        jsr TermPrintAH
        jsr TermCR
        jmp wait_for_key

_cs_got4
        ; Build args table at scratch_path+120:
        ;   [arg0_lo, arg0_hi, arg1_lo, arg1_hi]
        ;   arg0 = pArg (absolute path, for loaders to re-open via get_arg)
        ;   arg1 = pArg+1 (skip leading /, relative path for launched program)
        ;
        ; This matches command-line behavior where the program receives
        ; a relative path like "lkdemo/lk.pgZ" not "/lkdemo/lk.pgZ"
        lda pArg
        sta scratch_path+120         ; arg[0] low (absolute)
        clc
        adc #1
        sta scratch_path+122         ; arg[1] low (skip leading /)
        lda pArg+1
        sta scratch_path+121         ; arg[0] high
        adc #0
        sta scratch_path+123         ; arg[1] high
        stz scratch_path+124         ; null terminator
        stz scratch_path+125

        ; kernel_args_ext = full table (for get_arg in loaders)
        lda #<(scratch_path+120)
        sta kernel_args_ext
        lda #>(scratch_path+120)
        sta kernel_args_ext+1

        ; args_buf = arg[1] entry (relative path, for launched program)
        ; +2 for null terminator so programs that scan for it find it
        lda #<(scratch_path+122)
        sta args_buf
        lda #>(scratch_path+122)
        sta args_buf+1
        lda #4                       ; 1 pointer + null terminator = 4 bytes
        sta args_buflen

        ; Set up deferred chdir for launchProgram (after file is loaded)
        lda kernel_Chdir
        cmp #$4C
        bne _cs_no_cd

        lda chooser_oldos
        bne _cs_set_root

        ; CD to chooser's current directory
        ; scratch_path still has the dir path (not clobbered yet)
        lda #<scratch_path
        sta chooser_chdir
        lda #>scratch_path
        sta chooser_chdir+1
        bra _cs_do_exec

_cs_set_root
        ; CD / mode: point to a "/" string
        lda #<_cs_root_path
        sta chooser_chdir
        lda #>_cs_root_path
        sta chooser_chdir+1
        bra _cs_do_exec

_cs_no_cd
        stz chooser_chdir
        stz chooser_chdir+1

_cs_do_exec
        jsr execute_file
        jmp wait_for_key

_cs_root_path .text "/",0

;--------------------------------------
; Left arrow - go to parent directory
;
_chooser_parent_dir
        ; Find the second-to-last '/' in scratch_path
        ; Path looks like "/foo/bar/" - we want to truncate to "/foo/"
        ; Special case: if path is just "/" do nothing.

        ; First check if we're at root "/"
        lda scratch_path
        cmp #'/'
        bne _pd_do_it           ; shouldn't happen, but handle gracefully
        lda scratch_path+1
        beq _pd_done            ; path is "/" with null -> at root, do nothing

_pd_do_it
        ; Scan to find the null terminator
        ldx #0
_pd_find_end
        lda scratch_path,x
        beq _pd_found_end
        inx
        bne _pd_find_end
_pd_found_end
        ; X = index of null terminator
        ; The trailing '/' is at X-1, skip it
        dex                     ; X now points at trailing '/'
        beq _pd_done            ; safety: if X was 1, path is "/", root

        ; Now scan backwards from X-1 to find the previous '/'
        dex
_pd_scan_back
        cpx #0
        beq _pd_truncate        ; reached start, truncate after position 0
        lda scratch_path,x
        cmp #'/'
        beq _pd_truncate
        dex
        bra _pd_scan_back

_pd_truncate
        ; X = index of the second-to-last '/'
        ; Truncate: keep the slash, null terminate after it
        inx
        stz scratch_path,x

        jsr chooser_read_dir
        jsr chooser_draw
        jmp chooser_loop

_pd_done
        jmp chooser_loop
