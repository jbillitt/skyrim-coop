Scriptname SCD_RewardAlias extends neth_StatsOnKillScript
{Runs Stats On Kill's own reward for a kill the partner made. Its properties are copied from
Stats On Kill's victim alias at build time, with Victim pointing here.}

Function Pay(Actor akVictim)
	ForceRefTo(akVictim)
	StatsOnKill()
	Clear()
EndFunction
