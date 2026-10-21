# Builds dist\SkyrimCoop and dist\SkyrimCoopProbe (each an MO2 mod folder).
# Needs: Skyrim SE + Creation Kit (Papyrus compiler), SKSE 2.3.1 archive, Stats On Kill's esp.
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition',
    [string]$SkseArchive = "$env:USERPROFILE\Downloads\Skyrim Script Extender (SKSE64) Steam 30379 2.3.1 2026-08-27T16-52Z s6Og0dG94.7z",
    [string]$StatsOnKillEsp = 'C:\Games\SkyrimCoop\_installers\StatsOnKill\StatsOnKill\StatsOnKill.esp'
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$deps = Join-Path $root '.deps'
$dist = Join-Path $root 'dist'

function Need($path, $what) { if (-not (Test-Path $path)) { throw "Missing $what at $path" } }
Need "$Game\Papyrus Compiler\PapyrusCompiler.exe" 'Papyrus compiler (install the Creation Kit)'
Need $StatsOnKillEsp 'StatsOnKill.esp'

# Script sources we compile against; extracted once, never into the game folder
if (-not (Test-Path "$deps\vanilla\Source\Scripts\Actor.psc")) {
    New-Item -ItemType Directory -Force "$deps\vanilla" | Out-Null
    tar.exe -x -f "$Game\Data\Scripts.zip" -C "$deps\vanilla"
    if ($LASTEXITCODE) { throw 'Extracting Scripts.zip failed' }
}
$skseSrc = Get-ChildItem "$deps\skse" -Directory -Filter skse64_* -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $skseSrc) {
    Need $SkseArchive 'SKSE archive'
    New-Item -ItemType Directory -Force "$deps\skse" | Out-Null
    tar.exe -x -f $SkseArchive -C "$deps\skse"
    if ($LASTEXITCODE) { throw 'Extracting SKSE failed' }
    $skseSrc = Get-ChildItem "$deps\skse" -Directory -Filter skse64_* | Select-Object -First 1
}
if (-not (Test-Path "$deps\str\SkyrimTogetherUtils.psc")) {
    New-Item -ItemType Directory -Force "$deps\str" | Out-Null
    gh api repos/tiltedphoques/TiltedEvolution/contents/GameFiles/Skyrim/scripts/source/SkyrimTogetherUtils.psc -H 'Accept: application/vnd.github.raw' |
        Set-Content -Encoding ascii "$deps\str\SkyrimTogetherUtils.psc"
}

$vanilla = "$deps\vanilla\Source\Scripts"
$imports = @("$deps\str", "$($skseSrc.FullName)\Data\Scripts\Source", $vanilla)

function Compile($sourceDir, $outDir) {
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $inc = (@($sourceDir) + $imports) -join ';'
    & "$Game\Papyrus Compiler\PapyrusCompiler.exe" $sourceDir -all -q "-f=$vanilla\TESV_Papyrus_Flags.flg" "-i=$inc" "-o=$outDir"
    if ($LASTEXITCODE) { throw "Papyrus compile failed for $sourceDir" }
}

Compile "$root\Scripts\Source" "$dist\SkyrimCoop\Scripts"
Compile "$root\probe\Scripts\Source" "$dist\SkyrimCoopProbe\Scripts"

dotnet run --project "$root\tools\BuildPlugin" -c Release -- $StatsOnKillEsp $dist
if ($LASTEXITCODE) { throw 'Plugin generation failed' }

Get-ChildItem $dist -Recurse -File | ForEach-Object { $_.FullName.Substring($dist.Length + 1) }
