# Release validation

`config.py` is the single source for versions, engine/template paths and protected
output roots. This pipeline does not download dependencies or templates. It
records their hashes before testing and rejects changed inputs on resume.

Phase 1 uses only a scratch dry run:

```powershell
py tools/release_v2/release.py --dry-run --with-telemetry --out D:/DVD20_CODEX_SCRATCH/release_dryrun --baseline-summary zz_work/measure/C8/reference/summary_before_C8.json
```

The Phase 1 reference combines the original 810 balance battles and 448 navigation
battles from the frozen starting source (1,258 total). Its manifests, input hashes,
and agreement with the earlier balance/navigation summaries are recorded beside
it in `zz_work/measure/C8/reference/reference_evidence.json`.

Run from the Git checkout. The same command resumes valid completed stages;
changed source, engine, verification code or output artifacts require a new
`--run-id` and/or a new output folder as indicated by the error. Process concurrency
is at most four, every engine has a timeout, and child profiles are redirected to
scratch. Rendered tests and screenshots use the bundled QA helper installed as
`zz_work/tools/gd.ps1`; differing existing helpers are backed up before replacement.

The source ZIP excludes local ignored work files. To reconstruct only the helper
without running Godot or reading player profiles:

```powershell
py tools/release_v2/release.py --install-helper
```

S0–S11 record provenance, import, automatically discovered script/scene tests,
cold-start determinism, telemetry, calibration freshness, three exports, binary
structure, isolated smoke tests, a cache-free import, packaging and extraction
verification. Navigation uses both fixed seed sets. Balance uses enough explicit
seed sets for the current roster, then still requires at least 200 team appearances
for every hero; insufficient sampling is a failure.

Dry runs preserve unmet numerical gates and stale/version warnings in the reports.
A completed dry run does not mean that all gameplay acceptance criteria passed.
Missing, altered or contradictory evidence is an error even in a dry run. The
Korean validation document and release manifest distinguish these outcomes.

The default run stops on any failed headless test. For the documented C2 conflict
between the existing intentionally closed `ruined_gate` courtyard and the new
all-states connectivity requirement, an explicit diagnostic continuation is
available **only in dry-run**:

```powershell
py tools/release_v2/release.py --dry-run --with-telemetry --continue-on-test-failure --run-id phase1_connectivity_hold --out D:/DVD20_CODEX_SCRATCH/release_connectivity_hold --baseline-summary zz_work/measure/C8/reference/summary_before_C8.json
```

This permits only the completed assertion failure of `map_connectivity_v2`.
Its current complete contract has 35 assertions and 27 map samples; its failure
count/content is never fixed or removed. The runner empties the explicit `--report=`
file before execution, then requires a complete final FAIL JSON, the unique final
summary, exact assertion counts, full sample coverage, normal exit 1 with no timeout,
and a matching persisted process report. Every `ERROR:` line must correspond
exactly, including duplicate counts, to the JSON failure list. Additional engine
errors, warnings, parse/script errors, crashes, incomplete/changed coverage,
missing/malformed evidence, import failures and **every other failing suite**
still stop the run unless a separately enabled diagnostic policy below validates
its own exact case. If this suite's coverage changes, the optional continuation
policy requires review; normal test discovery is unaffected.

The original individual test remains **FAIL**. S2 has execution status WARN and
`acceptance_status=FAIL`, and S5 retains a separate connectivity FAIL even if all
navigation samples pass. S3–S11 can collect further diagnostic/build evidence;
neither the tests nor their acceptance thresholds are changed. The policy is
part of the run identity, so use a different `--run-id` when changing this option.
`--final --continue-on-test-failure` is rejected before initialization.

After this diagnostic run finishes, `complete` and `execution_complete` mean only
that every execution stage finished. Reports and the completion JSON preserve
`acceptance_status=FAIL`, `release_eligible=false`, the complete failed assertion
list and C2/C8 **HOLD**. The command exits **2**, not 0. Infrastructure errors exit
1 immediately; helper installation or a normal completed run retains exit 0.
Generated packages are diagnostic artifacts, not accepted releases. An ordinary
dry-run WARN for a version mismatch is distinct from this continued test failure.

### Known draft fixture diagnostic (runner protocol 4)

`--continue-on-known-draft-failure` is a separate, explicit **dry-run-only**
option for the reviewed `draft_14` failure after regenerating the C6 calibration
table. It does not change the test, the director, rollout gap, weights or generated
table. The default run still stops on this failure. The option cannot be used
with `--final` or `--install-helper`; rejection occurs before initialization,
output writes or profile inventories.

The fixed test's elimination 1v1 case requests a gap gate of 1.0. The new table
made that case exceed its gate, so the search skips rollout and the six assertions
depending on actual-engine trials fail. This diagnostic option recognizes only
the complete **231 PASS / 6 FAIL / 237 total** report from fixture SHA
`e66076f6c2a8fa3a4ef0e7dd5989dc33994eed7acfb168b70246dda264d2350b`.
Its policy identifier is
`dry_run_completed_draft14_gap_fixture_failure_only_v1`.

The producer writes to `res://reports/draft_14.json` and does not accept
`--report`. Before launching it, the runner empties that exact file inside the
QA copy. Immediately after exit, it freezes the full bytes and a capture receipt
under the run's `headless_assertions/` directory. It verifies source hashes,
normal exit 1, the persisted process receipt, a unique matching stdout summary,
the exact six assertion errors, all ten measurement payloads, and the bounded
rollout's `skipped="gap"`, 1.0 gate, 300-tick horizon, 1200-tick budget and zero
games/ticks. Other measured trials remain in the report. The report does not
contain the actual finalist score difference, so this policy does not invent it.
Missing, stale, malformed, truncated or contradictory data, additional failures,
warnings, engine errors, timeout, cancellation or cleanup errors still stop S2.

Each failing suite requires its own option. The draft option never permits a map
failure; the map option never permits a draft failure. For both reviewed cases:

```powershell
py -B tools/release_v2/release.py --dry-run --with-telemetry --continue-on-test-failure --continue-on-known-draft-failure --run-id phase1_known_diagnostics --out D:/DVD20_CODEX_SCRATCH/phase1_known_diagnostics --baseline-summary zz_work/measure/C8/reference/summary_before_C8.json
```

Use a new run-id after changing the options or runner protocol. Both policy
descriptions, fixture SHA and flags participate in run identity and are recorded
in provenance, manifests and completion evidence. The original suite remains
**FAIL**, S2 retains `acceptance_status=FAIL`, and diagnostic completion exits **2**
with `release_eligible=false`. Validation documents retain every failed assertion
and the report/log/process/capture hashes. The corresponding **C6/C8 HOLD** remains;
when the map failure is present, **C2/C6/C8 HOLD** and S5's connectivity FAIL remain.
These diagnostic packages are not accepted releases.

### Reproduce the known-draft regressions from a source ZIP

Extract the source ZIP to a writable directory and use Python 3.12 or newer.
Run from the extracted project root:

```powershell
py -B -X utf8 tools/release_v2/test_known_draft_diagnostic.py
```

The independent preview policy is `--continue-on-known-preview-failure`. It is
allowed only with `--dry-run`, and recognizes only the pinned `preview_ui_14`
producer completing all 106 checks with 105 PASS and the single failure
`final pick uses actual battle verification`. It does not authorize map or
headless draft failures; each of those requires its own separate option.
Default execution still stops on the UI failure. `--final` and `--install-helper`
reject this diagnostic option before initialization or profile/output access.

The policy clears the report, import and UI process artifacts before the approved
helper runs; it then freezes report, stdout, launch requests and process receipts
under the current run. It requires exact test/scene/helper hashes, one successful
import attempt, normal UI/helper exit 1 without timeout, cancellation or cleanup
errors, all 106 check labels and their order, the single exact error block, a
matching final summary, and complete finite measurements at both resolutions.
Additional failures, warnings, stale or incomplete evidence, changed producer
sources and import retries are outside this policy and stop the run.

S3 retains test FAIL and 105/1, while stage execution is WARN and acceptance is
FAIL. C7/C8 remain HOLD, `release_eligible` is false, and even a completed S11
returns exit code 2. Protocol 5 and all three independent policies are included
in resume identity and completion provenance; changing options needs a new run
ID. This option does not edit game scores, rollout gates, test expectations or
any acceptance threshold. The UI JSON does not contain draft score gaps or
rollout details, and the validation report does not infer them.

The helper is bound to the current hashed Python interpreter through
`-PythonExe`; the runner does not try to hash Windows App Execution Aliases.
After extraction of the source ZIP, the preview and runtime adapter regressions
are reproducible with no Git checkout, Godot, network, or real profile:

```powershell
py -B -X utf8 -m unittest discover -s tools/release_v2 -p "test_*preview*.py" -v
py -B -X utf8 -m unittest discover -s tools/release_v2 -p test_runtime_binding.py -v
```

The preview payloads are bundled under `test_fixtures/preview_14_known_v1/`.
The two preview suites currently contain 35 tests. Their process IDs/receipts
are synthetic; passing these tests proves classification and orchestration,
not an actual UI run or release acceptance. Temporary fake paths are deleted
by test cleanup. On Linux/macOS replace `py -B -X utf8` with `python3 -B`.

On Linux/macOS use `python3 -B tools/release_v2/test_known_draft_diagnostic.py`.
This suite contains 20 regression tests and uses only Python's standard library,
the sibling release modules and bundled `test_fixtures/draft_14_gap_v1/` files.
No local ignored-work directory, Git repository, Godot installation, download,
network connection or real profile is required. Temporary fake projects are made
under the test module's directory and removed by the test cleanup.

The fixture files preserve the reviewed producer payload and source; the stdout
fixture has only its Windows CRLF line endings normalized to LF. Their provenance
and SHA256 values are in the fixture README. Test process receipts and pipeline
stages are synthetic, so a passing result confirms parser/orchestration behavior,
not actual engine operation or game/release acceptance. The `.gd.txt` source
fixture is data and is not part of Godot's `tests/*.gd` discovery.

The validation document inside packages records the evidence available before
packaging. S11 extraction/smoke evidence is then written in the external
`POST_PACKAGE_VALIDATION_*_KO.txt`, `post_package_validation.json` and
`release_completion_v2.json`; packages remain immutable rather than recursively
embedding their own hashes. Linux executable mode and macOS ZIP metadata are
preserved, split files are below 28 MiB and are reassembled with hash checks.

The Phase 1 QA project is `D:/DVD20_QA_CODEX/release_v2/project`, with
`DVD_BATTLE_V20_CODEX_QA` under redirected scratch APPDATA. This follows the
Codex-only path guards in work-order sections 1–2 and the existing helper.
It deliberately does not create the separate `DVD20_QA_RELEASE` path named in
S2; this conservative section-8 interpretation is recorded in CODEX_STATUS.

Real player profiles and existing older releases are only inventoried and hashed,
never used by an engine or modified. The work order requires user approval before
reading real profiles. Obtain that approval before running the full pipeline.

Final mode is outside Phase 1 and requires explicit user/main-developer authorization.
It additionally requires a matching version, a fresh calibration stamp, a clean
initial Git checkout and full passing telemetry. `--resume-final` only permits
the same initially clean run with identical inputs and its own untracked reports;
it does not excuse unrelated changes or relax release gates.

Windows tests cannot establish native Linux/macOS execution, Apple signature
trust or notarization. Cross-booting their PCKs and parsing binary/signature
structures is reported separately from those unverified platform checks.

The local infrastructure tests use synthetic files/processes and do not certify
the actual game:

```powershell
py tools/release_v2/test_infrastructure.py
py tools/release_v2/test_telemetry_gates.py
py -B -X utf8 tools/release_v2/test_known_draft_diagnostic.py
```


### Known V2 render observation diagnostic (runner protocol 6)

`--continue-on-known-render-failure` is a separate **dry-run-only** option for
one pinned, complete `render_v2` result: 190 PASS and exactly five FAIL labels
for the live demo's TANK_DESTROYED/OVERDRIVE events and
`overdrive`/`charge`/`missileBarrage` states. It never changes test acceptance.
The source SHA is
`dedaabfe84a650811eebfff68238ed759cb4a103fd0b0deb667ac1525b96ca92`.

The unchanged SceneTree test has no `--report` contract. S2 binds its actual
native Godot command, QA/project fixture hashes, isolated profile, normal exit 1,
PID, and complete persisted process lifecycle. The single native `RENDER_V2`
stdout JSON is extracted byte-for-byte (plus a newline) as **derived evidence**;
it is not a separate report written by the producer. The native log, process
receipt, extracted JSON and capture receipt all enter S2 evidence hashes.
A fresh capture must contain exactly the five assertion errors and their pinned
source backtraces, the final 190/5 counts, all 14 patterns, the 1,861-tick live
metrics and complete showcase payload. Draw counters must meet the original
layer coverage and integer constraints; execution-specific absolute counters
are not pinned. Extra errors/warnings, different failures, corrupt/ambiguous
JSON, changed fixture, changed/missing metrics, interrupted processes or missing
coverage still stop the pipeline. Enabling the flag with no discovered
`render_v2` also stops. The payload does not establish a single movement
function as the cause of the five missing observations.

An ordinary render PASS remains PASS. A recognized render failure remains
**FAIL**; S2 may have execution status WARN while `acceptance_status=FAIL`,
`release_eligible=false`, and `render_v2/C8 HOLD` remain in the state, manifest,
completion and Korean validation documents. Completion of S0-S11 means only
execution completion: a continued assertion failure returns **exit 2**.
Infrastructure or other unrecognized failures still abort with a nonzero exit.
The new option is rejected with `--final` or `--install-helper` before
initialization, output writes or profile inventory.

Each failing suite needs its own explicitly enabled policy. The render flag
does not authorize map, draft or preview failures. Existing map coverage is
independent of the 26-hero roster and does not cover battleground connectivity.
The old draft policy is pinned to its old exact candidate/budget contract;
recalibrated 26-hero draft/preview results must be observed and evaluated without
assuming a diagnostic exception applies. Use a fresh run ID when changing a
policy, protocol, source or fixture. The policy version and fixture SHA are part
of the resume identity.

After reviewing an actual strict C8 failure, a separately authorized diagnostic
run may use the following form; this documentation does not execute it. The
absolute interpreter is the existing Python 3.14.6, not the Windows `py` alias:

```powershell
& 'C:/Path/To/Python/python.exe' -B -X utf8 tools/release_v2/release.py --dry-run --with-telemetry --continue-on-test-failure --continue-on-known-render-failure --run-id phase2_known_render_diagnostic --out D:/DVD20_CODEX_SCRATCH/phase2_known_render_diagnostic
```

Standalone source-ZIP regression checks use only bundled fixtures and synthetic
process records. They do not require `.git`, `zz_work`, Godot, a profile, network
access or the original measured report folders:

```powershell
& 'C:/Path/To/Python/python.exe' -B -X utf8 -m unittest discover -s tools/release_v2 -p 'test_*render*.py' -v
```

`test_known_render_diagnostic.py` proves orchestration boundaries;
`test_render_payload.py` checks the full native producer payload and log grammar.
These synthetic tests are infrastructure evidence, never a claim that the real
render test passed or that C8 accepted the release. The existing regression
files and three diagnostic policies remain unchanged.


### Known 26-hero draft diagnostic (runner protocol 7)

`--continue-on-known-draft26-failure` is an independent dry-run-only policy for
one reviewed 26-hero `draft_14` result: 255 PASS and exactly six FAIL assertions.
The existing 22-hero draft and preview policies remain unchanged. The 22- and
26-hero draft flags are mutually exclusive. This option is rejected with
`--final` or `--install-helper` before initialization or profile/output access.
There is no 26-hero preview exception in this version: the observed current UI
suite passed all 118 checks and remains on the ordinary passing path.

The policy pins the explicit 26 IDs and the exact test, DB, character data,
calibration table, director, and search source SHA256 in both the source project
and its QA copy before and after the test. The table SHA is
`92bc40abf792a7fa6d3351ca7601ab266cb3c0c7373102ff7f13a96c660f124b`.
It requires a fresh fixed-path producer report, all ten complete measurement
payloads, exact normal native process/command/profile receipts, six source-bound
error blocks, and a matching single final summary. Extra assertions, warnings,
unknown output, engine errors, missing lifecycle fields, timeouts, corrupted
JSON, changed sources, and stale/contradictory evidence stop S2. Later QA reuse
cannot rewrite the frozen capture that is used for proof revalidation.

Only the bounded-rollout failure row is pinned to 25 candidates, 45,000 budget,
1,800 quota and two static evaluations per candidate, gap gate 1.0, horizon 300,
1,200 tick budget, `skipped=gap`, zero games and zero ticks. The separate final
control row has 17 legal candidates and retains its full metrics without fixing
its timing, pick, or rollout result. The report does not expose an exact score
gap and does not prove that the new calibration table alone caused the failure.

A recognized case keeps test **FAIL**, S2 acceptance **FAIL**, C6/C8 **HOLD**, and
`release_eligible=false`; if all diagnostic stages complete the exit code is 2.
The flag, fixed sources and roster enter S0, S2, resume identity, manifests,
completion, and validation documents. Changing any of these requires a new run
ID. Missing `draft_14` discovery also stops. Other failed suites each need their
own matching policy; this option never authorizes map, render or UI failures.
Only after actual strict C8 evidence has been reviewed should a separately
approved diagnostic run use the appropriate three flags:

```powershell
& 'C:/Path/To/Python/python.exe' -B -X utf8 tools/release_v2/release.py --dry-run --with-telemetry --continue-on-test-failure --continue-on-known-render-failure --continue-on-known-draft26-failure --run-id phase2_known_26_diagnostic --out D:/DVD20_CODEX_SCRATCH/phase2_known_26_diagnostic
```

The actual post-calibration observation was from the regular test helper, not a
C8 QA evidence chain. Bundled fixtures preserve that distinction. Source-ZIP
regressions use those observed bytes with **synthetic** C8 process records:

```powershell
& 'C:/Path/To/Python/python.exe' -B -X utf8 -m unittest discover -s tools/release_v2 -p 'test_*draft26*.py' -v
```

These tests need only the standard library and bundled source/fixtures, with no
Godot, Git, network or actual player profile. They validate evidence handling,
not game or release acceptance. No test expectation, rollout gate or game code is
changed by this diagnostic option.
