<#
DVD BATTLE V2.0 Codex-worktree helper (NOT shipped; lives in zz_work which git ignores).

  -Mode check   : headless import (compile) of -Root. Prints every SCRIPT ERROR / ERROR / WARNING line. Exit 1 if errors.
  -Mode suite   : headless script test, e.g. -Suite mechanics_122 (runs res://tests/<Suite>.gd in -Root).
  -Mode shot    : renders the game in an ISOLATED QA copy of -Root (custom user dir, never the real profile)
                  and saves a PNG. -AppArgs are the app dev args, e.g. '--goto=codex'. -Out is the PNG path.
  -Mode shots   : standard screenshot set of every screen into -OutDir (default zz_work/shots/<rootleaf>).
  -Mode uitest  : runs a rendered UI test scene (deathmatch_ui_15, control_ui_13, preview_ui_14, codex_ui_151)
                  in the isolated QA copy and prints PASS/FAIL lines.

Examples (PowerShell):
  powershell -NoProfile -ExecutionPolicy Bypass -File D:\DVD_BATTLE_2.0_codex\zz_work\tools\gd.ps1 -Mode check -Root D:\DVD_BATTLE_2.0_codex
  ... -Mode shot -Root <worktree> -AppArgs '--goto=codex' -Out D:\DVD_BATTLE_2.0_codex\zz_work\shots\codex.png
  ... -Mode shots -Root <worktree>
  ... -Mode uitest -Root <worktree> -Suite deathmatch_ui_15
From Git Bash use:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\DVD_BATTLE_2.0_codex\zz_work\tools\gd.ps1' -Mode check -Root 'D:\...'
#>
param(
    [string]$Mode = 'check',
    [string]$Root = '',
    [string]$Suite = '',
    [string]$AppArgs = '',
    [string]$Out = '',
    [string]$OutDir = '',
    [int]$Frames = 90,
    [string]$Res = '1600x900',
    [string]$RenderExecutable = '',
    [string]$PythonExe = 'py',
    [ValidateRange(1, 900)][int]$TimeoutSeconds = 900,
    [switch]$NoSync
)
$ErrorActionPreference = 'Stop'
$G = 'D:\DVD_BATTLE_1.2.1_RECOVERY_WORK\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
$Main = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($Root -eq '') { $Root = $Main }
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$leaf = ($Root -replace '[:\\/ ]', '_').Trim('_')
if ($leaf.Length -gt 60) { $leaf = $leaf.Substring($leaf.Length - 60) }
$QaBase = Join-Path 'D:\DVD20_QA_CODEX' $leaf
$Qa = Join-Path $QaBase 'project'
$LogDir = Join-Path $Main ('zz_work\logs\' + $leaf)
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ProcessHelper = Join-Path $Main 'zz_work\tools\gd_process.py'
$ProfileRoot = Join-Path 'D:\DVD20_CODEX_SCRATCH\godot_profiles' $leaf
$Utf8 = New-Object Text.UTF8Encoding($false)

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $Utf8)
}

function Assert-QaDestination([string]$Path) {
    $allowed = [IO.Path]::GetFullPath('D:\DVD20_QA_CODEX').TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $target.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing QA copy outside $allowed : $target"
    }
    $probe = $target
    while ($probe -ne '') {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing QA copy through a junction/symlink: $probe"
            }
        }
        $parent = Split-Path -Parent $probe
        if ($parent -eq $probe) { break }
        $probe = $parent
    }
    return $target
}

function Assert-QaProfile {
    $pg = Join-Path $Qa 'project.godot'
    if (-not (Test-Path -LiteralPath $pg)) { throw "Missing QA project: $pg" }
    $text = [IO.File]::ReadAllText($pg)
    if ($text -notmatch 'config/use_custom_user_dir=true' -or $text -notmatch 'config/custom_user_dir_name="DVD_BATTLE_V20_CODEX_QA"') {
        throw 'QA user profile isolation is missing'
    }
}

function Run-Godot([string[]]$GArgs, [string]$LogName, [string]$Executable = '') {
    if ($Executable -eq '') { $Executable = $G }
    $log = Join-Path $LogDir $LogName
    $request = $log + '.request.json'
    $summary = $log + '.process.json'
    $runProfile = Join-Path $ProfileRoot ([IO.Path]::GetFileNameWithoutExtension($LogName))
    $spec = @{ executable = $Executable; args = @($GArgs); log = $log; summary = $summary;
        timeout = $TimeoutSeconds; appdata = (Join-Path $runProfile 'Roaming');
        localappdata = (Join-Path $runProfile 'Local') }
    Write-Utf8 $request ($spec | ConvertTo-Json -Depth 5)
    if (Test-Path -LiteralPath $summary) { Remove-Item -LiteralPath $summary -Force }
    $runnerOutput = & $PythonExe -B -X utf8 $ProcessHelper $request 2>&1
    if (-not (Test-Path -LiteralPath $summary)) { throw "Process guard did not report: $runnerOutput" }
    $state = [IO.File]::ReadAllText($summary) | ConvertFrom-Json
    $text = [IO.File]::ReadAllText($log)
    $output = @($text -split '\r?\n')
    return @{ code = [int]$state.code; text = $text; log = $log; lines = $output;
        pid = $state.pid; timed_out = $state.timed_out; process_report = $summary }
}

function Show-Problems($r) {
    $bad = @($r.lines | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR:|Parse Error|^\s+at: |WARNING: .*\.gd' })
    foreach ($l in $bad) { Write-Host ("  " + $l) }
    return $bad.Count
}

function Ensure-Cache([string]$Dir) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.godot'))) {
        $source = Join-Path $Main '.godot'
        $target = Join-Path $Dir '.godot'
        if ($source -eq $target -or -not (Test-Path -LiteralPath $source)) { return }
        $null = robocopy $source $target /E /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw "Cache copy failed $LASTEXITCODE" }
        $global:LASTEXITCODE = 0
    }
}

function Import([string]$Dir, [string]$Tag) {
    Ensure-Cache $Dir
    for ($i = 1; $i -le 3; $i++) {
        $r = Run-Godot @('--headless', '--path', $Dir, '--editor', '--quit') ("import_${Tag}_attempt${i}.log")
        if ($r.code -ne -1073741819) { return $r }
        Write-Host "  (import crashed 0xC0000005, retry $i)"
    }
    return $r
}

function Sync-Qa {
    $null = Assert-QaDestination $Qa
    if ($NoSync -and (Test-Path -LiteralPath $Qa)) { Assert-QaProfile; return }
    New-Item -ItemType Directory -Force -Path $Qa | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $Qa '.godot'))) {
        $src = Join-Path $Root '.godot'
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $Main '.godot' }
        if (Test-Path -LiteralPath $src) {
            $null = robocopy $src (Join-Path $Qa '.godot') /E /NFL /NDL /NJH /NJS /NP
            if ($LASTEXITCODE -ge 8) { throw "QA cache copy failed $LASTEXITCODE" }
        }
    }
    $null = Assert-QaDestination $Qa
    $null = robocopy $Root $Qa /MIR /XD .godot .git zz_work zz_diag reports .claude /XF *.png.import /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
    New-Item -ItemType Directory -Force -Path (Join-Path $Qa 'reports') | Out-Null
    Write-Utf8 (Join-Path $Qa 'reports\.gdignore') ''
    $pg = Join-Path $Qa 'project.godot'
    $text = [IO.File]::ReadAllText($pg)
    if ($text -match 'config/custom_user_dir_name="[^"]*"') {
        $text = [regex]::Replace($text, 'config/custom_user_dir_name="[^"]*"', 'config/custom_user_dir_name="DVD_BATTLE_V20_CODEX_QA"')
        $text = $text.Replace('config/use_custom_user_dir=false', 'config/use_custom_user_dir=true')
        Write-Utf8 $pg $text
    }
    elseif ($text -notmatch 'use_custom_user_dir') {
        $text = $text.Replace('config/icon="res://icon.svg"', ('config/icon="res://icon.svg"' + "`n" + 'config/use_custom_user_dir=true' + "`n" + 'config/custom_user_dir_name="DVD_BATTLE_V20_CODEX_QA"'))
        Write-Utf8 $pg $text
    }
    Assert-QaProfile
    $r = Import $Qa 'qa'
    $n = Show-Problems $r
    if ($n -gt 0 -or $r.code -ne 0) { throw "QA import failed: exit=$($r.code) problems=$n log=$($r.log)" }
}

function Shot([string]$ArgsLine, [string]$Png, [int]$F) {
    $png = $Png.Replace('\', '/')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Png) | Out-Null
    $previous = if (Test-Path -LiteralPath $Png) { (Get-Item -LiteralPath $Png).LastWriteTimeUtc } else { $null }
    $list = @('--path', $Qa, '--resolution', $Res, '--')
    if ($RenderExecutable -ne '') {
        $exe = (Resolve-Path -LiteralPath $RenderExecutable).Path
        $scratch = [IO.Path]::GetFullPath('D:\DVD20_CODEX_SCRATCH').TrimEnd('\')
        if (-not $exe.StartsWith($scratch + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Rendered executable must be an export copied to dedicated scratch'
        }
        if ([IO.Path]::GetExtension($exe) -ne '.exe') { throw 'Rendered executable must be an EXE' }
        # The exported EXE uses its embedded pack, never the QA source tree.
        $list = @('--resolution', $Res, '--')
    }
    if ($ArgsLine.Trim() -ne '') { $list += ($ArgsLine -split '\s+' | Where-Object { $_ -ne '' }) }
    $list += @("--shot=$png", "--shot-frames=$F")
    $name = [IO.Path]::GetFileNameWithoutExtension($Png)
    $r = Run-Godot $list ("shot_$name.log") $RenderExecutable
    $ok = Test-Path -LiteralPath $Png
    if ($ok) {
        $info = Get-Item -LiteralPath $Png
        $ok = $info.Length -gt 1000 -and ($null -eq $previous -or $info.LastWriteTimeUtc -gt $previous)
        if ($ok) {
            $stream = [IO.File]::OpenRead($Png)
            try { $magic = New-Object byte[] 8; $null = $stream.Read($magic, 0, 8) }
            finally { $stream.Dispose() }
            $ok = [BitConverter]::ToString($magic) -eq '89-50-4E-47-0D-0A-1A-0A'
        }
    }
    Write-Output ("SHOT {0} exit={1} saved={2}" -f $Png, $r.code, $ok)
    $n = Show-Problems $r
    if ($n -gt 0 -or $r.code -ne 0 -or -not $ok -or $r.text -notmatch 'SHOT saved') {
        throw "Screenshot failed: exit=$($r.code) problems=$n fresh_png=$ok log=$($r.log)"
    }
}

switch ($Mode) {
    'check' {
        $r = Import $Root 'check'
        $n = Show-Problems $r
        Write-Output ("CHECK exit={0} problems={1} log={2}" -f $r.code, $n, $r.log)
        if ($n -gt 0 -or $r.code -ne 0) { exit 1 }
    }
    'suite' {
        Ensure-Cache $Root
        $r = Run-Godot @('--headless', '--path', $Root, '--script', "res://tests/$Suite.gd") ("suite_$Suite.log")
        $r.lines | Select-Object -Last 6 | ForEach-Object { Write-Output ("  " + $_) }
        $n = Show-Problems $r
        Write-Output ("SUITE {0} exit={1} problems={2} log={3}" -f $Suite, $r.code, $n, $r.log)
        if ($n -gt 0 -or $r.code -ne 0) { exit 1 }
    }
    'shot' {
        Sync-Qa
        if ($Out -eq '') { $Out = Join-Path $Main ("zz_work\shots\$leaf\shot.png") }
        Shot $AppArgs $Out $Frames
    }
    'shots' {
        Sync-Qa
        if ($OutDir -eq '') { $OutDir = Join-Path $Main ("zz_work\shots\$leaf") }
        $set = @(
            @('home', '--goto=home', 90),
            @('setup', '--goto=setup', 60),
            @('draft', '--goto=draft', 60),
            @('deathmatch', '--goto=deathmatch', 90),
            @('codex_chars', '--demo-preview=torturer/active:2', 90),
            @('codex_arenas', '--goto=codex --codex=arenas', 60),
            @('codex_items', '--goto=codex --codex=items', 60),
            @('codex_glossary', '--goto=codex --codex=glossary', 60),
            @('settings', '--goto=settings', 60),
            @('battle_3v3', '--demo-battle=ruined_gate --warp=12 --select=0', 120),
            @('battle_dm8', '--demo-dm=8/dm_forest_village/20261001 --warp=45 --select=0 --speed=1', 150),
            @('battle_dm_rank', '--demo-dm=12/dm_ruined_town/4242 --warp=60 --tab=0', 150),
            @('battle_control', '--demo5=control_crossroads --warp=60', 150)
        )
        foreach ($s in $set) { Shot $s[1] (Join-Path $OutDir ($s[0] + '.png')) $s[2] }
    }
    'uitest' {
        Sync-Qa
        $rep = ($LogDir + "\$Suite.json").Replace('\', '/')
        $sd = (Join-Path $Main ("zz_work\shots\$leaf\ui_$Suite")).Replace('\', '/')
        New-Item -ItemType Directory -Force -Path $sd | Out-Null
        if (Test-Path -LiteralPath $rep) { Remove-Item -LiteralPath $rep -Force }
        $reportArg = if ($Suite -eq 'developer_152') { "--report=$rep" } else { "--ui-report=$rep" }
        $list = @('--path', $Qa, '--resolution', '1600x900', "res://tests/$Suite.tscn", '--', $reportArg)
        if ($Suite -in @('deathmatch_ui_15', 'codex_ui_151', 'developer_152')) { $list += "--qa-dir=$sd" }
        $r = Run-Godot $list ("uitest_$Suite.log")
        $r.lines | Where-Object { $_ -match 'FAIL|PASS|passed|failed' } | Select-Object -Last 40 | ForEach-Object { Write-Output ("  " + $_) }
        $n = Show-Problems $r
        Write-Output ("UITEST {0} exit={1} problems={2} log={3} report={4}" -f $Suite, $r.code, $n, $r.log, $rep)
        if ($n -gt 0 -or $r.code -ne 0 -or -not (Test-Path -LiteralPath $rep)) { exit 1 }
        $report = [IO.File]::ReadAllText($rep) | ConvertFrom-Json
        foreach ($key in @('failed', 'failures')) {
            if ($null -ne $report.$key -and @($report.$key).Count -gt 0) {
                if ($report.$key -is [array] -or [int]$report.$key -ne 0) { throw "UI report contains $key : $rep" }
            }
        }
    }
    default { throw "Unknown helper mode: $Mode" }
}
