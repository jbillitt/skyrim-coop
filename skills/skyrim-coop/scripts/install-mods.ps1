<#
Sets up (or updates) the portable MO2 co-op instance from modlist.json. Safe to re-run.
  -Phase 1|2|3   enable mods up to this phase (others stay installed but off)
  -NoProbe       leave the test plugin off
  -LocalMods     folder holding our own built mods (SkyrimCoop, SkyrimCoopProbe)
  -Profile       Default (co-op) or Solo (no STR, own saves); mods opt out with "coop": false / "solo": false
Exit code 2 means some archives still need downloading; the missing list prints with Nexus links.
#>
param(
    [ValidateRange(1, 3)][int]$Phase = 1,
    [ValidateSet('Default', 'Solo')][string]$Profile = 'Default',
    [switch]$NoProbe,
    [string]$Root = 'C:\Games\SkyrimCoop',
    [string]$LocalMods = (Join-Path $PSScriptRoot '..\mods'),
    [string]$Downloads = (Join-Path $env:USERPROFILE 'Downloads')
)
$ErrorActionPreference = 'Stop'
$list = Get-Content -Raw (Join-Path $PSScriptRoot '..\modlist.json') | ConvertFrom-Json
$mo = Join-Path $Root 'MO2'
$profileDir = Join-Path $mo "profiles\$Profile"
$solo = $Profile -eq 'Solo'
$rootLog = Join-Path $Root 'game-root-files.txt'
$tmp = Join-Path $Root '_extract'

function Find-GamePath {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath -replace '/', '\'
    $libs = @($steam) + (Select-String -Path "$steam\steamapps\libraryfolders.vdf" -Pattern '"path"\s+"([^"]+)"' |
        ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' })
    foreach ($l in $libs | Select-Object -Unique) {
        if (Test-Path "$l\steamapps\appmanifest_$($list.game.steamAppId).acf") {
            return "$l\steamapps\common\Skyrim Special Edition"
        }
    }
    throw 'Skyrim Special Edition is not installed in any Steam library'
}

function Find-Archive($mod) {
    $token = "(^|[ -])$($mod.modId)([ -.]|$)"
    foreach ($dir in (Join-Path $mo 'downloads'), $Downloads) {
        $hit = Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $mod.match -and $_.Name -match $token -and $_.Extension -in '.7z', '.zip', '.rar' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { return $hit }
    }
}

function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text) }

# --- game ---
$game = Find-GamePath
$ver = (Get-Item "$game\SkyrimSE.exe").VersionInfo.FileVersion
if ($ver -ne $list.game.version) { throw "SkyrimSE.exe is $ver, this setup needs $($list.game.version). Both players must match." }
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Skyrim Special Edition'
if (-not (Test-Path "$docs\Skyrim.ini")) { throw 'Launch Skyrim once from Steam (to the main menu, then quit) so it creates its ini files' }
"Game: $game ($ver)"

# --- MO2 ---
if (-not (Test-Path "$mo\ModOrganizer.exe")) {
    New-Item -ItemType Directory -Force $mo | Out-Null
    $zip = Join-Path $Root "Mod.Organizer-$($list.mo2.version).7z"
    curl.exe -sSL -o $zip $list.mo2.url
    & tar.exe -x -f $zip -C $mo
    if ($LASTEXITCODE -ne 0) { throw 'MO2 extract failed' }
    "Installed MO2 $($list.mo2.version)"
}
Write-Text "$mo\portable.txt" ''
foreach ($d in 'mods', 'downloads', 'overwrite', "profiles\$Profile") { New-Item -ItemType Directory -Force (Join-Path $mo $d) | Out-Null }
$g = $game -replace '\\', '/'
$strDir = "$($mo -replace '\\', '/')/mods/Skyrim Together Reborn/SkyrimTogetherReborn"
if (-not (Test-Path "$mo\ModOrganizer.ini")) {
    $exes = @(
        @('Skyrim Together', "$strDir/SkyrimTogether.exe", $strDir),
        @('SKSE', "$g/skse64_loader.exe", $g),
        @('Skyrim Special Edition', "$g/SkyrimSE.exe", $g)
    )
    $ini = "[General]`r`ngameName=Skyrim Special Edition`r`ngamePath=@ByteArray($($game -replace '\\', '\\'))`r`ngameEdition=Steam`r`ngame_edition=Steam`r`nselected_profile=@ByteArray(Default)`r`nfirst_start=false`r`nversion=$($list.mo2.version)`r`n`r`n[customExecutables]`r`nsize=$($exes.Count)`r`n"
    for ($i = 0; $i -lt $exes.Count; $i++) {
        $n = $i + 1
        $ini += "$n\arguments=`r`n$n\binary=$($exes[$i][1])`r`n$n\hide=false`r`n$n\ownicon=true`r`n$n\steamAppID=`r`n$n\title=$($exes[$i][0])`r`n$n\toolbar=true`r`n$n\workingDirectory=$($exes[$i][2])`r`n"
    }
    Write-Text "$mo\ModOrganizer.ini" $ini
}

# --- profile: local inis copied from the game's, with Papyrus logging on for the probe ---
# Solo keeps its own saves so co-op characters never load without STR
Write-Text "$profileDir\settings.ini" "[General]`r`nLocalSaves=$($solo.ToString().ToLower())`r`nLocalSettings=true`r`nAutomaticArchiveInvalidation=false`r`n"
if ($solo) { New-Item -ItemType Directory -Force "$profileDir\saves" | Out-Null }
foreach ($f in 'Skyrim.ini', 'SkyrimPrefs.ini', 'SkyrimCustom.ini') {
    $dest = Join-Path $profileDir $f.ToLower()
    if (-not (Test-Path $dest)) {
        if (Test-Path "$docs\$f") { Copy-Item "$docs\$f" $dest } else { Write-Text $dest '' }
    }
}
$skyIni = Join-Path $profileDir 'skyrim.ini'
$t = [IO.File]::ReadAllText($skyIni)
foreach ($k in 'bEnableLogging', 'bEnableTrace', 'bLoadDebugInformation') {
    if ($t -match "(?m)^$k=") { $t = $t -replace "(?m)^$k=\d", "$k=1" }
    elseif ($t -match '(?m)^\[Papyrus\]') { $t = $t -replace '(?m)^\[Papyrus\]\r?\n', "[Papyrus]`r`n$k=1`r`n" }
    else { $t += "`r`n[Papyrus]`r`n$k=1`r`n" }
}
Write-Text $skyIni $t

# --- mods ---
$missing = @()
$logged = @(if (Test-Path $rootLog) { Get-Content $rootLog })
foreach ($m in $list.mods) {
    $inProfile = if ($solo) { $m.solo -ne $false } else { $m.coop -ne $false }
    $enabled = $inProfile -and $m.phase -le $Phase -and -not ($m.testOnly -and $NoProbe)
    $dest = Join-Path $mo "mods\$($m.name)"
    $m | Add-Member -NotePropertyName enabled -NotePropertyValue $enabled -Force

    if ($m.local) {
        $src = Join-Path $LocalMods $m.name
        if (Test-Path $src) {
            if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            Copy-Item $src $dest -Recurse
            Write-Text "$dest\meta.ini" "[General]`r`ngameName=SkyrimSE`r`nversion=$($m.version)`r`n"
        } elseif ($enabled) { $missing += "$($m.name): our own build, get the kit from https://github.com/jbillitt/skyrim-coop/releases/latest" }
        continue
    }

    $archive = Find-Archive $m
    if (-not $archive) {
        if ($enabled -and -not $m.optional) { $missing += "$($m.name) $($m.version): https://www.nexusmods.com/skyrimspecialedition/mods/$($m.modId)?tab=files&file_id=$($m.fileId)" }
        $m.enabled = $false
        continue
    }
    $stored = Join-Path $mo "downloads\$($archive.Name)"
    if (-not (Test-Path -LiteralPath $stored)) { Copy-Item -LiteralPath $archive.FullName $stored }
    # Wabbajack reads these to know each archive's Nexus source
    Write-Text "$stored.meta" "[General]`r`ngameName=skyrimse`r`nmodID=$($m.modId)`r`nfileID=$($m.fileId)`r`nversion=$($m.version)`r`nrepository=Nexus`r`ninstalled=true`r`n"

    if ($m.fomod) {
        if (-not (Test-Path $dest)) { "$($m.name): install it from MO2's Downloads tab (it has an installer with choices)"; $m.enabled = $false }
        continue
    }
    if ($m.include -and -not (Test-Path $dest)) {
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        New-Item -ItemType Directory $tmp | Out-Null
        & tar.exe -x -f $stored -C $tmp
        if ($LASTEXITCODE -ne 0) { throw "Could not extract $($archive.Name)" }
        New-Item -ItemType Directory $dest | Out-Null
        foreach ($s in $m.include) { Copy-Item -Path (Join-Path (Join-Path $tmp $s) '*') -Destination $dest -Recurse -Force }
        Write-Text "$dest\meta.ini" "[General]`r`ngameName=SkyrimSE`r`nmodid=$($m.modId)`r`nversion=$($m.version)`r`ninstallationFile=$($archive.Name)`r`nrepository=Nexus`r`n[installedFiles]`r`n1\modid=$($m.modId)`r`n1\fileid=$($m.fileId)`r`nsize=1`r`n"
        "Installed $($m.name) $($m.version)"
    }

    # Files the game loads directly from its own folder, outside MO2
    if ($m.gameRoot) {
        foreach ($f in $m.gameRoot.files) {
            $target = Join-Path $game $f
            if ($enabled -and -not (Test-Path $target)) {
                if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
                New-Item -ItemType Directory $tmp | Out-Null
                & tar.exe -x -f $stored -C $tmp
                Copy-Item (Join-Path (Join-Path $tmp $m.gameRoot.from) $f) $target
                $logged += $target
                "Game folder: added $f"
            } elseif (-not $enabled -and (Test-Path $target) -and ($logged -contains $target)) {
                Remove-Item -LiteralPath $target
                $logged = @($logged | Where-Object { $_ -ne $target })
                "Game folder: removed $f (its phase is off)"
            }
        }
    }
}
if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
[IO.File]::WriteAllLines($rootLog, [string[]]@($logged | Sort-Object -Unique))

# --- modlist.txt (first line = highest priority) and plugins.txt; unknown entries are kept ---
$known = $list.mods | ForEach-Object { $_.name }
$ml = @($list.mods | Where-Object { Test-Path (Join-Path $mo "mods\$($_.name)") } | ForEach-Object { $(if ($_.enabled) { '+' } else { '-' }) + $_.name })
[array]::Reverse($ml)
$oldMl = @(if (Test-Path "$profileDir\modlist.txt") { Get-Content "$profileDir\modlist.txt" | Where-Object { $_ -and $known -notcontains $_.Substring(1) } })
[IO.File]::WriteAllLines("$profileDir\modlist.txt", [string[]]($oldMl + $ml))

$ordered = @($list.mods | Where-Object { $_.loadFirst }) + @($list.mods | Where-Object { -not $_.loadFirst })
$pl = @()
foreach ($m in $ordered) { foreach ($p in $m.plugins) { $pl += $(if ($m.enabled) { "*$p" } else { $p }) } }
$knownPlugins = $list.mods | ForEach-Object { $_.plugins } | Where-Object { $_ }
$oldPl = @(if (Test-Path "$profileDir\plugins.txt") { Get-Content "$profileDir\plugins.txt" | Where-Object { $_ -and $knownPlugins -notcontains $_.TrimStart('*') } })
[IO.File]::WriteAllLines("$profileDir\plugins.txt", [string[]]($oldPl + $pl))

""
"Phase $Phase enabled: " + (($list.mods | Where-Object { $_.enabled } | ForEach-Object { $_.name }) -join ', ')
if ($missing) {
    ""
    "Still needed (open each link, then Slow download):"
    $missing | ForEach-Object { "  $_" }
    exit 2
}
