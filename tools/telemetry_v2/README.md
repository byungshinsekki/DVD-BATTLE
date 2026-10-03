# V2 telemetry

These observers do not change game rules or AI decisions. `ai_probe_153.gd` is
unchanged; `nav_scan.gd` promotes the navigation probe. Run only against an
imported project with a Godot global-class cache. All engine launches are
headless, timed, and use a child-only redirected APPDATA directory.

```powershell
py tools/telemetry_v2/run.py --suite baseline --jobs 4 --out zz_work/measure/C1/baseline
py tools/telemetry_v2/run.py --suite nav_ring_thorn --jobs 4 --out zz_work/measure/C1/nav_ring_thorn
py tools/telemetry_v2/run.py --suite nav_links --jobs 4 --out zz_work/measure/C1/nav_links
py tools/telemetry_v2/run.py --suite nav_links_small --jobs 4 --out zz_work/measure/C1/nav_links_small
py tools/telemetry_v2/analyze.py zz_work/measure/C1/baseline zz_work/measure/C1/nav_ring_thorn zz_work/measure/C1/nav_links zz_work/measure/C1/nav_links_small --out zz_work/measure/C1 --label baseline
py tools/telemetry_v2/test_telemetry.py
```

Do not overlap runners beyond the shared process budget (normally 4, bulk C1/C5/
C6 at most 6). `--jobs` limits one runner, not other tools on this computer.
`--project` selects a read-only game snapshot; output can remain in this codex
worktree's `zz_work`/`reports`, or in `D:\DVD20_CODEX_SCRATCH`. The project snapshot
must contain the same observer scripts. No imports/downloads run automatically.

## Immutable configurations

Every suite defaults to **both** independent seed sets. `--seed-sets 1` or `2`
selects a diagnostic subset. Set 2 adds exactly 50000 to every seed0. The map
order, n, mode, size, and Godot `hash([seed0, mode, size, maps, n])` deck are part
of the test definition. Match seeds are `seed0 + map_index * 1000 + k * 17`.

| Suite | Set 1 configuration | Games per set |
|---|---|---:|
| baseline | Original run_probe.sh: E3 12x8, E5 6x4, C5 3x4, DM8 3x3 | 141 |
| extended | Original run_probe.sh: E3 12x18, E5 12x3, DM8 3x4 | 264 |
| balance | baseline + extended, unchanged decks | 405 |
| nav_ring_thorn | thorn_circuit,bastion_ring; n=40 size=3 seed0=171100 | 80 |
| nav_links | dimensional_lattice,rift_harbor,furnace_basin,gale_corridor; n=24 size=3 seed0=176100 | 96 |
| nav_links_small | Same link map order; n=12 size=3 seed0=172100 | 48 |

All matches use max_time=150; deathmatch uses kill_target=10. Baseline and
extended retain their original per-group shard counts. In a 22-hero roster,
balance has 5184 team appearances (average 235.6 per hero); the runner separately
checks that **every** current roster id has n_team >= 200 and fails if not.
New rosters may need additional measurement rather than assuming this still holds.
For baseline/extended/balance only, `--seed-sets 1,2,3` explicitly adds set 3
(offset +100000); any list of distinct positive IDs fitting signed int64 is
supported, with offset `(set_id - 1) * 50000`. The default `both` and its original
plans remain unchanged. Navigation presets remain restricted to sets 1 and 2.
For 26 heroes, two balance sets provide only 199.38 team appearances on average,
so use at least `--suite balance --seed-sets 1,2,3` and retain the actual per-hero
`n_team >= 200` check. No number of seed sets substitutes for that measured gate.

## Resume and completeness

`run_manifest.json` records source hashes, engine SHA, exact tasks, commands, PID,
isolated profile paths, return codes, timeouts, completed indices and result hashes.
Rerunning the same command resumes. Source/engine/plan changes reject reuse.
Completed shards must still match their SHA and expected indices/seeds/roster size.
An OS file lock rejects concurrent runners using the same output directory and
is released automatically when the owning process exits.
On timeout, valid complete rows are retained; a truncated last row is excluded.
Only missing indices rerun as `index/total` shards of the original full deck.
They are atomically merged after every completed retry. No completed battle is
silently omitted. Ctrl+C stops only PIDs this runner created.

Analysis rejects incomplete manifests, changed outputs, malformed rows,
duplicates and mixed source snapshots. `--allow-partial` is explicitly diagnostic
and stamps the summary; it must not be used to certify acceptance. Legacy raw
JSONL directories/files also work, but lack manifest completeness evidence.
Actual roster metadata is written by `ai_probe_153.gd --roster` on every new run.

`--ai=res://...` is supported. In the unchanged general probe, custom AI paths
bypass the decision recorder wrapper, so decision-time counts are unavailable.
The summary marks `decision_observer_complete=false`; do not use apparent zero
unobserved-order/decision counts as acceptance evidence for those prototype runs.
The normal shipping `tactician` run records the complete decision-time fields.

## Analysis schema (summary JSON schema 2)

Existing `hero`, `ability`, `maps`, `hazards` and `by_group` metrics retain the
original formulas. Team win rate counts draws as 0.5; deathmatch rank results stay
separate. `regression` uses aggregate numerators/denominators, rather than averaging
per-hero percentages, for unobserved orders, stuck/void stalls, environmental damage,
and E3/E5 timeouts. `--compare <summary.json>` adds before/after metric deltas.

`navigation.by_suite[suite].by_seed_set["1"|"2"].by_map[map_id]` is the acceptance
unit when analyzing multiple suites. `by_seed_set` also works for one-suite
summaries. Do not pool nav_links_small into the primary nav_links gate. It exposes
ring time/damage per match, `ring_episodes_1_5s`, `stuck_seconds_per_battle`,
`pocket_region_seconds`, `strict_pocket_seconds`, cause durations, accidental trips
against the goal per match, deliberate against-goal count, dropped commits and
timeouts. Combined `by_map` is a pooled summary and does not replace per-set gates.
`navigation_matches` preserves per-match scalar evidence. `--compare` also emits
`paired_navigation`, matching map, seed and **ordered composition**, with unmatched
counts, paired mean differences and their standard errors/approximate 95% intervals.

Spatial cause labels are fixed before measurement:

- `pocket_region`: thorn NE/SW outer 180x212px rectangles, including boulder
  approaches. This is a conservative region proxy, not proof of a sealed pocket.
- `strict_pocket`: within 40px of (1212.6,59.1) or (83.4,852.9), the documented
  sealed endpoints. Reported separately.
- `corner`: outside that pocket region, within 100px of both a horizontal and a
  vertical inner map bound; otherwise `other`.

The zero-pocket acceptance evidence is `strict_pocket_seconds == 0` together
with the independent C2 geometry/connectivity test. A spatial proxy alone cannot
prove that a point is trapped. `pocket_region_seconds` is reported separately;
all its episodes still contribute to the overall stuck-time ceiling. The older
analysis's 125.9-second/66% attribution used an unavailable threshold, so these
tools do not claim to recreate that specific classification.

The old nav probe omitted stuck episodes open at death/match end. The promoted
probe preserves the old `stuck` array and adds `censored_stuck`; conservative
`stuck_seconds` includes both. `legacy_stuck_seconds` and `censored_stuck_seconds`
make the measurement change explicit. Both new baseline and after runs use this
same observer. Older raw files lack the censored contribution.
They may also lack arena bounds; the corner fallback then uses assumed geometry.
`geometry_observed_battles` and `censored_observed_battles` expose that limitation;
use the newly measured complete baseline for acceptance rather than legacy files.

Trip causes preserve the original trigger-tick classification. `intentional_trips`
means `cause == "taken"`; the `taking` field is also retained in raw data. A trip
is against the goal when landing-to-goal path length exceeds takeoff-to-goal by
more than 40px. Causes distinguish dropped_commit, walk, dodge, forced statuses,
current/recent motion, and burst displacement. Enemy forced motion remains visible
in accidental trip totals; the observer does not change portal rules.
