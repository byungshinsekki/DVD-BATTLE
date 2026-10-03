"""Synthetic infrastructure tests only; never substitute these for live evidence."""
from collections import defaultdict
import copy
import importlib.util
import math
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
from telemetry_gates import ROSTER_22, evaluate, wilson


def seal_balance(rows):
    totals = defaultdict(lambda: [0, 0.0])
    groups = defaultdict(lambda: {"battles": 0, "timeouts": 0})
    for row in rows:
        groups[row["group"]]["battles"] += 1
        groups[row["group"]]["timeouts"] += row["reason"] == "time_limit"
        for index, hero in enumerate(row["comp"]):
            totals[hero][0] += 1
            totals[hero][1] += .5 if row["winner"] == 2 else float(index == row["winner"])
    heroes = [{"hero": hero, "name": hero, "n_team": n, "win_rate": round(wins / n, 3),
               "ci95": [round(value, 3) for value in wilson(wins, n)]} for hero, (n, wins) in sorted(totals.items())]
    return {"schema": 2, "partial_allowed": False, "provenance": [{"complete": True}],
            "battles": len(rows), "battles_list": rows, "hero": heroes, "by_group": dict(groups)}


def fixture(rounds=220):
    heroes = sorted(ROSTER_22)
    battles = []
    for k in range(rounds):
        for pair in range(11):
            battles.append({"group": "E1", "map": "classic", "seed": k * 100 + pair,
                "winner": k % 2, "reason": "elimination", "comp": heroes[pair * 2:pair * 2 + 2]})
    result = {"balance": seal_balance(battles)}
    for suite, maps, n in (("nav_ring_thorn", ["thorn_circuit", "bastion_ring"], 40),
                          ("nav_links", ["dimensional_lattice", "rift_harbor", "furnace_basin", "gale_corridor"], 24)):
        sets = {}
        for seed in ("1", "2"):
            sets[seed] = {"total": {"battles": len(maps) * n, "timeouts": 0,
                                  "accidental_against_goal": 24 if suite == "nav_links" else 0,
                                  "intentional_against_goal": 0, "dropped_commit_trips": 0},
                          "by_map": {name: {"battles": n, "strict_pocket_seconds": 0,
                                            "pocket_region_seconds": 19, "ring_out_seconds": 24.0,
                                            "ring_out_seconds_per_battle": .6} for name in maps}}
        result[suite] = {"schema": 2, "partial_allowed": False, "provenance": [{"complete": True}],
                         "navigation": {"by_seed_set": sets}}
    return result


def gate(result, metric):
    return next(row for row in result["gates"] if row["metric"] == metric)


class Gates(unittest.TestCase):
    def test_valid_threshold_boundaries_and_purity(self):
        inputs = fixture()
        original = copy.deepcopy(inputs)
        result = evaluate(inputs)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["failed_gates"], 0)
        self.assertEqual(len(result["heroes"]), 22)
        self.assertEqual(inputs, original)
        self.assertEqual(gate(result, "nav_links.seed_set_1.unintended_reverse_trips_per_battle")["observed"], .25)
        self.assertEqual(gate(result, "nav_ring_thorn.seed_set_1.bastion_ring_out_seconds_per_battle")["observed"], .6)
        self.assertTrue(any(row.get("observed") == 19 and row.get("gated") is False for row in result["observations"]))
        self.assertEqual(result["external_checks"][0]["status"], "EXTERNAL")

    def test_missing_summary_seed_and_required_measurement_fail(self):
        for suite in ("balance", "nav_ring_thorn", "nav_links"):
            inputs = fixture()
            del inputs[suite]
            self.assertEqual(evaluate(inputs)["status"], "FAIL")
        inputs = fixture()
        del inputs["nav_ring_thorn"]["navigation"]["by_seed_set"]["2"]
        self.assertEqual(evaluate(inputs)["status"], "FAIL")
        inputs = fixture()
        del inputs["nav_ring_thorn"]["navigation"]["by_seed_set"]["1"]["by_map"]["thorn_circuit"]["strict_pocket_seconds"]
        self.assertEqual(evaluate(inputs)["status"], "FAIL")
        inputs = fixture()
        del inputs["balance"]["battles_list"]
        self.assertEqual(evaluate(inputs)["status"], "FAIL")

    def test_each_seed_is_gated_without_pooled_dilution(self):
        inputs = fixture()
        ring = inputs["nav_ring_thorn"]["navigation"]["by_seed_set"]
        ring["1"]["by_map"]["bastion_ring"]["ring_out_seconds"] = 36
        ring["2"]["by_map"]["bastion_ring"]["ring_out_seconds"] = 4
        links = inputs["nav_links"]["navigation"]["by_seed_set"]
        links["1"]["total"]["accidental_against_goal"] = 30
        links["2"]["total"]["accidental_against_goal"] = 10
        result = evaluate(inputs)
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(gate(result, "nav_ring_thorn.seed_set_1.bastion_ring_out_seconds_per_battle")["status"], "FAIL")
        self.assertEqual(gate(result, "nav_ring_thorn.seed_set_2.bastion_ring_out_seconds_per_battle")["status"], "PASS")
        self.assertEqual(gate(result, "nav_links.seed_set_1.unintended_reverse_trips_per_battle")["status"], "FAIL")

    def test_recompute_ratio_instead_of_trusting_rounded_fields(self):
        inputs = fixture()
        row = inputs["nav_ring_thorn"]["navigation"]["by_seed_set"]["1"]["by_map"]["bastion_ring"]
        row["ring_out_seconds"] = 24.00004
        row["ring_out_seconds_per_battle"] = .6
        result = evaluate(inputs)
        decision = gate(result, "nav_ring_thorn.seed_set_1.bastion_ring_out_seconds_per_battle")
        self.assertEqual(decision["status"], "FAIL")
        self.assertGreater(decision["observed"], .6)

    def test_strict_pocket_not_broad_region(self):
        inputs = fixture()
        self.assertEqual(evaluate(inputs)["status"], "PASS")
        inputs["nav_ring_thorn"]["navigation"]["by_seed_set"]["1"]["by_map"]["thorn_circuit"]["strict_pocket_seconds"] = .1
        self.assertEqual(evaluate(inputs)["status"], "FAIL")

    def test_sample_floor_applies_to_every_hero(self):
        result = evaluate(fixture(rounds=199))
        self.assertEqual(result["status"], "FAIL")
        failures = [row for row in result["gates"] if row["metric"].endswith(".n_team") and row["status"] == "FAIL"]
        self.assertEqual(len(failures), 22)
        inputs = fixture()
        inputs["expected_roster"] = sorted(ROSTER_22) + ["new_hero"]
        self.assertEqual(evaluate(inputs)["status"], "FAIL")

    def test_balance_outside_interval_fails_and_wilson_uses_exact_counts(self):
        inputs = fixture()
        for row in inputs["balance"]["battles_list"]:
            if "metatron" in row["comp"]:
                row["winner"] = row["comp"].index("metatron")
        inputs["balance"] = seal_balance(inputs["balance"]["battles_list"])
        result = evaluate(inputs)
        self.assertEqual(gate(result, "hero.metatron.team_win_rate")["status"], "FAIL")
        hero = next(row for row in result["heroes"] if row["id"] == "metatron")
        self.assertEqual((hero["wins"], hero["n_team"], hero["win_rate"]), (220, 220, 1.0))
        self.assertEqual(hero["wilson95"], wilson(220, 220))
        # Independent closed form for p=1/2, using the analyzer's exact z=1.96.
        self.assertAlmostEqual(wilson(100, 200)[0], .5 - .98 / math.sqrt(200 + 1.96 ** 2), places=12)

    def test_time_limit_boundary_and_baseline_comparison(self):
        inputs = fixture()
        old = copy.deepcopy(inputs)
        for row in inputs["balance"]["battles_list"][:121]: row["reason"] = "time_limit"
        inputs["balance"] = seal_balance(inputs["balance"]["battles_list"])
        result = evaluate(inputs, old)
        self.assertEqual(result["status"], "PASS")
        row = gate(result, "balance.time_limit_rate")
        self.assertEqual((row["observed"], row["baseline"]), (.05, 0.0))
        inputs["balance"]["battles_list"][121]["reason"] = "time_limit"
        inputs["balance"] = seal_balance(inputs["balance"]["battles_list"])
        self.assertEqual(gate(evaluate(inputs), "balance.time_limit_rate")["status"], "FAIL")

    def test_partial_invalid_nan_duplicate_or_forged_summaries_fail(self):
        mutations = [lambda data: data["balance"].update(partial_allowed=True),
                     lambda data: data["nav_links"]["provenance"][0].update(complete=False),
                     lambda data: data["nav_links"]["navigation"]["by_seed_set"]["1"]["total"].update(accidental_against_goal=math.nan),
                     lambda data: data["balance"]["hero"][0].update(win_rate=.99),
                     lambda data: data["balance"]["hero"][0].update(n_team=999),
                     lambda data: data["balance"]["battles_list"].__setitem__(1, data["balance"]["battles_list"][0])]
        for mutate in mutations:
            inputs = fixture()
            mutate(inputs)
            self.assertEqual(evaluate(inputs)["status"], "FAIL")

    def test_current_analyzer_schema_compatibility(self):
        root = Path(__file__).resolve().parents[2]
        source = root / "tools/telemetry_v2/analyze.py"
        spec = importlib.util.spec_from_file_location("telemetry_analyzer_contract", source)
        analyzer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(analyzer)
        inputs = fixture()
        roster = {hero: {"id": hero, "name": hero, "role": "DAMAGE", "abilities": []} for hero in ROSTER_22}
        raw = []
        for row in inputs["balance"]["battles_list"]:
            raw.append({**row, "mode": "elimination", "duration": 60,
                        "heroes": [{"id": hero, "team": i, "alive_s": 60} for i, hero in enumerate(row["comp"])]})
        balance = analyzer.summarize_probe(raw, roster, "synthetic-contract", [])
        balance.update(schema=2, partial_allowed=False, provenance=[{"complete": True}])
        inputs["balance"] = balance
        for suite, maps, n in (("nav_ring_thorn", ["thorn_circuit", "bastion_ring"], 40),
                              ("nav_links", ["dimensional_lattice", "rift_harbor", "furnace_basin", "gale_corridor"], 24)):
            raw_nav = []
            for seed in (1, 2):
                for map_index, arena in enumerate(maps):
                    for k in range(n):
                        raw_nav.append({"_suite": suite, "_seed_set": seed, "map": arena, "seed": seed * 10000 + map_index * 1000 + k,
                            "ring_out_s": .5 if arena == "bastion_ring" else 0, "ring_dmg": 0,
                            "reason": "elimination", "heroes": [{"eps": []}], "stuck": [], "censored_stuck": [],
                            "trips": [{"cause": "walking", "against": True}] if suite == "nav_links" and k % 4 == 0 else []})
            inputs[suite]["navigation"] = analyzer.summarize_nav(raw_nav)
        result = evaluate(inputs)
        self.assertEqual(result["status"], "PASS", result["errors"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
