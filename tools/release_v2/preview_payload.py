"""Strict read-only classification of the pinned preview_ui_14 known failure.

This validates payload/log completeness only. The caller must separately verify
process outcome, exact test/source/fixture identity and output freshness. A match
remains FAIL; it does not establish the failure's cause or waive any gate.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re

FAILURE = "final pick uses actual battle verification"
LABELS_SHA256 = "f2d006ab5f533abd66e89592c694d7f7af5eb9f8a42bd222e6602639e5251f72"
SOURCE_SHA256 = "541b966a3ebaf753ea20e0507caf9e94b60050b2ce4cf64cf58332248047e30e"
SCENE_SHA256 = "8907a7970567ac839bb667ce05e8eb183402160b020e7df61e0191da3f2fb787"
REPORT_KEYS = {"suite", "status", "passed", "failed", "checks", "measurements"}
MEASUREMENT_KEYS = {"cancel_ms", "final_5v5_frames", "final_5v5_seconds", "search_peak_slice_ms",
	"render_backend", "layout_3440x1440", "layout_1600x900"}
LAYOUT_KEYS = {"visible_height", "canvas_width", "canvas_height", "controls_bottom", "conditions_bottom",
	"visible_bottom", "actual_window_size", "actual_display_size", "actual_render_size", "window_mode",
	"display_mode", "screen_size", "screen_usable_rect", "settle_ms"}
ENGINE_HEADER = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org"
RENDER_HEADER = re.compile(r"OpenGL API [0-9.]+ [^\r\n]+ - Compatibility - Using Device: [^\r\n]+")
RECT = re.compile(r"\[P: \((-?\d+), (-?\d+)\), S: \((\d+), (\d+)\)\]")
ERROR_BLOCK = [
	"ERROR: FAIL " + FAILURE,
	"   at: push_error (core/variant/variant_utility.cpp:1023)",
	"   GDScript backtrace (most recent call first):",
	"       [0] _check (res://tests/preview_ui_14.gd:27)",
	"       [1] _run (res://tests/preview_ui_14.gd:191)",
]
SUMMARY_PREFIX = "PREVIEW_UI_14 105 PASS / 1 FAIL "


def _require(ok, message):
	if not ok:
		raise ValueError("preview_ui_14 payload: " + message)


def _keys(value, expected, context):
	_require(type(value) is dict and set(value) == expected, context + " has missing/extra fields")


def _number(value, context, positive=False):
	_require(type(value) in (int, float), context + " is not a number")
	try:
		finite = math.isfinite(value)
	except (OverflowError, ValueError):
		finite = False
	_require(finite and (value > 0 if positive else value >= 0), context + " is non-finite/out of range")


def _integer(value, context, positive=False):
	_require(type(value) is int, context + " is not a valid integer")
	_number(value, context, positive=positive)


def _size(value, context):
	_require(type(value) is list and len(value) == 2, context + " must be a 2D size")
	for part in value:
		_integer(part, context, positive=True)


def _measurements(value):
	_keys(value, MEASUREMENT_KEYS, "measurements")
	_require(value["render_backend"] == "Windows", "render backend must be Windows")
	for field in ("cancel_ms", "final_5v5_seconds", "search_peak_slice_ms"):
		_number(value[field], field)
	_integer(value["final_5v5_frames"], "final_5v5_frames")
	for tag, dimensions in (("3440x1440", [3440, 1440]), ("1600x900", [1600, 900])):
		layout = value["layout_" + tag]
		_keys(layout, LAYOUT_KEYS, "layout_" + tag)
		for field in ("visible_height", "canvas_width", "canvas_height", "visible_bottom"):
			_number(layout[field], tag + "." + field, positive=True)
		for field in ("controls_bottom", "conditions_bottom", "settle_ms"):
			_number(layout[field], tag + "." + field)
		for field in ("actual_window_size", "actual_display_size", "actual_render_size"):
			_size(layout[field], tag + "." + field)
			_require(layout[field] == dimensions, tag + "." + field + " differs from requested size")
		_size(layout["screen_size"], tag + ".screen_size")
		for field in ("window_mode", "display_mode"):
			_integer(layout[field], tag + "." + field)
			_require(layout[field] <= 4, tag + "." + field + " is not a window mode")
		usable = layout["screen_usable_rect"]
		_require(type(usable) is str, tag + ".screen_usable_rect is not text")
		match = RECT.fullmatch(usable)
		_require(match is not None, tag + ".screen_usable_rect has invalid Rect2i form")
		_require(int(match.group(3)) > 0 and int(match.group(4)) > 0, tag + ".screen_usable_rect has empty size")
		_require(abs(layout["canvas_width"] / layout["canvas_height"] - 16 / 9) < .01,
			tag + " canvas contradicts the passing aspect assertion")
		for field in ("controls_bottom", "conditions_bottom"):
			_require(layout[field] <= layout["visible_bottom"] + 1, tag + "." + field + " contradicts visibility")


def _parse(parse_json, text, context):
	try:
		return parse_json(text)
	except Exception as exc:
		raise ValueError("preview_ui_14 payload: invalid " + context + " JSON") from exc


def validate(report_path: Path, log_path: Path, parse_json) -> dict:
	"""Return a verified diagnostic FAIL record; raise ValueError for any mismatch.

	parse_json is the caller's strict assertion_json(text) parser (duplicate-key
	and non-finite-number rejection). This function reads only the two given files.
	It accepts varying finite timing/frame/hardware measurements, never fixed scores.
	"""
	try:
		report_raw, log_raw = report_path.read_bytes(), log_path.read_bytes()
		report_text, log_text = report_raw.decode("utf-8"), log_raw.decode("utf-8")
	except (OSError, UnicodeError) as exc:
		raise ValueError("preview_ui_14 payload: unreadable report/log") from exc
	report = _parse(parse_json, report_text, "report")
	_keys(report, REPORT_KEYS, "report")
	_require(report["suite"] == "preview_ui_14" and report["status"] == "FAIL", "suite/status differs")
	_require(type(report["passed"]) is int and report["passed"] == 105
		and type(report["failed"]) is int and report["failed"] == 1, "expected exactly 105 PASS and 1 FAIL")
	checks = report["checks"]
	_require(type(checks) is list and len(checks) == 106, "expected complete 106-check list")
	for item in checks:
		_keys(item, {"check", "passed"}, "check")
		_require(type(item["check"]) is str and item["check"] and type(item["passed"]) is bool, "invalid check types")
	labels = [item["check"] for item in checks]
	_require(len(set(labels)) == 106, "duplicate check labels")
	label_hash = hashlib.sha256(json.dumps(labels, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()
	_require(label_hash == LABELS_SHA256, "check labels/order differ from pinned complete producer")
	failed = [item["check"] for item in checks if not item["passed"]]
	_require(failed == [FAILURE] and sum(item["passed"] for item in checks) == 105, "not the single known assertion failure")
	_measurements(report["measurements"])
	# Empty output lines are harmless; every nonempty line has an exact role.
	lines = [line for line in log_text.splitlines() if line.strip()]
	_require(len(lines) >= 3 and lines[0] == ENGINE_HEADER, "missing/foreign engine header")
	_require(RENDER_HEADER.fullmatch(lines[1]) is not None
		and not re.search(r"ERROR|WARNING|SCRIPT|FAIL|Parse Error", lines[1]), "missing/unsafe renderer header")
	expected_lines = []
	for item in checks:
		expected_lines.extend(["PASS " + item["check"]] if item["passed"] else ERROR_BLOCK)
	_require(lines[2:-1] == expected_lines, "stdout checks/error block incomplete, extra, reordered or foreign")
	_require(lines[-1].startswith(SUMMARY_PREFIX), "missing/foreign final summary or counts")
	measurements = _parse(parse_json, lines[-1][len(SUMMARY_PREFIX):], "stdout summary")
	_measurements(measurements)
	_require(measurements == report["measurements"], "stdout/report measurements differ")
	try:
		_require(report_path.read_bytes() == report_raw and log_path.read_bytes() == log_raw, "input changed during validation")
	except OSError as exc:
		raise ValueError("preview_ui_14 payload: input disappeared during validation") from exc
	return {"classification": "KNOWN_PREVIEW_ASSERTION_FAILURE", "status": "FAIL", "suite": "preview_ui_14",
		"passed": 105, "failed": 1, "checks": 106, "failed_checks": failed, "measurements": measurements,
		"report_sha256": hashlib.sha256(report_raw).hexdigest(), "log_sha256": hashlib.sha256(log_raw).hexdigest(),
		"check_labels_sha256": label_hash, "cause": "NOT_DETERMINED_BY_PAYLOAD",
		"requires_caller_checks": ["process", "source/fixture identity", "freshness"], "acceptance": "FAIL"}
