param([string]$GodotExe = $env:GODOT_EXE, [string]$OutputDirectory = '')
# V1.5.1 Windows export only (the full release run is tools/RUN_WIN151_A.bat -> V -> B).
# Exports DVD_BATTLE_1.5.1.exe; refuses any other release folder so a shipped EXE is never overwritten.
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if (-not $GodotExe) { $GodotExe = Join-Path (Split-Path -Parent $projectDirectory) 'DVD_BATTLE_1.2.1_RECOVERY_WORK\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw 'Supply -GodotExe with a Godot 4.7.2 executable path.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path -Parent $projectDirectory) 'DVD_BATTLE_1.5.1_RELEASE' }
$leaf = Split-Path -Leaf ([IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\'))
if ($leaf -match '^DVD_BATTLE_[0-9.]+_RELEASE$' -and $leaf -ne 'DVD_BATTLE_1.5.1_RELEASE') { throw "Refusing to export into a shipped release folder: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$exportTarget = Join-Path $OutputDirectory 'DVD_BATTLE_1.5.1.exe'
& $GodotExe --headless --path $projectDirectory --editor --export-release 'Windows Desktop' $exportTarget
if ($LASTEXITCODE -ne 0) { throw "Godot export failed: $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $exportTarget -PathType Leaf)) { throw 'Export did not create the executable.' }
Get-FileHash -LiteralPath $exportTarget -Algorithm SHA256
