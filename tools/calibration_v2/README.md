# Draft calibration V2

Run from the imported project on Windows with Godot 4.7.2. The roster is read
from `tools/balance_runner.gd`; no fixed hero count controls generation.

```powershell
$CalibrationPython = 'C:/Path/To/Python/python.exe'
& $CalibrationPython -B -X utf8 -m unittest discover -s tools/calibration_v2 -p 'test_*.py' -v
& $CalibrationPython -B -X utf8 tools/calibration_v2/run_calibration.py --root D:/DVD_BATTLE_2.0_codex --jobs 6 --chunk-size 1 --out D:/DVD_BATTLE_2.0_codex/zz_work/measure/C6/full
```

The training corpus contains every unordered hero pair on six elimination maps,
both sides, plus 1,500 elimination team games (1,000 3v3 and 500 5v5) and 300
control 5v5 games. This is 4,572 games for 22 heroes and 5,700 for 26. Each
training case retains its original `index % jobs` shard when resumed.

The runner repeats `ceil(5% of training)` cases in individual cold processes,
requires identical signatures, and validates the generated table before writing
`scripts/data/draft_calibration.gd`. It then checks 200 separate-seed duel games
and 90 first picks: 15 maps × seeds 1, 2, 3 × team sizes 1, 3.

Every Godot process has redirected APPDATA and LOCALAPPDATA, a timeout of at
most 900 seconds, and owned-PID-tree cleanup. Do not run other Godot jobs during
the six-worker bulk measurement. The simulation, data, tools, binaries, roster,
seed, and worker count are guarded against changes. Resume with the same command
and output directory; chunk size is also part of the resume contract, so older
contracts without that field cannot resume a newly measured run. Changed inputs
require a new output directory. Increase
the chunk size only after measuring actual process times. Cold repeats always
use one case per process.

Exit 0 means all acceptance gates passed. Exit 3 means measurement completed but
holdout or first-pick acceptance failed: preserve the table and reports, and do
not tune the director manually. Other failures require inspecting the process
and stage evidence before resuming. A game ending at its simulation time limit
is distinct from an operating-system process timeout.

`SIM_SHA` combines the runtime data fingerprint and core/AI/hero-data sources.
`sim_sha.py` is shared with the release pipeline. `TEAM_ELIM` and `TEAM_CONTROL`
are generated separately; `TEAM` aliases elimination for compatibility. Runtime
selection filters IDs not present in the current roster.

Newly generated tables also include `MAP_DUEL`, `MAP_TEAM_ELIM`, and
`MAP_TEAM_CONTROL`, each nested as map ID to pair/hero ID, with matching
`*_COUNTS` dictionaries. These are additive contextual residuals, not win
probabilities. The reference excludes the selected map: `(map_mean -
other_maps_mean) * n / (n + k)`, capped at +/-0.12. Duel residuals use `k=20`
because each pair has only two mirrored appearances per map; team residuals
use `k=60`. Counts describe appearances, not statistically independent trials.
Global `DUEL`/`TEAM_ELIM`/`TEAM_CONTROL` formulas remain unchanged. Missing maps
or modes contribute zero; elimination duel observations are never reused as
control, deathmatch, or battleground evidence. The schema still reads complete
older tables without map fields, but rejects partial/malformed map extensions.

`audit_bugfix.py` requires saved, unmodified director and search scripts and
compares 72 pre/post decisions with engine rollouts disabled. It is search-only
evidence; it does not establish engine-rollout equivalence.

Keep the raw case manifests, JSONL results, process logs/receipts, source stamps,
`calib_check.json`, `determinism.json`, `holdout.json`, `first_pick.json`, and
`summary.json` together. The `tests/calibration_v2.gd` suite additionally checks
the table schema, roster, ranges, and Python/GDScript SIM_SHA agreement. Phase 1
reports a stale stamp as a warning; a newly generated table should be fresh.

The V2 fingerprint CLI preserves the V1.5.1 canonical schema, display-only
exclusions, and deathmatch seeds. It supports the current static `ArenaData.LIST`
as well as the former constant. The original `tools/data_fingerprint_151.gd`
is unchanged; it cannot read the current static arena list. Both Python and
GDScript use `data_fingerprint.gd` and their combined SIM_SHA is cross-checked.
