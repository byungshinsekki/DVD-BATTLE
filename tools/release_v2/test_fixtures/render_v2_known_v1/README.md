# Frozen render_v2 native producer fixture

These are preserved native output/source bytes for the Phase2 merged fixture,
not a successful test or a real C8 process receipt.

- Source: tests/render_v2.gd, SHA256 dedaabfe84a650811eebfff68238ed759cb4a103fd0b0deb667ac1525b96ca92.
- Native stdout: suite_render_v2.log, SHA256 e6bcfc7e52b0676f647cacb255643357688838e1cfb992845edbb43c664e8c4f.
- Producer: Godot 4.7.2 stable official ed1daf0bf, 190 PASS and exactly five FAIL.
- Observed input commit: 29623ec3f7f9f3eea7aa9bba123e6dffbe9017a5.
- Reference main 2f6d35cbbb23fbcf5dad381a69e750e60d99a47d had 195 PASS / 0 FAIL in a separate actual run.

The source file is named `.gd.txt`: it is evidence and is not discovered as a
Godot test. The unmodified producer prints one RENDER_V2 JSON line to stdout;
there is no separate producer JSON file. New tests construct explicitly fake
process lifecycle receipts in disposable local folders, and never reuse a
measured process receipt as if it belonged to C8. No original workspace path is
needed for these tests in an extracted source ZIP. Failure remains FAIL.

The five missing live observations are TANK_DESTROYED, OVERDRIVE, overdrive,
charge and missileBarrage. Complete metrics and original layer-coverage limits
are checked; draw counters may vary within the original passing conditions.
The fixture does not prove a single AI function caused the outcome, nor does it
establish a release acceptance PASS.
