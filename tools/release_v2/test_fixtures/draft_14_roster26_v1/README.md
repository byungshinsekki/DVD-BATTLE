# Observed 26-hero draft fixture

These bytes were frozen after the individual `draft_14` post-calibration test
completed on 2026-10-02, before tracked reports were restored. They preserve
255 passing assertions and exactly six failing bounded-rollout assertions.
`report.json`, `stdout.txt`, `observed_request.json`, and `observed_process.json`
are unchanged observed data. The native process was launched by the ordinary
project test helper, **not by a C8 QA capture chain**. The saved process/request
are contextual evidence only; tests construct separate explicitly synthetic
C8 lifecycle receipts to check the new adapter.

Pinned SHA256:

| File | SHA256 |
|---|---|
| report.json | 722cd3d2e5b7cd0676375f798a12ec65194872fdbd72cd3269e752f8934ab47a |
| stdout.txt | 119b4ee7b2153bd546e9bb32af29e02e27fdb069b7739e4986ca6b3dbb785da9 |
| draft_14.gd.txt | 16484c6f07b525066f068ab77d8221d352135a75d24e327a1aeddb1efd84d03f |
| db.gd.txt | e2873b655d5a8161ae0976d345cd864ee35aebdfead955f4c2af3d5fa6d18338 |
| char_data.gd.txt | 9a7ed544b8b4636293cd0a2b3181d80175640c6f6a560a94ee6ef152fde60ce4 |
| draft_calibration.gd.txt | 92bc40abf792a7fa6d3351ca7601ab266cb3c0c7373102ff7f13a96c660f124b |
| draft_director.gd.txt | 8d6b5d0104ae7dbba2d8b383db835f7eebdbd8139582bfc3b5cad26522e2d3c3 |
| draft_search.gd.txt | 4b497125c11414446f9a758772065b6c080fa486074f887f3faf8ddd66574c66 |

The bounded-rollout row has 25 legal candidates, 45,000 allocated evaluations
(1,800 per candidate), 50 completed static evaluations, gap gate 1.0, and a
1,200-tick/300-horizon engine budget that was skipped for `gap` with zero games
and ticks. Its exact numerical score gap is not in this report. The final control
row has 17 legal candidates; its full schema is validated without pinning an
execution result, pick, timing, or engine-game count. No single-source causal
claim is made from these observations.

The `.gd.txt` files are data fixtures, not Godot scripts discovered in `tests/`.
They make the Python regressions reproducible from a source ZIP without ignored
work files, Git, Godot, network, or a real user profile. A passing Python test
does not mean the observed draft test or any release acceptance passed.
