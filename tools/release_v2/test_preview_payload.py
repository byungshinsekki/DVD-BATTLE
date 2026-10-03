"""Pure payload tests: local immutable fixtures, no processes/network/profile writes."""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
if __package__:
	from . import preview_payload as payload
else:
	import preview_payload as payload


def assertion_json(text):
	def unique(pairs):
		result = {}
		for key, value in pairs:
			if key in result:
				raise ValueError("duplicate key")
			result[key] = value
		return result
	def reject(value):
		raise ValueError("non-finite constant " + value)
	def finite(value):
		parsed = float(value)
		if not math.isfinite(parsed):
			raise ValueError("non-finite float")
		return parsed
	return json.loads(text, object_pairs_hook=unique, parse_constant=reject, parse_float=finite)


class MemoryFile:
	def __init__(self, raw):
		self.raw = raw.encode("utf-8") if isinstance(raw, str) else raw
	def read_bytes(self):
		return self.raw


class PayloadTests(unittest.TestCase):
	@classmethod
	def setUpClass(cls):
		folder = Path(__file__).resolve().parent / "test_fixtures/preview_14_known_v1"
		cls.report_raw = (folder / "report.json").read_bytes()
		cls.log = (folder / "stdout.txt").read_text(encoding="utf-8")
		cls.fixture = assertion_json(cls.report_raw.decode("utf-8"))
		cls.fixture_source = (folder / "preview_ui_14.gd.txt").read_bytes()
		cls.fixture_scene = (folder / "preview_ui_14.tscn.txt").read_bytes()

	def setUp(self):
		self.report = copy.deepcopy(self.fixture)

	def invoke(self, report=None, log=None, parser=assertion_json):
		raw = json.dumps(self.report if report is None else report, ensure_ascii=False)
		return payload.validate(MemoryFile(raw), MemoryFile(self.log if log is None else log), parser)

	def reject(self, report=None, log=None):
		with self.assertRaises(ValueError):
			self.invoke(report=report, log=log)

	def summary_log(self, measurements):
		lines = self.log.splitlines()
		assert lines[-1].startswith(payload.SUMMARY_PREFIX)
		lines[-1] = payload.SUMMARY_PREFIX + json.dumps(measurements, ensure_ascii=False)
		return "\n".join(lines) + "\n"

	def test_actual_fixture_is_classified_but_remains_fail(self):
		result = self.invoke()
		self.assertEqual((result["status"], result["acceptance"], result["passed"], result["failed"], result["checks"]), ("FAIL", "FAIL", 105, 1, 106))
		self.assertEqual(result["failed_checks"], [payload.FAILURE])
		self.assertEqual(result["cause"], "NOT_DETERMINED_BY_PAYLOAD")
		self.assertEqual(result["check_labels_sha256"], payload.LABELS_SHA256)

	def test_pinned_sources_are_actual_preserved_fixture(self):
		self.assertEqual(hashlib.sha256(self.fixture_source).hexdigest(), payload.SOURCE_SHA256)
		self.assertEqual(hashlib.sha256(self.fixture_scene).hexdigest(), payload.SCENE_SHA256)

	def test_timing_frame_and_hardware_numbers_are_not_fixed(self):
		m = self.report["measurements"]
		m.update(cancel_ms=0, final_5v5_frames=300, final_5v5_seconds=12.75, search_peak_slice_ms=.05)
		for tag in ("3440x1440", "1600x900"):
			m["layout_" + tag].update(settle_ms=75, screen_size=[3840, 2160], screen_usable_rect="[P: (-3840, 0), S: (3840, 2100)]")
		result = self.invoke(log=self.summary_log(m))
		self.assertEqual(result["measurements"], m)

	def test_json_parser_is_used_for_both_payloads(self):
		calls = []
		def parser(text):
			calls.append(text)
			return assertion_json(text)
		self.invoke(parser=parser)
		self.assertEqual(len(calls), 2)

	def test_report_schema_is_exact(self):
		for key in self.report:
			with self.subTest(missing=key):
				r = copy.deepcopy(self.report); del r[key]; self.reject(report=r)
		r = copy.deepcopy(self.report); r["extra"] = 1; self.reject(report=r)
		self.reject(report=[])

	def test_suite_status_and_counts_are_strict(self):
		for key, value in [("suite", "preview_ui_15"), ("status", "PASS"), ("passed", 105.0), ("passed", True), ("failed", True), ("failed", 0), ("failed", 2), ("passed", 104)]:
			with self.subTest(key=key, value=value):
				r = copy.deepcopy(self.report); r[key] = value; self.reject(report=r)

	def test_missing_duplicate_reordered_and_foreign_labels_rejected(self):
		for mutation in ("missing", "duplicate", "reorder", "rename"):
			r = copy.deepcopy(self.report)
			if mutation == "missing": r["checks"].pop()
			elif mutation == "duplicate": r["checks"][1] = r["checks"][0]
			elif mutation == "reorder": r["checks"][0], r["checks"][1] = r["checks"][1], r["checks"][0]
			else: r["checks"][0]["check"] += " changed"
			with self.subTest(mutation=mutation): self.reject(report=r)

	def test_check_shape_and_boolean_are_strict(self):
		for mutation in ("extra", "missing", "integer", "string", "nondict"):
			r = copy.deepcopy(self.report)
			if mutation == "extra": r["checks"][0]["extra"] = True
			elif mutation == "missing": del r["checks"][0]["passed"]
			elif mutation == "integer": r["checks"][0]["passed"] = 1
			elif mutation == "string": r["checks"][0]["passed"] = "true"
			else: r["checks"][0] = "PASS"
			with self.subTest(mutation=mutation): self.reject(report=r)

	def test_other_or_additional_or_absent_failure_rejected(self):
		for mutation in ("additional", "other", "none"):
			r = copy.deepcopy(self.report)
			if mutation != "none": r["checks"][0]["passed"] = False
			if mutation != "additional":
				for row in r["checks"]:
					if row["check"] == payload.FAILURE: row["passed"] = True
			with self.subTest(mutation=mutation): self.reject(report=r)

	def test_all_stdout_pass_lines_and_order_required(self):
		first = "PASS " + self.report["checks"][0]["check"]
		second = "PASS " + self.report["checks"][1]["check"]
		for log in (self.log.replace(first+"\n", "", 1), self.log.replace(first, first+"\n"+first, 1), self.log.replace(first+"\n"+second, second+"\n"+first, 1), self.log.replace(first, "PASS fabricated", 1)):
			self.reject(log=log)

	def test_any_extra_error_warning_script_or_fail_is_rejected(self):
		for extra in ("ERROR: unrelated", "WARNING: unrelated", "SCRIPT ERROR: invalid", "Parse Error: invalid", "FAIL additional assertion", "PASS unrelated", "unknown output"):
			with self.subTest(extra=extra): self.reject(log=self.log+extra+"\n")
		self.reject(log=self.log.replace("OpenGL API 3.3.0 NVIDIA", "OpenGL API 3.3.0 WARNING: NVIDIA", 1))

	def test_expected_error_block_is_complete_and_exact(self):
		for line in payload.ERROR_BLOCK:
			with self.subTest(line=line): self.reject(log=self.log.replace(line+"\n", "", 1))
		self.reject(log=self.log.replace("res://tests/preview_ui_14.gd:191", "res://tests/other.gd:191"))
		self.reject(log=self.log.replace("ERROR: FAIL " + payload.FAILURE, "ERROR: FAIL another assertion"))

	def test_exactly_one_final_summary_with_matching_counts(self):
		line = self.log.splitlines()[-1]
		self.reject(log=self.log.replace(line, ""))
		self.reject(log=self.log+line+"\n")
		self.reject(log=self.log.replace(payload.SUMMARY_PREFIX, "PREVIEW_UI_14 104 PASS / 2 FAIL "))
		self.reject(log=self.log.replace(payload.SUMMARY_PREFIX, "PREVIEW_UI_14 105 PASS / 0 FAIL "))

	def test_measurement_payload_and_stdout_must_match(self):
		m = copy.deepcopy(self.report["measurements"]); m["cancel_ms"] += 1
		self.reject(log=self.summary_log(m))

	def test_measurement_schema_and_backend_are_complete(self):
		for key in payload.MEASUREMENT_KEYS:
			r = copy.deepcopy(self.report); del r["measurements"][key]
			with self.subTest(key=key): self.reject(report=r)
		for value in ("headless", "Linux", "", None):
			r = copy.deepcopy(self.report); r["measurements"]["render_backend"] = value; self.reject(report=r)
		r = copy.deepcopy(self.report); r["measurements"]["score"] = 1; self.reject(report=r)

	def test_numeric_time_and_frames_validation(self):
		for field in ("cancel_ms", "final_5v5_seconds", "search_peak_slice_ms"):
			for value in (-1, True, "0", None, float("nan"), float("inf")):
				r = copy.deepcopy(self.report); r["measurements"][field] = value
				with self.subTest(field=field, value=value): self.reject(report=r)
		for value in (-1, True, 3.5):
			r = copy.deepcopy(self.report); r["measurements"]["final_5v5_frames"] = value; self.reject(report=r)


	def test_integer_overflow_is_not_treated_as_finite_measurement(self):
		r = copy.deepcopy(self.report); r["measurements"]["final_5v5_frames"] = 10**400; self.reject(report=r)
		r = copy.deepcopy(self.report); r["measurements"]["layout_1600x900"]["screen_size"] = [10**400, 1440]; self.reject(report=r)

	def test_layout_schema_dimensions_and_modes_are_complete(self):
		for tag in ("3440x1440", "1600x900"):
			key = "layout_" + tag
			for field in payload.LAYOUT_KEYS:
				r = copy.deepcopy(self.report); del r["measurements"][key][field]
				with self.subTest(tag=tag, field=field): self.reject(report=r)
			for field in ("actual_window_size", "actual_display_size", "actual_render_size"):
				for value in ([1600, 899], [3440], [True, 900], [1600.0, 900], "1600x900"):
					r = copy.deepcopy(self.report); r["measurements"][key][field] = value; self.reject(report=r)
			for field in ("display_mode", "window_mode"):
				for value in (True, -1, 5, 3.0):
					r = copy.deepcopy(self.report); r["measurements"][key][field] = value; self.reject(report=r)

	def test_layout_finite_geometry_and_rect_format(self):
		for field in ("visible_height", "canvas_width", "canvas_height", "controls_bottom", "conditions_bottom", "visible_bottom", "settle_ms"):
			for value in (True, None, "nan", -1, float("nan"), float("inf")):
				r = copy.deepcopy(self.report); r["measurements"]["layout_1600x900"][field] = value
				with self.subTest(field=field, value=value): self.reject(report=r)
		for value in ("", "[P: (NaN, 0), S: (3440, 1392)]", "[P: (0, 0), S: (0, 1392)]", 3):
			r = copy.deepcopy(self.report); r["measurements"]["layout_1600x900"]["screen_usable_rect"] = value; self.reject(report=r)
		for value in ([0, 1440], [3440, True], [3440.0, 1440]):
			r = copy.deepcopy(self.report); r["measurements"]["layout_1600x900"]["screen_size"] = value; self.reject(report=r)

	def test_layout_cannot_contradict_passed_geometry_assertions(self):
		for field, value in (("canvas_width", 30), ("controls_bottom", 2000), ("conditions_bottom", 2000)):
			r = copy.deepcopy(self.report); r["measurements"]["layout_1600x900"][field] = value; self.reject(report=r)

	def test_duplicate_json_keys_in_report_or_summary_rejected(self):
		raw = json.dumps(self.report).replace('"failed": 1', '"failed": 1, "failed": 1', 1)
		with self.assertRaises(ValueError): payload.validate(MemoryFile(raw), MemoryFile(self.log), assertion_json)
		log = self.log.replace('"cancel_ms":17.063', '"cancel_ms":17.063,"cancel_ms":17.063')
		self.assertNotEqual(log, self.log); self.reject(log=log)

	def test_nonfinite_overflow_or_boolean_summary_rejected(self):
		for value in (float("nan"), float("inf"), True):
			m = copy.deepcopy(self.report["measurements"]); m["cancel_ms"] = value; self.reject(log=self.summary_log(m))
		self.reject(log=self.log.replace('"cancel_ms":17.063', '"cancel_ms":1e9999'))

	def test_invalid_utf8_missing_file_and_changing_input_rejected(self):
		with self.assertRaises(ValueError): payload.validate(MemoryFile(b'\xff'), MemoryFile(self.log), assertion_json)
		class MissingFile:
			def read_bytes(self): raise FileNotFoundError("synthetic missing input")
		with self.assertRaises(ValueError): payload.validate(MissingFile(), MemoryFile(self.log), assertion_json)
		class ChangingFile(MemoryFile):
			reads = 0
			def read_bytes(self):
				self.reads += 1
				return self.raw if self.reads == 1 else self.raw+b" "
		with self.assertRaises(ValueError): payload.validate(ChangingFile(self.report_raw), MemoryFile(self.log), assertion_json)


if __name__ == "__main__":
	unittest.main(verbosity=2)
