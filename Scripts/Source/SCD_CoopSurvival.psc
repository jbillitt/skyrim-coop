Scriptname SCD_CoopSurvival extends ReferenceAlias
{On the player: Survival Mode fixes for co-op. Sleep gets its hours credited (STR locks the game clock while
connected, so sleep passes no game time and Survival rests you for ~0 hours), and an owned bed can be slept in while the partner is in the same cell (a room rented on one PC is still the
innkeeper's on the other).}

String Property SurvivalFile = "ccQDRSSE001-SurvivalMode.esl" AutoReadOnly

Float sleepStart
Float sleepEnd
; the bed we took over for this sleep, and who owned it before
ObjectReference borrowedBed
ActorBase bedOwner
Faction bedFaction

Event OnInit()
	Setup()
EndEvent

Event OnPlayerLoadGame()
	Setup()
EndEvent

Function Setup()
	RegisterForSleep()
	RegisterForCrosshairRef()
EndFunction

Event OnSleepStart(Float afSleepStartTime, Float afDesiredSleepEndTime)
	sleepStart = afSleepStartTime
	sleepEnd = afDesiredSleepEndTime
EndEvent

Event OnSleepStop(Bool abInterrupted)
	ReturnBed()
	GlobalVariable survivalOn = Game.GetFormFromFile(0x826, SurvivalFile) as GlobalVariable
	If abInterrupted || survivalOn.GetValue() != 1.0
		Return
	EndIf
	; whatever the clock did pass, Survival has already credited
	Float missing = (sleepEnd - Utility.GetCurrentGameTime()) * 24.0
	Debug.Trace("SCD: slept " + ((Utility.GetCurrentGameTime() - sleepStart) * 24.0) + " h of " + ((sleepEnd - sleepStart) * 24.0) + ", crediting " + missing)
	If missing <= 0.0
		Return
	EndIf
	Survival_NeedExhaustion exhaustion = Game.GetFormFromFile(0x899, SurvivalFile) as Survival_NeedExhaustion
	Float perHour = (Game.GetFormFromFile(0x80E, SurvivalFile) as GlobalVariable).GetValue()
	Actor player = GetActorReference()
	; same quality test as Survival's own sleep detection
	Bool quality = player.IsInInterior() || (Game.GetFormFromFile(0x92F, SurvivalFile) as FormList).HasForm(player.GetWorldSpace())
	exhaustion.DecreaseExhaustion(missing * perHour, quality)
EndEvent

; --- shared beds ---

Event OnCrosshairRefChange(ObjectReference ref)
	; in the bed the crosshair is None; only looking at something else gives the bed back
	If !ref || ref == borrowedBed
		Return
	EndIf
	ReturnBed()
	; chisle: English bed names; a keyword check would need a list of every bed base
	If !(ref.GetBaseObject() as Furniture) || StringUtil.Find(ref.GetDisplayName(), "Bed") < 0
		Return
	EndIf
	Actor player = GetActorReference()
	ActorBase person = ref.GetActorOwner()
	Faction group = ref.GetFactionOwner()
	Cell here = ref.GetParentCell()
	If !person && !group && here
		If !here.GetActorOwner() && !here.GetFactionOwner()
			Return
		EndIf
	ElseIf person == player.GetActorBase() || (group && player.IsInFaction(group))
		Return
	EndIf
	Actor partner = ((self as ReferenceAlias) as SCD_CoopPlayer).Partner()
	If !partner || partner.GetParentCell() != here
		Return
	EndIf
	borrowedBed = ref
	bedOwner = person
	bedFaction = group
	ref.SetActorOwner(player.GetActorBase())
EndEvent

Function ReturnBed()
	If !borrowedBed
		Return
	EndIf
	If bedFaction
		borrowedBed.SetFactionOwner(bedFaction)
	Else
		; None falls back to the cell's owner
		borrowedBed.SetActorOwner(bedOwner)
	EndIf
	borrowedBed = None
EndFunction
