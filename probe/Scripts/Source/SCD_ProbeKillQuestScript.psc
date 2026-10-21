Scriptname SCD_ProbeKillQuestScript extends Quest
{Probe: logs every Kill Actor story event this client sees, to learn whether kills of
NPCs controlled by another STR client reach this client's Story Manager.}

Event OnStoryKillActor(ObjectReference akVictim, ObjectReference akKiller, Location akLocation, Int aiCrimeStatus, Int aiRelationshipRank)
	Actor killer = akKiller as Actor
	Bool remote = False
	; STR's native does not null-check
	If killer
		remote = SkyrimTogetherUtils.IsRemotePlayer(killer)
	EndIf
	String msg = "SCDProbe kill: victim=" + akVictim + " killer=" + akKiller + " remote=" + remote + " isPlayer=" + (killer == Game.GetPlayer())
	Debug.Notification(msg)
	Debug.Trace(msg)
	Stop()
EndEvent
