## furEPSM driver format 1.1

`(T)` means reading this byte (or after its parameter, if available) terminates reading more commands in this tick.

$00     = note cut (T)

$01     = note release (T)

$02-$7F = note, starting from A-0 (T)

$80-$9F = effects

$A0-$BF = effects (T)

$C0-$FF = delay (T)