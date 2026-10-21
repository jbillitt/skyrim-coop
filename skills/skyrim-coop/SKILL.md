---
name: skyrim-coop
description: Set up, update, test and troubleshoot Josh and Jesse's Skyrim Together Reborn co-op build (portable MO2, Stats On Kill, the SkyrimCoop patch). Use when asked to install or update the co-op Skyrim setup, fetch its mods from Nexus, run a co-op test session, collect logs for Josh, or fix something in that setup.
---

# Skyrim co-op setup

Josh and Jesse play Skyrim Special Edition together through Skyrim Together Reborn (STR), with Stats On Kill (levelling from kills) and our own patch, SkyrimCoop. It shares kill credit (when either player lands a kill, both get Stats On Kill rewards) and replaces death with a downed/revive system: at 0 health you bleed out, your partner holds E next to you for 3 seconds to get you up, or you get up yourself after 30 seconds while they are still standing. If both are down at once, or you go down with no partner nearby, the party is wiped and both wake up at the nearest town.

Everything here mirrors Josh's machine. The mod list and installer in this folder are the same files he uses, so the two installs cannot drift.

## Ground rules

- **Both PCs must match exactly.** Same game version (`1.7.104.0`), same mods, same versions, same load order. STR breaks quietly when they differ. Never update or add a mod on one PC alone; changes arrive as a new copy of this skill from Josh. The one exception is Skyland AIO (textures only), which each player sizes to their own GPU.
- **Confirm before deleting or overwriting anything** the user did not create in this session, and prefer archiving to deleting. Report outcomes plainly, including failures.
- **Nexus:** the user logs in themselves; never type a password. For each download, open its `file_id` link and get the user's go-ahead before clicking "Slow download". Never try to get round the free-account limits.
- **Stats On Kill's author forbids modifying or re-uploading their files.** Always download it from Nexus. Our patch is a separate plugin and never touches their files.
- **The game folder** only gets the files `install-mods.ps1` logs in `C:\Games\SkyrimCoop\game-root-files.txt`. Everything else lives in MO2.
- **Work in phases:** phase 1 (core), then a co-op test, then phase 2, another test, then phase 3. Do not jump ahead because a mod looks good.
- **Server settings belong to the host** (normally Josh). Turn STR's own death system off (`bEnableDeathSystem=false`): our revive system replaces it, and the two fight if both are on. Also set `bSyncPlayerCalendar=true` so dates and seasons match.

## What gets installed

`modlist.json` holds every mod with its Nexus mod id, file id, version and phase:

| Phase | Mods |
|---|---|
| 1 | SKSE 2.3.1, Address Library v13, Skyrim Together Reborn 1.8.3, Stats On Kill 1.0.2, SkyrimCoop |
| 2 | SkyUI, SSE Engine Fixes (+ preloader), Assorted Mesh Fixes, Community Shaders, Skyland AIO (optional) |
| 3 | Cathedral Weathers, USSEP |

## Setup

1. **Steam:** Skyrim Special Edition installed, launched once to the main menu, then quit. The installer refuses any version other than `1.7.104.0`. If Steam has already moved on to a newer version, stop and tell Josh; do not try to downgrade on your own.
2. **Get the kit:** download the latest build from the public link below (no GitHub account needed), then unzip it so this folder is at `%USERPROFILE%\.claude\skills\skyrim-coop`, with our built mods in its `mods\` subfolder.
   ```powershell
   $zip = "$env:TEMP\SkyrimCoop-kit.zip"
   curl.exe -sSL -o $zip https://github.com/jbillitt/skyrim-coop/releases/latest/download/SkyrimCoop-kit.zip
   tar.exe -x -f $zip -C "$env:USERPROFILE\.claude\skills"
   ```
3. **Run the installer:**
   ```powershell
   & "$env:USERPROFILE\.claude\skills\skyrim-coop\scripts\install-mods.ps1" -Phase 1
   ```
   It installs MO2 2.5.2 portable into `C:\Games\SkyrimCoop\MO2` and sets up the profile, with Papyrus logging on. It then installs every archive it finds in `Downloads`. Exit code 2 means some downloads are still missing; it prints a Nexus link for each.
4. **Missing downloads:** open each printed link in the browser. If Claude in Chrome is available, use it, check the user is logged in to Nexus, and decline optional cookies. Get the user's go-ahead, then click "Slow download". When all of them are in `Downloads`, run the installer again until it exits 0.
5. **Launch:** open `C:\Games\SkyrimCoop\MO2\ModOrganizer.exe`, choose **Skyrim Together** in the executable dropdown, then **Run**. Always launch through MO2, never through Steam. If MO2 shows its first-run wizard anyway, choose Portable → Skyrim Special Edition → Steam and keep the defaults; the installer's settings survive it. If it offers to handle Nexus links, that's optional.
6. **Later phases:** after a good co-op test, re-run with `-Phase 2`, and later `-Phase 3`.

### Solo profile (optional)

For single-player with the same mods minus co-op:
```powershell
& "$env:USERPROFILE\.claude\skills\skyrim-coop\scripts\install-mods.ps1" -Profile Solo -Phase 3
```
In MO2, pick the **Solo** profile and launch with **SKSE**, not Skyrim Together.
- **Off in Solo:** STR, our patch, Engine Fixes and Community Shaders.
- **On in Solo:** Alternate Start (skips Helgen; needs USSEP, which is phase 3).
- **Saves:** Solo keeps its own, separate from co-op.
- **Starting a run:** pick any Alternate Start option ("camping in the woods" is quickest). Then cast Stats On Kill's **Setup** power, which wipes your inventory and resets stats on purpose. Then cast **Teleport** for a random spawn. Teleport is reusable at any time.

### Skyland AIO (phase 2, optional, per player)

It's textures only, so it doesn't need to match Josh's.
- Check the GPU's VRAM: `HardwareInformation.qwMemorySize` under `HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*`. Check the screen resolution too.
- **8 GB+ VRAM at 1440p or higher:** the main "Skyland AIO" file (2K, 6.5 GB).
- **Otherwise:** "Skyland AIO 1k" (2.0 GB).
- Install it from MO2's Downloads tab (it has an installer with choices) and pick the **Vanilla** mountains option.

## Test session

Both players connect to the host's STR server and stand near each other, then:

1. **Kill credit:** take turns killing an enemy. Both players should get Stats On Kill's stat pop-ups for every kill either of you lands, and nothing for kills by NPCs. The partner's pop-ups can lag the killer's by a second or two.
2. **Revive:** one player gets knocked to 0 health. The other walks up and holds E for 3 seconds; the downed player should stand up. Then let the downed player wait 30 seconds alone; they should get up by themselves.
3. **Wipe:** both players get downed together. Both should wake at the nearest town.
4. **Send Josh the logs:** zip and send these, with notes on anything that didn't happen as above.
   - `Documents\My Games\Skyrim Special Edition\Logs\Script\Papyrus.0.log` (our lines start with `SCD:`)
   - `Documents\My Games\Skyrim Special Edition\SKSE\` (all `.log` files)

## Updating

When Josh says there's a new version, repeat setup step 2. It replaces this folder and leaves the game and MO2 alone. Then run `install-mods.ps1` again with the current phase. Check the version in `modlist.json` (SkyrimCoop entry) matches Josh's. It refreshes our own mods every run and only installs Nexus mods that aren't there yet.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Failed to load Skyrim Address Library" | Address Library not on, or the game updated | Re-run the installer; check the game version |
| STR says the server's mods differ | Different mod list or load order | Compare `profiles\Default\modlist.txt` and `plugins.txt` with Josh's |
| Game updated itself overnight | Steam auto-update | Tell Josh. Ask the user before changing Steam's update setting for Skyrim |
| Phase 2 crash on start | Engine Fixes isn't confirmed for 1.7.104 | Check `Documents\My Games\Skyrim Special Edition\SKSE\EngineFixes.log`; if it failed, tell Josh |
| Download sits at 0 bytes as `Unconfirmed NNN.crdownload` | Chrome is waiting on a prompt | Ask the user to open Ctrl+J and click Keep/Resume on that entry |
| Nexus shows "Download this large file" after Slow download | Files over 500 MB get a choice | Pick **Standard download** |
| Stats On Kill gives nothing for party kills | Patch not loading, or the partner isn't found | Check `SkyrimCoop.esp` is ticked and loads after `StatsOnKill.esp`; send logs |
| Going down respawns you after 5 seconds | STR's own death system is still on | The host sets `bEnableDeathSystem=false` in `STServer.ini` and restarts the server |
