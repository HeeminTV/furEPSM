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

furEPSM_effChan = furEPSM_fmChan+furEPSM_ssgChan
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

		furEPSM_patLo: .dsb furEPSM_allChan
		furEPSM_patHi: .dsb furEPSM_allChan
		furEPSM_defaultChanDelay: .dsb furEPSM_allChan
		furEPSM_ChanDelay: .dsb furEPSM_allChan

		furEPSM_baseNote: .dsb furEPSM_effChan ; $00 = kill channel and set to $80, $01 = release, $02-$7F = note, $80 = nothing
		furEPSM_instrument: .dsb furEPSM_effChan ; bit 7 = instrument changed flag
		furEPSM_vol: .dsb furEPSM_effChan ; bit 7 = volume changed flag

		furEPSM_ssgVolEnvPtrLo: .dsb furEPSM_ssgChan
		furEPSM_ssgVolEnvPtrHi: .dsb furEPSM_ssgChan
		furEPSM_ssgVolEnvPos: .dsb furEPSM_ssgChan
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
		STY furEPSM_groovePos
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
		
		LDX #furEPSM_allChan-1
@clear1:
		LDA #-1
		STA furEPSM_defaultChanDelay,X
		LDA #1
		STA furEPSM_ChanDelay,X
		DEX
		BPL @clear1
		
		LDX #furEPSM_effChan-1
@clear2:
		LDA #0
		STA furEPSM_instrument,X
		LDA #$80
		STA furEPSM_baseNote,X
		DEX
		BPL @clear2
		
		STA furEPSM_songFlag
		
		JSR furEPSM_getSpeed
		LDA #0
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
		LDA furEPSM_delayTick
		BNE @no_seq_update
		
		LDX #furEPSM_allChan-1
@seq_loop:
		DEC furEPSM_ChanDelay,X
		BNE @skip_seq
		LDA furEPSM_defaultChanDelay,X
		STA furEPSM_ChanDelay,X
		JSR furEPSM_update_seq
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
		JSR furEPSM_getSpeed
		INC furEPSM_delayTick

@no_seq_update:
		DEC furEPSM_delayTick
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
		
		LDA #0
		STA furEPSM_currRow
		LDX #0
@loop:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_patLo,X
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_patHi,X
		INX
		CPX #furEPSM_allChan
		BNE @loop
		RTS
		
; =========================================================================================

furEPSM_getSpeed:
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
		
furEPSM_update_seq:
		LDA furEPSM_patLo,X
		STA furEPSM_temp_ptr+0
		LDA furEPSM_patHi,X
		STA furEPSM_temp_ptr+1

		LDA (furEPSM_temp_ptr),Y
		INY
		CMP #$80 ; INY ate negative flag :(
		BCS @effectloop
@notes:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_baseNote,X
		
		LDA (furEPSM_temp_ptr),Y ; Check if next command is a note (stop reading) or a command (continue reading)
		BPL @sequpdatedone
@effectloop:
		CMP #$C0
		BCS @delay
		INY

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
		BCC @effectloop ; always
		
@delay:
		INY
		AND #$3F
		ADC #1-1 ; carry is set
		STA furEPSM_defaultChanDelay,x
@sequpdatedone:
		TYA
		CLC
		ADC furEPSM_temp_ptr+0
		STA furEPSM_patLo,X
		LDA furEPSM_patHi
		ADC #0
		STA furEPSM_patHi
		RTS
		
@commandtbl:
		.WORD @eff_inst 			; $80
		.WORD @eff_vol 				; $81
		.WORD @eff_vibrato			; $82
		
@eff_inst:
		LDA (furEPSM_temp_ptr),Y
		INY
		ORA #$80
		STA furEPSM_instrument,X
		JMP @effret
		
@eff_vol:
		LDA (furEPSM_temp_ptr),Y
		INY
		ORA #$80
		STA furEPSM_vol,X
		JMP @effret
	
@eff_vibrato:
		LDA (furEPSM_temp_ptr),Y
		INY
		; TODO
		JMP @effret

; =========================================================================================

furEPSM_fnumTable:
		.WORD $269, $28E, $2B5, $2DE, $30A, $338, $369, $39D, $3D4, $40E, $44C, $48D

; =========================================================================================