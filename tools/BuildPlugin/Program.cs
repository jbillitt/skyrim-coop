// Generates SkyrimCoop.esp and SkyrimCoopProbe.esp.
// Usage: BuildPlugin <path to StatsOnKill.esp> <dist dir>
using Mutagen.Bethesda;
using Mutagen.Bethesda.Plugins;
using Mutagen.Bethesda.Skyrim;

var sokPath = args[0];
var dist = args[1];

var playerNpc = FormKey.Factory("000007:Skyrim.esm");
var playerRef = FormKey.Factory("000014:Skyrim.esm");
var killActorBranch = FormKey.Factory("013010:Skyrim.esm");
var sokNode = FormKey.Factory("003311:StatsOnKill.esp");
const ushort EventR2 = 0x3252; // "R2": the killer in a Kill Actor event
const float CreditRange = 2048f; // units, about 30 m

var loadOrder = new[] { "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm", "StatsOnKill.esp" }
    .Select(n => ModKey.FromFileName(n)).ToArray();

BuildCoop();
BuildProbe();

void BuildCoop()
{
    var mod = NewLightMod("SkyrimCoop.esp");

    var party = mod.Factions.AddNew("SCD_PartyFaction");
    party.Flags = Faction.FactionFlag.HiddenFromPC;

    var tagEffect = mod.MagicEffects.AddNew("SCD_PartyTagEffect");
    tagEffect.Archetype = new MagicEffectArchetype { Type = MagicEffectArchetype.TypeEnum.Script };
    tagEffect.CastType = CastType.Concentration;
    tagEffect.TargetType = TargetType.Touch;
    tagEffect.Flags = MagicEffect.Flag.HideInUI | MagicEffect.Flag.NoHitEvent | MagicEffect.Flag.Painless
        | MagicEffect.Flag.NoMagnitude | MagicEffect.Flag.NoArea | MagicEffect.Flag.NoDuration;
    tagEffect.VirtualMachineAdapter = Script("SCD_PartyTagEffect", ("SCD_PartyFaction", party.FormKey));

    var tagSpell = mod.Spells.AddNew("SCD_PartyTagSpell");
    tagSpell.Type = SpellType.Spell;
    tagSpell.CastType = CastType.Concentration;
    tagSpell.TargetType = TargetType.Touch;
    tagSpell.Flags = SpellDataFlag.NoAbsorbOrReflect | SpellDataFlag.IgnoreResistance;
    tagSpell.Effects.Add(new Effect
    {
        BaseEffect = tagEffect.ToNullableLink(),
        Data = new EffectData(),
        // once tagged, stop re-applying
        Conditions = { Cond(new GetInFactionConditionData { RunOnType = Condition.RunOnType.Subject }, party.FormKey, 0) },
    });

    var cloakEffect = mod.MagicEffects.AddNew("SCD_PartyCloakEffect");
    var cloakArchetype = new MagicEffectArchetype { Type = MagicEffectArchetype.TypeEnum.Cloak };
    cloakArchetype.Association.SetTo(tagSpell.FormKey);
    cloakEffect.Archetype = cloakArchetype;
    cloakEffect.CastType = CastType.ConstantEffect;
    cloakEffect.TargetType = TargetType.Self;
    cloakEffect.Flags = MagicEffect.Flag.HideInUI | MagicEffect.Flag.NoHitEvent | MagicEffect.Flag.Painless | MagicEffect.Flag.NoDuration;

    var cloak = mod.Spells.AddNew("SCD_PartyCloakAbility");
    cloak.Type = SpellType.Ability;
    cloak.CastType = CastType.ConstantEffect;
    cloak.TargetType = TargetType.Self;
    // cloak magnitude is the radius in feet; ~100 ft covers CreditRange
    cloak.Effects.Add(new Effect { BaseEffect = cloakEffect.ToNullableLink(), Data = new EffectData { Magnitude = 100 } });

    var quest = mod.Quests.AddNew("SCD_CoopQuest");
    quest.Flags = Quest.Flag.StartGameEnabled;
    quest.Priority = 50;
    quest.Aliases.Add(new QuestAlias
    {
        ID = 0,
        Name = "Player",
        ForcedReference = playerRef.ToNullableLink<IPlacedGetter>(),
        Spells = { cloak.ToLink() },
    });
    quest.NextAliasID = 1;

    // Stats On Kill credits only kills by the local player; also accept a tagged party member in range.
    // Skyrim groups ORs before ANDs, so (A OR B) AND (A OR C) means A OR (B AND C).
    var sok = SkyrimMod.CreateFromBinaryOverlay(sokPath, SkyrimRelease.SkyrimSE);
    var node = mod.StoryManagerQuestNodes.GetOrAddAsOverride(sok.StoryManagerQuestNodes[sokNode]);
    node.Conditions.Clear();
    node.Conditions.Add(KillerIsPlayer(Condition.Flag.OR));
    node.Conditions.Add(Cond(new GetInFactionConditionData(), party.FormKey, 1, killer: true));
    node.Conditions.Add(KillerIsPlayer(Condition.Flag.OR));
    node.Conditions.Add(Cond(new GetDistanceConditionData(), playerRef, CreditRange, CompareOperator.LessThan, killer: true));

    Write(mod, Path.Combine(dist, "SkyrimCoop"));
}

void BuildProbe()
{
    var mod = NewLightMod("SkyrimCoopProbe.esp");

    var quest = mod.Quests.AddNew("SCD_ProbeKillQuest");
    quest.Event = new RecordType("KILL");
    quest.Priority = 50;
    quest.VirtualMachineAdapter = new QuestAdapter { Scripts = { new ScriptEntry { Name = "SCD_ProbeKillQuestScript" } } };

    var node = mod.StoryManagerQuestNodes.AddNew("SCD_ProbeKillNode");
    node.Parent.SetTo(killActorBranch);
    // share the event so Stats On Kill and vanilla nodes still fire
    node.QuestFlags = StoryManagerQuestNode.QuestFlag.SharesEvent;
    node.Quests.Add(new StoryManagerQuest { Quest = new FormLinkNullable<IQuestGetter>(quest.FormKey) });

    Write(mod, Path.Combine(dist, "SkyrimCoopProbe"));
}

SkyrimMod NewLightMod(string name)
{
    var mod = new SkyrimMod(ModKey.FromFileName(name), SkyrimRelease.SkyrimSE);
    mod.ModHeader.Flags |= SkyrimModHeader.HeaderFlag.Small;
    return mod;
}

ConditionFloat KillerIsPlayer(Condition.Flag flags)
{
    var c = Cond(new GetIsIDConditionData(), playerNpc, 1, killer: true);
    c.Flags = flags;
    return c;
}

ConditionFloat Cond(ConditionData data, FormKey target, float value, CompareOperator op = CompareOperator.EqualTo, bool killer = false)
{
    if (killer)
    {
        data.RunOnType = Condition.RunOnType.EventData;
        data.RunOnTypeIndex = EventR2;
    }
    switch (data)
    {
        case GetIsIDConditionData d: d.Object.Link.SetTo(target); break;
        case GetInFactionConditionData d: d.Faction.Link.SetTo(target); break;
        case GetDistanceConditionData d: d.Target.Link.SetTo(target); break;
        default: throw new ArgumentException(data.GetType().Name);
    }
    return new ConditionFloat { Data = data, ComparisonValue = value, CompareOperator = op };
}

VirtualMachineAdapter Script(string name, params (string Name, FormKey Target)[] props)
{
    var entry = new ScriptEntry { Name = name };
    foreach (var (propName, target) in props)
        entry.Properties.Add(new ScriptObjectProperty { Name = propName, Object = new FormLink<ISkyrimMajorRecordGetter>(target) });
    return new VirtualMachineAdapter { Scripts = { entry } };
}

void Write(SkyrimMod mod, string dir)
{
    Directory.CreateDirectory(dir);
    var path = Path.Combine(dir, mod.ModKey.FileName);
    mod.BeginWrite.ToPath(path).WithLoadOrder(loadOrder).WithNoDataFolder().Write();
    Console.WriteLine($"wrote {path}");
}
