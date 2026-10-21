# skyrim-coop

A small co-op patch and setup kit for playing Skyrim Special Edition (1.7.104) with [Skyrim Together Reborn](https://www.nexusmods.com/skyrimspecialedition/mods/69993) and [Stats On Kill](https://www.nexusmods.com/skyrimspecialedition/mods/183621).

**SkyrimCoop.esp** gives Stats On Kill's rewards to a party member who is standing near the player who made the kill, not only to the killer. It's a separate patch plugin: it needs Stats On Kill installed from Nexus and does not include or change any of its files.

## Use it

Download `SkyrimCoop-kit.zip` from the [latest release](https://github.com/jbillitt/skyrim-coop/releases/latest). It's a [Claude Code](https://claude.com/claude-code) skill (`skyrim-coop/SKILL.md`) plus the built plugins. It also works by hand: `skyrim-coop/scripts/install-mods.ps1` sets up a portable Mod Organizer 2 from the mods listed in `modlist.json`, all downloaded from their Nexus pages.

## Build it

Needs the Skyrim SE Creation Kit (for the Papyrus compiler), the .NET 10 SDK, SKSE and Stats On Kill's archive.

```powershell
.\build.ps1     # compiles scripts and generates the plugins into dist\
.\package.ps1   # build, then zip the skill and plugins into dist\SkyrimCoop-kit.zip
```

All credit for Stats On Kill goes to Nethalythic, and for Skyrim Together Reborn to the Together Team.
