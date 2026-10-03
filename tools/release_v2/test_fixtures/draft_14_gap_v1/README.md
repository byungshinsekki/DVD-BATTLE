# Known draft gap fixture, version 1

These are fixed local regression inputs for `test_known_draft_diagnostic.py`.
They come from this project's original `tests/draft_14.gd` and its completed C6
run after generating the 22-hero calibration table on 2026-10-02. The report
contains 231 passing assertions, the six reviewed failing assertions and all ten
measurement payloads. The actual-engine bounded rollout is skipped by its gap
gate; the final control 5v5 measurement retains its two actual trials.

| File | SHA256 | Treatment |
|---|---|---|
| `draft_14.gd.txt` | `e66076f6c2a8fa3a4ef0e7dd5989dc33994eed7acfb168b70246dda264d2350b` | Original test source bytes; `.txt` keeps it out of engine script discovery. |
| `report.json` | `5bd983fc5ff9f391e900a6f1606fd39a02a28b82bde8fe402143bdc30a9b14d8` | Complete original JSON bytes. |
| `stdout.txt` | `f90e5fac41b23c5d34becc4fc06d0f8d1f4978e22893e1e422f3571c5e7564eb` | Original stdout with CRLF changed to LF only. |

The original CRLF stdout SHA is
`79686194999a85310e2604b76a6ca0c6b0d0036d0f02c6ad8b1b4ab6414b5c2a`.
No error text, summary, count, timing, candidate, measurement or report content
was changed. All shipped text uses UTF-8 without BOM and LF.

The regression suite creates **synthetic** process receipts, reports and fake QA
paths around these bytes. It does not claim to reproduce the simulation, launch
an engine or prove release acceptance. It neither reads local player profiles nor
requires the original local measurement directories. The map failure used by the
two-policy tests is separately generated in memory from the full map sample
contract, with the same synthetic payload used by the original continuation
regressions.

Do not replace the fixture or weaken expected failures merely to obtain a pass.
If the producer contract changes, review the diagnostic policy version and its
fixed source SHA explicitly. Such a review does not alter the original game's
test acceptance criteria.
