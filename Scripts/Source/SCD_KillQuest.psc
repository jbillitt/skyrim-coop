Scriptname SCD_KillQuest extends Quest
{Started by the Story Manager for every kill this PC sees.}

SCD_CoopPlayer Property Coop Auto

Event OnStoryKillActor(ObjectReference akVictim, ObjectReference akKiller, Location akLocation, Int aiCrimeStatus, Int aiRelationshipRank)
	; free the quest for the next kill before the slower work
	Stop()
	Coop.OnKill(akVictim as Actor, akKiller as Actor)
EndEvent
