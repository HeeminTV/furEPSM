## furEPSM driver format 1.0

$00     = note cut

$01     = note release

$02-$7F = note (starting from A-0)

$80-$9F = effect without ending channel read

$A0-$BF = effect with channel read done

$C0-$FF = delay command with channel read done
