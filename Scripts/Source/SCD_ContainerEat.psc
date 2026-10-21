Scriptname SCD_ContainerEat extends ReferenceAlias
{On the player: press G on food in a container (or on a corpse) to eat it without taking it first.}

Int Property EatKey = 34 AutoReadOnly ; G

ObjectReference opened

Event OnInit()
	RegisterForMenu("ContainerMenu")
EndEvent

Event OnPlayerLoadGame()
	RegisterForMenu("ContainerMenu")
EndEvent

Event OnMenuOpen(String menuName)
	opened = Game.GetCurrentCrosshairRef()
	RegisterForKey(EatKey)
EndEvent

Event OnMenuClose(String menuName)
	UnregisterForKey(EatKey)
	opened = None
EndEvent

Event OnKeyDown(Int keyCode)
	Actor holder = opened as Actor
	; trading and pickpocketing keep their own rules
	If !opened || (holder && !holder.IsDead())
		Return
	EndIf
	Form item = Game.GetFormEx(UI.GetInt("ContainerMenu", "_root.Menu_mc.inventoryLists.itemList.selectedEntry.formId"))
	Potion food = item as Potion
	If !(item as Ingredient) && !(food && food.IsFood())
		Return
	EndIf
	; the selection may be on the player's side of the menu
	If opened.GetItemCount(item) < 1
		Return
	EndIf
	Actor player = GetActorReference()
	If !Mine(opened, player)
		Debug.Notification("That isn't yours to eat.")
		Return
	EndIf
	opened.RemoveItem(item, 1, True, player)
	player.EquipItem(item, False, True)
EndEvent

; RemoveItem skips the crime system, so owned food has to be taken the normal way
Bool Function Mine(ObjectReference box, Actor player)
	ActorBase person = box.GetActorOwner()
	Faction group = box.GetFactionOwner()
	Cell here = box.GetParentCell()
	If !person && !group && here
		person = here.GetActorOwner()
		group = here.GetFactionOwner()
	EndIf
	If person
		Return person == player.GetActorBase()
	EndIf
	Return !group || player.IsInFaction(group)
EndFunction
