// Generates SkyrimCoop.esp.
// Usage: BuildPlugin <path to StatsOnKill.esp> <game Data dir> <dist dir>
using Mutagen.Bethesda;
using Mutagen.Bethesda.Plugins;
using Mutagen.Bethesda.Skyrim;

var sokPath = args[0];
var gameData = args[1];
var dist = args[2];

var playerNpc = FormKey.Factory("000007:Skyrim.esm");
var playerRef = FormKey.Factory("000014:Skyrim.esm");
var playerFaction = FormKey.Factory("000DB1:Skyrim.esm");
// STR forwards spells with this keyword when cast on a remote player
var magicRestoreHealth = FormKey.Factory("01CEB0:Skyrim.esm");
var killActorBranch = FormKey.Factory("013010:Skyrim.esm");
var sokQuest = FormKey.Factory("000D62:StatsOnKill.esp");
// Survival Mode's -150 carry weight; with Stats On Kill's 10 base it pins you overencumbered
var survivalCarry = FormKey.Factory("000887:ccQDRSSE001-SurvivalMode.esl");
var survivalToggle = FormKey.Factory("000828:ccQDRSSE001-SurvivalMode.esl");
var gold = FormKey.Factory("00000F:Skyrim.esm");
var tamriel = "00003C:Skyrim.esm";
var solstheim = "000800:Dragonborn.esm";

// Party-wipe respawn points: (map marker, hold location, worldspace, discovery marker), capitals first.
// Walled cities land at their stables, which is outside in Tamriel, but count as found once the city is.
(string Marker, string Hold, string World, string? Found)[] towns =
[
    ("072879:Skyrim.esm", "016772:Skyrim.esm", tamriel, "0162CE:Skyrim.esm"), // Whiterun Stables
    ("01635E:Skyrim.esm", "016770:Skyrim.esm", tamriel, "04D0F4:Skyrim.esm"), // Katla's Farm, Solitude
    ("09846F:Skyrim.esm", "01676A:Skyrim.esm", tamriel, "038436:Skyrim.esm"), // Windhelm Stables
    ("096A46:Skyrim.esm", "01676C:Skyrim.esm", tamriel, "01C390:Skyrim.esm"), // Riften Stables
    ("0E962F:Skyrim.esm", "016769:Skyrim.esm", tamriel, "01C38A:Skyrim.esm"), // Markarth Stables
    ("017760:Skyrim.esm", "01676F:Skyrim.esm", tamriel, null), // Falkreath
    ("01773A:Skyrim.esm", "01676D:Skyrim.esm", tamriel, null), // Dawnstar
    ("0177EF:Skyrim.esm", "01676B:Skyrim.esm", tamriel, null), // Winterhold
    ("0177B0:Skyrim.esm", "01676E:Skyrim.esm", tamriel, null), // Morthal
    ("0143DC:Dragonborn.esm", "016E2A:Dragonborn.esm", solstheim, null), // Raven Rock
    ("0162A4:Skyrim.esm", "016772:Skyrim.esm", tamriel, null), // Riverwood
    ("0177CC:Skyrim.esm", "016772:Skyrim.esm", tamriel, null), // Rorikstead
    ("017791:Skyrim.esm", "01676C:Skyrim.esm", tamriel, null), // Ivarstead
    ("0177D7:Skyrim.esm", "01676C:Skyrim.esm", tamriel, null), // Shor's Stone
    ("017753:Skyrim.esm", "016770:Skyrim.esm", tamriel, null), // Dragon Bridge
    ("01779A:Skyrim.esm", "016769:Skyrim.esm", tamriel, null), // Karthwasten
    ("0177A1:Skyrim.esm", "01676A:Skyrim.esm", tamriel, null), // Kynesgrove
    ("0143E2:Dragonborn.esm", "016E2A:Dragonborn.esm", solstheim, null), // Skaal Village
];

var loadOrder = new[] { "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm", "ccQDRSSE001-SurvivalMode.esl", "StatsOnKill.esp" }
    .Select(n => ModKey.FromFileName(n)).ToArray();

var mod = new SkyrimMod(ModKey.FromFileName("SkyrimCoop.esp"), SkyrimRelease.SkyrimSE);
mod.ModHeader.Flags |= SkyrimModHeader.HeaderFlag.Small;
// 0.1 used 0x800-0x806 for since-removed records that saves still mention
mod.ModHeader.Stats.NextFormID = 0x900;

var main = mod.Quests.AddNew("SCD_CoopMainQuest");
main.Flags = Quest.Flag.StartGameEnabled;
main.Priority = 50;
main.Aliases.Add(new QuestAlias
{
    ID = 0,
    Name = "Player",
    ForcedReference = playerRef.ToNullableLink<IPlacedGetter>(),
    // bleed out instead of dying; SCD_CoopPlayer decides when to get up
    Flags = QuestAlias.Flag.Essential,
});
main.Aliases.Add(new QuestAlias
{
    ID = 1,
    Name = "RewardVictim",
    Flags = QuestAlias.Flag.Optional | QuestAlias.Flag.AllowReuseInQuest | QuestAlias.Flag.AllowDead,
});
main.NextAliasID = 2;

// Partner = closest PlayerFaction member that is not the player or a vanilla member (housecarls etc.); STR puts stand-ins in it
var finder = mod.Quests.AddNew("SCD_PartnerFinderQuest");
finder.Priority = 50;
var partnerAlias = new QuestAlias
{
    ID = 0,
    Name = "Partner",
    Flags = QuestAlias.Flag.Optional | QuestAlias.Flag.MatchingRefInLoadedArea | QuestAlias.Flag.MatchingRefClosest | QuestAlias.Flag.AllowReserved,
};
partnerAlias.Conditions.Add(Cond(new GetInFactionConditionData(), playerFaction, 1));
var esm = SkyrimMod.CreateFromBinaryOverlay(Path.Combine(gameData, "Skyrim.esm"), SkyrimRelease.SkyrimSE);
foreach (var npc in esm.Npcs.Where(n => n.Factions.Any(f => f.Faction.FormKey == playerFaction)))
    partnerAlias.Conditions.Add(Cond(new GetIsIDConditionData(), npc.FormKey, 0));
finder.Aliases.Add(partnerAlias);
finder.NextAliasID = 1;

// Compass/map marker on the partner, with a second objective while they are down
var marker = mod.Quests.AddNew("SCD_PartnerDownQuest");
marker.Name = "Co-op";
marker.Type = Quest.TypeEnum.Misc;
marker.Priority = 50;
marker.Aliases.Add(new QuestAlias { ID = 0, Name = "Partner", Flags = QuestAlias.Flag.Optional | QuestAlias.Flag.AllowReserved });
marker.NextAliasID = 1;
marker.Objectives.Add(new QuestObjective { Index = 10, DisplayText = "Your partner", Targets = { new QuestObjectiveTarget { AliasID = 0 } } });
marker.Objectives.Add(new QuestObjective { Index = 20, DisplayText = "Help your partner up", Targets = { new QuestObjectiveTarget { AliasID = 0 } } });

// index = SCD_SignalEffect.Kind; kinds added later get fixed FormIDs so older saves keep their records
string[] signalNames = ["Down", "Up", "Revive", "Credit", "Wipe"];
var signals = new List<FormKey>();
for (var kind = 0; kind < 4; kind++)
    signals.Add(Signal(kind, null, null));
signals.Add(Signal(4, new FormKey(mod.ModKey, 0x9F0), new FormKey(mod.ModKey, 0x9F1)));

FormKey Signal(int kind, FormKey? effectKey, FormKey? spellKey)
{
    var name = $"SCD_Signal{signalNames[kind]}";
    var effect = effectKey is { } ek ? mod.MagicEffects.AddNew(ek) : mod.MagicEffects.AddNew();
    effect.EditorID = name + "Effect";
    effect.Archetype = new MagicEffectArchetype { Type = MagicEffectArchetype.TypeEnum.Script };
    effect.CastType = CastType.FireAndForget;
    effect.TargetType = TargetType.TargetActor;
    effect.Flags = MagicEffect.Flag.HideInUI | MagicEffect.Flag.NoHitEvent | MagicEffect.Flag.Painless
        | MagicEffect.Flag.NoMagnitude | MagicEffect.Flag.NoArea;
    // older STR builds look for the keyword on the effect, newer ones also on the spell
    effect.Keywords = [magicRestoreHealth.ToLink<IKeywordGetter>()];
    effect.VirtualMachineAdapter = new VirtualMachineAdapter
    {
        Scripts = { new ScriptEntry { Name = "SCD_SignalEffect", Properties = { Obj("Coop", main.FormKey, 0), new ScriptIntProperty { Name = "Kind", Data = kind } } } },
    };

    var spell = spellKey is { } sk ? mod.Spells.AddNew(sk) : mod.Spells.AddNew();
    spell.EditorID = name;
    spell.Type = SpellType.Spell;
    spell.CastType = CastType.FireAndForget;
    spell.TargetType = TargetType.TargetActor;
    spell.Flags = SpellDataFlag.ManualCostCalc | SpellDataFlag.NoAbsorbOrReflect | SpellDataFlag.IgnoreResistance;
    spell.Keywords = [magicRestoreHealth.ToLink<IKeywordGetter>()];
    spell.Effects.Add(new Effect { BaseEffect = effect.ToNullableLink(), Data = new EffectData { Duration = 1 } });
    return spell.FormKey;
}

var survival = SkyrimMod.CreateFromBinaryOverlay(Path.Combine(gameData, "ccQDRSSE001-SurvivalMode.esl"), SkyrimRelease.SkyrimSE);
var carrySpell = survival.Spells[survivalCarry].DeepCopy();
carrySpell.Effects[0].Data!.Magnitude = 0;
mod.Spells.Add(carrySpell);

// Survival's hunger, tiredness and cold pulses blur the screen, which made him feel sick; keep the tint, drop the blur
foreach (var imad in survival.ImageSpaceAdapters)
{
    var calm = imad.DeepCopy();
    foreach (var frames in new[] { calm.BlurRadius, calm.DepthOfFieldStrength, calm.RadialBlurStrength })
        foreach (var frame in frames ?? [])
            frame.Value = 0;
    mod.ImageSpaceAdapters.Add(calm);
}
// Stats On Kill's reward script, configured exactly like its own victim alias
var sok = SkyrimMod.CreateFromBinaryOverlay(sokPath, SkyrimRelease.SkyrimSE);
var sokScript = sok.Quests[sokQuest].VirtualMachineAdapter!.Aliases.Single().Scripts.Single(s => s.Name == "neth_StatsOnKillScript");
var reward = new ScriptEntry { Name = "SCD_RewardAlias" };
foreach (var p in sokScript.Properties)
    reward.Properties.Add(p.Name == "Victim" ? Obj("Victim", main.FormKey, 1) : (ScriptProperty)p.DeepCopy());

main.VirtualMachineAdapter = new QuestAdapter
{
    Aliases =
    {
        new QuestFragmentAlias
        {
            Property = new ScriptObjectProperty { Object = main.ToLink<ISkyrimMajorRecordGetter>(), Alias = 0 },
            Scripts =
            {
                new ScriptEntry
                {
                    Name = "SCD_CoopPlayer",
                    Properties =
                    {
                        Obj("Finder", finder.FormKey),
                        Obj("FoundPartner", finder.FormKey, 0),
                        Obj("Marker", marker.FormKey),
                        Obj("MarkerTarget", marker.FormKey, 0),
                        Objs("Signals", signals),
                        Obj("WipeSignal", signals[4]),
                        Obj("Reward", main.FormKey, 1),
                        Objs("Towns", towns.Select(t => FormKey.Factory(t.Marker))),
                        Objs("TownHolds", towns.Select(t => FormKey.Factory(t.Hold))),
                        Objs("TownWorlds", towns.Select(t => FormKey.Factory(t.World))),
                        Objs("TownFound", towns.Select(t => FormKey.Factory(t.Found ?? t.Marker))),
                        Obj("SurvivalCarry", survivalCarry),
                        Obj("SurvivalOn", survivalToggle),
                        Obj("Gold", gold),
                    },
                },
                new ScriptEntry { Name = "SCD_ContainerEat" },
                new ScriptEntry { Name = "SCD_CoopSurvival" },
            },
        },
        new QuestFragmentAlias
        {
            Property = new ScriptObjectProperty { Object = main.ToLink<ISkyrimMajorRecordGetter>(), Alias = 1 },
            Scripts = { reward },
        },
    },
};

// Every kill this PC sees, shared so Stats On Kill and vanilla nodes still fire
var killQuest = mod.Quests.AddNew("SCD_KillQuest");
killQuest.Event = new RecordType("KILL");
killQuest.Priority = 50;
killQuest.VirtualMachineAdapter = new QuestAdapter
{
    Scripts = { new ScriptEntry { Name = "SCD_KillQuest", Properties = { Obj("Coop", main.FormKey, 0) } } },
};
var node = mod.StoryManagerQuestNodes.AddNew("SCD_KillNode");
node.Parent.SetTo(killActorBranch);
node.QuestFlags = StoryManagerQuestNode.QuestFlag.SharesEvent;
node.Quests.Add(new StoryManagerQuest { Quest = new FormLinkNullable<IQuestGetter>(killQuest.FormKey) });

var dir = Path.Combine(dist, "SkyrimCoop");
Directory.CreateDirectory(dir);
var path = Path.Combine(dir, mod.ModKey.FileName);
mod.BeginWrite.ToPath(path).WithLoadOrder(loadOrder).WithNoDataFolder().Write();
Console.WriteLine($"wrote {path}");

ConditionFloat Cond(ConditionData data, FormKey target, float value)
{
    switch (data)
    {
        case GetIsIDConditionData d: d.Object.Link.SetTo(target); break;
        case GetInFactionConditionData d: d.Faction.Link.SetTo(target); break;
        default: throw new ArgumentException(data.GetType().Name);
    }
    return new ConditionFloat { Data = data, ComparisonValue = value, CompareOperator = CompareOperator.EqualTo };
}

ScriptObjectProperty Obj(string name, FormKey target, short alias = -1) =>
    new() { Name = name, Object = new FormLink<ISkyrimMajorRecordGetter>(target), Alias = alias };

ScriptObjectListProperty Objs(string name, IEnumerable<FormKey> targets)
{
    var list = new ScriptObjectListProperty { Name = name };
    foreach (var t in targets)
        list.Objects.Add(Obj("", t));
    return list;
}
