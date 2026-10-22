Scriptname SCD_CoopPlayer extends ReferenceAlias
{On the player: downed/revive, party wipe and shared kill credit. The two PCs talk through the
SCD_Signal spells, because STR forwards a healing-keyword spell cast on a remote player to that player's PC.
STR delivers those through one queue that stalls 4 s on any entry it can't resolve, so each event sends one
signal and nothing is repeated.}

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
Int Property KindRevive = 2 AutoReadOnly ; sent by patches before 0.11
Int Property KindCredit = 3 AutoReadOnly
Int Property KindWipe = 4 AutoReadOnly

; held while down: moved to the partner (stuck or drowning); held while standing: unstick
Float Property CallHoldSecs = 5.0 AutoReadOnly
; after a revive, hits can't put you straight back down
Float Property GraceSecs = 5.0 AutoReadOnly
; crouched next to the downed partner this long gets them up
Float Property ReviveHoldSecs = 3.0 AutoReadOnly
Float Property ReviveRange = 400.0 AutoReadOnly
; a downed player can't walk, so a stand-in that moves this far is up
Float Property MovedRange = 150.0 AutoReadOnly
Float Property VictimTtl = 5.0 AutoReadOnly
; down with no partner anywhere near this long: wipe (rides out STR swapping their stand-in)
Float Property AloneSecs = 10.0 AutoReadOnly
Float Property CreditWait = 3.0 AutoReadOnly

Actor partner
Bool downed
Bool partnerIsDown
; we stood the partner's stand-in up and it hasn't finished getting up yet
Bool standInRecovering
Float downX
Float downY
Float callStart = -1.0
Float upAt = -100.0
Float nextLookup
Float wipedAt = -100.0
Float helpStart = -1.0
Float aloneSince = -1.0
; when to snap our player / the partner's stand-in back to the default pose
Float poseResetAt = -1.0
Float standInResetAt = -1.0
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
	partnerIsDown = False
	standInRecovering = False
	wipedAt = -100.0
	helpStart = -1.0
	aloneSince = -1.0
	callStart = -1.0
	upAt = -100.0
	nextLookup = 0.0
	reequipAt = -1.0
	poseResetAt = -1.0
	standInResetAt = -1.0
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
	Debug.Trace("SCD: downed, partner=" + Partner() + " partnerDown=" + partnerIsDown)
	If partnerIsDown
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
	If poseResetAt >= 0.0 && t >= poseResetAt
		poseResetAt = -1.0
		ResetPose(GetActorReference())
	EndIf
	If standInResetAt >= 0.0 && t >= standInResetAt
		standInResetAt = -1.0
		If partner
			ResetPose(partner)
		EndIf
	EndIf
	If downed
		If GetActorReference().IsSwimming() || (callStart >= 0.0 && t - callStart >= CallHoldSecs)
			callStart = -1.0
			Rescue()
		Else
			WatchForHelp(t)
		EndIf
	ElseIf callStart >= 0.0 && t - callStart >= CallHoldSecs
		callStart = -1.0
		Unstick()
	ElseIf partnerIsDown
		Help(t)
	Else
		helpStart = -1.0
	EndIf
	RefreshMarker()
	If pendingCredits > 0
		PayCredits()
	EndIf
	If downed || callStart >= 0.0 || pendingCredits > 0 || partnerIsDown
		RegisterForSingleUpdate(0.5)
	Else
		RegisterForSingleUpdate(1.0)
	EndIf
EndEvent

; Revive is seen, not signalled: STR keeps the partner's position and crouch in sync, so the
; downed player's own PC watches for them crouching close by
Function WatchForHelp(Float t)
	Actor p = Partner()
	; a partner who wiped teleports away, and their wipe signal can go missing; with nobody here
	; to help, this is a wipe too
	If p
		aloneSince = -1.0
	ElseIf aloneSince < 0.0
		aloneSince = t
	ElseIf t - aloneSince >= AloneSecs
		Wipe("Nobody could reach you.")
		Return
	EndIf
	If !(p && p.IsSneaking() && GetActorReference().GetDistance(p) <= ReviveRange)
		helpStart = -1.0
	ElseIf helpStart < 0.0
		helpStart = t
		Debug.Notification("Your partner is helping you up...")
	ElseIf t - helpStart >= ReviveHoldSecs
		helpStart = -1.0
		GetUp(0.5, "Your partner got you back up.")
	EndIf
EndFunction

; The helper's side: the same 3 s, seen from here
Function Help(Float t)
	Actor p = Partner()
	If !(p && GetActorReference().IsSneaking() && GetActorReference().GetDistance(p) <= ReviveRange)
		helpStart = -1.0
	ElseIf helpStart < 0.0
		helpStart = t
		Debug.Notification("Helping your partner up, stay crouched...")
	ElseIf t - helpStart >= ReviveHoldSecs
		helpStart = -1.0
		PartnerUp(p)
		Debug.Notification("You got your partner back up.")
	EndIf
EndFunction

Event OnControlDown(String control)
	callStart = Now()
	If downed
		Debug.Notification("Calling for help, keep holding...")
	EndIf
	RegisterForSingleUpdate(0.5)
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
	poseResetAt = upAt + 4.0
	Debug.Notification(msg)
	Utility.Wait(3.0)
	Actor player = GetActorReference()
	If !downed && player.IsBleedingOut()
		; below the engine's recovery threshold; top up
		player.RestoreActorValue("Health", player.GetActorValueMax("Health"))
	EndIf
EndFunction

; Both down: wake in the nearest discovered town, 10% poorer
Function Wipe(String why)
	If !downed
		Return
	EndIf
	downed = False
	callStart = -1.0
	wipedAt = Now()
	partnerIsDown = False
	Debug.Trace("SCD: wipe: " + why)
	; sent before the teleport takes us out of the partner's reach; a downed partner wipes on hearing it
	Send(KindWipe)
	StandUp(1.0)
	Actor player = GetActorReference()
	player.MoveTo(NearestTown())
	reequipAt = Now() + 3.0
	poseResetAt = Now() + 4.0
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
	If p && !partnerIsDown
		GetActorReference().MoveTo(p, 60.0)
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

; --- keeping the two screens looking right ---

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

; Getting up from bleedout can leave a body stuck mid-animation (arms bent back); the default-state
; idle snaps it out, and STR forwards it from our player to the partner's screen
Function ResetPose(Actor a)
	If a.IsBleedingOut() || a.GetSitState() != 0
		Return
	EndIf
	Debug.SendAnimationEvent(a, "IdleForceDefaultState")
EndFunction

Function Unstick()
	Debug.Trace("SCD: unstick")
	ResetPose(GetActorReference())
	Reequip()
	If partner
		ResetPose(partner)
	EndIf
	Debug.Notification("Reset your pose and gear.")
EndFunction

; Their signal or their stand-in here going into bleedout (STR syncs health), whichever comes first
Function PartnerWentDown(Actor p)
	partnerIsDown = True
	If p
		downX = p.GetPositionX()
		downY = p.GetPositionY()
	EndIf
	Debug.Trace("SCD: partner down")
	; seen from their stand-in rather than signalled, this is our only cue that both of us are down
	If downed
		Wipe("Your party was wiped out.")
		Return
	EndIf
	Debug.Notification("Your partner is down! Follow the marker and crouch next to them.")
	RegisterForSingleUpdate(0.5)
EndFunction
; The partner is up. STR's stand-in for them has no bleedout recovery and never gets their heal,
; so stand it up here too
Function PartnerUp(Actor p)
	partnerIsDown = False
	If p
		standInRecovering = True
		p.SetNoBleedoutRecovery(False)
		p.RestoreActorValue("Health", p.GetActorValueMax("Health"))
		standInResetAt = Now() + 2.0
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
	If !(partner && SkyrimTogetherUtils.IsRemotePlayer(partner))
		partner = ScanForPartner()
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
EndFunction

; STR now delivers these without a caster, so the sender is not used
Function OnSignal(Int kind, Actor sender)
	Debug.Trace("SCD: signal " + kind)
	If kind == KindDown
		; the partner going down with us arrives after our wipe; it's the same wipe
		If Now() - wipedAt < 10.0
			Return
		EndIf
		If downed
			Wipe("Your party was wiped out.")
			Return
		EndIf
		If !partnerIsDown
			PartnerWentDown(Partner())
		EndIf
	ElseIf kind == KindUp
		PartnerUp(Partner())
		RefreshMarker()
	ElseIf kind == KindWipe
		partnerIsDown = False
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

Function RefreshMarker()
	Actor p = partner
	; a missing partner costs a finder restart, so look again only every few seconds
	If (p && p.Is3DLoaded()) || partnerIsDown || Now() >= nextLookup
		p = Partner()
		If !p
			nextLookup = Now() + 5.0
		EndIf
	Else
		p = None
	EndIf
	If p && p != lastSeen
		Debug.Trace("SCD: partner is " + p)
		; a fresh stand-in for the partner usually means they got a fresh one of us too, and it can
		; arrive in a broken pose (half in the floor, arms bent back)
		reequipAt = Now() + 2.0
		standInResetAt = Now() + 2.0
	EndIf
	lastSeen = p
	If p
		If partnerIsDown
			; their "up" can go missing on the way here; someone who walks off is up
			Float dx = p.GetPositionX() - downX
			Float dy = p.GetPositionY() - downY
			If dx * dx + dy * dy > MovedRange * MovedRange
				PartnerUp(p)
			EndIf
		ElseIf standInRecovering
			standInRecovering = p.IsBleedingOut()
		ElseIf p.IsBleedingOut()
			PartnerWentDown(p)
		EndIf
		; re-forced each tick, in case STR swapped the stand-in
		MarkerTarget.ForceRefTo(p)
	Else
		MarkerTarget.Clear()
	EndIf
	Marker.SetObjectiveDisplayed(20, p && partnerIsDown)
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
