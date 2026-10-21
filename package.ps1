# Builds the plugins, then zips the skill plus our built mods into dist\SkyrimCoop-kit.zip for Jesse.
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build.ps1"
$stage = "$PSScriptRoot\dist\kit\skyrim-coop"
if (Test-Path "$PSScriptRoot\dist\kit") { Remove-Item -LiteralPath "$PSScriptRoot\dist\kit" -Recurse -Force }
Copy-Item "$PSScriptRoot\skills\skyrim-coop" $stage -Recurse
New-Item -ItemType Directory "$stage\mods" | Out-Null
foreach ($m in 'SkyrimCoop') { Copy-Item "$PSScriptRoot\dist\$m" "$stage\mods\$m" -Recurse }
$zip = "$PSScriptRoot\dist\SkyrimCoop-kit.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
Compress-Archive -Path $stage -DestinationPath $zip
"Wrote $zip"
