param([string]$GodotExe = $env:GODOT_EXE, [switch]$Matches, [switch]$DraftBenchmark)
# V1.5.1 quick check: import and the headless suites. Logs and outputs use V1.5.1 (_151) names; the
# suites write their own reports/<suite>.json. The V1.5 baselines (reports/*_15.*) and the shipped
# DVD_BATTLE_1.5_RELEASE are never written. Full release run: tools/RUN_WIN151_A.bat -> V -> B.
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if (-not $GodotExe) { $GodotExe = Join-Path (Split-Path -Parent $projectDirectory) 'DVD_BATTLE_1.2.1_RECOVERY_WORK\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw 'Supply -GodotExe with a Godot 4.7.2 executable path.' }
function Invoke-CheckedGodot {
    param([string[]]$Arguments, [string]$LogName)
    $logPath = Join-Path $projectDirectory "reports\$LogName"
    $output = & $GodotExe @Arguments 2>&1 | Tee-Object -FilePath $logPath
    $engineExit = $LASTEXITCODE
    $output | Write-Output
    if ($engineExit -ne 0 -or (($output -join "`n") -match 'SCRIPT ERROR|ERROR:')) { throw "Godot check failed: $LogName" }
}
Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--editor', '--quit') -LogName 'final_import_151.log'
$tests = @('mechanics_122', 'ai_information_122', 'control_maps_13', 'control_rules_13', 'control_ai_13', 'control_information_13', 'skill_preview_14', 'preview_isolation_14', 'draft_14', 'draft_audit_14', 'draft_isolation_14', 'deathmatch_15', 'conquest_15', 'codex_data_151')
foreach ($testName in $tests) {
    Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--script', "res://tests/$testName.gd") -LogName "$testName.log"
}
Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tools/data_fingerprint_151.gd', '--', ("--out=" + ((Join-Path $projectDirectory 'reports\data_fingerprint_151.json') -replace '\\', '/'))) -LogName 'data_fingerprint_151.log'
if ($Matches) {
    # Replays the 15 V1.3/V1.4 reference battles. With --legacy_walls=1 the 12 elimination battles must
    # reproduce reports/regression_matches_14.jsonl exactly. V1.5.1 changes no simulation code or data, so
    # both runs must also equal the V1.5 results (reports/regression_matches_15[_legacy_walls].jsonl, kept as baselines).
    $casePath = (Join-Path $projectDirectory 'reports\regression_cases_14.json') -replace '\\', '/'
    $legacyPath = (Join-Path $projectDirectory 'reports\regression_matches_151_legacy_walls.jsonl') -replace '\\', '/'
    $resultPath = (Join-Path $projectDirectory 'reports\regression_matches_151.jsonl') -replace '\\', '/'
    Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tools/balance_runner.gd', '--', "--cases=$casePath", "--output=$legacyPath", '--legacy_walls=1') -LogName 'regression_matches_151_legacy_walls.log'
    Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tools/balance_runner.gd', '--', "--cases=$casePath", "--output=$resultPath") -LogName 'regression_matches_151.log'
}
if ($DraftBenchmark) {
    # Same V1.4 draft cases; results go to _151 files so the V1.4 draft evidence stays untouched.
    foreach ($splitName in @('validation', 'holdout')) {
        $casePath = (Join-Path $projectDirectory "reports\draft_${splitName}_cases_14.json") -replace '\\', '/'
        $resultPath = (Join-Path $projectDirectory "reports\draft_${splitName}_151.jsonl") -replace '\\', '/'
        Invoke-CheckedGodot -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tools/draft_benchmark_14.gd', '--', "--cases=$casePath", "--output=$resultPath") -LogName "draft_${splitName}_151.log"
    }
    Write-Output 'Drafts complete: reports/draft_validation_151.jsonl and draft_holdout_151.jsonl (compare with the V1.4 files draft_*_14.jsonl).'
}
Write-Output 'V1.5.1 automated scripts passed. Isolated graphical UI checks: tools/windows_release_151.ps1 (stages A and V) and reports/UI_VISUAL_1.5.1.txt.'
