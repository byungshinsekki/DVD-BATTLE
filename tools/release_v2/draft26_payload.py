"""Read-only classification of the reviewed 26-hero draft payload; FAIL stays FAIL.

Lifecycle, source identity, strict JSON parsing, and capture freshness are the
caller's responsibility. This module never runs Godot or changes an input.
"""
import copy
import math
import re


ROSTER = tuple("achilles aphrodite archer baseball blood_mage dimensionalist engineer fisherman giant hades hermes hive_mind joker mage metatron nitro pirate plague_doctor politician sniper swordsman torquemada torturer war_machine werewolf world_tree".split())
LEGAL = set(ROSTER) - {"giant"}
FAILURES = (
	"final-pick actual-engine phase starts",
	"actual-engine phase can be cancelled",
	"two candidates with mirrored sides obey fixed tick budget",
	"rollout candidate side coverage is balanced",
	"chosen finalist received both engine side trials",
	"only comparable finalists appear as engine alternatives",
)
LABELS = tuple(f"{mode} {size}v{size}" for mode in ("elimination", "control") for size in (1, 3, 5)) + (
	"1ms cooperative static search", "full-composition horizon", "actual-engine bounded rollout",
	"control5v5 final pick default 8ms slices",
)
FINAL_LEGAL = set(ROSTER) - set("swordsman archer mage giant politician werewolf sniper metatron engineer".split())
SUMMARY = "DRAFT 1.4 FAIL passed=255 failures=6"
HEADER = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org"
SEVERITY = re.compile(r"SCRIPT ERROR|Parse Error|\bERROR:|\bWARNING:", re.IGNORECASE)


def require(condition, message):
	if not condition:
		raise RuntimeError(message)


def number(value, minimum=None):
	return type(value) in (int, float) and math.isfinite(value) and (minimum is None or value >= minimum)


def integer(value, minimum=0):
	return type(value) is int and value >= minimum


def search_shape(search, legal):
	counts = {"nodes", "evals", "cache_misses", "depth", "completed_depth", "target_depth", "candidates", "covered_candidates", "budget"}
	flags = {"forecast_complete", "search_complete"}
	nested = {"policy_completion", "per_candidate_evals", "per_candidate_budget", "opponent_model", "rollout"}
	require(isinstance(search, dict) and set(search) == counts | flags | nested
		and all(integer(search[key]) for key in counts) and all(type(search[key]) is bool for key in flags),
		"Missing/malformed complete draft26 search metrics")
	require(search["budget"] == 45000 and 0 < search["candidates"] == search["covered_candidates"] == len(legal)
		and search["forecast_complete"] and 0 < search["completed_depth"] <= search["target_depth"],
		"Incomplete draft26 candidate/depth coverage")
	quotas, evaluations = search["per_candidate_budget"], search["per_candidate_evals"]
	require(isinstance(quotas, dict) and isinstance(evaluations, dict) and set(quotas) == set(evaluations) == legal
		and all(integer(quotas[key], 1) and integer(evaluations[key]) and evaluations[key] <= quotas[key] for key in quotas)
		and sum(quotas.values()) == search["budget"] and sum(evaluations.values()) == search["evals"],
		"Incomplete draft26 per-candidate budget evidence")
	policy = search["policy_completion"]
	require(isinstance(policy, dict) and set(policy) == {"enabled", "completed_candidates", "evals", "leaves", "prefix_fallback", "policy"}
		and policy["enabled"] is True and policy["prefix_fallback"] is False and policy["policy"] == "public_legal_greedy"
		and all(integer(policy[key]) for key in ("completed_candidates", "evals", "leaves"))
		and policy["completed_candidates"] == search["candidates"], "Missing draft26 completion policy evidence")
	model = search["opponent_model"]
	require(isinstance(model, dict) and set(model) == {"worst_weight", "expected_weight", "history_prior_max", "history_samples"}
		and all(number(value, 0) for value in model.values())
		and math.isclose(model["worst_weight"] + model["expected_weight"], 1.0, abs_tol=1e-12), "Malformed draft26 opponent model")
	rollout = search["rollout"]
	numeric = {"tick_budget", "ticks", "games", "horizon_ticks", "min_horizon_ticks", "sides_per_finalist"}
	require(isinstance(rollout, dict) and set(rollout) == numeric | {"enabled", "final_pick_only", "finalists_only", "weight", "gap_gate", "rows", "skipped"}
		and all(integer(rollout[key]) for key in numeric)
		and all(type(rollout[key]) is bool for key in ("enabled", "final_pick_only", "finalists_only"))
		and all(number(rollout[key], 0) for key in ("weight", "gap_gate"))
		and rollout["skipped"] in ("", "gap", "horizon") and isinstance(rollout["rows"], list)
		and rollout["games"] == len(rollout["rows"]) and rollout["ticks"] <= rollout["tick_budget"],
		"Missing/malformed draft26 rollout evidence")
	for trial in rollout["rows"]:
		require(isinstance(trial, dict) and set(trial) == {"id", "side", "ticks", "seconds", "value", "finished"}
			and trial["id"] in legal and integer(trial["side"]) and trial["side"] in (0, 1)
			and integer(trial["ticks"]) and trial["ticks"] <= rollout["horizon_ticks"]
			and number(trial["seconds"], 0) and number(trial["value"]) and -1 <= trial["value"] <= 1
			and type(trial["finished"]) is bool, "Incomplete draft26 engine trial evidence")
	require(sum(trial["ticks"] for trial in rollout["rows"]) == rollout["ticks"], "Draft26 trial/tick totals disagree")


def _complete_measurements(measured):
	"""Retain all ten producer payload schemas; picks and timings are not pinned."""
	require(isinstance(measured, list) and all(isinstance(row, dict) for row in measured)
		and tuple(row.get("label") for row in measured) == LABELS,
		"Missing/changed completed draft26 measurement coverage")
	structure_legal = set(ROSTER) - {"archer"}
	for row in measured[:6]:
		require(set(row) == {"label", "id", "milliseconds", "search"} and row["id"] in structure_legal
			and number(row["milliseconds"], 0), "Incomplete draft26 structure measurement")
		search_shape(row["search"], structure_legal)
	frame = measured[6]
	require(set(frame) == {"label", "largest_slice_ms"} and number(frame["largest_slice_ms"], 0), "Incomplete draft26 frame measurement")
	horizon = measured[7]
	require(set(horizon) == {"label", "three", "five"}, "Incomplete draft26 horizon measurement")
	for name, count in (("three", 5), ("five", 9)):
		row = horizon[name]
		require(isinstance(row, dict) and set(row) == {"id", "value", "depth", "forecast"} and row["id"] in ROSTER
			and number(row["value"]) and integer(row["depth"], 1) and isinstance(row["forecast"], list)
			and len(row["forecast"]) == count, "Incomplete draft26 full-composition forecast")
		for pick in row["forecast"]:
			require(isinstance(pick, dict) and set(pick) in ({"id", "side"}, {"id", "side", "policy"})
				and pick["id"] in ROSTER and pick["side"] in ("ai", "user")
				and ("policy" not in pick or type(pick["policy"]) is bool), "Malformed draft26 forecast pick")
	require(set(measured[8]) == {"label", "search"}, "Incomplete draft26 bounded-rollout measurement")
	search_shape(measured[8]["search"], LEGAL)
	performance = measured[9]
	require(set(performance) == {"label", "id", "largest_slice_ms", "p95_slice_ms", "search", "slice_count", "wall_seconds"}
		and performance["id"] in FINAL_LEGAL and integer(performance["slice_count"], 1)
		and all(number(performance[key], 0) for key in ("largest_slice_ms", "p95_slice_ms", "wall_seconds")),
		"Incomplete draft26 final-pick performance measurement")
	search_shape(performance["search"], FINAL_LEGAL)


def complete_measurements(measured):
	"""Validate the complete producer shape, including the caller's PASS path."""
	try:
		_complete_measurements(measured)
	except (TypeError, KeyError, IndexError, ValueError, OverflowError) as error:
		raise RuntimeError(f"Malformed draft26 measurements: {error}") from error


def _validate(data, lines, problems):
	require(isinstance(data, dict) and set(data) == {"status", "passed", "failures", "measurements"}, "Malformed draft26 report root")
	require(data["status"] == "FAIL" and type(data["passed"]) is int and data["passed"] == 255
		and isinstance(data["failures"], list) and data["failures"] == list(FAILURES),
		"Not the exact completed 255 PASS / six FAIL draft26 fixture")
	complete_measurements(data["measurements"])
	search = data["measurements"][8]["search"]
	expected = {"budget": 45000, "candidates": 25, "covered_candidates": 25, "evals": 50, "nodes": 25,
		"cache_misses": 25, "depth": 1, "completed_depth": 1, "target_depth": 1,
		"search_complete": True, "forecast_complete": True}
	require(all(type(search[key]) is type(value) and search[key] == value for key, value in expected.items()),
		"Known draft26 bounded search changed or is incomplete")
	require(all(type(value) is int and value == 1800 for value in search["per_candidate_budget"].values())
		and all(type(value) is int and value == 2 for value in search["per_candidate_evals"].values()),
		"Known draft26 bounded candidate allocations changed")
	expected_rollout = dict(enabled=True, final_pick_only=True, finalists_only=True, games=0, gap_gate=1.0,
		horizon_ticks=300, min_horizon_ticks=300, rows=[], sides_per_finalist=2,
		skipped="gap", tick_budget=1200, ticks=0, weight=0.24)
	rollout = search["rollout"]
	require(set(rollout) == set(expected_rollout)
		and all(type(rollout[key]) is type(value) and rollout[key] == value for key, value in expected_rollout.items()),
		"Draft26 failure is not the reviewed bounded final-pick gap case")
	require(isinstance(lines, list) and all(isinstance(line, str) and "\n" not in line and "\r" not in line for line in lines),
		"Draft26 stdout must contain complete individual lines")
	expected_errors = ["ERROR: " + failure for failure in FAILURES]
	actual_errors = [line for line in lines if SEVERITY.search(line)]
	require(isinstance(problems, list) and problems == actual_errors == expected_errors,
		"Additional/missing draft26 engine or assertion errors")
	expected_lines = [HEADER]
	for failure, source_line in zip(FAILURES, (155, 159, 167, 173, 174, 175)):
		expected_lines.extend(("ERROR: " + failure,
			"   at: push_error (core/variant/variant_utility.cpp:1023)",
			"   GDScript backtrace (most recent call first):",
			"       [0] check (res://tests/draft_14.gd:15)",
			f"       [1] rollout_contract (res://tests/draft_14.gd:{source_line})",
			"       [2] _run (res://tests/draft_14.gd:26)"))
	expected_lines.append(SUMMARY)
	require([line for line in lines if line != ""] == expected_lines,
		"Unexpected/missing draft26 stdout, summary, or source backtrace")
	return dict(classification="completed_known_draft26_gap_fixture_failure", status="FAIL", acceptance_status="FAIL",
		passed=data["passed"], failed=list(FAILURES), assertion_count=261, measurement_count=10,
		roster=list(ROSTER), rollout=copy.deepcopy(rollout), measurements=copy.deepcopy(data["measurements"]),
		assertion_error_lines=actual_errors, infrastructure_errors=[], infrastructure_error_count=0)


def validate(data, lines, problems):
	"""Return complete reviewed payload evidence, or raise RuntimeError.

	The caller must parse JSON strictly before calling. A successful return is a
	classification of the known failure, never an acceptance success.
	"""
	try:
		return _validate(data, lines, problems)
	except (TypeError, KeyError, IndexError, ValueError, OverflowError) as error:
		raise RuntimeError(f"Malformed draft26 payload: {error}") from error
