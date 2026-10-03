"""Strict payload classification of render_v2's pinned five live-demo failures.

The caller must independently verify process exit/lifecycle, exact test and
fixture identities, source binding, and output freshness. A match is still FAIL.
No simulation is run and no gate or test expectation is changed here.
"""
from __future__ import annotations

import hashlib
import math
from pathlib import Path

SOURCE_SHA256 = "dedaabfe84a650811eebfff68238ed759cb4a103fd0b0deb667ac1525b96ca92"
FIXTURE_LOG_SHA256 = "e6bcfc7e52b0676f647cacb255643357688838e1cfb992845edbb43c664e8c4f"
ENGINE_HEADER = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org"
SUMMARY_PREFIX = "RENDER_V2 "
FAILURES = [
	"the demo battle shows TANK_DESTROYED",
	"the demo battle shows OVERDRIVE",
	"the demo battle draws the overdrive state",
	"the demo battle draws the charge state",
	"the demo battle draws the missileBarrage state",
]
PATTERNS = ["shadeSpawn", "underworldCleave", "soulHarvest", "boosterDash", "missileBarrage",
	"arcShield", "genocideStrip", "autoDaFe", "edictBind", "alhambraEdict", "peliasSpear",
	"hephaestusShield", "warRoar", "chariotCharge"]
LIVE_KINDS = ["cerberus", "fuel_tank", "shade", "chariot"]
LIVE_EVENTS = ["CHARIOT_KNOCK", "CLEANSED", "FRONT_BLOCKED"]
LIVE_STATES = ["concealed", "peliasSpear"]
SHOWCASE_KINDS = {"cerberus": 1, "chariot": 1, "fuel_tank": 1, "shade": 5}
SHOWCASE_ZONES = ["rect:genocideStrip", "circle:autoDaFe"]
SHOWCASE_FX = ["cleanse", "block", "soft", "sig", "cone", "flash", "strip", "impact", "tether", "wave"]
DRAW_KEYS = {"ev_fx", "fx", "hud_layer", "proj_solid_layer", "unit_layer", "zone_layer"}
ERROR_BLOCKS = [
	["ERROR: FAIL " + label,
		"   at: push_error (core/variant/variant_utility.cpp:1023)",
		"   GDScript backtrace (most recent call first):",
		"       [0] _check (res://tests/render_v2.gd:39)",
		"       [1] _live_battle (res://tests/render_v2.gd:%d)" % (252 if i < 2 else 254)]
	for i, label in enumerate(FAILURES)
]


def _require(ok, message):
	if not ok:
		raise ValueError("render_v2 payload: " + message)


def _keys(value, expected, context):
	_require(type(value) is dict and set(value) == expected, context + " has missing/extra fields")


def _integer(value, context, minimum=0):
	_require(type(value) is int, context + " must be an integer (not bool or float)")
	try:
		finite = math.isfinite(value)
	except (OverflowError, ValueError):
		finite = False
	_require(finite and value >= minimum, context + " is non-finite/out of range")


def _list(value, expected, context):
	_require(type(value) is list and value == expected, context + " values/order differ")


def _metrics(metrics):
	_keys(metrics, {"live", "patterns", "showcase"}, "metrics")
	_list(metrics["patterns"], PATTERNS, "patterns")
	live = metrics["live"]
	_keys(live, {"draws", "events", "kinds", "states", "ticks"}, "live")
	_integer(live["ticks"], "live.ticks")
	_require(live["ticks"] == 1861, "live must contain the complete 1861-tick demo")
	_list(live["events"], LIVE_EVENTS, "live.events")
	_list(live["kinds"], LIVE_KINDS, "live.kinds")
	_list(live["states"], LIVE_STATES, "live.states")
	draws = live["draws"]
	_keys(draws, DRAW_KEYS, "live.draws")
	for name, value in draws.items():
		_integer(value, "live.draws." + name)
	# Preserve the producer's coverage test exactly; do not pin a run's counters.
	_require(draws["unit_layer"] >= live["ticks"] * .5 - 2.0
		and draws["zone_layer"] > 0 and draws["ev_fx"] > 0
		and draws["proj_solid_layer"] > 0, "draws contradict the passing layer-coverage assertion")
	showcase = metrics["showcase"]
	_keys(showcase, {"fx_items", "kinds", "zones"}, "showcase")
	_keys(showcase["kinds"], set(SHOWCASE_KINDS), "showcase.kinds")
	for name, count in showcase["kinds"].items():
		_integer(count, "showcase.kinds." + name)
		_require(count == SHOWCASE_KINDS[name], "showcase count differs for " + name)
	_list(showcase["zones"], SHOWCASE_ZONES, "showcase.zones")
	_list(showcase["fx_items"], SHOWCASE_FX, "showcase.fx_items")


def validate(log_path: Path, parse_json) -> dict:
	"""Read one native log and return its narrowly classified, preserved FAIL.

	parse_json is the caller's strict assertion_json(text) callback, rejecting
	duplicate keys, non-finite constants/overflow and trailing JSON. Nonempty
	stdout must consist of exactly one engine header, five pinned backtraces,
	and one final anchored summary. Arbitrary additional output is rejected.
	"""
	try:
		raw = log_path.read_bytes()
		text = raw.decode("utf-8")
	except (OSError, UnicodeError) as exc:
		raise ValueError("render_v2 payload: unreadable UTF-8 native log") from exc
	# Native Windows CRLF and LF are equivalent; other control-line separators
	# are not discarded as harmless whitespace.
	lines = [line for line in text.replace("\r\n", "\n").split("\n") if line.strip(" \t")]
	expected = [ENGINE_HEADER] + [line for block in ERROR_BLOCKS for line in block]
	_require(len(lines) == len(expected) + 1 and lines[:-1] == expected,
		"native header/error blocks are missing, additional, reordered or foreign")
	_require(lines[-1].startswith(SUMMARY_PREFIX), "missing/foreign final anchored summary")
	try:
		report = parse_json(lines[-1][len(SUMMARY_PREFIX):])
	except Exception as exc:
		raise ValueError("render_v2 payload: invalid strict summary JSON") from exc
	_keys(report, {"failed", "metrics", "passed", "status"}, "summary")
	_require(report["status"] == "FAIL", "expected FAIL status")
	_integer(report["passed"], "passed")
	_require(report["passed"] == 190, "expected exactly 190 passing assertions")
	_list(report["failed"], FAILURES, "failed")
	_require(report["passed"] + len(report["failed"]) == 195, "expected 195 total assertions")
	_metrics(report["metrics"])
	try:
		_require(log_path.read_bytes() == raw, "input changed during validation")
	except OSError as exc:
		raise ValueError("render_v2 payload: input disappeared during validation") from exc
	return {"classification": "KNOWN_RENDER_ASSERTION_FAILURE", "suite": "render_v2",
		"status": "FAIL", "acceptance_status": "FAIL", "passed": 190, "failed": 5,
		"failed_checks": list(report["failed"]), "checks": 195,
		"metrics": report["metrics"], "payload": report,
		"log_sha256": hashlib.sha256(raw).hexdigest(),
		"cause": "NOT_DETERMINED_BY_PAYLOAD",
		"requires_caller_checks": ["process", "source/fixture identity", "freshness"]}
