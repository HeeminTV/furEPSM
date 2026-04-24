; =========================================================================================
;
; **USER SETTINGS**
;
; =========================================================================================

furEPSM_zp = $FC ; 6 bytes zero page variable
furEPSM_bss = $300 ; < 256 bytes of main variables

; Only `furEPSM_play` and `furEPSM_update` are public subroutines, other subroutines are furEPSM internal ones.

; =========================================================================================

enum furEPSM_zp
		furEPSM_temp_ptr: .dsb 2
		furEPSM_temp_ptr2: .dsb 2
		furEPSM_temp0: .dsb 1
		furEPSM_temp1: .dsb 1
ende

furEPSM_fmChan = 6
furEPSM_ssgChan = 3
furEPSM_rhythmChan = 1

furEPSM_allChan = furEPSM_fmChan+furEPSM_ssgChan+furEPSM_rhythmChan

enum furEPSM_bss
		furEPSM_framesPtr: .dsb 2
		furEPSM_frames: .dsb 1
		furEPSM_currFrame: .dsb 1
		furEPSM_rows: .dsb 1
		furEPSM_currRow: .dsb 1
		furEPSM_groovePtr: .dsb 2
		furEPSM_groovePos: .dsb 1
		furEPSM_delayTick: .dsb 1
		furEPSM_songFlag: .dsb 1 ; bit 7 = is song playing

		furEPSM_chanPatLo: .dsb furEPSM_allChan
		furEPSM_chanPatHi: .dsb furEPSM_allChan
		furEPSM_chanDefaultDelay: .dsb furEPSM_allChan
		furEPSM_chanDelay: .dsb furEPSM_allChan
		furEPSM_chanBaseNote: .dsb furEPSM_allChan ; $00 = kill the channel, $01 = release (does nothing in FM), $02-$7F = note

		furEPSM_fChanInst: .dsb furEPSM_fmChan ; bit 7 = instrument changed flag
		furEPSM_fChanVol: .dsb furEPSM_fmChan ; bit 7 = volume changed flag
		furEPSM_fChanBaseFLo: .dsb furEPSM_fmChan ; base note freq
		furEPSM_fChanBaseFHi: .dsb furEPSM_fmChan
		furEPSM_fChanBaseOct: .dsb furEPSM_fmChan
		furEPSM_fChanFLo: .dsb furEPSM_fmChan ; final register out
		furEPSM_fChanFHi: .dsb furEPSM_fmChan
		furEPSM_fChanOct: .dsb furEPSM_fmChan

		furEPSM_sChanVolEnvPtrLoLo: .dsb furEPSM_ssgChan
		furEPSM_sChanVolEnvPtrLoHi: .dsb furEPSM_ssgChan
		furEPSM_sChanVolEnvPos: .dsb furEPSM_ssgChan
ende

; =========================================================================================
;
; - furEPSM_play: Initialize driver with song
;     input: A = track number (starting from 0)
;     output:
;
; =========================================================================================

furEPSM_play:
		ASL
		TAX
		LDA furEPSM_header+0,X
		STA furEPSM_temp_ptr+0
		CLC
		ADC #2+1+1
		STA furEPSM_groovePtr+0
		LDA furEPSM_header+1,X
		STA furEPSM_temp_ptr+1
		ADC #0
		STA furEPSM_groovePtr+1
		
		JSR furEPSM_silenceChannels

		LDY #0
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_framesPtr+0
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_framesPtr+1
		
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_frames
		
		LDA (furEPSM_temp_ptr),Y
		STA furEPSM_rows
		
		LDA #$80
		STA furEPSM_songFlag
		
		LDA #0 ; note off
		LDX #furEPSM_allChan-1
@clear1:
		STA furEPSM_chanBaseNote,X
		DEX
		BPL @clear1
		
		LDX #furEPSM_fmChan-1
@clear2:
		LDA #0
		STA furEPSM_fChanInst,X
		LDA #$7F
		STA furEPSM_fChanVol,X
		DEX
		BPL @clear2

		LDA #1
		STA furEPSM_delayTick
		LDA #0
		STA furEPSM_groovePos
		JMP furEPSM_loadFrame

; =========================================================================================
;
; - furEPSM_update: Update sequences, EPSM registers
;     input:
;     output: X=0
;
; =========================================================================================

furEPSM_update:
		BIT furEPSM_songFlag
		BMI @is_play
		RTS
@is_play:
		DEC furEPSM_delayTick
		BNE @no_seq_update
		
		LDX #furEPSM_allChan-furEPSM_rhythmChan-1
@seq_loop:
		DEC furEPSM_chanDelay,X
		BNE @skip_seq
		LDA furEPSM_chanDefaultDelay,X
		STA furEPSM_chanDelay,X
		JSR furEPSM_updateSeq
@skip_seq:
		DEX
		BPL @seq_loop
		
		INC furEPSM_currRow
		LDA furEPSM_currRow
		CMP furEPSM_rows
		BNE @no_next_frame
		INC furEPSM_currFrame
		LDA furEPSM_currFrame
		CMP furEPSM_frames
		BNE @no_frame_wrap
		LDA #0
@no_frame_wrap:
		JSR furEPSM_loadFrame
@no_next_frame:
		JSR furEPSM_updateSpeed
@no_seq_update:
		JSR furEPSM_updatePitch
		JSR furEPSM_updateRegFM
		; JSR furEPSM_updateRegSSG
		RTS

; =========================================================================================

furEPSM_silenceChannels:
		LDA #$28
		LDX #6
; Kill EPSM
@loop1:
		STA $401C
		STX $401D
		DEX
		BPL @loop1
	
; Kill SSG
		LDA #0
		LDX #8
		STX $401C
		STA $401D
		INX
		STX $401C
		STA $401D
		INX
		STX $401C
		STA $401D
		
		LDX #$20
		STX $401C
		STA $401D
		
		LDA #$29 ; Enable 6 channels
		STA $401C
		LDA #$80
		STA $401D
		RTS
		
; =========================================================================================

furEPSM_loadFrame:
		STA furEPSM_currFrame
		ASL
		TAY

		LDA furEPSM_framesPtr+0
		STA furEPSM_temp_ptr+0
		LDA furEPSM_framesPtr+1
		STA furEPSM_temp_ptr+1

		LDA (furEPSM_temp_ptr),Y
		INY
		PHA
		LDA (furEPSM_temp_ptr),Y
		STA furEPSM_temp_ptr+1
		PLA
		STA furEPSM_temp_ptr+0

		LDX #0 
		STX furEPSM_currRow
		LDY #0
@loop1:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_chanPatLo,X
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_chanPatHi,X
		INX
		CPX #furEPSM_allChan
		BNE @loop1
		
		; LDX #furEPSM_allChan-1
@loop2:
		LDA #-1
		STA furEPSM_chanDefaultDelay-1,X
		LDA #1
		STA furEPSM_chanDelay-1,X
		DEX
		BNE @loop2
		RTS
		
; =========================================================================================

furEPSM_updateSpeed:
		LDA furEPSM_groovePtr+0
		STA furEPSM_temp_ptr+0
		LDA furEPSM_groovePtr+1
		STA furEPSM_temp_ptr+1
		
		LDY furEPSM_groovePos
		
		LDA (furEPSM_temp_ptr),Y
		CMP #$FF
		BNE @not_grooveloop
		LDA #-1
		STA furEPSM_groovePos
		LDY #0
		LDA (furEPSM_temp_ptr),Y
@not_grooveloop:
		STA furEPSM_delayTick
		INC furEPSM_groovePos
		RTS
		
; =========================================================================================
;
; **COMMAND INTERPRITTER**
;
; =========================================================================================
		
furEPSM_updateSeq:
		LDA furEPSM_chanPatLo,X
		STA furEPSM_temp_ptr+0
		LDA furEPSM_chanPatHi,X
		STA furEPSM_temp_ptr+1
		
		LDY #0

		LDA (furEPSM_temp_ptr),Y
		INY
		CMP #$80 ; INY ate negative flag :(
		BCS @effectloop
@notes:
		STA furEPSM_chanBaseNote,X
		
		LDA (furEPSM_temp_ptr),Y ; Check if next command is a note (stop reading) or a command (continue reading)
		BPL @sequpdatedone
		INY
@effectloop:
		CMP #$C0
		BCS @delay

		PHA
		AND #$1F
		ASL
		STY furEPSM_temp0
		TAY
		LDA @commandtbl+0,Y
		STA furEPSM_temp_ptr2+0
		LDA @commandtbl+1,Y
		STA furEPSM_temp_ptr2+1
		LDY furEPSM_temp0
		JMP (furEPSM_temp_ptr2)
@effret:
		PLA
		CMP #$A0
		BCS @sequpdatedone
		LDA (furEPSM_temp_ptr),Y
		INY
		BCC @effectloop ; always
		
@delay:
		CMP #$FF ; no single note / effects in this frame
		BEQ @framelock
		AND #$3F
		ADC #1 ; carry is clear
@framelock:
		STA furEPSM_chanDelay,X
		STA furEPSM_chanDefaultDelay,x
@sequpdatedone:
		TYA
		CLC
		ADC furEPSM_temp_ptr+0
		STA furEPSM_chanPatLo,X
		LDA furEPSM_chanPatHi
		ADC #0
		STA furEPSM_chanPatHi
		RTS
		
@commandtbl:
		.WORD @eff_inst 			; $80
		.WORD @eff_vol 				; $81
		.WORD @eff_vibrato			; $82
		
@eff_inst:
		LDA (furEPSM_temp_ptr),Y
		INY
		ORA #$80
		STA furEPSM_fChanInst,X
		JMP @effret
		
@eff_vol:
		LDA (furEPSM_temp_ptr),Y
		INY
		ORA #$80
		STA furEPSM_fChanVol,X
		JMP @effret
	
@eff_vibrato:
		LDA (furEPSM_temp_ptr),Y
		INY
		; TODO
		JMP @effret
		
; =========================================================================================

furEPSM_updatePitch:
		LDX #furEPSM_fmChan-1
@getbasefreq:
		LDA furEPSM_chanBaseNote,X
		BEQ @noteoff
		JSR furEPSM_getBaseFNum
		LDA furEPSM_temp_ptr2+0
		STA furEPSM_fChanBaseFLo,X
		LDA furEPSM_temp_ptr2+1
		STA furEPSM_fChanBaseFHi,X
		LDA furEPSM_temp0
		STA furEPSM_fChanBaseOct,X
@noteoff:
		DEX
		BPL @getbasefreq
		
		LDX #furEPSM_fmChan-1
@applyfreq:
		LDA furEPSM_fChanBaseFLo,X
		STA furEPSM_fChanFLo,X
		LDA furEPSM_fChanBaseFHi,X
		STA furEPSM_fChanFHi,X
		LDA furEPSM_fChanBaseOct,X
		STA furEPSM_fChanOct,X
		DEX
		BPL @applyfreq
		RTS

furEPSM_getBaseFNum: ; A = note
		STY furEPSM_temp1

		SEC
		SBC #2
		TAY
		LDA #0
		STA furEPSM_temp0
		TYA
@getmod:
		CMP #12
		BCC @ret
		SBC #12
		INC furEPSM_temp0
@ret:
		ASL
		TAY
		LDA furEPSM_fnumTable+0,Y
		STA furEPSM_temp_ptr2+0
		LDA furEPSM_fnumTable+1,Y
		STA furEPSM_temp_ptr2+1
		
		LDY furEPSM_temp1
		RTS

; =========================================================================================

furEPSM_updateRegFM:
		LDX #furEPSM_fmChan
@loop:
		LDY @chanregoffsettbl,X ; $401C,$401D / $401E,$401F

		LDA #$28
		STA $401C

		LDA furEPSM_chanBaseNote,X
		BNE @not_noteoff ; $00 = note cut
; Note off
		LDA @keyOnRegTbl,X
		STA $401D
		BPL @dont_enable_key ; always
@not_noteoff:
		; TODO : release notes?
		LDA @keyOnRegTbl,X
		ORA #$F0
		STA $401D
@dont_enable_key:
		LDA furEPSM_fChanInst,X
		BPL @noinstchange
		AND #$7F
		STA furEPSM_fChanInst,X
		JSR furEPSM_uploadFMPatch
@noinstchange:
		LDA @A0RegTbl,X
		STA $401C,Y
		LDA furEPSM_fChanFLo,X
		STA $401D,Y
		
		LDA @A4RegTbl,X
		STA $401C,Y
		LDA furEPSM_fChanOct,X
		ASL
		ASL
		ASL
		STA furEPSM_temp0
		LDA furEPSM_fChanFHi,X
		ORA furEPSM_temp0
		STA $401D,Y
		
		DEX
		BPL @loop
		RTS

@chanregoffsettbl:
		.BYTE 2, 2, 2, 0, 0, 0
		
@keyOnRegTbl:
		.BYTE $00, $01, $02, $04, $05, $06
		
@A0RegTbl:
		.BYTE $A0, $A1, $A2, $A0, $A1, $A2	
@A4RegTbl:
		.BYTE $A4, $A5, $A6, $A4, $A5, $A6

; =========================================================================================
;
; - FM patch data format
;     REG $B0/$B1/$B2, REG $B4/$B5/$B6
;     REG $30-$3E, REG $40-$4E, REG $50-$5E, REG $60-$6E, REG $70-$7E, REG $80-$8E, REG $90-$9E for OP1
;     REG $30-$3E, REG $40-$4E, REG $50-$5E, REG $60-$6E, REG $70-$7E, REG $80-$8E, REG $90-$9E for OP3
;     REG $30-$3E, REG $40-$4E, REG $50-$5E, REG $60-$6E, REG $70-$7E, REG $80-$8E, REG $90-$9E for OP2
;     REG $30-$3E, REG $40-$4E, REG $50-$5E, REG $60-$6E, REG $70-$7E, REG $80-$8E, REG $90-$9E for OP4
;
; =========================================================================================

MACRO furEPSM_loadEPSM regoffset
		LDY #0
		STY furEPSM_temp0

		LDA furEPSM_B0RegTbl,X
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_B4RegTbl,X
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		ORA #$C0 ; TODO : panning
		STA $401D+regoffset
		
		CLC
@oploop:
		LDA furEPSM_30RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_40RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_50RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_60RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_70RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_80RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_90RegTbl,X
		ADC furEPSM_temp0
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_temp0
		ADC #4
		STA furEPSM_temp0
		CMP #16
		BNE @oploop
		PLA
		TAY
		RTS
ENDM
		
furEPSM_uploadFMPatch:
		TYA
		PHA
		LDA furEPSM_fChanInst,X
		ASL
		TAY
		LDA furEPSM_instptr+0,Y
		STA furEPSM_temp_ptr+0
		LDA furEPSM_instptr+1,Y
		STA furEPSM_temp_ptr+1

		CPX #3
		; BNE @secondbank
		BEQ @firstbank
		JMP @secondbank
@firstbank:
		furEPSM_loadEPSM 0
@secondbank:
		furEPSM_loadEPSM +2
		
furEPSM_B0RegTbl:
		.BYTE $B0, $B1, $B2, $B0, $B1, $B2
		
furEPSM_B4RegTbl:
		.BYTE $B4, $B5, $B6, $B4, $B5, $B6

furEPSM_30RegTbl:
		.BYTE $30, $31, $32, $30, $31, $32
furEPSM_40RegTbl:
		.BYTE $40, $41, $42, $40, $41, $42
furEPSM_50RegTbl:
		.BYTE $50, $51, $52, $50, $51, $52
furEPSM_60RegTbl:
		.BYTE $60, $61, $62, $60, $61, $62
furEPSM_70RegTbl:
		.BYTE $70, $71, $72, $70, $71, $72
furEPSM_80RegTbl:
		.BYTE $80, $81, $82, $80, $81, $82
furEPSM_90RegTbl:
		.BYTE $90, $91, $92, $90, $91, $92
		
; =========================================================================================

furEPSM_fnumTable:
		.WORD $269, $28E, $2B5, $2DE, $30A, $338, $369, $39D, $3D4, $40E, $44C, $48D

; =========================================================================================