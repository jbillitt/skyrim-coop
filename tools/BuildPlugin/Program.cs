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
var tamriel = "00003C:Skyrim.esm";
var solstheim = "000800:Dragonborn.esm";

// Party-wipe respawn points: (map marker, hold location, worldspace), capitals first.
// Walled cities use their stables marker, which is outside in Tamriel.
(string Marker, string Hold, string World)[] towns =
[
    ("072879:Skyrim.esm", "016772:Skyrim.esm", tamriel), // Whiterun Stables
    ("01635E:Skyrim.esm", "016770:Skyrim.esm", tamriel), // Katla's Farm, Solitude
    ("09846F:Skyrim.esm", "01676A:Skyrim.esm", tamriel), // Windhelm Stables
    ("096A46:Skyrim.esm", "01676C:Skyrim.esm", tamriel), // Riften Stables
    ("0E962F:Skyrim.esm", "016769:Skyrim.esm", tamriel), // Markarth Stables
    ("017760:Skyrim.esm", "01676F:Skyrim.esm", tamriel), // Falkreath
    ("01773A:Skyrim.esm", "01676D:Skyrim.esm", tamriel), // Dawnstar
    ("0177EF:Skyrim.esm", "01676B:Skyrim.esm", tamriel), // Winterhold
    ("0177B0:Skyrim.esm", "01676E:Skyrim.esm", tamriel), // Morthal
    ("0143DC:Dragonborn.esm", "016E2A:Dragonborn.esm", solstheim), // Raven Rock
    ("0162A4:Skyrim.esm", "016772:Skyrim.esm", tamriel), // Riverwood
    ("0177CC:Skyrim.esm", "016772:Skyrim.esm", tamriel), // Rorikstead
    ("017791:Skyrim.esm", "01676C:Skyrim.esm", tamriel), // Ivarstead
    ("0177D7:Skyrim.esm", "01676C:Skyrim.esm", tamriel), // Shor's Stone
    ("017753:Skyrim.esm", "016770:Skyrim.esm", tamriel), // Dragon Bridge
    ("01779A:Skyrim.esm", "016769:Skyrim.esm", tamriel), // Karthwasten
    ("0177A1:Skyrim.esm", "01676A:Skyrim.esm", tamriel), // Kynesgrove
    ("0143E2:Dragonborn.esm", "016E2A:Dragonborn.esm", solstheim), // Skaal Village
];

var loadOrder = new[] { "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm", "StatsOnKill.esp" }
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

string[] signalNames = ["Down", "Up", "Revive", "Credit"]; // index = SCD_SignalEffect.Kind
var signals = new List<FormKey>();
for (var kind = 0; kind < signalNames.Length; kind++)
{
    var effect = mod.MagicEffects.AddNew($"SCD_Signal{signalNames[kind]}Effect");
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

    var spell = mod.Spells.AddNew($"SCD_Signal{signalNames[kind]}");
    spell.Type = SpellType.Spell;
    spell.CastType = CastType.FireAndForget;
    spell.TargetType = TargetType.TargetActor;
    spell.Flags = SpellDataFlag.ManualCostCalc | SpellDataFlag.NoAbsorbOrReflect | SpellDataFlag.IgnoreResistance;
    spell.Keywords = [magicRestoreHealth.ToLink<IKeywordGetter>()];
    spell.Effects.Add(new Effect { BaseEffect = effect.ToNullableLink(), Data = new EffectData { Duration = 1 } });
    signals.Add(spell.FormKey);
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
                        Objs("Signals", signals),
                        Obj("Reward", main.FormKey, 1),
                        Objs("Towns", towns.Select(t => FormKey.Factory(t.Marker))),
                        Objs("TownHolds", towns.Select(t => FormKey.Factory(t.Hold))),
                        Objs("TownWorlds", towns.Select(t => FormKey.Factory(t.World))),
                    },
                },
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
