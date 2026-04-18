; =========================================================================================
;
; **USER SETTINGS**
;
; =========================================================================================

furEPSM_zp: $FC ; 6 bytes zero page
furEPSM_bss: $300

; =========================================================================================

enum furEPSM_zp
		furEPSM_temp_ptr: .dsb 2
		furEPSM_temp_ptr2: .dsb 2
		furEPSM_temp0: .dsb 1
		furEPSM_temp1: .dsb 1
ende

furEPSM_fmChan = 6
furEPSM_ssgChan = 3
furEPSM_rhythmChan 1

furEPSM_effChan: furEPSM_fmChan+furEPSM_ssgChan
furEPSM_allChan: furEPSM_fmChan+furEPSM_ssgChan+furEPSM_rhythmChan

enum furEPSM_bss
		furEPSM_framesPtr: .dsb 2
		furEPSM_frames: .dsb 1
		furEPSM_rows: .dsb 1
		furEPSM_currRow: .dsb 1
		furEPSM_groovePos: .dsb 1

		furEPSM_patLo: .dsb furEPSM_allChan
		furEPSM_patHi: .dsb furEPSM_allChan

		furEPSM_instrument: .dsb furEPSM_effChan ; bit 7 = instrument changed flag

		furEPSM_ssgVolEnvPtrLo: furEPSM_ssgChan
		furEPSM_ssgVolEnvPtrHi: furEPSM_ssgChan
		furEPSM_ssgVolEnvPos: furEPSM_ssgChan
ende

; =========================================================================================
;
; - furEPSM_play: Initialize driver with song
;     input: A = track number (starting from 0)
;     output:
;
; =========================================================================================

furEPSM_play:
		PHA
		JSR furEPSM_silenceChannels
		PLA
		ASL
		TAX
		LDA furEPSM_header+0,X
		STA furEPSM_temp_ptr+0
		LDA furEPSM_header+1,X
		STA furEPSM_temp_ptr+1

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
		INY
		STA furEPSM_rows

; =========================================================================================
;
; - furEPSM_update: Update sequences, EPSM registers
;     input:
;     output: X=0
;
; =========================================================================================

furEPSM_update:

; =========================================================================================

furEPSM_silenceChannels:
		LDA #$28
		LDX #6
@loop1: ; Kill EPSM
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