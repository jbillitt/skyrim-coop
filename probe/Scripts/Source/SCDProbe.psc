Scriptname SCDProbe
{Probe: does STR show a remote player's downed state on this client?
In game: open the console, click the other player to select them, then run
    cgf "SCDProbe.Watch"
Watches for 3 minutes; every change is shown on screen and written to Papyrus.0.log.}

Function Watch() global
	Actor target = Game.GetCurrentConsoleRef() as Actor
	If !target
		Debug.MessageBox("SCDProbe: select the other player in the console first")
		Return
	EndIf

	Report(target, "start")
	String last = Describe(target)
	Int ticks = 0
	While ticks < 360
		Utility.Wait(0.5)
		String now = Describe(target)
		If now != last
			Report(target, "change")
			last = now
		EndIf
		ticks += 1
	EndWhile
	Report(target, "end")
EndFunction

String Function Describe(Actor a) global
	Return "remote=" + SkyrimTogetherUtils.IsRemotePlayer(a) + " bleedout=" + a.IsBleedingOut() + " dead=" + a.IsDead() + " hp=" + (a.GetActorValuePercentage("Health") * 100) as Int + "%"
EndFunction

Function Report(Actor a, String tag) global
	String msg = "SCDProbe " + tag + ": " + Describe(a)
	Debug.Notification(msg)
	Debug.Trace(msg)
EndFunction
