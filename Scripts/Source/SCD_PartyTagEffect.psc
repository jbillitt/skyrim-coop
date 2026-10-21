Scriptname SCD_PartyTagEffect extends ActiveMagicEffect
{Applied by the party cloak to nearby actors. Tags STR remote players with SCD_PartyFaction,
which the Stats On Kill story node override accepts as a killer.}

Faction Property SCD_PartyFaction Auto

Int checks = 0

Event OnEffectStart(Actor akTarget, Actor akCaster)
	Check(akTarget)
EndEvent

Event OnUpdate()
	Check(GetTargetActor())
EndEvent

Function Check(Actor target)
	; STR's native does not null-check
	If !target
		Return
	EndIf
	If SkyrimTogetherUtils.IsRemotePlayer(target)
		target.AddToFaction(SCD_PartyFaction)
	ElseIf checks < 3
		; a freshly spawned stand-in may not be flagged as remote yet
		checks += 1
		RegisterForSingleUpdate(5.0)
	EndIf
EndFunction
