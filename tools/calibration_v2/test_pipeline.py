"""Pure Python contract tests; all match results are synthetic, never QA evidence."""
import json
from pathlib import Path
import tempfile
import unittest

import calib_build
import calib_cases
from common import digest
import sim_sha


def roster(n=22):
    return [{"id": f"hero_{i:02d}"} for i in range(n)]


def results(cases):
    return {case["id"]: {"case_id": case["id"], "config": case, "winner": case["index"] % 3,
        "signature": digest(case), "invariant_error": ""} for case in cases}


class Pipeline(unittest.TestCase):
    def test_map_residual_uses_other_maps_and_shrinks_sparse_duels(self):
        local = {"special": {"a|b": [2.0, 2]}, "ordinary": {"a|b": [0.0, 10]}}
        overall = {"a|b": [2.0, 12]}
        residuals = calib_build.map_residuals(local, overall, 20.0)
        self.assertAlmostEqual(residuals["special"]["a|b"], 2.0 / 22.0, places=8)
        self.assertEqual(residuals["ordinary"]["a|b"], -0.12)
        self.assertEqual(calib_build.map_counts(local), {"ordinary": {"a|b": 10}, "special": {"a|b": 2}})
        # An equally strong hero on every map needs no contextual adjustment.
        flat = {"a": {"hero": [2.0, 2]}, "b": {"hero": [10.0, 10]}}
        self.assertEqual(calib_build.map_residuals(flat, {"hero": [12.0, 12]}, 60.0),
                         {"a": {"hero": 0.0}, "b": {"hero": 0.0}})
        with self.assertRaisesRegex(RuntimeError, "local and other-map samples"):
            calib_build.map_residuals({"only": {"hero": [1.0, 1]}}, {"hero": [1.0, 1]}, 60.0)

    def test_map_priors_preserve_global_formula_and_exact_mode_counts(self):
        source = roster(26)
        cases = calib_cases.generate(source)
        rows = results(cases)
        # The three-way synthetic outcome pattern is unrelated to real QA.
        for case in cases:
            if case["kind"] == "duel":
                rows[case["id"]]["winner"] = 0 if case["blue"][0] < case["red"][0] else 1
        data = calib_build.aggregate(source, cases, rows)
        self.assertTrue(all(value == 0.75 for value in data["duel"].values()))
        self.assertTrue(all(value == 0.0 for table in data["map_duel"].values() for value in table.values()))
        self.assertEqual(set(data["map_duel"]), set(calib_cases.DUEL_ARENAS))
        self.assertEqual(set(data["map_team_elimination"]), set(calib_cases.ELIMINATION))
        self.assertEqual(set(data["map_team_control"]), set(calib_cases.CONTROL))
        self.assertFalse(set(data["map_team_control"]) & set(data["map_team_elimination"]))
        for family, count in (("map_duel", 3900), ("map_team_elimination", 11000), ("map_team_control", 3000)):
            self.assertEqual(sum(n for table in data[family + "_counts"].values() for n in table.values()), count)
            self.assertTrue(all(abs(value) <= 0.12 for table in data[family].values() for value in table.values()))
        for mode in ("elimination", "control"):
            totals = {hero["id"]: [0, 0] for hero in source}
            for case in cases:
                if case["kind"] != "team" or case["ruleset"] != mode:
                    continue
                winner = rows[case["id"]]["winner"]
                score = 1 if winner == 0 else (-1 if winner == 1 else 0)
                for side, heroes in enumerate((case["blue"], case["red"])):
                    for hero in heroes:
                        totals[hero][0] += score if side == 0 else -score
                        totals[hero][1] += 1
            expected = {hero: round(max(-.3, min(.3, total/(n+20.0))), 8) for hero, (total, n) in totals.items()}
            self.assertEqual(data["team_" + mode], expected)
        text = calib_build.build_text(data, {"platform": "windows", "sha256": "a"*64, "data_fingerprint": "b"*64})
        for name in ("MAP_DUEL", "MAP_DUEL_COUNTS", "MAP_TEAM_ELIM", "MAP_TEAM_ELIM_COUNTS", "MAP_TEAM_CONTROL", "MAP_TEAM_CONTROL_COUNTS"):
            self.assertIn("const " + name + " := {", text)
        self.assertIn('const MAP_PRIOR_SEMANTICS := "' + calib_build.MAP_PRIOR_SEMANTICS + '"', text)
        self.assertNotIn("br_", text)

    def test_roster_scales_and_exact_dataset(self):
        for n, games, duels, cold in ((22, 4572, 2772, 229), (26, 5700, 3900, 285)):
            cases = calib_cases.generate(roster(n))
            report = calib_cases.manifest(roster(n), cases)
            self.assertEqual((len(cases), report["duels"], len(calib_cases.determinism_sample(cases))), (games, duels, cold))
            self.assertEqual(report["team_elimination"], 1500)
            self.assertEqual(report["team_control"], 300)
            self.assertEqual(sum(case["kind"] == "team" and case["ruleset"] == "elimination" and len(case["blue"]) == 3 for case in cases), 1000)
            self.assertEqual(sum(case["kind"] == "team" and case["ruleset"] == "elimination" and len(case["blue"]) == 5 for case in cases), 500)
            self.assertTrue(all(case["max_time"] == 240.0 for case in cases if case["kind"] == "duel"))
            self.assertTrue(all(len(case["blue"]) == len(case["red"]) == 5 for case in cases if case["ruleset"] == "control"))
            self.assertEqual(cases, calib_cases.generate(roster(n)))
            self.assertNotEqual(cases, calib_cases.generate(roster(n), seed=200602))
            self.assertEqual(len({case["id"] for case in cases}), games)
            for shards in (1, 2, 4, 6):
                partitions = [[case for case in cases if case["index"] % shards == k] for k in range(shards)]
                self.assertEqual(sorted((case for part in partitions for case in part), key=lambda case: case["index"]), cases)

    def test_holdout_and_cold_are_disjoint_purpose(self):
        cases = calib_cases.generate(roster())
        holdout = calib_cases.holdout(roster())
        self.assertEqual(len(holdout), 200)
        self.assertFalse({case["seed"] for case in cases} & {case["seed"] for case in holdout})
        self.assertFalse({case["id"] for case in cases} & {case["id"] for case in holdout})
        self.assertTrue(all(case["index"] % 20 == 0 for case in calib_cases.determinism_sample(cases)))

    def test_aggregation_shrink_mode_split_and_generated_text(self):
        cases = calib_cases.generate(roster())
        rows = results(cases)
        # All duels favor the alphabetically first hero regardless of side.
        for case in cases:
            if case["kind"] == "duel":
                rows[case["id"]]["winner"] = 0 if case["blue"][0] < case["red"][0] else 1
        table = calib_build.aggregate(roster(), cases, rows)
        self.assertEqual(len(table["duel"]), 231)
        self.assertTrue(all(value == 0.75 for value in table["duel"].values()))
        self.assertTrue(all(value == 12 for value in table["duel_counts"].values()))
        self.assertEqual(len(table["team_control"]), 22)
        self.assertEqual(len(table["team_elimination"]), 22)
        self.assertTrue(all(abs(value) <= 0.3 for name in ("team_control", "team_elimination") for value in table[name].values()))
        text = calib_build.build_text(table, {"platform": "windows", "sha256": "a" * 64, "data_fingerprint": "b" * 64})
        self.assertIn('const ENGINE := "GD-2.0"', text)
        self.assertIn("const GAMES := 4572", text)
        self.assertIn("const TEAM := TEAM_ELIM", text)
        self.assertNotIn("\r", text)

    def test_resume_rejects_bad_rows_and_recovers_only_last_partial(self):
        cases = calib_cases.generate(roster())[:2]
        rows = results(cases)
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as folder:
            path = Path(folder) / "part.jsonl"
            first = json.dumps(rows[cases[0]["id"]]) + "\n"
            path.write_text(first + '{"case_id":"interrupted', encoding="utf-8", newline="\n")
            calib_build.recover_truncated_tails(folder)
            self.assertEqual(path.read_text(encoding="utf-8"), first)
            partial = calib_build.read_results([path], cases, allow_incomplete=True)
            self.assertEqual(list(partial), [cases[0]["id"]])
            self.assertEqual(len(list(Path(folder).glob("*.incomplete.*"))), 1)
            with self.assertRaises(RuntimeError): calib_build.read_results([path], cases)
            path.write_text(first + first, encoding="utf-8", newline="\n")
            with self.assertRaisesRegex(RuntimeError, "Duplicate"): calib_build.read_results([path], cases, allow_incomplete=True)
            bad = dict(rows[cases[0]["id"]], invariant_error="non-finite state")
            path.write_text(json.dumps(bad) + "\n", encoding="utf-8", newline="\n")
            with self.assertRaisesRegex(RuntimeError, "Invariant"): calib_build.read_results([path], cases, allow_incomplete=True)
            bad = dict(rows[cases[0]["id"]], config={})
            path.write_text(json.dumps(bad) + "\n", encoding="utf-8", newline="\n")
            with self.assertRaisesRegex(RuntimeError, "Config differs"): calib_build.read_results([path], cases, allow_incomplete=True)

    def test_holdout_zero_signs_are_not_dropped(self):
        cases = calib_cases.holdout(roster())
        rows = results(cases)
        table = {"|".join(sorted((case["blue"][0], case["red"][0]))): 0 for case in cases}
        audit = calib_build.holdout_audit(table, cases, rows)
        self.assertEqual(audit["cases"], 200)
        self.assertEqual(audit["predicted_zero"], 200)
        self.assertEqual(audit["matches"], 66)
        self.assertEqual(audit["status"], "FAIL")

    def test_sim_sha_order_independence_and_sensitivity(self):
        left = {"scripts/core/z.gd": "a" * 64, "scripts/ai/a.gd": "b" * 64}
        right = dict(reversed(list(left.items())))
        self.assertEqual(sim_sha.combine("c" * 64, left), sim_sha.combine("c" * 64, right))
        self.assertNotEqual(sim_sha.combine("c" * 64, left), sim_sha.combine("d" * 64, left))
        right["scripts/ai/a.gd"] = "e" * 64
        self.assertNotEqual(sim_sha.combine("c" * 64, left), sim_sha.combine("c" * 64, right))


if __name__ == "__main__":
    unittest.main(verbosity=2)
