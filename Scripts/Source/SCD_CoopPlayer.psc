Scriptname SCD_CoopPlayer extends ReferenceAlias
{On the player: downed/revive, party wipe and shared kill credit. The two PCs talk through the
SCD_Signal spells, because STR forwards a healing-keyword spell cast on a remote player to that player's PC.}

Quest Property Finder Auto
ReferenceAlias Property FoundPartner Auto
Quest Property Marker Auto ; compass marker on the partner; objective 20 while they are down
ReferenceAlias Property MarkerTarget Auto
Spell[] Property Signals Auto ; indexed by SCD_SignalEffect.Kind
; saves keep the 4-entry Signals array they were made with, so later kinds get their own property
Spell Property WipeSignal Auto
; a script-typed alias property fails to bind ("not the right type"), so it is cast at use
ReferenceAlias Property Reward Auto
; capitals first, so an interior resolves to its hold's capital
ObjectReference[] Property Towns Auto
Location[] Property TownHolds Auto
WorldSpace[] Property TownWorlds Auto
; the marker that counts as discovering each town (a walled city's own, not its stables)
ObjectReference[] Property TownFound Auto
MiscObject Property Gold Auto
GlobalVariable Property SurvivalOn Auto
; Survival Mode's carry weight ability, zeroed by our plugin
Spell Property SurvivalCarry Auto

Int Property KindDown = 0 AutoReadOnly
Int Property KindUp = 1 AutoReadOnly
Int Property KindRevive = 2 AutoReadOnly
Int Property KindCredit = 3 AutoReadOnly
Int Property KindWipe = 4 AutoReadOnly

; held while down: moved to the partner, or a wipe if they can't be reached
Float Property CallHoldSecs = 5.0 AutoReadOnly
; after a revive, hits can't put you straight back down
Float Property GraceSecs = 5.0 AutoReadOnly
; down with no partner around this long: they wiped (their signal lost) or left, so it's a wipe
Float Property AloneSecs = 20.0 AutoReadOnly
; crouched next to the downed partner this long gets them up
Float Property ReviveHoldSecs = 3.0 AutoReadOnly
Float Property ReviveRange = 400.0 AutoReadOnly
; a downed player re-signals every 5 s, so a lost "up" signal only lingers this long
Float Property DownTtl = 12.0 AutoReadOnly
Float Property VictimTtl = 5.0 AutoReadOnly
Float Property CreditWait = 3.0 AutoReadOnly

Actor partner
Bool downed
Float lastDownSignal
Float callStart = -1.0
Float upAt = -100.0
Float reviveSentAt = -100.0
Float ackAt = -100.0
Float nextLookup
Float partnerDownUntil
Float wipedAt = -100.0
Float helpStart = -1.0
Float aloneSince = -1.0
Bool travelBlocked
Float reequipAt = -1.0
Actor lastSeen
Actor[] victims
Float[] victimTimes
Int nextVictim
Int pendingCredits
Float creditAt

Event OnInit()
	Setup()
EndEvent

Event OnPlayerLoadGame()
	; real-time stamps restart with the game
	partnerDownUntil = 0.0
	wipedAt = -100.0
	helpStart = -1.0
	callStart = -1.0
	upAt = -100.0
	reviveSentAt = -100.0
	ackAt = -100.0
	nextLookup = 0.0
	reequipAt = -1.0
	lastSeen = None
	; the stand-in a save remembers is gone
	partner = None
	Setup()
EndEvent

Event OnPlayerFastTravelEnd(Float afTravelGameTimeHours)
	reequipAt = Now() + 3.0
EndEvent

Function Setup()
	victims = new Actor[4]
	victimTimes = new Float[4]
	pendingCredits = 0
	RegisterForControl("Activate")
	Actor player = GetActorReference()
	If player.HasSpell(SurvivalCarry)
		; saves keep the old -150 until the ability is reapplied
		player.RemoveSpell(SurvivalCarry)
		player.AddSpell(SurvivalCarry, False)
	EndIf
	; older versions could leave the quest running with the objective off, so set it up every load
	If !Marker.IsRunning()
		Marker.Start()
	EndIf
	Marker.SetObjectiveDisplayed(10)
	Marker.SetActive()
	Debug.Trace("SCD: marker running=" + Marker.IsRunning() + " shown=" + Marker.IsObjectiveDisplayed(10) + " active=" + Marker.IsActive())
	RegisterForSingleUpdate(1.0)
EndFunction

Float Function Now()
	Return Utility.GetCurrentRealTime()
EndFunction

; --- downed, revive, wipe ---

Event OnEnterBleedout()
	If downed
		Return
	EndIf
	Actor player = GetActorReference()
	If Now() - upAt < GraceSecs
		; just revived: shrug it off
		player.RestoreActorValue("Health", player.GetActorValueMax("Health") * 0.5 - player.GetActorValue("Health"))
		Return
	EndIf
	player.SetNoBleedoutRecovery(True)
	downed = True
	aloneSince = -1.0
	Debug.Trace("SCD: downed, partner=" + Partner() + " partnerDown=" + PartnerDown())
	; an unseen partner is far away, not down, so only a known-down partner means a wipe
	If PartnerDown()
		Wipe("Your party was wiped out.")
		Return
	EndIf
	Send(KindDown)
	Debug.Notification("You're down! Your partner has to crouch next to you to get you up.")
	Debug.Notification("Somewhere they can't reach? Hold E for 5 seconds.")
	RegisterForSingleUpdate(0.5)
EndEvent

Event OnUpdate()
	Float t = Now()
	GuardFastTravel()
	If reequipAt >= 0.0 && t >= reequipAt
		reequipAt = -1.0
		Reequip()
	EndIf
	If downed
		If PartnerDown()
			Wipe("Your party was wiped out.")
		ElseIf GetActorReference().IsSwimming() || (callStart >= 0.0 && t - callStart >= CallHoldSecs)
			callStart = -1.0
			Rescue()
		Else
			WatchForHelp(t)
		EndIf
	ElseIf PartnerDown()
		Help(t)
	Else
		helpStart = -1.0
	EndIf
	RefreshMarker()
	If pendingCredits > 0
		PayCredits()
	EndIf
	If downed || callStart >= 0.0 || pendingCredits > 0 || PartnerDown()
		RegisterForSingleUpdate(0.5)
	Else
		RegisterForSingleUpdate(1.0)
	EndIf
EndEvent

; Revive is seen, not signalled: signals to one PC arrived minutes late in play, but STR keeps the
; partner's position and crouch in sync, so the downed player's own PC watches for them crouching close by
Function WatchForHelp(Float t)
	Actor player = GetActorReference()
	Actor p = Partner()
	Bool helping = p && p.IsSneaking() && player.GetDistance(p) <= ReviveRange
	If p
		aloneSince = -1.0
	ElseIf aloneSince < 0.0
		aloneSince = t
	ElseIf t - aloneSince >= AloneSecs
		aloneSince = -1.0
		Wipe("Your party was wiped out.")
		Return
	EndIf
	If t - lastDownSignal >= 5.0
		Send(KindDown)
		If p
			Debug.Trace("SCD: still down, partner dist=" + player.GetDistance(p) + " sneaking=" + p.IsSneaking())
		EndIf
	EndIf
	If !helping
		helpStart = -1.0
	ElseIf helpStart < 0.0
		helpStart = t
		Debug.Notification("Your partner is helping you up...")
	ElseIf t - helpStart >= ReviveHoldSecs
		helpStart = -1.0
		GetUp(0.5, "Your partner got you back up.")
	EndIf
EndFunction

; The helper's side, for feedback; the revive itself happens on the downed player's PC
Function Help(Float t)
	If !(GetActorReference().IsSneaking() && PartnerInReach())
		helpStart = -1.0
	ElseIf helpStart < 0.0
		helpStart = t
		Debug.Notification("Helping your partner up, stay crouched...")
	ElseIf t - helpStart >= ReviveHoldSecs
		helpStart = -1.0
		; for an older patch on their side
		Send(KindRevive)
		reviveSentAt = t
		partnerDownUntil = 0.0
		Debug.Notification("You got your partner back up.")
	EndIf
EndFunction

Event OnControlDown(String control)
	If downed
		callStart = Now()
		Debug.Notification("Calling for help, keep holding...")
		RegisterForSingleUpdate(0.5)
	EndIf
EndEvent

Event OnControlUp(String control, Float holdTime)
	callStart = -1.0
EndEvent

Function GetUp(Float healthFraction, String msg)
	If !downed
		Return
	EndIf
	downed = False
	upAt = Now()
	StandUp(healthFraction)
	Debug.Notification(msg)
	Utility.Wait(3.0)
	Actor player = GetActorReference()
	If !downed && player.IsBleedingOut()
		; below the engine's recovery threshold; top up
		player.RestoreActorValue("Health", player.GetActorValueMax("Health"))
	EndIf
EndFunction

; Down, and nobody can get you up: wake in the nearest discovered town, 10% poorer
Function Wipe(String why)
	If !downed
		Return
	EndIf
	downed = False
	callStart = -1.0
	wipedAt = Now()
	partnerDownUntil = 0.0
	Debug.Trace("SCD: wipe: " + why)
	; a downed partner's PC wipes too when it hears this. Signals to the partner go missing in play,
	; so repeat until they answer (their wipe or their getting up), all before the teleport takes us out of reach
	Float started = Now()
	Int tries = 0
	While tries < 12 && ackAt < started && Partner()
		Send(KindWipe)
		Utility.Wait(0.5)
		tries += 1
	EndWhile
	Debug.Trace("SCD: wipe sent " + tries + " times, answered=" + (ackAt >= started))
	StandUp(1.0)
	Actor player = GetActorReference()
	player.MoveTo(NearestTown())
	reequipAt = Now() + 3.0
	String place = "the nearest town"
	Location here = player.GetCurrentLocation()
	If here
		place = here.GetName()
	EndIf
	Debug.Notification(why + " You come to near " + place + ".")
	Int lost = (player.GetGoldAmount() * 0.1) as Int
	If lost > 0
		player.RemoveItem(Gold, lost, True)
		Debug.Notification("You lost " + lost + " gold.")
	EndIf
EndFunction

; drowned, or stuck where the partner can't reach: still down, but next to them
Function Rescue()
	Actor p = Partner()
	If p && !PartnerDown()
		GetActorReference().MoveTo(p, 60.0)
		Send(KindDown)
		Debug.Notification("You were brought to your partner. They still have to get you up.")
	Else
		Wipe("Nobody could reach you.")
	EndIf
EndFunction

Function StandUp(Float healthFraction)
	Actor player = GetActorReference()
	player.SetNoBleedoutRecovery(False)
	; health can sit below zero after an overkill hit, so restore to an absolute level
	player.RestoreActorValue("Health", player.GetActorValueMax("Health") * healthFraction - player.GetActorValue("Health"))
	Send(KindUp)
EndFunction

ObjectReference Function NearestTown()
	Actor player = GetActorReference()
	WorldSpace world = player.GetWorldSpace()
	ObjectReference best
	Float bestDist
	Int i = 0
	While world && i < Towns.Length
		If TownWorlds[i] == world && TownFound[i].CanFastTravelToMarker()
			Float d = player.GetDistance(Towns[i])
			If !best || d < bestDist
				best = Towns[i]
				bestDist = d
			EndIf
		EndIf
		i += 1
	EndWhile
	If best
		Return best
	EndIf
	; interiors and walled-city worldspaces: a discovered town in this hold
	Location here = player.GetCurrentLocation()
	i = 0
	While here && i < Towns.Length
		If (here == TownHolds[i] || here.IsChild(TownHolds[i])) && TownFound[i].CanFastTravelToMarker()
			Return Towns[i]
		EndIf
		i += 1
	EndWhile
	i = 0
	While i < Towns.Length
		If TownFound[i].CanFastTravelToMarker()
			Return Towns[i]
		EndIf
		i += 1
	EndWhile
	Return Towns[0]
EndFunction

; After a teleport STR's copy of us on the partner's PC draws no hands or feet until our gear changes
Function Reequip()
	Actor player = GetActorReference()
	ReequipSlot(player, 0x04) ; body
	ReequipSlot(player, 0x08) ; hands
	ReequipSlot(player, 0x80) ; feet
EndFunction

Function ReequipSlot(Actor player, Int slotMask)
	Armor worn = player.GetWornForm(slotMask) as Armor
	If worn
		player.UnequipItem(worn, False, True)
		player.EquipItem(worn, False, True)
	EndIf
EndFunction

Function GuardFastTravel()
	; Survival already blocks it; this keeps a quest that re-enables fast travel from slipping through
	Bool survival = SurvivalOn.GetValue() == 1.0
	If survival && Game.IsFastTravelEnabled()
		Game.EnableFastTravel(False)
		travelBlocked = True
	ElseIf !survival && travelBlocked
		Game.EnableFastTravel(True)
		travelBlocked = False
	EndIf
EndFunction

; --- partner and signals ---

Actor Function Partner()
	; STR's native does not null-check
	If partner && partner.Is3DLoaded() && SkyrimTogetherUtils.IsRemotePlayer(partner)
		Return partner
	EndIf
	; restarting refills the finder's closest-match alias
	Finder.Stop()
	Int tries = 0
	While !Finder.IsStopped() && tries < 10
		Utility.Wait(0.1)
		tries += 1
	EndWhile
	Finder.Start()
	partner = FoundPartner.GetActorReference()
	Debug.Trace("SCD: finder found " + partner + " remote=" + (partner && SkyrimTogetherUtils.IsRemotePlayer(partner)))
	If !(partner && SkyrimTogetherUtils.IsRemotePlayer(partner))
		partner = ScanForPartner()
		Debug.Trace("SCD: scan found " + partner)
	EndIf
	Return partner
EndFunction

Actor Function ScanForPartner()
	Actor player = GetActorReference()
	; STR spawns the stand-in in our cell (62 = Character)
	Cell here = player.GetParentCell()
	Int n = 0
	If here
		n = here.GetNumRefs(62)
	EndIf
	Int i = 0
	While i < n
		Actor inCell = here.GetNthRef(i, 62) as Actor
		If inCell && inCell != player && SkyrimTogetherUtils.IsRemotePlayer(inCell)
			Return inCell
		EndIf
		i += 1
	EndWhile
	; it may have walked into a neighbouring cell
	i = 0
	While i < 20
		Actor nearby = Game.FindRandomActorFromRef(player, 8192.0)
		If nearby && nearby != player && SkyrimTogetherUtils.IsRemotePlayer(nearby)
			Return nearby
		EndIf
		i += 1
	EndWhile
	Return None
EndFunction

Bool Function PartnerDown()
	Return Now() < partnerDownUntil
EndFunction

Bool Function PartnerInReach()
	Actor p = Partner()
	Return p && GetActorReference().GetDistance(p) <= ReviveRange
EndFunction

Function Send(Int kind)
	Actor p = Partner()
	If !p
		Return
	EndIf
	Spell signal = WipeSignal
	If kind != KindWipe
		signal = Signals[kind]
	EndIf
	signal.Cast(GetActorReference(), p)
	If kind == KindDown
		lastDownSignal = Now()
	EndIf
EndFunction

Function OnSignal(Int kind, Actor sender)
	Debug.Trace("SCD: signal " + kind + " from " + sender)
	If sender && SkyrimTogetherUtils.IsRemotePlayer(sender)
		partner = sender
	EndIf
	If kind == KindDown
		; the partner wiping with us echoes back; ignore it
		If Now() - wipedAt < 10.0
			Return
		EndIf
		If Now() - reviveSentAt < 20.0
			; our revive went missing; they are still down
			Debug.Trace("SCD: partner still down, resending revive")
			Send(KindRevive)
			Return
		EndIf
		Bool wasDown = PartnerDown()
		partnerDownUntil = Now() + DownTtl
		If downed
			Wipe("Your party was wiped out.")
		Else
			RefreshMarker()
			If !wasDown
				Debug.Notification("Your partner is down! Follow the marker and crouch next to them.")
			EndIf
		EndIf
	ElseIf kind == KindUp
		ackAt = Now()
		reviveSentAt = -100.0
		partnerDownUntil = 0.0
		; STR now delivers these without a caster, so use the partner we know
		Actor p = Partner()
		If p
			StandInUp(p)
		EndIf
		RefreshMarker()
	ElseIf kind == KindWipe
		ackAt = Now()
		If downed
			Wipe("Your party was wiped out.")
		EndIf
	ElseIf kind == KindRevive
		GetUp(0.5, "Your partner got you back up.")
	ElseIf kind == KindCredit
		pendingCredits += 1
		creditAt = Now()
		PayCredits()
		If pendingCredits > 0
			RegisterForSingleUpdate(0.5)
		EndIf
	EndIf
EndFunction

; STR's stand-in for the partner has no bleedout recovery and may never get their heal, so it stays
; lying down here after they are up
Function StandInUp(Actor p)
	p.SetNoBleedoutRecovery(False)
	p.RestoreActorValue("Health", p.GetActorValueMax("Health"))
EndFunction

Function RefreshMarker()
	Actor p = partner
	; a missing partner costs a finder restart, so look again only every few seconds
	If (p && p.Is3DLoaded()) || PartnerDown() || Now() >= nextLookup
		p = Partner()
		If !p
			nextLookup = Now() + 5.0
		EndIf
	Else
		p = None
	EndIf
	If p && p != lastSeen
		; a fresh stand-in for the partner usually means they got a fresh one of us too
		reequipAt = Now() + 2.0
	EndIf
	lastSeen = p
	If p
		; STR stand-ins never recover from bleedout, so one stays down after its player is back up
		If !PartnerDown() && p.IsBleedingOut()
			StandInUp(p)
		EndIf
		; re-forced each tick, in case STR swapped the stand-in
		MarkerTarget.ForceRefTo(p)
	Else
		MarkerTarget.Clear()
	EndIf
	Marker.SetObjectiveDisplayed(20, p && PartnerDown())
EndFunction

; --- shared kill credit ---

Function OnKill(Actor victim, Actor killer)
	If killer && killer == GetActorReference()
		; Stats On Kill rewards us; the partner's PC only sees this kill with no killer
		Send(KindCredit)
	ElseIf victim
		; may be the partner's kill, with its credit signal on the way
		victims[nextVictim] = victim
		victimTimes[nextVictim] = Now()
		nextVictim = (nextVictim + 1) % victims.Length
		PayCredits()
	EndIf
EndFunction

Function PayCredits()
	While pendingCredits > 0
		Actor victim = TakeVictim()
		If !victim
			If Now() - creditAt < CreditWait
				Return
			EndIf
			; the death never showed up here; score it at our own level
			victim = GetActorReference()
		EndIf
		pendingCredits -= 1
		(Reward as SCD_RewardAlias).Pay(victim)
	EndWhile
EndFunction

Actor Function TakeVictim()
	Float t = Now()
	Int best = -1
	Int i = 0
	While i < victims.Length
		If victims[i] && t - victimTimes[i] <= VictimTtl && (best < 0 || victimTimes[i] > victimTimes[best])
			best = i
		EndIf
		i += 1
	EndWhile
	If best < 0
		Return None
	EndIf
	Actor victim = victims[best]
	victims[best] = None
	Return victim
EndFunction
