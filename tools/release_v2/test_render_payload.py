"""Pure stdlib payload checks: local fixtures and memory mutations, no processes."""
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
	from . import render_payload as payload
else:
	import render_payload as payload


def assertion_json(text):
	def unique(pairs):
		out = {}
		for key, value in pairs:
			if key in out:
				raise ValueError("duplicate key")
			out[key] = value
		return out
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


class RenderPayloadTests(unittest.TestCase):
	@classmethod
	def setUpClass(cls):
		folder = Path(__file__).resolve().parent / "test_fixtures/render_v2_known_v1"
		cls.log_raw = (folder / "stdout.txt").read_bytes()
		cls.source_raw = (folder / "render_v2.gd.txt").read_bytes()
		cls.log = cls.log_raw.decode("utf-8").replace("\r\n", "\n")
		cls.summary_line = next(line for line in cls.log.splitlines() if line.startswith(payload.SUMMARY_PREFIX))
		cls.fixture = assertion_json(cls.summary_line[len(payload.SUMMARY_PREFIX):])

	def setUp(self):
		self.report = copy.deepcopy(self.fixture)

	def with_report(self, report):
		return self.log.replace(self.summary_line, payload.SUMMARY_PREFIX + json.dumps(report, ensure_ascii=False))

	def invoke(self, report=None, log=None, parser=assertion_json):
		text = self.with_report(self.report if report is None else report) if log is None else log
		return payload.validate(MemoryFile(text), parser)

	def reject(self, report=None, log=None):
		with self.assertRaises(ValueError):
			self.invoke(report=report, log=log)

	def test_actual_fixture_remains_fail_with_complete_payload(self):
		result = payload.validate(MemoryFile(self.log_raw), assertion_json)
		self.assertEqual((result["status"], result["acceptance_status"], result["passed"], result["failed"], result["checks"]), ("FAIL", "FAIL", 190, 5, 195))
		self.assertEqual(result["failed_checks"], payload.FAILURES)
		self.assertEqual(result["payload"], self.fixture)
		self.assertEqual(result["metrics"], self.fixture["metrics"])
		self.assertEqual(result["log_sha256"], payload.FIXTURE_LOG_SHA256)
		self.assertEqual(result["cause"], "NOT_DETERMINED_BY_PAYLOAD")

	def test_source_and_native_log_are_pinned_local_fixtures(self):
		self.assertEqual(hashlib.sha256(self.log_raw).hexdigest(), payload.FIXTURE_LOG_SHA256)
		self.assertEqual(hashlib.sha256(self.source_raw).hexdigest(), payload.SOURCE_SHA256)
		lines = self.source_raw.decode("utf-8").splitlines()
		self.assertIn('push_error("FAIL " + label)', lines[38])
		self.assertIn('"the demo battle shows %s"', lines[251])
		self.assertIn('"the demo battle draws the %s state"', lines[253])

	def test_callback_is_used_once_for_entire_summary(self):
		calls = []
		def parser(text):
			calls.append(text)
			return assertion_json(text)
		self.invoke(parser=parser)
		self.assertEqual(len(calls), 1)
		self.assertEqual(assertion_json(calls[0]), self.report)

	def test_every_object_schema_is_exact(self):
		paths = [(), ("metrics",), ("metrics", "live"), ("metrics", "live", "draws"),
			("metrics", "showcase"), ("metrics", "showcase", "kinds")]
		for path in paths:
			obj = self.report
			for key in path: obj = obj[key]
			for missing in obj:
				r = copy.deepcopy(self.report); node = r
				for key in path: node = node[key]
				del node[missing]
				with self.subTest(path=path, missing=missing): self.reject(report=r)
			r = copy.deepcopy(self.report); node = r
			for key in path: node = node[key]
			node["unexpected"] = 0
			with self.subTest(path=path, extra=True): self.reject(report=r)

	def test_nonobject_schema_values_rejected(self):
		self.reject(report=[])
		for path in [("metrics",), ("metrics", "live"), ("metrics", "live", "draws"), ("metrics", "showcase"), ("metrics", "showcase", "kinds")]:
			for value in ([], None, True, "object"):
				r = copy.deepcopy(self.report); node = r
				for key in path[:-1]: node = node[key]
				node[path[-1]] = value
				with self.subTest(path=path, value=value): self.reject(report=r)

	def test_status_and_pass_counts_are_strict(self):
		for key, value in [("status", "PASS"), ("status", None), ("passed", 189), ("passed", 191), ("passed", 195), ("passed", True), ("passed", 190.0), ("passed", "190")]:
			r = copy.deepcopy(self.report); r[key] = value
			with self.subTest(key=key, value=value): self.reject(report=r)

	def test_exact_five_failures_and_order_required(self):
		for values in ([], payload.FAILURES[:-1], payload.FAILURES + ["another failure"], list(reversed(payload.FAILURES)), payload.FAILURES[:1] * 5, 5, None):
			r = copy.deepcopy(self.report); r["failed"] = values
			with self.subTest(values=values): self.reject(report=r)

	def test_pattern_and_live_and_showcase_lists_are_complete_ordered(self):
		paths = [("metrics", "patterns"), ("metrics", "live", "kinds"), ("metrics", "live", "events"),
			("metrics", "live", "states"), ("metrics", "showcase", "zones"), ("metrics", "showcase", "fx_items")]
		for path in paths:
			original = self.report
			for key in path: original = original[key]
			for value in (original[:-1], original + [original[0]], list(reversed(original)), ["foreign"] + original[1:], None, "list"):
				r = copy.deepcopy(self.report); node = r
				for key in path[:-1]: node = node[key]
				node[path[-1]] = value
				with self.subTest(path=path, value=value): self.reject(report=r)

	def test_other_live_failure_fingerprints_are_not_accepted(self):
		for field, value in [("events", payload.LIVE_EVENTS + ["TANK_DESTROYED"]), ("states", payload.LIVE_STATES + ["charge"]), ("kinds", payload.LIVE_KINDS[:-1])]:
			r = copy.deepcopy(self.report); r["metrics"]["live"][field] = value; self.reject(report=r)

	def test_live_ticks_are_complete_and_integer(self):
		for value in (0, 1860, 1862, 1861.0, True, "1861", None, float("nan"), float("inf"), 10**400):
			r = copy.deepcopy(self.report); r["metrics"]["live"]["ticks"] = value
			with self.subTest(value=value): self.reject(report=r)

	def test_showcase_counts_are_exact_nonboolean_integers(self):
		for key in payload.SHOWCASE_KINDS:
			for value in (0, True, float(payload.SHOWCASE_KINDS[key]), "1", payload.SHOWCASE_KINDS[key] + 1):
				r = copy.deepcopy(self.report); r["metrics"]["showcase"]["kinds"][key] = value
				with self.subTest(key=key, value=value): self.reject(report=r)

	def test_draw_counters_are_not_pinned_to_one_execution(self):
		d = self.report["metrics"]["live"]["draws"]
		d.update(ev_fx=17, fx=41, hud_layer=29, proj_solid_layer=23, unit_layer=1024, zone_layer=13)
		result = self.invoke()
		self.assertEqual(result["payload"], self.report)
		self.assertEqual(result["metrics"]["live"]["draws"], d)

	def test_draw_coverage_boundary_matches_original_assertion(self):
		d = self.report["metrics"]["live"]["draws"]
		d.update(unit_layer=929, zone_layer=1, ev_fx=1, proj_solid_layer=1, fx=0, hud_layer=0)
		self.invoke()
		for key, value in [("unit_layer", 928), ("zone_layer", 0), ("ev_fx", 0), ("proj_solid_layer", 0)]:
			r = copy.deepcopy(self.report); r["metrics"]["live"]["draws"][key] = value
			with self.subTest(key=key): self.reject(report=r)

	def test_all_draw_counters_reject_invalid_numeric_types(self):
		for key in payload.DRAW_KEYS:
			for value in (-1, True, 930.0, "930", None, float("nan"), float("inf"), 10**400):
				r = copy.deepcopy(self.report); r["metrics"]["live"]["draws"][key] = value
				with self.subTest(key=key, value=value): self.reject(report=r)

	def test_each_expected_error_block_line_is_mandatory(self):
		for block in payload.ERROR_BLOCKS:
			for line in block:
				with self.subTest(line=line): self.reject(log=self.log.replace(line + "\n", "", 1))

	def test_backtrace_source_and_line_and_failure_label_are_exact(self):
		for before, after in [("render_v2.gd:39", "render_v2.gd:40"), ("render_v2.gd:252", "render_v2.gd:254"),
			("render_v2.gd:254", "render_v2.gd:252"), ("res://tests/render_v2.gd", "res://tests/another.gd"),
			("variant_utility.cpp:1023", "variant_utility.cpp:1024"), ("ERROR: FAIL the demo battle shows OVERDRIVE", "ERROR: FAIL another failure")]:
			with self.subTest(before=before): self.reject(log=self.log.replace(before, after, 1))

	def test_error_block_order_or_duplication_is_rejected(self):
		b0 = "\n".join(payload.ERROR_BLOCKS[0]); b1 = "\n".join(payload.ERROR_BLOCKS[1])
		self.reject(log=self.log.replace(b0 + "\n" + b1, b1 + "\n" + b0, 1))
		self.reject(log=self.log.replace(b0, b0 + "\n" + b0, 1))

	def test_extra_output_at_any_location_is_rejected(self):
		for extra in ["ERROR: unrelated", "WARNING: unrelated", "SCRIPT ERROR: invalid", "Parse Error: invalid", "FAIL additional", "PASS unrelated", "OpenGL API 3.3.0", "unknown"]:
			for text in [extra + "\n" + self.log, self.log + extra + "\n", self.log.replace(self.summary_line, extra + "\n" + self.summary_line)]:
				with self.subTest(extra=extra): self.reject(log=text)

	def test_exactly_one_engine_header_required(self):
		self.reject(log=self.log.replace(payload.ENGINE_HEADER, "", 1))
		self.reject(log=payload.ENGINE_HEADER + "\n" + self.log)
		self.reject(log=self.log.replace("v4.7.2.stable.official.ed1daf0bf", "v4.7.2.stable.official.other", 1))

	def test_single_final_anchored_summary_required(self):
		for log in [self.log.replace(self.summary_line, ""), self.log + self.summary_line + "\n",
			self.log.replace(self.summary_line, " " + self.summary_line),
			self.log.replace(self.summary_line, "prefix " + self.summary_line),
			self.log.replace(self.summary_line, self.summary_line.replace("RENDER_V2 ", "RENDER_V3 ")),
			self.summary_line + "\n" + self.log.replace(self.summary_line, "")]:
			self.reject(log=log)

	def test_duplicate_json_keys_and_trailing_json_rejected(self):
		for before, after in [('"passed":190', '"passed":190,"passed":190'), ('"ticks":1861', '"ticks":1861,"ticks":1861'), ('"shade":5', '"shade":5,"shade":5')]:
			changed = self.log.replace(before, after, 1)
			self.assertNotEqual(changed, self.log); self.reject(log=changed)
		self.reject(log=self.log.replace(self.summary_line, self.summary_line + " {}"))

	def test_nonfinite_json_overflow_and_malformed_json_rejected(self):
		for value in ["NaN", "Infinity", "-Infinity", "1e9999", "null", "true"]:
			self.reject(log=self.log.replace('"unit_layer":930', '"unit_layer":' + value, 1))
		self.reject(log=self.log.replace(self.summary_line, payload.SUMMARY_PREFIX + "{"))

	def test_lf_crlf_and_blank_lines_allowed_without_other_control_lines(self):
		self.invoke(log=self.log.replace("\n", "\r\n"))
		self.invoke(log="\n \t\n" + self.log.replace("\n", "\n\n") + "\n \t\n")
		for character in ["\x00", "\x0b", "\x0c", "\r", "\u2028"]:
			with self.subTest(character=repr(character)): self.reject(log=self.log + character)

	def test_utf8_and_file_errors_are_value_errors(self):
		with self.assertRaises(ValueError): payload.validate(MemoryFile(b"\xff"), assertion_json)
		with self.assertRaises(ValueError): payload.validate(MemoryFile(b"\xef\xbb\xbf" + self.log_raw), assertion_json)
		class Missing:
			def read_bytes(self): raise FileNotFoundError("synthetic missing")
		with self.assertRaises(ValueError): payload.validate(Missing(), assertion_json)

	def test_changing_or_disappearing_input_is_rejected(self):
		class Changing(MemoryFile):
			calls = 0
			def read_bytes(self):
				self.calls += 1
				return self.raw if self.calls == 1 else self.raw + b"\n"
		class Disappearing(MemoryFile):
			calls = 0
			def read_bytes(self):
				self.calls += 1
				if self.calls > 1: raise FileNotFoundError("synthetic disappeared")
				return self.raw
		for kind in (Changing, Disappearing):
			with self.assertRaises(ValueError): payload.validate(kind(self.log_raw), assertion_json)


if __name__ == "__main__":
	unittest.main()
