param([string]$GodotExe = $env:GODOT_EXE, [string]$Stage = 'A')
# V1.5 Windows release pipeline. Stage A: import, automated suites, regression
# replays, Windows export, rendered UI/visual checks and exported-EXE start.
# Stage V: rendered UI/visual checks only. Stage B: cache-free copy of the
# source tree imported, started and tested from scratch.
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $project
if (-not $GodotExe) { $GodotExe = Join-Path $root 'DVD_BATTLE_1.2.1_RECOVERY_WORK\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw 'Godot 4.7.2 console executable not found. Pass -GodotExe.' }
$reports = Join-Path $project 'reports'
$visualRoot = Join-Path $root 'DVD_BATTLE_1.5_VISUAL_QA'
$shots = Join-Path $visualRoot 'shots'
$release = Join-Path $root 'DVD_BATTLE_1.5_RELEASE'
$exe = Join-Path $release 'DVD_BATTLE_1.5.exe'
$progressFile = Join-Path $reports ("win15_progress_{0}.txt" -f $Stage)
$summaryFile = Join-Path $reports ("windows_stage_{0}_15.json" -f $Stage)
$summary = [ordered]@{ stage = $Stage; started = (Get-Date).ToString('s'); godot = $GodotExe; steps = [ordered]@{} }
Set-Content -LiteralPath $progressFile -Value ("start " + (Get-Date).ToString('s')) -Encoding UTF8

function Note([string]$Message) {
    $line = (Get-Date).ToString('HH:mm:ss') + ' ' + $Message
    Add-Content -LiteralPath $progressFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Save-Summary {
    $summary['updated'] = (Get-Date).ToString('s')
    $summary | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $summaryFile -Encoding utf8
}

function Invoke-Godot([string[]]$Arguments, [string]$LogName) {
    $log = Join-Path $reports $LogName
    $started = Get-Date
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $GodotExe @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $output | Out-File -LiteralPath $log -Encoding utf8
    $text = ($output -join "`n")
    $ok = ($code -eq 0) -and -not ($text -match 'SCRIPT ERROR') -and -not ($text -match '(?m)^ERROR:')
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $summary.steps[$LogName] = [ordered]@{ exit = $code; ok = $ok; seconds = $seconds }
    Note ("{0} exit={1} {2} {3}s" -f $LogName, $code, $(if ($ok) { 'OK' } else { 'FAIL' }), $seconds)
    Save-Summary
    return $ok
}

function Invoke-Import([string]$ProjectDir, [string]$LogName) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $name = $LogName
        if ($attempt -gt 1) { $name = $LogName.Replace('.log', "_retry$attempt.log") }
        if (Invoke-Godot @('--headless', '--path', $ProjectDir, '--editor', '--quit') $name) { return $true }
    }
    return $false
}

function Settings-Hash {
    $base = Join-Path $env:APPDATA 'Godot\app_userdata'
    if (-not (Test-Path -LiteralPath $base)) { return 'none' }
    $parts = @()
    foreach ($dir in Get-ChildItem -LiteralPath $base -Directory | Where-Object { $_.Name -like 'DVD BATTLE*' }) {
        $cfg = Join-Path $dir.FullName 'settings.cfg'
        if (Test-Path -LiteralPath $cfg) { $parts += ($dir.Name + ':' + (Get-FileHash -LiteralPath $cfg -Algorithm SHA256).Hash) }
    }
    if ($parts.Count -eq 0) { return 'none' }
    return ($parts -join ';')
}

function Copy-Tree([string]$From, [string]$To, [switch]$WithCache) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    if ($WithCache) { $null = robocopy $From $To /MIR /XD zz_diag /NFL /NDL /NJH /NJS /NP }
    else { $null = robocopy $From $To /MIR /XD .godot zz_diag /NFL /NDL /NJH /NJS /NP }
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
}

function Set-QaUserDir([string]$ProjectDir, [string]$Name) {
    $pg = Join-Path $ProjectDir 'project.godot'
    $text = [IO.File]::ReadAllText($pg)
    if ($text -notmatch 'use_custom_user_dir') {
        $text = $text.Replace('config/icon="res://icon.svg"', ('config/icon="res://icon.svg"' + "`n" + 'config/use_custom_user_dir=true' + "`n" + 'config/custom_user_dir_name="' + $Name + '"'))
        [IO.File]::WriteAllText($pg, $text, (New-Object Text.UTF8Encoding($false)))
    }
}

$fwd = { param($p) $p.Replace('\', '/') }

function Run-Visual {
    $qa = Join-Path $visualRoot 'project'
    New-Item -ItemType Directory -Force -Path $shots | Out-Null
    Copy-Tree $project $qa -WithCache
    Set-QaUserDir $qa 'DVD_BATTLE_V15_VISUAL_QA'
    Invoke-Import $qa 'visual_qa_import_15.log' | Out-Null
    $s = & $fwd $shots
    $r = & $fwd $reports
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', 'res://tests/deathmatch_ui_15.tscn', '--', "--qa-dir=$s", "--ui-report=$r/deathmatch_ui_15.json") 'deathmatch_ui_15.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', 'res://tests/control_ui_13.tscn', '--', "--ui-report=$r/control_ui_13.json", "--qa-shot=$s/control_ui_13.png") 'control_ui_13.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', 'res://tests/preview_ui_14.tscn') 'preview_ui_14.log' | Out-Null
    if (Test-Path -LiteralPath (Join-Path $qa 'reports\preview_ui_14.json')) { Copy-Item -LiteralPath (Join-Path $qa 'reports\preview_ui_14.json') -Destination (Join-Path $reports 'preview_ui_14.json') -Force }
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', '--', '--demo-dm=12/dm_forest_village/20261001', '--warp=50', '--select=0', '--speed=1', "--shot=$s/dm12_follow.png", '--shot-frames=150') 'shot_dm12_follow.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', '--', '--demo-dm=12/dm_ruined_town/4242', '--warp=90', '--cam=1800,1100,1.0', "--shot=$s/dm12_overview.png", '--shot-frames=150') 'shot_dm12_overview.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', '--', '--demo-dm=8/dm_open_steppe/31', '--warp=60', '--select=3', '--vision=3', "--shot=$s/dm8_participant_view.png", '--shot-frames=150') 'shot_dm8_view.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', '--', '--demo5=control_crossroads', '--warp=75', "--shot=$s/conquest_crossroads.png", '--shot-frames=150') 'shot_conquest.log' | Out-Null
    Invoke-Godot @('--path', $qa, '--resolution', '1600x900', '--', '--goto=deathmatch', "--shot=$s/deathmatch_setup_menu.png", '--shot-frames=90') 'shot_dm_setup.log' | Out-Null

}


if ($Stage -eq 'A') {
    $summary['settings_before'] = Settings-Hash
    Invoke-Import $project 'final_import_15.log' | Out-Null
    $suites = @('mechanics_122', 'ai_information_122', 'control_maps_13', 'control_rules_13', 'control_ai_13', 'control_information_13',
        'skill_preview_14', 'preview_isolation_14', 'draft_14', 'draft_audit_14', 'draft_isolation_14', 'deathmatch_15', 'conquest_15')
    foreach ($suite in $suites) {
        Invoke-Godot @('--headless', '--path', $project, '--script', "res://tests/$suite.gd") "$suite.log" | Out-Null
    }
    $cases = & $fwd (Join-Path $reports 'regression_cases_14.json')
    $legacyOut = & $fwd (Join-Path $reports 'regression_matches_15_legacy_walls.jsonl')
    $currentOut = & $fwd (Join-Path $reports 'regression_matches_15.jsonl')
    Invoke-Godot @('--headless', '--path', $project, '--script', 'res://tools/balance_runner.gd', '--', "--cases=$cases", "--output=$legacyOut", '--legacy_walls=1') 'regression_matches_15_legacy_walls.log' | Out-Null
    Invoke-Godot @('--headless', '--path', $project, '--script', 'res://tools/balance_runner.gd', '--', "--cases=$cases", "--output=$currentOut") 'regression_matches_15.log' | Out-Null
    $base = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $reports 'regression_matches_14.jsonl') -Encoding UTF8) {
        if ($line.Trim()) { $row = $line | ConvertFrom-Json; $base[$row.case_id] = $row.signature }
    }
    $comparison = @()
    foreach ($pair in @(@('legacy_walls', 'regression_matches_15_legacy_walls.jsonl'), @('current', 'regression_matches_15.jsonl'))) {
        $path = Join-Path $reports $pair[1]
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
            if (-not $line.Trim()) { continue }
            $row = $line | ConvertFrom-Json
            $comparison += [ordered]@{ run = $pair[0]; case_id = $row.case_id; ruleset = $row.ruleset; equal_to_14 = ($row.signature -eq $base[$row.case_id]); winner = $row.winner; duration = $row.duration; invariant_error = $row.invariant_error }
        }
    }
    $comparison | ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $reports 'battle_regression_15.json') -Encoding utf8
    Note ('regression rows ' + $comparison.Count)

    New-Item -ItemType Directory -Force -Path $release | Out-Null
    Invoke-Godot @('--headless', '--path', $project, '--editor', '--export-release', 'Windows Desktop', $exe) 'windows_export_15.log' | Out-Null
    if (Test-Path -LiteralPath $exe) {
        $item = Get-Item -LiteralPath $exe
        $summary['exe'] = [ordered]@{ bytes = $item.Length; sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower();
            file_version = $item.VersionInfo.FileVersion; product_version = $item.VersionInfo.ProductVersion; description = $item.VersionInfo.FileDescription; product = $item.VersionInfo.ProductName }
        Save-Summary
    }

    Run-Visual
    $s = & $fwd $shots
    if (Test-Path -LiteralPath $exe) {
        $before = Settings-Hash
        $p = Start-Process -FilePath $exe -ArgumentList @('--headless', '--quit-after', '240') -Wait -PassThru
        $summary['exported_headless_start_exit'] = $p.ExitCode
        $p2 = Start-Process -FilePath $exe -ArgumentList @('--resolution', '1600x900', '--', '--demo-dm=8/dm_ruined_town/777', '--warp=30', '--select=2', "--shot=$s/exported_exe_dm.png", '--shot-frames=180') -Wait -PassThru
        $summary['exported_render_exit'] = $p2.ExitCode
        $summary['exported_render_shot'] = (Test-Path -LiteralPath (Join-Path $shots 'exported_exe_dm.png'))
        $after = Settings-Hash
        $summary['settings_after_exe'] = $after
        $summary['settings_unchanged_by_exe'] = ($before -eq $after)
        Note ('exported exe: headless exit ' + $p.ExitCode + ', render exit ' + $p2.ExitCode + ', shot ' + $summary['exported_render_shot'])
    }
    $summary['settings_after'] = Settings-Hash
    $summary['settings_unchanged'] = ($summary['settings_before'] -eq $summary['settings_after'])
}

if ($Stage -eq 'V') {
    Run-Visual
}

if ($Stage -eq 'B') {
    # Cache-free copy of the source tree (what the source ZIP contains), imported and started from scratch.
    $fresh = Join-Path $root 'DVD_BATTLE_1.5_FRESH_IMPORT'
    $summary['settings_before'] = Settings-Hash
    if (Test-Path -LiteralPath $fresh) {
        # A previous copy still holds its import cache: move it aside (nothing is deleted) so this import starts cold.
        $aside = Join-Path $root ('_to_delete\DVD_BATTLE_1.5_FRESH_IMPORT_' + (Get-Date).ToString('yyyyMMdd_HHmmss'))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $aside) | Out-Null
        Move-Item -LiteralPath $fresh -Destination $aside
        $summary['previous_copy_moved_to'] = $aside
        Note ('previous fresh copy moved to ' + $aside)
    }
    Copy-Tree $project $fresh
    $summary['has_godot_cache_before_import'] = (Test-Path -LiteralPath (Join-Path $fresh '.godot'))
    Invoke-Import $fresh 'fresh_import_15.log' | Out-Null
    Invoke-Godot @('--headless', '--path', $fresh, '--quit-after', '240') 'fresh_startup_15.log' | Out-Null
    Invoke-Godot @('--headless', '--path', $fresh, '--script', 'res://tests/deathmatch_15.gd') 'fresh_deathmatch_15.log' | Out-Null
    $mismatch = @()
    $checked = 0
    foreach ($file in Get-ChildItem -LiteralPath $project -Recurse -File | Where-Object { $_.FullName -notmatch '\\(\.godot|reports|zz_diag)\\' -and ($_.Extension -in @('.gd', '.tscn', '.gdshader', '.godot', '.cfg')) }) {
        $rel = $file.FullName.Substring($project.Length + 1)
        $other = Join-Path $fresh $rel
        $checked += 1
        if (-not (Test-Path -LiteralPath $other) -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $other).Hash) { $mismatch += $rel }
    }
    $summary['source_files_checked'] = $checked
    $summary['source_mismatches'] = $mismatch
    Note ('source files checked ' + $checked + ', mismatches ' + $mismatch.Count)
    $summary['settings_after'] = Settings-Hash
    $summary['settings_unchanged'] = ($summary['settings_before'] -eq $summary['settings_after'])
}

$summary['finished'] = (Get-Date).ToString('s')
Save-Summary
Note 'DONE'
