# Fixed preview producer evidence

These data files preserve the C7 final UI result: 105 passing checks and the
single failed check `final pick uses actual battle verification`. They are not
an expected game success result and never change the test's acceptance status.

`report.json` and both source fixtures are byte copies of the preserved C7
native evidence. `stdout.txt` only normalizes CRLF to LF. The source fixtures
use `.gd.txt`/`.tscn.txt` names, so Godot's top-level test discovery will not
execute them. This directory is included in Source.zip and excluded from game
exports by the existing `tools/*` export filter.

The source SHA256 values are:

- preview_ui_14.gd.txt: `541b966a3ebaf753ea20e0507caf9e94b60050b2ce4cf64cf58332248047e30e`
- preview_ui_14.tscn.txt: `8907a7970567ac839bb667ce05e8eb183402160b020e7df61e0191da3f2fb787`
- report.json: `e3f6f71faa12f2a59b8717439b52181fe0cc917b14b9d00d16fe360b44cd8d1f`

The independent source test validates exact check-label order using SHA256
`f2d006ab5f533abd66e89592c694d7f7af5eb9f8a42bd222e6602639e5251f72`.
The production adapter pins source hashes and complete producer semantics;
timings, frame counts, graphics hardware and monitor values are not fixed.
All process receipts used by Python tests are explicitly synthetic. No actual
engine, Git, profile or ignored preparation path is required by these fixtures.

The real UI JSON has no draft score gap field. Separate root-run diagnostic
evidence showed the current table gap 0.05070395355003887 above default 0.03,
while the same runtime with only the prior empty table had gap
0.024288393715552914 and entered rollout. That probe stopped before battle ticks;
it does not certify a historical complete UI rerun. These numbers explain the
diagnosis only and are not substituted for UI report fields or acceptance.
