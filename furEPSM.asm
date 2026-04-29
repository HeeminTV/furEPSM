; =========================================================================================
;
; **USER SETTINGS**
;
; =========================================================================================

furEPSM_zp = $FB ; 5 bytes zero page variable
furEPSM_bss = $300 ; < 256 bytes of main variables

furEPSM_TEMPOCONSTANT = 3600 ; 3600 = NTSC, 3000 = PAL
furEPSM_DISABLESSG = 0 ; 1 to disable SSG channels

; Only `furEPSM_play` and `furEPSM_update` are public subroutines, other subroutines are furEPSM internal ones.
; (You may want to call `furEPSM_silenceChannels` at RESET as initialization process but it's optional)	

; =========================================================================================

enum furEPSM_zp
		furEPSM_temp_ptr: .dsb 2
		furEPSM_temp_ptr2: .dsb 2
		furEPSM_temp: .dsb 1
ende

furEPSM_fmChan = 6
furEPSM_ssgChan = 3*(1-furEPSM_DISABLESSG)

furEPSM_allChan = furEPSM_fmChan+furEPSM_ssgChan

enum furEPSM_bss
		furEPSM_framesPtr: .dsb 2
		furEPSM_frames: .dsb 1
		furEPSM_currFrame: .dsb 1
		furEPSM_rowCount: .dsb 1
		furEPSM_rowCountReload: .dsb 1
		furEPSM_speed: .dsb 1
		furEPSM_tempo: .dsb 1
		furEPSM_tempoDec: .dsb 2
		furEPSM_tempoAcc: .dsb 2
		furEPSM_tempoCnt: .dsb 2
		furEPSM_tempoRem: .dsb 1
		furEPSM_delayTick: .dsb 1
		furEPSM_songFlag: .dsb 1 ; bit 7 = is song playing, bit 6 = stop command occured
		furEPSM_jumpFrame: .dsb 1 ; $FF = no jump

		furEPSM_chanPtrLo: .dsb furEPSM_allChan
		furEPSM_chanPtrHi: .dsb furEPSM_allChan
		furEPSM_chanDefaultDelay: .dsb furEPSM_allChan
		furEPSM_chanDelay: .dsb furEPSM_allChan
		furEPSM_chanBaseNote: .dsb furEPSM_allChan ; $00-$7D = note
		furEPSM_chanStatus: .dsb furEPSM_allChan
		furEPSM_chanInst: .dsb furEPSM_allChan ; bit 7 = instrument changed flag
		furEPSM_chanVol: .dsb furEPSM_allChan ; bit 7 = volume changed flag
		
; EDxx
		furEPSM_effDelayTimer: .dsb furEPSM_allChan ; $00 = no delay (obviously lol)
		furEPSM_effDelayDelayedRowPtrLo: .dsb furEPSM_allChan
		furEPSM_effDelayDelayedRowPtrHi: .dsb furEPSM_allChan
; E5xx
		furEPSM_effPitchOffset: .dsb furEPSM_allChan
		
		furEPSM_fmPanL: .dsb 1 ; xx123456
		furEPSM_fmPanR: .dsb 1
		furEPSM_fmPanChanged: .dsb 1

		furEPSM_sChanVolEnvPos: .dsb furEPSM_ssgChan
		furEPSM_sChanFreqLo: .dsb furEPSM_ssgChan ; final register out
		furEPSM_sChanFreqHi: .dsb furEPSM_ssgChan
		furEPSM_sChanVol: .dsb furEPSM_ssgChan
ende

enum 0 ; must be in order
		furEPSM_CHANSTAT_NOTECUT: .dsb 1
		furEPSM_CHANSTAT_NOTERELEASE: .dsb 1

		furEPSM_CHANSTAT_NONE: .dsb 1
		furEPSM_CHANSTAT_NEWNOTE: .dsb 1
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
		LDA furEPSM_header+1,X
		STA furEPSM_temp_ptr+1
		
		JSR furEPSM_silenceChannels

		LDY #0
		STY furEPSM_fmPanChanged
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
		INY
		STA furEPSM_rowCountReload
		
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_speed
		
		LDA (furEPSM_temp_ptr),Y
		STA furEPSM_tempo
		
		LDA #$80
		STA furEPSM_songFlag

		LDX #furEPSM_allChan-1
@clear1:
		LDA #0
		STA furEPSM_chanBaseNote,X
		STA furEPSM_effDelayTimer,X
		STA furEPSM_effPitchOffset,X

		LDA #furEPSM_CHANSTAT_NOTECUT
		STA furEPSM_chanStatus,X

		LDA #$7F
		STA furEPSM_chanInst,X
		STA furEPSM_chanVol,X

		DEX
		BPL @clear1
		STX furEPSM_jumpFrame
		STX furEPSM_fmPanL
		STX furEPSM_fmPanR
		
		LDA #<furEPSM_TEMPOCONSTANT
		STA furEPSM_tempoDec+0
		LDA #>furEPSM_TEMPOCONSTANT
		STA furEPSM_tempoDec+1
		
		JSR furEPSM_calculateSpeed+2

		LDA #1
		STA furEPSM_delayTick
		LDA #0
		JMP furEPSM_loadFrame

; =========================================================================================
;
; - furEPSM_update: Update sequences, EPSM registers
;     input:
;     output: X=$FF
;
; =========================================================================================

furEPSM_update:
		BIT furEPSM_songFlag
		BMI @is_play
		JMP furEPSM_silenceChannels
@is_play:
; Process delayed rows
		LDX #furEPSM_allChan-1
@delayed_row_loop:
		LDA furEPSM_effDelayTimer,X
		BEQ @no_delay_row
		DEC furEPSM_effDelayTimer,X
		BNE @no_delay_row
		
		LDA furEPSM_chanPtrLo,X
		PHA
		LDA furEPSM_chanPtrHi,X
		PHA

		LDA furEPSM_effDelayDelayedRowPtrLo,X
		STA furEPSM_temp_ptr+0
		LDA furEPSM_effDelayDelayedRowPtrHi,X
		JSR furEPSM_updateSeq+8
		
		PLA
		STA furEPSM_chanPtrHi,X
		PLA
		STA furEPSM_chanPtrLo,X
@no_delay_row:
		DEX
		BPL @delayed_row_loop

		LDA furEPSM_tempoAcc+1
		BMI @do_seq_update
		ORA furEPSM_tempoAcc+0
		BNE @no_seq_update
@do_seq_update:
		BIT furEPSM_songFlag ; check if `eff_end` was occured in previous row
		BVC @no_stop_command
		LDA furEPSM_songFlag
		AND #%00111111
		STA furEPSM_songFlag
		JMP furEPSM_silenceChannels
@no_stop_command:

		LDX #furEPSM_allChan-1
@seq_loop:
		DEC furEPSM_chanDelay,X
		BNE @skip_seq
		LDA furEPSM_chanDefaultDelay,X
		STA furEPSM_chanDelay,X
		JSR furEPSM_updateSeq
@skip_seq:
		DEX
		BPL @seq_loop
		
		CPX furEPSM_jumpFrame ; if furEPSM_jumpFrame == $FF
		BEQ @no_jumpframe_specified
		LDA furEPSM_jumpFrame
		BCC @jumpframe ; always
@no_jumpframe_specified:
		TXA
		DCP furEPSM_rowCount
		BNE @no_next_frame
		INC furEPSM_currFrame
		LDA furEPSM_currFrame
@jumpframe:
		CMP furEPSM_frames
		BCC @no_frame_wrap
		LDA #0
@no_frame_wrap:
		JSR furEPSM_loadFrame
@no_next_frame:
		
		LDA furEPSM_tempoAcc+0
		CLC
		ADC furEPSM_tempoDec+0
		STA furEPSM_temp_ptr+0
		LDA furEPSM_tempoAcc+1
		ADC furEPSM_tempoDec+1
		STA furEPSM_temp_ptr+1

		LDA furEPSM_temp_ptr+0
		SEC
		SBC furEPSM_tempoRem
		STA furEPSM_tempoAcc+0
		LDA furEPSM_temp_ptr+1
		SBC #0
		STA furEPSM_tempoAcc+1

@no_seq_update:
		LDA furEPSM_tempoAcc+0
		SEC
		SBC furEPSM_tempoCnt+0
		STA furEPSM_tempoAcc+0
		LDA furEPSM_tempoAcc+1
		SBC furEPSM_tempoCnt+1
		STA furEPSM_tempoAcc+1

IF (!furEPSM_DISABLESSG)
		JSR furEPSM_updatePitchSSG
		JSR furEPSM_updateVolSSG
		JSR furEPSM_updateRegSSG
ENDIF
		JMP furEPSM_updateRegFM

; =========================================================================================
;
; - furEPSM_silenceChannels: Silence all EPSM CHANNELS
;     input:
;     output:
;
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
		
		LDA #7
		STA $401C
		LDA #$38
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
		
		LDA furEPSM_rowCountReload
		STA furEPSM_rowCount

		LDA (furEPSM_temp_ptr),Y
		INY
		PHA
		LDA (furEPSM_temp_ptr),Y
		STA furEPSM_temp_ptr+1
		PLA
		STA furEPSM_temp_ptr+0

		LDX #0 
		LDY #0
@loop1:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_chanPtrLo,X
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_chanPtrHi,X
		INX
		CPX #furEPSM_allChan
		BNE @loop1
		
		; LDX #furEPSM_allChan-1
@loop2:
		LDA #255
		STA furEPSM_chanDefaultDelay-1,X
		LDA #1
		STA furEPSM_chanDelay-1,X
		DEX
		BNE @loop2
		RTS
		
; =========================================================================================

furEPSM_calculateSpeed:
		STX furEPSM_temp

		LDA furEPSM_tempo
		STA furEPSM_tempoCnt+0
		ASL
		ROL furEPSM_tempoCnt+1
		CLC
		ADC furEPSM_tempoCnt+0
		STA furEPSM_tempoCnt+0
		LDA furEPSM_tempoCnt+1
		AND #1
		ADC #0
		ASL furEPSM_tempoCnt+0
		ROL
		ASL furEPSM_tempoCnt+0
		ROL
		ASL furEPSM_tempoCnt+0
		ROL
		STA furEPSM_tempoCnt+1

		LDX #16
		LDA #0
		STA furEPSM_tempoAcc+0
		STA furEPSM_tempoAcc+1
@divloop:
		ASL furEPSM_tempoCnt+0
		ROL furEPSM_tempoCnt+1
		ROL
		CMP furEPSM_speed
		BCC @skip
		SBC furEPSM_speed ; carry is set
		INC furEPSM_tempoCnt+0
@skip:
		DEX
		BNE @divloop
		STA furEPSM_tempoRem

		LDX furEPSM_temp
		RTS
		
; =========================================================================================
;
; **COMMAND INTERPRITTER**
;
; =========================================================================================
		
furEPSM_updateSeq:
		LDA furEPSM_chanPtrLo,X
		STA furEPSM_temp_ptr+0
		LDA furEPSM_chanPtrHi,X
		STA furEPSM_temp_ptr+1
		
		LDY #0
@readloop:
		LDA (furEPSM_temp_ptr),Y
		BMI @effect
@notes:
		INY
		CMP #2 ; note cut / note release
		BCC @misc
		SBC #2 ; carry is set
		STA furEPSM_chanBaseNote,X
		LDA #furEPSM_CHANSTAT_NEWNOTE
@misc:
		STA furEPSM_chanStatus,X
		JMP @sequpdatedone

@effect:
		INY
		CMP #$C0
		BCS @somethingelse

		PHA
		AND #$1F
		STY furEPSM_temp
		TAY
		LDA @commandtbl_lsb,Y
		STA furEPSM_temp_ptr2+0
		LDA @commandtbl_msb,Y
		STA furEPSM_temp_ptr2+1
		LDY furEPSM_temp
		JMP (furEPSM_temp_ptr2)

@effret:
		PLA
		CMP #$A0
		BCC @readloop
@sequpdatedone:
		TYA
		CLC
		ADC furEPSM_temp_ptr+0
		STA furEPSM_chanPtrLo,X
		LDA furEPSM_chanPtrHi,X
		ADC #0
		STA furEPSM_chanPtrHi,X
		RTS
		
; ------------------------------------------------
		
@somethingelse:
		CMP #$E0
		BCS @delay
; quick instrument change
		AND #$1F
		CMP furEPSM_chanInst,X
		BEQ @skipsetflag4
		ORA #$80
		STA furEPSM_chanInst,X
@skipsetflag4:
		JMP @readloop

@delay:
		CMP #$FF ; no single note / effects in this frame
		BEQ @framelock
		AND #$1F
		ADC #1 ; carry is clear
@framelock:
		STA furEPSM_chanDefaultDelay,x
		STA furEPSM_chanDelay,X
		JMP @sequpdatedone
	
; =========================================================================================
;
; **EFFECTS**
;
; =========================================================================================
		
@commandtbl_lsb:
		.DL @eff_inst 				; $80
		.DL @eff_vol 				; $81
		.DL @eff_maxvol				; $82
		.DL @eff_vibrato			; $83

		.DL @eff_nextframe			; $84
		.DL @eff_jumpframe			; $85
		.DL @eff_end				; $86
		.DL @eff_set_delay			; $87
		
		.DL @eff_speed				; $88
		.DL @eff_tempo				; $89
		.DL @eff_rowdelay			; $8A
		.DL @eff_pitchoffset		; $8B
		
		.DL @eff_pan				; $8C

@commandtbl_msb:
		.DH @eff_inst 				; $80
		.DH @eff_vol 				; $81
		.DH @eff_maxvol				; $82
		.DH @eff_vibrato			; $83

		.DH @eff_nextframe			; $84
		.DH @eff_jumpframe			; $85
		.DH @eff_end				; $86
		.DH @eff_set_delay			; $87
		
		.DH @eff_speed				; $88
		.DH @eff_tempo				; $89
		.DH @eff_rowdelay			; $8A
		.DH @eff_pitchoffset		; $8B
		
		.DH @eff_pan				; $8C
		
; ------------------------------------------------

@eff_inst:
		LDA (furEPSM_temp_ptr),Y
		INY
		CMP furEPSM_chanInst,X
		BEQ @skipsetflag
		ORA #$80
		STA furEPSM_chanInst,X
@skipsetflag:
		JMP @effret

; ------------------------------------------------
	
@eff_vol:
		LDA (furEPSM_temp_ptr),Y
		INY
		CMP furEPSM_chanVol,X
		BEQ @skipsetflag2
		ORA #$80
		STA furEPSM_chanVol,X
@skipsetflag2:
		JMP @effret

; ------------------------------------------------

@eff_maxvol:
		LDA #$7F
		CMP furEPSM_chanVol,X
		BEQ @skipsetflag3
		ORA #$80
		STA furEPSM_chanVol,X
@skipsetflag3:
		JMP @effret
	
; ------------------------------------------------

@eff_vibrato:
		LDA (furEPSM_temp_ptr),Y
		INY
		; TODO
		JMP @effret
		
; ------------------------------------------------
		
@eff_nextframe:
		LDA furEPSM_currFrame
		CLC
		ADC #1
@frameexceedcheck:
		CMP furEPSM_frames
		BCC @not_frameexceed
		LDA #0
@not_frameexceed:
		STA furEPSM_jumpFrame
		JMP @effret
		
; ------------------------------------------------

@eff_jumpframe:
		LDA (furEPSM_temp_ptr),Y
		INY
		BNE @frameexceedcheck ; always
		
; ------------------------------------------------

@eff_end:
		LDA furEPSM_songFlag
		ORA #$40
		STA furEPSM_songFlag
		JMP @effret
		
; ------------------------------------------------

@eff_set_delay:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_chanDefaultDelay,x
		STA furEPSM_chanDelay,X
		JMP @effret
		
; ------------------------------------------------

@eff_speed:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_speed
		JSR furEPSM_calculateSpeed
		JMP @effret

; ------------------------------------------------

@eff_tempo:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_tempo
		JSR furEPSM_calculateSpeed
		JMP @effret
		
; ------------------------------------------------

@eff_rowdelay:
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_effDelayTimer,X
		
		TYA
		CLC
		ADC furEPSM_temp_ptr+0
		STA furEPSM_effDelayDelayedRowPtrLo,X
		LDA furEPSM_temp_ptr+1
		ADC #0
		STA furEPSM_effDelayDelayedRowPtrHi,X
		
		PLA
		CMP #$A0
		BCS @found ; next byte is next row's location

@find_next_row: ; has to find next row's location. kinda like small interpritter.
		LDA (furEPSM_temp_ptr),Y
		STA furEPSM_temp
		INY
		LDA furEPSM_temp
		BPL @found ; note
		CMP #$E0
		BCS @found ; 1-byte delay
		CMP #$C0
		BCS @find_next_row ; quick instrument change
; otherwise it should figure out if it's one byte command or two bytes
		PHA
		AND #$1F
		STY furEPSM_temp
		TAY
		LDA @commandtbl_lsb,Y
		STA furEPSM_temp_ptr2+0
		LDA @commandtbl_msb,Y
		STA furEPSM_temp_ptr2+1
		LDY #0
		LDA (furEPSM_temp_ptr2),Y
		LDY furEPSM_temp
		CMP #$B1 ; check if it's `LDA (zp),Y`, which indicates two byte command.
		BNE @not_twobyte
		INY
@not_twobyte:
		PLA
		CMP #$A0 ; was the command terminating channel read?
		BCC @find_next_row ; otherwise read next command
@found:
		JMP @sequpdatedone
		
; ------------------------------------------------
		
@eff_pitchoffset:
		LDA (furEPSM_temp_ptr),Y
		INY
		SEC
		SBC #$80
		PHA
		ASL ; msb -> c
		PLA
		ROR ; bit 7 = c
		STA furEPSM_effPitchOffset,X
		JMP @effret
		
; ------------------------------------------------

@eff_pan:
		LDA (furEPSM_temp_ptr),Y ; 2-byte commands **have** to start with `LDA (zp),Y` instruction
		LDA furEPSM_panORTbl,X
		ORA furEPSM_fmPanChanged
		STA furEPSM_fmPanChanged

		LDA furEPSM_fmPanL
		AND furEPSM_panANDTbl,X
		STA furEPSM_fmPanL
		LDA furEPSM_fmPanR
		AND furEPSM_panANDTbl,X
		STA furEPSM_fmPanR
		LDA (furEPSM_temp_ptr),Y
		INY
		LSR
		BCC @no_set_r
		PHA
		LDA furEPSM_fmPanR
		ORA furEPSM_panORTbl,X
		STA furEPSM_fmPanR
		PLA
@no_set_r:
		LSR
		BCC @no_set_l
		LDA furEPSM_fmPanL
		ORA furEPSM_panORTbl,X
		STA furEPSM_fmPanL
@no_set_l:
		JMP @effret

; =========================================================================================

furEPSM_updateRegFM:
		LDX #furEPSM_fmChan-1
@loop:
		LDY @chanregoffsettbl,X ; $401C,$401D / $401E,$401F

		LDA furEPSM_chanInst,X
		BPL @noinstchange
		AND #$7F
		STA furEPSM_chanInst,X
		LDA furEPSM_fmPanChanged ; force panning update
		ORA furEPSM_panORTbl,X
		STA furEPSM_fmPanChanged
		LDA furEPSM_chanVol,X ; force volume update
		ORA #$80
		STA furEPSM_chanVol,X
		JSR furEPSM_uploadFMPatch
@noinstchange:
		LDA furEPSM_fmPanChanged
		AND furEPSM_panORTbl,X
		BEQ @nopanchange
		LDA furEPSM_fmPanChanged
		AND furEPSM_panANDTbl,X
		STA furEPSM_fmPanChanged
		JSR furEPSM_updatePan
@nopanchange:
		LDA furEPSM_chanVol,X
		BPL @novolchange
		AND #$7F
		STA furEPSM_chanVol,X
		JSR furEPSM_updateTL
@novolchange:

		LDA #$28 ; KEYON
		STA $401C
		
		LDA furEPSM_chanStatus,X
		CMP #furEPSM_CHANSTAT_NEWNOTE
		BNE @not_new_note
		LDA #furEPSM_CHANSTAT_NONE
		STA furEPSM_chanStatus,X

		LDA @keyOnRegTbl,X
		AND #$0F
		STA $401D
		TXA
		LDX #5
@wait:
		DEX
		BNE @wait
		TAX
		BPL @turn_on_key ; always

@not_new_note:
		CMP #furEPSM_CHANSTAT_NOTECUT
		BNE @turn_on_key
; Note off
		LDA @keyOnRegTbl,X
		AND #$0F
		STA $401D
		BPL @update_pitch ; always
@turn_on_key:
		LDA @keyOnRegTbl,X
		STA $401D
@update_pitch:
; Update pitch
		LDA @A4RegTbl,X
		STA $401C,Y
		STY furEPSM_temp_ptr+0 ; save Y

		LDA furEPSM_effPitchOffset,X
		AND #$80
		TAY
		LDA @getmod-1,Y
		STA furEPSM_temp_ptr+1 ; top 3 bits of furEPSM_effPitchOffset

		LDA furEPSM_chanBaseNote,X
		CLC
		ADC #9
		LDY #0
@getmod:
		CMP #12
		BCC @ret
		SBC #12 ; carry is set
		INY
		BNE @getmod ; always
@ret:
		STY furEPSM_temp_ptr2+0 ; block
		TAY

		LDA furEPSM_fnumTblLo,Y
		ADC furEPSM_effPitchOffset,X ; carry is clear
		STA furEPSM_temp_ptr2+1 ; fnum Low
		LDA furEPSM_fnumTblHi,Y
		ADC furEPSM_temp_ptr+1 ; top 3 bits of furEPSM_effPitchOffset
		AND #7
		STA furEPSM_temp
		LDA furEPSM_temp_ptr2+0 ; block
		ASL
		ASL
		ASL
		ORA furEPSM_temp
		LDY furEPSM_temp_ptr+0 ; restore Y
		STA $401D,Y
		
		LDA @A0RegTbl,X
		STA $401C,Y
		LDA furEPSM_temp_ptr2+1 ; fnum Low
		STA $401D,Y
		
		DEX
		BMI @loopend
		JMP @loop
@loopend:
		RTS

@chanregoffsettbl:
		.BYTE 0, 0, 0, 2, 2, 2
		
@keyOnRegTbl:
		.BYTE $F0, $F1, $F2, $F4, $F5, $F6
		
@A0RegTbl:
		.BYTE $A0, $A1, $A2, $A0, $A1, $A2	
@A4RegTbl:
		.BYTE $A4, $A5, $A6, $A4, $A5, $A6

.org @getmod-1+128
		.BYTE $07

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

MACRO furEPSM_loadEPSMPatch regoffset
		LDY #0
		STY furEPSM_temp

		LDA furEPSM_B0RegTbl,X
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_B4RegTbl,X
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		CLC
@oploop:
		LDA furEPSM_30RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_40RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_50RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_60RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_70RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_80RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_90RegTbl,X
		ADC furEPSM_temp
		STA $401C+regoffset
		LDA (furEPSM_temp_ptr),Y
		INY
		STA $401D+regoffset
		
		LDA furEPSM_temp
		ADC #4
		STA furEPSM_temp
		CMP #16
		BNE @oploop
		PLA
		TAX
		PLA
		TAY
		RTS
ENDM
		
furEPSM_uploadFMPatch:
		TYA
		PHA
		JSR furEPSM_loadInstPtr

		TXA
		PHA
		CPX #3
		BCC @firstbank
		JMP @secondbank
@firstbank:
		furEPSM_loadEPSMPatch 0
@secondbank:
		AXS #3 ; cap the X range to 0-2
		furEPSM_loadEPSMPatch +2
		
furEPSM_updatePan:
		STY furEPSM_temp_ptr2+0 ; y saver
		
		LDA furEPSM_B4RegTbl,X
		STA $401C,Y

		JSR furEPSM_loadInstPtr
		
		LDA furEPSM_fmPanR
		AND furEPSM_panORTbl,X
		CMP #1
		ROR furEPSM_temp ; R???????
		LDA furEPSM_fmPanL
		AND furEPSM_panORTbl,X
		CMP #1
		ROR furEPSM_temp ; LR??????
		LDA furEPSM_temp
		AND #$C0 ; LR000000
		LDY #1
		ORA (furEPSM_temp_ptr),Y
		LDY furEPSM_temp_ptr2+0
		STA $401D,Y
		RTS

MACRO furEPSM_saveNewTL op
		LDA furEPSM_40RegTbl,X
		CLC
		ADC #((((op-1)>>1)|((op-1)<<1)&2))*4 
		STA $401C,Y

		LDY #2+(7*(((op-1)>>1)|(((op-1)<< 1)&2)))+1
		LDA (furEPSM_temp_ptr),Y
		EOR #$7F
		ADC #1
		LDY furEPSM_chanVol,X
		JSR furEPSM_mult
		ASL furEPSM_temp_ptr2+1
		ROL
		EOR #$7F
		LDY furEPSM_temp
		STA $401D,Y
ENDM

furEPSM_updateTL:
		STY furEPSM_temp ; y saver
		
		JSR furEPSM_loadInstPtr
		
		LDY #0
		LDA (furEPSM_temp_ptr),Y
		LDY furEPSM_temp
		AND #7 ; ALG
		; 0, 1, 2, 3 	= OP4 only
		; 4 			= OP2, OP4
		; 5, 6 			= OP2, OP3, OP4
		; 7 			= OP1, OP2, OP3, OP4
		CMP #4
		BCC @op4only
		BEQ @op2op4
		CMP #7
		BNE @op2op3op4

		furEPSM_saveNewTL 1
@op2op3op4:
		furEPSM_saveNewTL 3
@op2op4:
		furEPSM_saveNewTL 2
@op4only:
		furEPSM_saveNewTL 4

furEPSM_60RegTbl: ; RTS
		.BYTE $60, $61, $62
furEPSM_30RegTbl:
		.BYTE $30, $31, $32
furEPSM_40RegTbl:
		.BYTE $40, $41, $42, $40, $41, $42
furEPSM_50RegTbl:
		.BYTE $50, $51, $52
furEPSM_70RegTbl:
		.BYTE $70, $71, $72
furEPSM_80RegTbl:
		.BYTE $80, $81, $82
furEPSM_90RegTbl:
		.BYTE $90, $91, $92
		
furEPSM_B0RegTbl:
		.BYTE $B0, $B1, $B2
		
furEPSM_B4RegTbl:
		.BYTE $B4, $B5, $B6, $B4, $B5, $B6
		
; =========================================================================================
;
; - furEPSM_mult: Perform A*X multiplication
;     input: A = multiplier, Y = multiplicand
;     output: furEPSM_temp_ptr2+1 = result LSB, A = result MSB
;
; =========================================================================================
		
furEPSM_mult:
		cpY #0              ;
		beq @zero            ; a*0=0
		deY                 ; decrement multiplicand to avoid the clc before 'adc multiplicand'
		stY furEPSM_temp_ptr2+0    ;
		lsr                 ; prepare first bit
		sta furEPSM_temp_ptr2+1      ;
		lda #0              ;
		ldY #4              ;
@l0:
		bcc @l1               ; no add
		adc furEPSM_temp_ptr2+0    ;
@l1:
		ror                 ;
		ror furEPSM_temp_ptr2+1      ;
		bcc @l2               ; no add
		adc furEPSM_temp_ptr2+0    ;
@l2:
		ror                 ;
		ror furEPSM_temp_ptr2+1      ;
		deY                 ;
		bne @l0               ;
		; TAY
		; ldA furEPSM_temp_ptr2+1      ;
		rts                 ;

@zero:
		STY furEPSM_temp_ptr2+1
		tYa                 ; a = 0
		rts                 ;
		
; =========================================================================================

IF (!furEPSM_DISABLESSG)
furEPSM_updatePitchSSG:
		LDX #furEPSM_ssgChan-1
@loop:
		LDY furEPSM_chanBaseNote+6,X
		LDA furEPSM_ssgPeriodTblLo,Y
		STA furEPSM_sChanFreqLo,X
		LDA furEPSM_ssgPeriodTblHi,Y
		STA furEPSM_sChanFreqHi,X
		DEX
		BPL @loop
		RTS
		
furEPSM_updateVolSSG:
		LDX #furEPSM_ssgChan-1
@loop:
		LDA #0
		STA furEPSM_sChanVol,X

		LDA furEPSM_chanStatus+6,X
		CMP #furEPSM_CHANSTAT_NOTECUT
		BEQ @skip
		CMP #furEPSM_CHANSTAT_NEWNOTE
		BNE @not_newnote
		LDA #furEPSM_CHANSTAT_NONE
		STA furEPSM_chanStatus+6,X
		LDA #0
		STA furEPSM_sChanVolEnvPos,X
@not_newnote:
		LDA furEPSM_chanInst+6,X
		ASL
		TAY
		LDA furEPSM_instptr+0,Y
		STA furEPSM_temp_ptr+0
		LDA furEPSM_instptr+1,Y
		STA furEPSM_temp_ptr+1
		LDY furEPSM_sChanVolEnvPos,X
		LDA (furEPSM_temp_ptr),Y
		INY
		STA furEPSM_sChanVol,X
		LDA (furEPSM_temp_ptr),Y
		CMP #16
		BCC @skip_volenvloop
		SBC #16 ; carry is set
		STA furEPSM_sChanVolEnvPos,X
		BCS @volenvloopdone ; always
@skip_volenvloop:
		INC furEPSM_sChanVolEnvPos,X
@volenvloopdone:
@skip:
		DEX
		BPL @loop
		RTS
		
furEPSM_updateRegSSG:
		LDX #furEPSM_ssgChan-1
@loop:
		LDA @00RegTbl,X
		STA $401C
		LDA furEPSM_sChanFreqLo,X
		STA $401D

		LDA @01RegTbl,X
		STA $401C
		LDA furEPSM_sChanFreqHi,X
		STA $401D
		
		LDA @08RegTbl,X
		STA $401C
		LDA furEPSM_sChanVol,X
		STA $401D
		
		DEX
		BPL @loop
		RTS

@00RegTbl:
		.BYTE $00, $02, $04
@01RegTbl:
		.BYTE $01, $03, $05
@08RegTbl:
		.BYTE $08, $09, $0A
ENDIF

; =========================================================================================
		
furEPSM_loadInstPtr:
		LDA furEPSM_chanInst,X
		ASL
		TAY
		LDA furEPSM_instptr+0,Y
		STA furEPSM_temp_ptr+0
		LDA furEPSM_instptr+1,Y
		STA furEPSM_temp_ptr+1
		RTS

; =========================================================================================

furEPSM_panANDTbl:
		.BYTE %00011111, %00101111, %00110111, %00111011, %00111101, %00111110
		
furEPSM_panORTbl:
		.BYTE %00100000, %00010000, %00001000, %00000100, %00000010, %00000001

furEPSM_fnumTblLo:
		.DL 617, 654, 693, 734, 778, 824, 873, 925, 980, 1038, 1100, 1165
furEPSM_fnumTblHi:
		.DH 617, 654, 693, 734, 778, 824, 873, 925, 980, 1038, 1100, 1165
		
IF (!furEPSM_DISABLESSG)
furEPSM_ssgPeriodTblLo:
		.DL $11C1, $10C2, $0FD2, $0EEE, $0E18, $0D4D, $0C8E, $0BDA, $0B2F, $0A8F, $09F7, $0968
		.DL $08E1, $0861, $07E9, $0777, $070C, $06A7, $0647, $05ED, $0598, $0547, $04FC, $04B4
		.DL $0470, $0431, $03F4, $03BC, $0386, $0353, $0324, $02F6, $02CC, $02A4, $027E, $025A
		.DL $0238, $0218, $01FA, $01DE, $01C3, $01AA, $0192, $017B, $0166, $0152, $013F, $012D
		.DL $011C, $010C, $00FD, $00EF, $00E1, $00D5, $00C9, $00BE, $00B3, $00A9, $009F, $0096
		.DL $008E, $0086, $007F, $0077, $0071, $006A, $0064, $005F, $0059, $0054, $0050, $004B
		.DL $0047, $0043, $003F, $003C, $0038, $0035, $0032, $002F
furEPSM_ssgPeriodTblHi:
		.DH $11C1, $10C2, $0FD2, $0EEE, $0E18, $0D4D, $0C8E, $0BDA, $0B2F, $0A8F, $09F7, $0968
		.DH $08E1, $0861, $07E9, $0777, $070C, $06A7, $0647, $05ED, $0598, $0547, $04FC, $04B4
		.DH $0470, $0431, $03F4, $03BC, $0386, $0353, $0324, $02F6, $02CC, $02A4, $027E, $025A
		.DH $0238, $0218, $01FA, $01DE, $01C3, $01AA, $0192, $017B, $0166, $0152, $013F, $012D
		.DH $011C, $010C, $00FD, $00EF, $00E1, $00D5, $00C9, $00BE, $00B3, $00A9, $009F, $0096
		.DH $008E, $0086, $007F, $0077, $0071, $006A, $0064, $005F, $0059, $0054, $0050, $004B
		.DH $0047, $0043, $003F, $003C, $0038, $0035, $0032, $002F
ENDIF

; =========================================================================================