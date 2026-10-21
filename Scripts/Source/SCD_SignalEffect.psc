Scriptname SCD_SignalEffect extends ActiveMagicEffect
{One co-op message (see SCD_CoopPlayer). STR applies it to the local player on the receiving PC.}

SCD_CoopPlayer Property Coop Auto
Int Property Kind Auto

Event OnEffectStart(Actor akTarget, Actor akCaster)
	; the sending PC also runs this, on the partner's stand-in
	If akTarget == Game.GetPlayer()
		Coop.OnSignal(Kind, akCaster)
	EndIf
EndEvent
