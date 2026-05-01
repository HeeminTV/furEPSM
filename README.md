# MAIN UPDATES PAUSED UNTIL FURNACE FIXES TEXT EXPORT ISSUE

# furEPSM

A ***WIP*** lightweight NES [EPSM](https://www.nesdev.org/wiki/Expansion_Port_Sound_Module) music driver for [Furnace](https://github.com/tildearrow/furnace)

Gone are the days you had to learn [FamiStudio](https://famistudio.org/) just to put EPSM tracks into your game. Waited a long time, tracker users.

## Resource usage

- CPU cycles: Approx. 2329 cycles
- RAM usage: 150 bytes (+ 5 bytes on zero-page)
- ROM usage: 2150 bytes

## Supported effects

- `08xy` - Set panning
- `80xx` - Set panning
- `0Bxx` - Jump to frame xx
- `0D00` - Next frame
- `0Fxx` - Set speed
- `E5xx` - Set pitch offset (pseudo implementation)
- `ECxx` - Delayed note cut (priority has inaccuracy)
- `EDxx` - Note delay (only one at once)
- `FDxx` - Set tempo
- `FFxx` - Stop song

## TODO

- Add rhythm kit support
- Add noise support for SSG
- Add pitch bend effects (portamento, vibrato)

## Major missing features

- Pitch related effects
- SSG macros except for volume
- SSG macro release
- Rhythm kit support

## Non-goals (lowest priority)

- Arpeggio effect
- FM macros
- SSG PCM streaming
- 2A03 APU hijack

## Usage

The driver is particularly intended to use with bankswitched songs. You should write your own bankswitching logic. (a music driver will have no idea how your bankswitching system works) Just the update routine has to be called with the correct bank set right before.

The bytecode converter accepts YM2608 (no CSM or exp 3CH) Furnace .txt export and generates one header file and track sequence data for each subsongs.

### Including in your game

Obviously you would want to find a bank for the driver itself first. (Fixed bank works too anyway)

Include the driver `.asm` source using `.include` directive. Don't forget to `.include` the music header file **in the same bank** as well.

```x86asm
.base $8000
		.include "furEPSM.asm"
		.include "song_header.asm"
.pad $A000,$FF
```

In very first lines of `furEPSM.asm`, you can locate where furEPSM RAM variables live.

```x86asm
; =========================================================================================
;
; **USER SETTINGS**
;
; =========================================================================================

furEPSM_zp = $FB ; 5 bytes zero page variable
furEPSM_bss = $300 ; < 256 bytes of main variables

...
```

The song data can be added with the same way as the driver. Find an empty bank for the track data, and just `.include` them.

You don't have to label them here. The labels are already defined in each files already.

```x86asm
.base $A000
		; No labels required
		.include "song_song00.asm"
.pad $C000,$FF
```

### Playing a song

Playing a song is as easy as pressing \[NEXT\] button in your MP3 player. Load **subsong number** in `A` register and call `furEPSM_play`.

**THE SONG BANK** should be set before calling `furEPSM_play` and `furEPSM_update`. Otherwise the driver will read wrong data from other unrelated banks.

```x86asm
		LDA #SONG_BANK
		STA MAPPER_PRG
		LDA #SONG_TITLE
		JSR furEPSM_play
```

Call `furEPSM_update` in every frames to update sequence constantly, normally it's done as a part of NMI routine. Again, make sure **the song bank** is loaded already before calling `furEPSM_update`.

It's recommended to call `furEPSM_play` or `furEPSM_update` only single time in a frame because of CPU usage. Best and clean way to do this is to make a RAM variable for "Track request" and do something like this:

```
update_driver:
		LDA #SONG_BANK
		STA MAPPER_PRG

		LDA track_req
		CMP #$FF
		BEQ @update
		LDX #$FF
		STX track_req
		JMP furEPSM_play
@update:
		JMP furEPSM_update
```