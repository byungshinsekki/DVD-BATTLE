"""Resumable V2 validation and exports. Phase 1 uses --dry-run only.

Final starts require a completely clean tree BEFORE this runner writes reports.
An interrupted final run is resumed only with --resume-final, the same run ID,
identical source/tool/engine/template/baseline hashes, and only untracked files
under that run's own report directory. Tracked changes are never exempted.
Dry runs record dirty input honestly. --install-helper only installs the bundled
QA wrapper; it does not run Godot or inspect any real user profile.
"""
from __future__ import annotations
import argparse
from collections import Counter
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import zipfile
import config
import preview_diagnostic
import render_diagnostic
import draft26_diagnostic
from common import PROBLEMS, atomic_bytes, atomic_copy, copy_project, digest, discover_tests, git, guard_output, import_project, legacy_inventory, profile_inventory, require, run, runtime_hashes, safe_write_path, sha, verification_hashes, within, write_json
from common import process_pool
from audit import audit_all
from package import package_all, source_paths, verify_and_extract
from validation import write_validation

PROTOCOL = 7
CONTINUABLE_SUITE = "map_connectivity_v2"
CONTINUE_POLICY = "dry_run_completed_map_connectivity_assertions_only_v1"
CONNECTIVITY_SAMPLES = set("classic ruined_gate thorn_circuit furnace_basin wind_temple dimensional_lattice crossroads moon_garden twin_foundry gale_corridor rift_harbor bastion_ring control_crossroads control_citadel control_waterway ruined_gate/r28 crossroads/r28 thorn_circuit/r28".split()) | {
    f"{arena}/seed={seed}" for arena in ("dm_forest_village", "dm_ruined_town", "dm_open_steppe") for seed in (1, 77, 20261001)}
SCREENSHOTS = ("home", "setup", "draft", "deathmatch", "codex_chars", "codex_arenas", "codex_items", "codex_glossary", "settings", "battle_3v3", "battle_dm8", "battle_dm_rank", "battle_control")
REQUIRED_HEADLESS = set("ai_audit_152 ai_core_153 ai_gimmicks_153 ai_heroes_153 ai_information_122 codex_data_151 conquest_15 control_ai_13 control_information_13 control_maps_13 control_rules_13 deathmatch_15 draft_14 draft_audit_14 draft_isolation_14 environment_152 environment_153 map_battles_152 maps_152 maps_153 mechanics_122 mode_ai_153 preview_isolation_14 render_153 skill_preview_14 backlog_v2 map_connectivity_v2 fonts_v2 calibration_v2".split())
REQUIRED_RENDERED = set("codex_ui_151 control_ui_13 deathmatch_ui_15 developer_152 preview_ui_14".split())
STRUCTURED_HEADLESS = {"backlog_v2", "fonts_v2", "calibration_v2"}
KNOWN_DRAFT_SUITE = "draft_14"
KNOWN_DRAFT_POLICY = "dry_run_completed_draft14_gap_fixture_failure_only_v1"
KNOWN_DRAFT_FIXTURE_SHA = "e66076f6c2a8fa3a4ef0e7dd5989dc33994eed7acfb168b70246dda264d2350b"
KNOWN_DRAFT_FAILURES = (
    "final-pick actual-engine phase starts",
    "actual-engine phase can be cancelled",
    "two candidates with mirrored sides obey fixed tick budget",
    "rollout candidate side coverage is balanced",
    "chosen finalist received both engine side trials",
    "only comparable finalists appear as engine alternatives",
)
KNOWN_DRAFT_LABELS = tuple(f"{mode} {size}v{size}" for mode in ("elimination", "control") for size in (1, 3, 5)) + (
    "1ms cooperative static search", "full-composition horizon", "actual-engine bounded rollout",
    "control5v5 final pick default 8ms slices")
KNOWN_DRAFT_LEGAL = set("aphrodite archer baseball blood_mage dimensionalist engineer fisherman hermes hive_mind joker mage metatron nitro pirate plague_doctor politician sniper swordsman torturer werewolf world_tree".split())


def file_evidence(paths):
    result = {}
    for item in paths:
        path = Path(item).resolve()
        require(path.is_file(), "Required evidence is missing: " + str(path))
        result[str(path)] = sha(path)
    return result


def process_evidence(value):
    paths = []
    def visit(item):
        if isinstance(item, dict):
            if "log" in item and "code" in item:
                log = Path(item["log"])
                paths.extend([log, log.with_suffix(log.suffix + ".process.json")])
            for child in item.values():
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)
    visit(value)
    return file_evidence(paths)


def dirty_entries(status):
    entries, records = [], iter(status.split("\0"))
    for record in records:
        if not record:
            continue
        require(len(record) > 3 and record[2] == " ", "Malformed Git porcelain record")
        code, name = record[:2], record[3:]
        entries.append({"code": code, "path": name})
        if "R" in code or "C" in code:
            old = next(records, "")
            require(bool(old), "Missing Git rename source")
            entries.append({"code": code, "path": old})
    return entries


def final_clean_policy(entries, state, resume, report_prefix):
    if state is None:
        require(not resume, "--resume-final requires an existing final run")
        require(not entries, "A new final run requires a completely clean Git tree")
        return "initial_full_clean"
    require(resume, "Existing final run: use --resume-final explicitly or choose a new clean run ID")
    require(state.get("initial_clean") is True, "Final resume requires recorded initial full-clean provenance")
    require(all(row["code"] == "??" and row["path"].startswith(report_prefix + "/") for row in entries),
            "Final resume permits only this run's untracked reports; tracked or unrelated changes are forbidden")
    return "explicit_resume_own_untracked_reports_only"


def ensure_helper(project):
    """Install tracked templates into ignored zz_work, preserving old bytes first."""
    project = Path(project).resolve()
    bundle = Path(__file__).resolve().parent
    result = {}
    # A source ZIP does not carry .git/info/exclude. Keep generated helpers and
    # QA logs private if that source is later placed in a fresh Git checkout.
    for relative, payload in (("zz_work/.gitignore", b"*\n"), ("zz_work/.gdignore", b"")):
        marker = safe_write_path(project / relative)
        if not marker.exists():
            atomic_bytes(marker, payload)
    for source_name, target_name in (("qa_helper.ps1", "gd.ps1"), ("qa_process.py", "gd_process.py")):
        source = bundle / source_name
        target = safe_write_path(project / "zz_work/tools" / target_name)
        require(within(target, project / "zz_work/tools"), "Unsafe helper target")
        require(source.is_file(), "Bundled QA template is missing: " + source_name)
        expected = sha(source)
        backup = None
        if target.exists() and sha(target) != expected:
            previous = sha(target)
            backup = safe_write_path(project / "zz_work/tool_backups" / (target_name + "." + previous + ".bak"))
            if backup.exists():
                require(sha(backup) == previous, "Existing helper backup differs from the original")
            else:
                atomic_copy(target, backup)
            require(sha(backup) == previous, "Helper backup verification failed")
        if not target.exists() or sha(target) != expected:
            atomic_copy(source, target)
        require(sha(target) == expected, "QA helper installation hash mismatch")
        result[target_name] = dict(path=str(target), template=str(source), sha256=expected, backup=str(backup) if backup else None)
    return result


def png_evidence(path):
    path = Path(path)
    require(path.is_file() and path.stat().st_size > 1000, "Missing/truncated screenshot: " + str(path))
    with path.open("rb") as stream:
        header = stream.read(24)
    require(header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", "Invalid screenshot: " + str(path))
    width, height = struct.unpack(">II", header[16:24])
    require((width, height) == (1600, 900), "Wrong screenshot dimensions: " + str(path))
    return dict(path=str(path), width=width, height=height, sha256=sha(path))


def ui_report(path, suite):
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    require(isinstance(value, dict) and value.get("suite", suite) == suite, "Invalid UI report identity")
    require(value.get("status", "PASS") == "PASS", "UI report status failed")
    require("failed" in value or "failures" in value, "UI report lacks a failure count")
    for key in ("failed", "failures"):
        if key in value:
            count = len(value[key]) if isinstance(value[key], list) else value[key]
            require(type(count) is int and count == 0, "UI report has failures")
    require(type(value.get("passed")) is int and value["passed"] > 0, "UI report has no passing assertions")
    checks = value.get("checks")
    require(isinstance(checks, list) and len(checks) == value["passed"] and all(row.get("passed") is True for row in checks),
            "UI check rows do not agree with assertion counts")
    return value


def assertion_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate assertion JSON key: " + key)
            result[key] = value
        return result
    def invalid_constant(value):
        raise ValueError("Non-finite assertion JSON constant: " + value)
    def finite_float(value):
        parsed = float(value)
        require(math.isfinite(parsed), "Non-finite assertion JSON number")
        return parsed
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid_constant, parse_float=finite_float)


def headless_assertion_report(path, suite, process):
    """Validate the exact current producer contracts, including its stdout."""
    require(suite in STRUCTURED_HEADLESS, "Unknown structured headless suite")
    require(process.get("status") == "PASS" and type(process.get("code")) is int and process["code"] == 0
            and process.get("timeout") is False and not process.get("problems")
            and not process.get("cleanup_errors") and not process.get("cancelled")
            and not process.get("exception"), "Headless process did not complete successfully")
    value = assertion_json(Path(path).read_text(encoding="utf-8"))
    require(isinstance(value, dict), "Assertion report must be an object")
    require(value.get("status") == "PASS" and value.get("failed") == []
            and type(value.get("passed")) is int and value["passed"] > 0,
            "Headless assertion report is incomplete or failed")
    lines = Path(process["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
    require(not any(PROBLEMS.search(line) for line in lines), "Headless log contains engine errors")
    label = suite.upper()
    summaries = [line.strip() for line in lines if line.strip().startswith(label + " ")]
    if suite == "backlog_v2":
        require(set(value) == {"suite", "status", "passed", "failed", "metrics"}
                and value["suite"] == suite and isinstance(value["metrics"], dict) and value["metrics"],
                "Incomplete backlog report schema")
        require(summaries == [f"BACKLOG_V2 PASS passed={value['passed']} failed=0"],
                "Backlog stdout/report mismatch")
    elif suite == "fonts_v2":
        require(set(value) == {"suite", "status", "passed", "failed", "unique_codepoints", "faces",
                              "coverage", "system_fallback", "resource_fallbacks"}
                and value["suite"] == suite, "Incomplete fonts report schema")
        expected_faces = {"res://assets/fonts/glyph_serif.otf", "res://assets/fonts/ui_black.otf", "res://assets/fonts/symbols.ttf"}
        faces, coverage = value["faces"], value["coverage"]
        require(isinstance(faces, list) and all(isinstance(face, str) for face in faces)
                and len(faces) == 3 and set(faces) == expected_faces
                and value["system_fallback"] is False and value["resource_fallbacks"] is False,
                "Fonts report must use all three raw bundled faces without fallback")
        require(type(value["unique_codepoints"]) is int and value["unique_codepoints"] > 0
                and isinstance(coverage, dict) and len(coverage) >= value["unique_codepoints"]
                and all(isinstance(key, str) and key and isinstance(items, list) and items
                        and all(isinstance(item, str) and item in expected_faces for item in items)
                        for key, items in coverage.items()), "Incomplete raw-font coverage evidence")
        require(summaries == [f"FONTS_V2 PASS passed={value['passed']} failed=0 unique_codepoints={value['unique_codepoints']}"],
                "Fonts stdout/report mismatch")
    else:
        # This producer intentionally has no suite field; identify it using its
        # exact schema and CALIBRATION_V2 JSON stdout, never a guessed default.
        require(set(value) == {"status", "passed", "failed", "calibration", "fresh", "current_sim_sha",
                              "stored_sim_sha", "freshness_policy"}, "Incomplete calibration report schema")
        nested = value["calibration"]
        require(isinstance(nested, dict) and set(nested) == {"status", "passed", "failed", "games", "duel_pairs", "roster_count"}
                and nested["status"] == "PASS" and nested["failed"] == []
                and type(nested["passed"]) is int and 0 < nested["passed"] < value["passed"],
                "Calibration schema assertions are incomplete or failed")
        require(all(type(nested[key]) is int and nested[key] > 0 for key in ("games", "duel_pairs", "roster_count")),
                "Invalid calibration sample counts")
        n = nested["roster_count"]
        require(nested["duel_pairs"] == n * (n - 1) // 2 and nested["games"] == nested["duel_pairs"] * 12 + 1800,
                "Calibration game/pair counts contradict the roster")
        require(all(isinstance(value[key], str) and re.fullmatch(r"[0-9a-f]{64}", value[key])
                    for key in ("current_sim_sha", "stored_sim_sha"))
                and type(value["fresh"]) is bool
                and value["fresh"] == (value["current_sim_sha"] == value["stored_sim_sha"])
                and value["freshness_policy"] == "warn in Phase 1; final release rejects stale data",
                "Calibration freshness evidence is contradictory")
        warnings = [line for line in summaries if line.startswith("CALIBRATION_V2 WARN ")]
        expected_warning = [] if value["fresh"] else [f"CALIBRATION_V2 WARN stale calibration: stored={value['stored_sim_sha']} current={value['current_sim_sha']}"]
        payloads = [line[len(label) + 1:] for line in summaries if not line.startswith("CALIBRATION_V2 WARN ")]
        require(warnings == expected_warning and len(payloads) == 1 and assertion_json(payloads[0]) == value,
                "Calibration stdout/report mismatch")
    return value


def test_failure_policy(options):
    enabled = bool(getattr(options, "continue_on_test_failure", False))
    require(not enabled or (not options.final and bool(getattr(options, "dry_run", False))),
            "--continue-on-test-failure is allowed only with --dry-run; final never permits this option")
    return dict(enabled=enabled, policy=CONTINUE_POLICY, allowed_suites=[CONTINUABLE_SUITE] if enabled else [],
                required_assertion_count=35, required_sample_count=27, infrastructure_errors_allowed=0, changes_test_acceptance=False)


def known_draft_failure_policy(options):
    enabled = getattr(options, "continue_on_known_draft_failure", False) is True
    require(not enabled or (not options.final and bool(getattr(options, "dry_run", False))),
            "--continue-on-known-draft-failure is allowed only with --dry-run; final never permits this option")
    return dict(enabled=enabled, policy=KNOWN_DRAFT_POLICY,
                allowed_suites=[KNOWN_DRAFT_SUITE] if enabled else [], fixture_sha256=KNOWN_DRAFT_FIXTURE_SHA,
                required_assertion_count=237, required_passed=231, required_failures=list(KNOWN_DRAFT_FAILURES),
                infrastructure_errors_allowed=0, changes_test_acceptance=False)


def prepare_draft_report(qa, report):
    """Clear the producer's fixed path before launch; never pass an ignored --report."""
    qa, report = Path(qa).resolve(), safe_write_path(report)
    source = qa / "tests/draft_14.gd"
    require(source.is_file(), "Missing draft fixture source")
    fixed = safe_write_path(qa / "reports/draft_14.json")
    require(within(fixed, qa), "Draft report escaped QA")
    atomic_bytes(fixed, b"")
    atomic_bytes(report, b"")
    receipt = dict(schema=1, status="CLEARED", qa=str(qa), producer_report=str(fixed),
                   captured_report=str(report), cleared_sha256=sha(fixed), cleared_bytes=fixed.stat().st_size,
                   fixture_source=str(source), fixture_before_sha256=sha(source))
    write_json(report.with_suffix(".capture.json"), receipt)
    return receipt


def capture_draft_report(receipt):
    """Freeze bytes immediately; later QA rebuilds must not invalidate evidence."""
    require(receipt.get("status") == "CLEARED", "Draft producer was not cleared before launch")
    fixed, report = Path(receipt["producer_report"]), Path(receipt["captured_report"])
    require(fixed.is_file(), "Draft producer did not leave its fixed report")
    atomic_copy(fixed, report)
    receipt = dict(receipt, status="CAPTURED", captured_sha256=sha(report), captured_bytes=report.stat().st_size,
                   producer_sha256=sha(fixed), fixture_after_sha256=sha(Path(receipt["fixture_source"])))
    write_json(report.with_suffix(".capture.json"), receipt)
    return receipt


def draft_report_evidence(process, report_path, qa):
    """Check launch, immutable capture and persisted process evidence before parsing."""
    report_path, qa = Path(report_path).resolve(), Path(qa).resolve()
    require(process.get("suite") == KNOWN_DRAFT_SUITE, "Draft evidence belongs to another suite")
    command = process.get("command", [])
    require(isinstance(command, list) and all(isinstance(arg, str) for arg in command), "Invalid draft command")
    require(command.count("--headless") == 1 and command.count("--path") == 1 and command.count("--script") == 1,
            "Draft launch is missing/duplicating required arguments")
    require(command.index("--path") + 1 < len(command) and Path(command[command.index("--path") + 1]).resolve() == qa
            and command.index("--script") + 1 < len(command) and command[command.index("--script") + 1] == "res://tests/draft_14.gd"
            and len(command) == 6 and not any(arg.startswith("--report=") for arg in command), "Unexpected draft launch or QA path")
    require(type(process.get("pid")) is int and process["pid"] > 0
            and process.get("timeout") is False and process.get("cleanup_errors") == []
            and process.get("cancelled") is False and process.get("interrupted") is False
            and process.get("exception", "missing") is None and process.get("termination", "missing") is None,
            "Draft process contains timeout/cancellation/infrastructure errors or incomplete lifecycle evidence")
    log = Path(process["log"])
    persisted_path = log.with_suffix(log.suffix + ".process.json")
    persisted = assertion_json(persisted_path.read_text(encoding="utf-8"))
    for key in ("code", "timeout", "status", "pid", "command", "log", "problems", "cleanup_errors", "cancelled", "interrupted", "exception", "termination"):
        require(key in process and persisted.get(key, object()) == process[key], "Persisted draft process disagrees: " + key)
    receipt_path = report_path.with_suffix(".capture.json")
    receipt = assertion_json(receipt_path.read_text(encoding="utf-8"))
    require(isinstance(receipt, dict) and receipt.get("schema") == 1 and receipt.get("status") == "CAPTURED"
            and receipt.get("qa") == str(qa) and receipt.get("producer_report") == str(qa / "reports/draft_14.json")
            and receipt.get("captured_report") == str(report_path)
            and receipt.get("fixture_source") == str(qa / "tests/draft_14.gd")
            and receipt.get("cleared_bytes") == 0 and type(receipt.get("cleared_bytes")) is int
            and receipt.get("cleared_sha256") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            and receipt.get("fixture_before_sha256") == receipt.get("fixture_after_sha256")
            and isinstance(receipt.get("fixture_after_sha256"), str)
            and re.fullmatch(r"[0-9a-f]{64}", receipt["fixture_after_sha256"])
            and receipt.get("captured_sha256") == sha(report_path) == receipt.get("producer_sha256")
            and type(receipt.get("captured_bytes")) is int and receipt["captured_bytes"] == report_path.stat().st_size > 0,
            "Draft report lacks fresh complete capture/source evidence")
    data = assertion_json(report_path.read_text(encoding="utf-8"))
    require(isinstance(data, dict) and set(data) == {"status", "passed", "failures", "measurements"}
            and type(data.get("passed")) is int and data["passed"] > 0 and isinstance(data.get("failures"), list)
            and isinstance(data.get("measurements"), list) and data["measurements"], "Incomplete draft report")
    lines = log.read_text(encoding="utf-8", errors="strict").splitlines()
    summaries = [line for line in lines if line.startswith("DRAFT 1.4 ")]
    require(summaries == [f"DRAFT 1.4 {data['status']} passed={data['passed']} failures={len(data['failures'])}"],
            "Draft stdout/report final counts disagree")
    return data, lines, receipt


def complete_known_draft_measurements(measured):
    """Require all producer payloads, not just labels; do not pin picks or timings."""
    require(isinstance(measured, list) and all(isinstance(row, dict) for row in measured)
            and tuple(row.get("label") for row in measured) == KNOWN_DRAFT_LABELS,
            "Missing/changed completed draft measurement coverage")
    roster = KNOWN_DRAFT_LEGAL | {"giant"}
    def number(value, minimum=None):
        return type(value) in (int, float) and math.isfinite(value) and (minimum is None or value >= minimum)
    def integer(value, minimum=0):
        return type(value) is int and value >= minimum
    def search_shape(search):
        counts = {"nodes", "evals", "cache_misses", "depth", "completed_depth", "target_depth", "candidates", "covered_candidates", "budget"}
        flags = {"forecast_complete", "search_complete"}
        nested = {"policy_completion", "per_candidate_evals", "per_candidate_budget", "opponent_model", "rollout"}
        require(isinstance(search, dict) and set(search) == counts | flags | nested
                and all(integer(search[key]) for key in counts) and all(type(search[key]) is bool for key in flags),
                "Missing/malformed complete draft search metrics")
        require(search["budget"] == 45000 and 0 < search["candidates"] == search["covered_candidates"]
                and search["forecast_complete"] and 0 < search["completed_depth"] <= search["target_depth"],
                "Incomplete draft candidate/depth coverage")
        quotas, evaluations = search["per_candidate_budget"], search["per_candidate_evals"]
        require(isinstance(quotas, dict) and isinstance(evaluations, dict) and set(quotas) == set(evaluations)
                and len(quotas) == search["candidates"] and set(quotas) <= roster
                and all(integer(quotas[key], 1) and integer(evaluations[key]) and evaluations[key] <= quotas[key] for key in quotas)
                and sum(quotas.values()) == search["budget"] and sum(evaluations.values()) == search["evals"],
                "Incomplete draft per-candidate budget evidence")
        policy = search["policy_completion"]
        require(isinstance(policy, dict) and set(policy) == {"enabled", "completed_candidates", "evals", "leaves", "prefix_fallback", "policy"}
                and policy["enabled"] is True and policy["prefix_fallback"] is False and policy["policy"] == "public_legal_greedy"
                and all(integer(policy[key]) for key in ("completed_candidates", "evals", "leaves"))
                and policy["completed_candidates"] == search["candidates"], "Missing draft completion policy evidence")
        model = search["opponent_model"]
        require(isinstance(model, dict) and set(model) == {"worst_weight", "expected_weight", "history_prior_max", "history_samples"}
                and all(number(value, 0) for value in model.values())
                and math.isclose(model["worst_weight"] + model["expected_weight"], 1.0, abs_tol=1e-12), "Malformed draft opponent model")
        rollout = search["rollout"]
        numeric = {"tick_budget", "ticks", "games", "horizon_ticks", "min_horizon_ticks", "sides_per_finalist"}
        require(isinstance(rollout, dict) and set(rollout) == numeric | {"enabled", "final_pick_only", "finalists_only", "weight", "gap_gate", "rows", "skipped"}
                and all(integer(rollout[key]) for key in numeric)
                and all(type(rollout[key]) is bool for key in ("enabled", "final_pick_only", "finalists_only"))
                and all(number(rollout[key], 0) for key in ("weight", "gap_gate"))
                and rollout["skipped"] in ("", "gap", "horizon") and isinstance(rollout["rows"], list)
                and rollout["games"] == len(rollout["rows"]) and rollout["ticks"] <= rollout["tick_budget"],
                "Missing/malformed draft rollout evidence")
        for trial in rollout["rows"]:
            require(isinstance(trial, dict) and set(trial) == {"id", "side", "ticks", "seconds", "value", "finished"}
                    and trial["id"] in roster and integer(trial["side"]) and trial["side"] in (0, 1)
                    and integer(trial["ticks"]) and trial["ticks"] <= rollout["horizon_ticks"]
                    and number(trial["seconds"], 0) and number(trial["value"]) and -1 <= trial["value"] <= 1
                    and type(trial["finished"]) is bool, "Incomplete draft engine trial evidence")
        require(sum(trial["ticks"] for trial in rollout["rows"]) == rollout["ticks"], "Draft trial/tick totals disagree")
    for row in measured[:6]:
        require(set(row) == {"label", "id", "milliseconds", "search"} and row["id"] in roster
                and number(row["milliseconds"], 0), "Incomplete draft structure measurement")
        search_shape(row["search"])
    frame = measured[6]
    require(set(frame) == {"label", "largest_slice_ms"} and number(frame["largest_slice_ms"], 0), "Incomplete draft frame measurement")
    horizon = measured[7]
    require(set(horizon) == {"label", "three", "five"}, "Incomplete draft horizon measurement")
    for name, count in (("three", 5), ("five", 9)):
        row = horizon[name]
        require(isinstance(row, dict) and set(row) == {"id", "value", "depth", "forecast"} and row["id"] in roster
                and number(row["value"]) and integer(row["depth"], 1) and isinstance(row["forecast"], list)
                and len(row["forecast"]) == count, "Incomplete full-composition forecast")
        for pick in row["forecast"]:
            require(isinstance(pick, dict) and set(pick) in ({"id", "side"}, {"id", "side", "policy"})
                    and pick["id"] in roster and pick["side"] in ("ai", "user")
                    and ("policy" not in pick or type(pick["policy"]) is bool), "Malformed draft forecast pick")
    require(set(measured[8]) == {"label", "search"}, "Incomplete bounded-rollout measurement")
    search_shape(measured[8]["search"])
    performance = measured[9]
    require(set(performance) == {"label", "id", "largest_slice_ms", "p95_slice_ms", "search", "slice_count", "wall_seconds"}
            and performance["id"] in roster and integer(performance["slice_count"], 1)
            and all(number(performance[key], 0) for key in ("largest_slice_ms", "p95_slice_ms", "wall_seconds")),
            "Incomplete final-pick performance measurement")
    search_shape(performance["search"])


def completed_draft_failure(process, report_path, qa):
    """Allow only the reviewed 231 PASS / six FAIL gap fixture for diagnostics."""
    data, lines, receipt = draft_report_evidence(process, report_path, qa)
    require(process.get("status") == "FAIL" and type(process.get("code")) is int and process["code"] == 1,
            "Known draft failure requires normal exit=1")
    require(receipt["fixture_before_sha256"] == KNOWN_DRAFT_FIXTURE_SHA, "Draft fixture changed; policy requires review")
    require(data["status"] == "FAIL" and data["passed"] == 231 and data["failures"] == list(KNOWN_DRAFT_FAILURES)
            and data["passed"] + len(data["failures"]) == 237, "Not the exact completed known draft assertion failure")
    measured = data["measurements"]
    complete_known_draft_measurements(measured)
    search = measured[8].get("search", {})
    expected = {"budget": 45000, "candidates": 21, "covered_candidates": 21, "evals": 42, "nodes": 21,
                "completed_depth": 1, "target_depth": 1, "search_complete": True, "forecast_complete": True}
    require(isinstance(search, dict) and all(type(search.get(key)) is type(value) and search[key] == value for key, value in expected.items()),
            "Known draft search was incomplete or used different options")
    allocations, evaluations = search.get("per_candidate_budget"), search.get("per_candidate_evals")
    require(isinstance(allocations, dict) and set(allocations) == KNOWN_DRAFT_LEGAL
            and all(type(value) is int and value in (2142, 2143) for value in allocations.values()) and sum(allocations.values()) == 45000
            and isinstance(evaluations, dict) and set(evaluations) == KNOWN_DRAFT_LEGAL
            and all(type(value) is int and value == 2 for value in evaluations.values()), "Draft candidate coverage/budget changed")
    expected_rollout = dict(enabled=True, final_pick_only=True, finalists_only=True, games=0, gap_gate=1.0,
                            horizon_ticks=300, min_horizon_ticks=300, rows=[], sides_per_finalist=2,
                            skipped="gap", tick_budget=1200, ticks=0, weight=0.24)
    rollout = search.get("rollout")
    require(isinstance(rollout, dict) and set(rollout) == set(expected_rollout)
            and all(type(rollout[key]) is type(value) and rollout[key] == value for key, value in expected_rollout.items()),
            "Draft failure is not the reviewed final-pick gap-gate case")
    expected_errors = ["ERROR: " + value for value in KNOWN_DRAFT_FAILURES]
    severity = re.compile(r"SCRIPT ERROR|Parse Error|\bERROR:|\bWARNING:", re.IGNORECASE)
    actual_errors = [line for line in lines if severity.search(line)]
    require(actual_errors == expected_errors and process["problems"] == [line for line in lines if PROBLEMS.search(line)] == expected_errors,
            "Additional/missing draft engine or assertion errors")
    suspicious_failures = [line for line in lines if re.search(r"\bFAIL(?:ED|URE)?\b", line, re.IGNORECASE)]
    require(suspicious_failures == ["DRAFT 1.4 FAIL passed=231 failures=6"], "Unexpected additional draft failure output")
    log, report_path = Path(process["log"]), Path(report_path)
    return dict(classification="completed_known_draft_gap_fixture_failure", acceptance_status="FAIL", suite=KNOWN_DRAFT_SUITE,
                policy=KNOWN_DRAFT_POLICY, passed=data["passed"], failed=data["failures"], assertion_count=237,
                fixture_sha256=receipt["fixture_before_sha256"], rollout=rollout, assertion_error_lines=actual_errors,
                infrastructure_errors=[], infrastructure_error_count=0, report=str(report_path), report_sha256=sha(report_path),
                log=str(log), log_sha256=sha(log), process_report=str(log.with_suffix(log.suffix + ".process.json")),
                process_report_sha256=sha(log.with_suffix(log.suffix + ".process.json")),
                capture_receipt=str(report_path.with_suffix(".capture.json")), capture_receipt_sha256=sha(report_path.with_suffix(".capture.json")))


def completed_connectivity_failure(process, report_path):
    """Recognize one completed assertion failure; never make its status PASS.

    Caller must empty this explicit --report path immediately before this run.
    Persisted process output, fresh JSON and exact assertion ERROR text must agree.
    Any missing/extra warning, engine error, crash or incomplete suite is fatal.
    """
    require(process.get("suite") == CONTINUABLE_SUITE, "Failure continuation is restricted to map_connectivity_v2")
    require(type(process.get("code")) is int and process["code"] == 1 and process.get("timeout") is False,
            "Only a normal exit=1 without timeout can be a completed assertion failure")
    require(process.get("status") == "FAIL", "Expected the original failing process status")
    report_path = Path(report_path).resolve()
    command = process.get("command", [])
    require("--report=" + report_path.as_posix() in command and "res://tests/map_connectivity_v2.gd" in command,
            "Process was not given the expected explicit connectivity report path")
    log = Path(process["log"])
    persisted = json.loads(log.with_suffix(log.suffix + ".process.json").read_text(encoding="utf-8"))
    for key in ("code", "timeout", "status", "pid", "command", "log", "problems"):
        require(key in process and persisted.get(key) == process[key], "Persisted process evidence disagrees: " + key)
    def invalid_constant(value):
        raise ValueError("Nonfinite JSON constant: " + value)
    data = json.loads(report_path.read_text(encoding="utf-8"), parse_constant=invalid_constant)
    require(isinstance(data, dict) and data.get("suite") == CONTINUABLE_SUITE and data.get("status") == "FAIL", "Missing final connectivity FAIL report")
    passed, failed = data.get("passed"), data.get("failed")
    require(type(passed) is int and passed >= 0 and isinstance(failed, list) and failed and
            all(isinstance(value, str) and value and "\n" not in value and "\r" not in value for value in failed), "Invalid final assertion counts/list")
    require(passed + len(failed) == 35, "Incomplete/changed assertion coverage; diagnostic policy requires re-review")
    require(data.get("step") == 8.0 and data.get("radii") == [14, 16, 18, 20, 22, 24], "Connectivity report lacks the complete configured measurement contract")
    measured = data.get("maps")
    require(isinstance(measured, list) and measured and isinstance(data.get("historical_thorn"), list) and
            all(isinstance(issue, str) for issue in data["historical_thorn"]), "Connectivity report is incomplete")
    samples = []
    for row in measured:
        require(isinstance(row, dict) and isinstance(row.get("sample"), str) and row["sample"], "Invalid measured map sample")
        seconds = row.get("seconds")
        require(type(seconds) in (int, float) and math.isfinite(seconds) and seconds >= 0, "Invalid measurement duration")
        require(isinstance(row.get("issues"), list) and all(isinstance(issue, str) for issue in row["issues"]), "Invalid measured issues")
        samples.append(row["sample"])
    require(len(samples) == len(set(samples)) and set(samples) == CONNECTIVITY_SAMPLES, "Missing/duplicate/changed measured map coverage")
    lines = log.read_text(encoding="utf-8", errors="strict").splitlines()
    summaries = [re.fullmatch(r"MAP_CONNECTIVITY_V2 (PASS|FAIL) passed=(\d+) failed=(\d+)", line) for line in lines]
    summaries = [value for value in summaries if value]
    require(len(summaries) == 1 and summaries[0].groups() == ("FAIL", str(passed), str(len(failed))), "Missing/contradictory final connectivity summary")
    sample_lines = [re.fullmatch(r"MAP_CONNECTIVITY_V2 sample=(.+) seconds=([0-9.eE+\-]+) problems=(\d+)", line) for line in lines]
    sample_lines = [value for value in sample_lines if value]
    require([(value.group(1), int(value.group(3))) for value in sample_lines] == [(row["sample"], len(row["issues"])) for row in measured], "Final map measurements disagree with completed log samples")
    expected_errors = Counter("ERROR: MAP_CONNECTIVITY_V2 " + value for value in failed)
    severity = re.compile(r"SCRIPT ERROR|Parse Error|\bERROR:|\bWARNING:", re.IGNORECASE)
    actual_errors = [line for line in lines if severity.search(line)]
    require(Counter(actual_errors) == expected_errors, "Extra/missing engine errors or assertion text mismatch; cannot continue")
    common_problems = [line for line in lines if PROBLEMS.search(line)]
    require(process["problems"] == common_problems and Counter(common_problems) == expected_errors, "Process problem list is incomplete or contradictory")
    return dict(classification="completed_assertion_failure", acceptance_status="FAIL", suite=CONTINUABLE_SUITE,
                passed=passed, failed=failed, assertion_error_lines=actual_errors, infrastructure_errors=[], infrastructure_error_count=0,
                report=str(report_path), report_sha256=sha(report_path), log=str(log), log_sha256=sha(log),
                process_report=str(log.with_suffix(log.suffix + ".process.json")),
                process_report_sha256=sha(log.with_suffix(log.suffix + ".process.json")))


def acceptance_summary(stages):
    failed = [key for key, value in stages.items() if value.get("acceptance_status", value.get("status")) == "FAIL"]
    continued = stages.get("S2", {}).get("continued_test_failures", []) + stages.get("S3", {}).get("continued_ui_test_failures", [])
    all_pass = len(stages) == 12 and all(value.get("status") == "PASS" for value in stages.values())
    return dict(acceptance_status="FAIL" if failed else ("PASS" if all_pass else "UNVERIFIED"),
                failed_acceptance_stages=failed, continued_test_failures=continued,
                release_eligible=all_pass and not failed and not continued)

class Release:
    @property
    def known_draft26_failure_policy(self):
        return draft26_diagnostic.policy(self.options)

    @property
    def known_render_failure_policy(self):
        return render_diagnostic.policy(self.options)

    @property
    def known_preview_failure_policy(self):
        return preview_diagnostic.policy(self.options)

    @property
    def known_draft_failure_policy(self):
        return known_draft_failure_policy(self.options)

    def __init__(self, options):
        self.options = options
        self.test_failure_policy = test_failure_policy(options)
        known_draft_failure_policy(options)
        draft26_diagnostic.policy(options)
        preview_diagnostic.policy(options)
        render_diagnostic.policy(options)
        self.project = config.PROJECT.resolve()
        self.initial_git_status = git(self.project, "status", "--porcelain", "-z", "--untracked-files=all")
        self.initial_git_entries = dirty_entries(self.initial_git_status)
        self.out = guard_output(options.out, options.final)
        self.reports = safe_write_path(self.project / "reports/release_v2" / options.run_id)
        self.logs = self.reports / "logs"
        self.profiles = config.SCRATCH / "release_profiles" / options.run_id
        self.source = dict(head=git(self.project, "rev-parse", "HEAD"), runtime=runtime_hashes(self.project), verification=verification_hashes(self.project),
                           package_files={name: sha(path) for path, name in source_paths(self.project)})
        self.source["input_sha256"] = digest(self.source)
        self.binary_inputs = self.binary_hashes()
        self.tool_inputs = self.tool_hashes()
        self.identity = dict(protocol=PROTOCOL, input_sha256=self.source["input_sha256"], out=str(self.out), final=options.final,
                             telemetry=options.with_telemetry, binaries=self.binary_inputs, tools=self.tool_inputs,
                             test_failure_policy=self.test_failure_policy,
                             known_draft_failure_policy=self.known_draft_failure_policy,
                             known_draft26_failure_policy=self.known_draft26_failure_policy,
                             known_preview_failure_policy=self.known_preview_failure_policy,
                             known_render_failure_policy=self.known_render_failure_policy,
                             baseline=sha(options.baseline_summary) if options.baseline_summary else None)
        self.state_path = self.reports / "run_state.json"
        existing = json.loads(self.state_path.read_text(encoding="utf-8")) if self.state_path.exists() else None
        self.clean_policy = final_clean_policy(self.initial_git_entries, existing, options.resume_final, self.reports.relative_to(self.project).as_posix()) if options.final else "dry_run_records_all_changes"
        if existing is not None:
            self.state = existing
            require(self.state["identity"] == self.identity, "Resume input changed; use a new --run-id")
        else:
            self.state = dict(identity=self.identity, source=self.source, stages={}, complete=False,
                              initial_clean=not self.initial_git_entries, initial_git_entries=self.initial_git_entries)
        self.original_appdata = Path(os.environ["APPDATA"])
        self.profile_names = list(config.PROFILE_NAMES)
        custom = re.search(r'config/custom_user_dir_name="([^"]+)"', (self.project / "project.godot").read_text(encoding="utf-8"))
        if custom and custom.group(1) not in self.profile_names:
            self.profile_names.append(custom.group(1))
        observed = dict(profiles=profile_inventory(self.original_appdata, self.profile_names), legacy=legacy_inventory(self.project.parent, include_release=not options.final))
        if existing is not None:
            protected = self.state.get("protected_before")
            require(isinstance(protected, dict), "Resume lacks original protected-path evidence")
            require(observed["profiles"] == protected["profiles"], "Real profile changed since this run started; original baseline is preserved")
            require(self.legacy_equal(observed["legacy"], protected["legacy"]), "Protected legacy paths changed since this run started")
        else:
            self.state["protected_before"] = observed
        self.profile_before = self.state["protected_before"]["profiles"]
        self.legacy_before = self.state["protected_before"]["legacy"]
        self.out.mkdir(parents=True, exist_ok=True)
        self.logs.mkdir(parents=True, exist_ok=True)
        self.state["complete"] = False
        self.state["execution_complete"] = False
        self.state["release_eligible"] = False
        self.state["acceptance_status"] = "UNVERIFIED"
        write_json(self.state_path, self.state)

    def binary_hashes(self):
        gui = config.GODOT.with_name(config.GODOT.name.replace("_console.exe", ".exe"))
        powershell = shutil.which("powershell")
        require(powershell, "Windows PowerShell is required for the QA helper")
        # Windows App Execution Aliases are launch redirects, not readable PE files.
        # Bind the helper to this exact interpreter, whose bytes are hashed here.
        return file_evidence([config.GODOT, gui, sys.executable, powershell, *config.TEMPLATES.values()])

    def tool_hashes(self):
        return file_evidence(p for p in Path(__file__).parent.iterdir() if p.suffix in (".py", ".ps1"))

    def legacy_equal(self, current, original):
        # Creating the specifically authorized final output is expected only in final mode.
        if self.options.final:
            return {k:v for k,v in current.items() if k != config.RELEASE.name} == {k:v for k,v in original.items() if k != config.RELEASE.name}
        return current == original

    def process(self, args, name, **kwargs):
        cwd = kwargs.pop("cwd", self.project)
        return run(args, self.logs / (name + ".log"), self.profiles / name, cwd=cwd, **kwargs)

    def godot(self, args, name, **kwargs):
        return self.process([config.GODOT, *args], name, **kwargs)

    def unchanged(self):
        require(git(self.project, "rev-parse", "HEAD") == self.source["head"], "Git HEAD changed during validation")
        require(runtime_hashes(self.project) == self.source["runtime"], "Runtime sources changed during validation")
        require(verification_hashes(self.project) == self.source["verification"], "Tests/tools changed during validation")
        require({name: sha(path) for path, name in source_paths(self.project)} == self.source["package_files"], "Packaged source files changed during validation")
        require(self.binary_hashes() == self.binary_inputs, "Engine/template/Python binary changed during validation")
        require(self.tool_hashes() == self.tool_inputs, "Release runner or helper template changed during validation")
        require((sha(self.options.baseline_summary) if self.options.baseline_summary else None) == self.identity["baseline"], "Baseline evidence changed during validation")

    def module(self, name, path):
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[name] = mod
        spec.loader.exec_module(mod)
        return mod

    def freshness(self, tag):
        package = self.project / "tools/calibration_v2"
        name = "release_calibration_" + self.source["input_sha256"][:16]
        if name not in sys.modules:
            spec = importlib.util.spec_from_file_location(name, package / "__init__.py", submodule_search_locations=[str(package)])
            require(spec is not None and spec.loader is not None, "Cannot load calibration package")
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            spec.loader.exec_module(module)
        module = importlib.import_module(name + ".sim_sha")
        out = self.reports / "fingerprint" / tag
        result = module.compute(self.project, config.GODOT, out, timeout=900)
        require(re.fullmatch(r"[0-9a-f]{64}", result.get("sim_sha", "")) is not None, "Invalid current SIM_SHA")
        write_json(out / "sim_sha.json", result)
        result["output_hashes"] = file_evidence(p for p in out.rglob("*") if p.is_file() and "profiles" not in p.relative_to(out).parts)
        return result

    def stage(self, key, function, always=False):
        self.unchanged()
        previous = self.state["stages"].get(key)
        allowed = ("PASS",) if self.options.final else ("PASS", "WARN", "SKIP")
        dependency_sha = digest({k:v.get("evidence_sha256") for k,v in self.state["stages"].items() if int(k[1:]) < int(key[1:]) and k not in ("S0", "S6", "S8")})
        if not always and previous and previous.get("status") in allowed and previous.get("dependency_sha256") == dependency_sha:
            outputs = previous.get("output_hashes", {})
            if outputs and all(Path(path).is_file() and sha(path) == value for path,value in outputs.items()):
                print(f"RESUME {key} {previous['status']}", flush=True)
                return previous
        print(f"BEGIN {key}", flush=True)
        try:
            result = function()
            result.setdefault("status", "PASS")
            result["output_hashes"] = {**process_evidence(result), **result.get("output_hashes", {})}
            require(all(Path(path).is_file() and sha(path) == value for path, value in result["output_hashes"].items()), "Evidence changed during stage")
            result["dependency_sha256"] = dependency_sha
            # Stable evidence identity excludes the report containing this digest.
            result["evidence_sha256"] = digest(result["output_hashes"])
            self.unchanged()
        except Exception as exc:
            result = dict(status="FAIL", error=str(exc))
            self.state["stages"][key] = result
            self.state.update(acceptance_summary(self.state["stages"]))
            self.state["release_eligible"] = False
            write_json(self.reports / f"{key}.json", result)
            write_json(self.state_path, self.state)
            raise
        report = self.reports / f"{key}.json"
        write_json(report, result)
        result["output_hashes"] = {str(report):sha(report), **result.get("output_hashes", {})}
        self.state["stages"][key] = result
        self.state.update(acceptance_summary(self.state["stages"]))
        self.state["release_eligible"] = False
        write_json(self.state_path, self.state)
        print(f"END {key} {result['status']}", flush=True)
        require(result["status"] != "FAIL", f"{key} failed; measured evidence remains in {report}")
        require(not self.options.final or result["status"] == "PASS", f"Final release requires PASS: {key}")
        return result

    def S0(self):
        version_result = self.godot(["--version"], "engine_version")
        version = Path(version_result["log"]).read_text(encoding="utf-8").strip()
        require(version.startswith(config.ENGINE_VERSION), "Engine version mismatch: " + version)
        status = self.state["initial_git_entries"]
        pg = (self.project / "project.godot").read_text(encoding="utf-8")
        app = (self.project / "scripts/ui/app.gd").read_text(encoding="utf-8")
        versions = dict(project=re.search(r'config/version="([^"]+)"', pg).group(1),
                        app=re.search(r'const VERSION[^=]*=\s*"([^"]+)"', app).group(1))
        warnings = []
        if status:
            warnings.append("작업 트리에 변경이 있습니다: dry-run 출처에 전체 변경 목록을 기록했습니다.")
        if any(value != config.GAME_VERSION for value in versions.values()):
            warnings.append("게임 내 버전이 목표 버전과 다릅니다. Phase 1에서는 버전 문자열을 수정하지 않습니다.")
        require(not self.options.final or not warnings, "Final requires clean git and matching runtime versions")
        fingerprint = self.freshness("S0")
        protected = self.reports / "protected_before.json"
        write_json(protected, {"profiles":self.profile_before,"legacy":self.legacy_before})
        return dict(status="WARN" if warnings else "PASS", warnings=warnings, head=self.source["head"],
                    git_status=status, engine_version=version, versions=versions, source=self.source,
                    current_git_entries=self.initial_git_entries, clean_policy=self.clean_policy, version_process=version_result,
                    test_failure_policy=self.test_failure_policy,
                    known_draft_failure_policy=self.known_draft_failure_policy,
                    known_draft26_failure_policy=self.known_draft26_failure_policy,
                    known_preview_failure_policy=self.known_preview_failure_policy,
                    known_render_failure_policy=self.known_render_failure_policy,
                    templates={k:{"path":str(v),"sha256":sha(v)} for k,v in config.TEMPLATES.items()}, fingerprint=fingerprint,
                    binary_inputs=self.binary_inputs, tool_inputs=self.tool_inputs,
                    output_hashes={**file_evidence([protected]), **fingerprint["output_hashes"]})

    def S1(self):
        return dict(attempts=import_project(self.project, self.logs / "S1", self.profiles / "S1"))

    def S2(self):
        copied = copy_project(self.project, config.QA)
        imported = import_project(config.QA, self.logs / "S2_import", self.profiles / "S2_import")
        suites = discover_tests(config.QA)["headless"]
        require(REQUIRED_HEADLESS <= set(suites), "Required headless tests are missing: " + ", ".join(sorted(REQUIRED_HEADLESS - set(suites))))
        require(not self.known_render_failure_policy["enabled"] or render_diagnostic.SUITE in suites,
                "Known-render continuation requires the render_v2 fixture to be discovered")
        require(not self.known_draft26_failure_policy["enabled"] or draft26_diagnostic.SUITE in suites,
                "Known-draft26 continuation requires the draft_14 fixture to be discovered")
        def check(suite):
            arguments = ["--headless", "--path", config.QA, "--script", f"res://tests/{suite}.gd"]
            report = None
            draft_capture = None
            draft26_capture = None
            render_capture = None
            if suite == CONTINUABLE_SUITE or suite in STRUCTURED_HEADLESS:
                report = self.reports / "headless_assertions" / (suite + ".json")
                # An empty file cannot accidentally certify an old completed run.
                atomic_bytes(report, b"")
                arguments += ["--", "--report=" + report.resolve().as_posix()]
            elif suite == draft26_diagnostic.SUITE and self.known_draft26_failure_policy["enabled"]:
                report = self.reports / "headless_assertions" / (suite + ".json")
                draft26_capture = draft26_diagnostic.prepare(self.project, config.QA, report,
                    self.logs / ("headless_" + suite + ".log"), self.profiles / ("headless_" + suite))
            elif suite == KNOWN_DRAFT_SUITE and self.known_draft_failure_policy["enabled"]:
                report = self.reports / "headless_assertions" / (suite + ".json")
                draft_capture = prepare_draft_report(config.QA, report)
            elif suite == render_diagnostic.SUITE and self.known_render_failure_policy["enabled"]:
                report = self.reports / "headless_assertions" / (suite + ".stdout.json")
                render_capture = render_diagnostic.prepare(self.project, config.QA, report,
                    self.logs / ("headless_" + suite + ".log"), self.profiles / ("headless_" + suite))
            result = self.godot(arguments, "headless_"+suite, check=False)
            result["suite"] = suite
            if report is not None:
                result["assertion_report"] = str(report)
                if draft_capture is not None or draft26_capture is not None or render_capture is not None:
                    result["assertion_capture"] = str(report.with_suffix(".capture.json"))
                try:
                    if draft26_capture is not None:
                        draft26_diagnostic.capture(draft26_capture, result, assertion_json)
                        args = (result, report, self.project, config.QA, self.profiles / ("headless_" + suite), assertion_json)
                        if result["status"] == "PASS":
                            result["assertions"] = draft26_diagnostic.completed_pass(*args)
                        else:
                            result["assertion_failure"] = draft26_diagnostic.completed_failure(*args)
                            result["failure_continuation_allowed"] = True
                    elif render_capture is not None:
                        render_diagnostic.capture(render_capture, result, assertion_json)
                        args = (result, report, self.project, config.QA, self.profiles / ("headless_" + suite), assertion_json)
                        if result["status"] == "PASS":
                            result["assertions"] = render_diagnostic.completed_pass(*args)
                        else:
                            result["assertion_failure"] = render_diagnostic.completed_failure(*args)
                            result["failure_continuation_allowed"] = True
                    elif draft_capture is not None:
                        capture_draft_report(draft_capture)
                        if result["status"] == "PASS":
                            data, lines, _ = draft_report_evidence(result, report, config.QA)
                            require(type(result.get("code")) is int and result["code"] == 0
                                    and data["status"] == "PASS" and data["failures"] == []
                                    and not any(PROBLEMS.search(line) for line in lines), "Incomplete draft PASS evidence")
                            result["assertions"] = data
                        else:
                            result["assertion_failure"] = completed_draft_failure(result, report, config.QA)
                            result["failure_continuation_allowed"] = True
                    elif suite in STRUCTURED_HEADLESS:
                        result["assertions"] = headless_assertion_report(report, suite, result)
                    elif result["status"] == "PASS":
                        data = json.loads(report.read_text(encoding="utf-8"))
                        require(data.get("suite") == suite and data.get("status") == "PASS" and data.get("failed") == [] and
                                type(data.get("passed")) is int and data["passed"] > 0, "Missing complete connectivity PASS report")
                        result["assertions"] = data
                    else:
                        result["assertion_failure"] = completed_connectivity_failure(result, report)
                        result["failure_continuation_allowed"] = self.test_failure_policy["enabled"]
                except (RuntimeError, ValueError, OSError, KeyError, TypeError) as exc:
                    # Preserve all raw failure evidence, including malformed JSON.
                    result["status"] = "FAIL"
                    result["failure_continuation_allowed"] = False
                    result["assertion_evidence_error"] = str(exc)
            return result
        with process_pool(max_workers=self.options.jobs) as pool:
            tests = list(pool.map(check, suites))
        report = self.reports / "headless_tests.json"
        write_json(report, tests)
        # QA sources are reusable only while their bytes still match the tested copy.
        qa_files = [p for p in config.QA.rglob("*") if p.is_file() and not any(part in (".godot", "reports", "__pycache__") for part in p.relative_to(config.QA).parts)]
        failed = [test for test in tests if test["status"] != "PASS"]
        continued = [test["assertion_failure"] for test in failed if test.get("failure_continuation_allowed") is True]
        # Each failure requires its own explicit policy. One flag cannot allow
        # the other suite, and an additional/unknown failure always stops S2.
        can_continue = bool(failed) and len(continued) == len(failed)
        status = "PASS" if not failed else ("WARN" if can_continue else "FAIL")
        assertion_reports = [Path(test["assertion_report"]) for test in tests if "assertion_report" in test]
        capture_reports = [Path(test["assertion_capture"]) for test in tests if "assertion_capture" in test]
        holds = (["C2"] if any(test["suite"] == CONTINUABLE_SUITE for test in failed) else []) + (["C6"] if any(test["suite"] == KNOWN_DRAFT_SUITE for test in failed) else []) + (["render_v2"] if any(test["suite"] == render_diagnostic.SUITE for test in failed) else []) + ["C8"]
        return dict(status=status, acceptance_status="FAIL" if failed else "PASS", copy=copied, imports=imported, discovered=suites, tests=tests,
                    test_failure_policy=self.test_failure_policy, continued_test_failures=continued if can_continue else [],
                    known_draft_failure_policy=self.known_draft_failure_policy,
                    known_draft26_failure_policy=self.known_draft26_failure_policy,
                    known_render_failure_policy=self.known_render_failure_policy,
                    release_eligible=not failed, warnings=["FAIL: " + ", ".join(test["suite"] for test in failed) + "의 완료된 assertion 실패를 보존하고 진단 검증만 계속합니다. " + "/".join(holds) + " 수락은 HOLD이며 정식 배포할 수 없습니다."] if can_continue else [],
                    output_hashes=file_evidence([report, *qa_files, *assertion_reports, *capture_reports]))

    def helper(self, mode, name, extra, known_preview=False):
        require(mode in ("shot", "shots", "uitest"), "Rendered checks must use an approved helper mode")
        installed = ensure_helper(self.project)
        helper = self.project / "zz_work/tools/gd.ps1"
        preview_capture = None
        if known_preview:
            require(self.known_preview_failure_policy["enabled"] and mode == "uitest" and extra == ["-Suite", preview_diagnostic.SUITE],
                    "Preview diagnostic capture requires its own explicit dry-run flag and exact UI suite")
            preview_capture = preview_diagnostic.prepare(self.project, self.reports / "helper_evidence" / name / "preview_capture.json")
        result = self.process(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper,
                               "-PythonExe", sys.executable, "-Mode", mode, "-Root", self.project, *extra], name, **({"check":False} if known_preview else {}))
        result["helper_templates"] = installed
        # The private helper overwrites its logs on subsequent calls. Freeze each
        # call's evidence under this release run before another helper invocation.
        leaf = re.sub(r"[:\\/ ]", "_", str(self.project)).strip("_")[-60:]
        origin = self.project / "zz_work/logs" / leaf
        require(origin.is_dir(), "QA helper did not create its log directory")
        frozen = self.reports / "helper_evidence" / name
        copied = []
        for path in origin.iterdir():
            if path.is_file() and path.suffix in (".log", ".json"):
                target = frozen / path.name
                atomic_copy(path, target)
                copied.append(target)
        require(copied, "No QA helper evidence was captured")
        result["helper_evidence_dir"] = str(frozen)
        if preview_capture is not None:
            preview_diagnostic.capture(preview_capture, frozen, installed)
            result["preview_capture"] = preview_capture["proof_path"]
            copied.append(Path(preview_capture["proof_path"]))
        result["output_hashes"] = file_evidence(copied)
        return result

    def S3(self):
        tests = []
        suites = discover_tests(self.project)["rendered"]
        require(REQUIRED_RENDERED <= set(suites), "Required rendered test scenes are missing")
        files = {}
        for suite in suites:
            diagnostic = suite == preview_diagnostic.SUITE and self.known_preview_failure_policy["enabled"]
            result = self.helper("uitest", "rendered_"+suite, ["-Suite", suite], **({"known_preview":True} if diagnostic else {}))
            result["suite"] = suite
            report = Path(result["helper_evidence_dir"]) / (suite + ".json")
            if diagnostic and result["status"] != "PASS":
                result["assertion_failure"] = preview_diagnostic.completed_failure(result, self.project, assertion_json)
                result["failure_continuation_allowed"] = True
                result["assertions"] = assertion_json(report.read_text(encoding="utf-8"))
            else:
                result["assertions"] = ui_report(report, suite)
            result["report"] = str(report)
            files.update(result["output_hashes"])
            tests.append(result)
        shots = self.out / "screenshots"
        process = self.helper("shots", "screenshots", ["-OutDir", shots, "-Res", "1600x900"])
        screenshots = [png_evidence(shots / (name + ".png")) for name in SCREENSHOTS]
        files.update(process["output_hashes"])
        files.update({s["path"]:s["sha256"] for s in screenshots})
        failed = [test for test in tests if test["status"] != "PASS"]
        continued = [test["assertion_failure"] for test in failed if test.get("failure_continuation_allowed") is True]
        require(not failed or (self.known_preview_failure_policy["enabled"] and len(failed) == len(continued)
                              and all(test["suite"] == preview_diagnostic.SUITE for test in failed)), "Unrecognized UI test failure")
        return dict(status="WARN" if failed else "PASS", acceptance_status="FAIL" if failed else "PASS",
                    tests=tests, screenshots=screenshots, screenshot_process=process, output_hashes=files,
                    continued_ui_test_failures=continued, known_preview_failure_policy=self.known_preview_failure_policy,
                    release_eligible=not failed,
                    warnings=["FAIL: preview_ui_14의 완료된 단일 assertion 실패를 보존하고 진단 검증만 계속합니다. C7/C8 수락은 HOLD이며 정식 배포할 수 없습니다."] if failed else [])

    def S4(self):
        folder = self.reports / "determinism"
        folder.mkdir(exist_ok=True)
        roster_path = folder / "roster.json"
        roster_process = self.godot(["--headless", "--path", config.QA, "--script", "res://tools/balance_runner.gd", "--", "--roster="+roster_path.as_posix()], "determinism_roster")
        ids = sorted(row["id"] for row in json.loads(roster_path.read_text(encoding="utf-8")))
        require(len(ids) >= 10 and len(ids) == len(set(ids)), "Invalid roster for determinism coverage")
        maps = ["classic", "thorn_circuit", "bastion_ring", "rift_harbor", "control_crossroads"]
        cases = []
        for index in range(10):
            size = 5 if index % 5 == 4 else (1 if index < 5 else 3)
            deck = ids[index:] + ids[:index]
            cases.append(dict(id=f"release_cold_{index}", arena_id=maps[index%5], ruleset="control" if index%5 == 4 else "elimination",
                              seed=2009000+index*37, max_time=30.0, blue=deck[:size], red=deck[size:size*2]))
        def replay(item):
            index, rep = item
            case = cases[index]
            path, output = folder / f"case_{index}_{rep}.json", folder / f"result_{index}_{rep}.jsonl"
            write_json(path, [case])
            atomic_bytes(output, b"")
            process = self.godot(["--headless", "--path", config.QA, "--script", "res://tools/balance_runner.gd", "--", "--cases="+path.as_posix(), "--output="+output.as_posix()], f"cold_{index}_{rep}")
            rows = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines() if line]
            require(len(rows) == 1 and rows[0].get("case_id") == case["id"] and rows[0].get("config") == case and not rows[0].get("invariant_error"), "Invalid cold replay")
            require(re.fullmatch(r"[0-9a-f]{64}", rows[0].get("signature", "")) is not None, "Missing/invalid cold replay signature")
            return dict(index=index, repeat=rep, signature=rows[0]["signature"], process=process, raw=str(output))
        with process_pool(max_workers=self.options.jobs) as pool:
            outcomes = list(pool.map(replay, [(i,rep) for i in range(10) for rep in range(2)]))
        results = []
        for index, case in enumerate(cases):
            signatures = [row["signature"] for row in sorted(outcomes, key=lambda r:r["repeat"]) if row["index"] == index]
            results.append(dict(case_id=case["id"], config=case, signatures=signatures, equal=len(signatures) == 2 and len(set(signatures)) == 1))
        return dict(status="PASS" if all(row["equal"] for row in results) else "FAIL", cases=results, processes=outcomes, roster_process=roster_process,
                    output_hashes=file_evidence(folder.glob("*.json*")))

    def S5(self):
        if not self.options.with_telemetry:
            require(not self.options.final, "Final release requires --with-telemetry")
            return dict(status="SKIP", gates=[], heroes=[])
        telemetry_path = self.project / "tools/telemetry_v2"
        # A balance seed set has 2,592 team appearances. Preserve C1's two sets
        # for 22 heroes; 26 heroes require three sets to make n_team >= 200
        # feasible with a 230-appearance planning margin. Never weaken the gate.
        planned_roster_path = self.reports / "telemetry/release_roster.json"
        atomic_bytes(planned_roster_path, b"")
        roster_process = self.godot(["--headless", "--path", self.project, "--script", "res://tools/ai_probe_153.gd", "--", "--roster=" + planned_roster_path.as_posix()], "telemetry_release_roster")
        planned_roster = sorted(row["id"] for row in json.loads(planned_roster_path.read_text(encoding="utf-8")))
        require(planned_roster and len(planned_roster) == len(set(planned_roster)), "Invalid release telemetry planning roster")
        balance_set_count = max(2, math.ceil(len(planned_roster) * 230 / 2592))
        balance_sets = "both" if balance_set_count == 2 else ",".join(str(i) for i in range(1, balance_set_count + 1))
        # The runner owns each Godot timeout. Calling it in-process avoids an
        # arbitrary 900s limit on a many-hour Python orchestration step.
        runner = self.module("release_telemetry_runner_v2", telemetry_path / "run.py")
        old_run = sys.modules.get("run")
        sys.modules["run"] = runner
        summaries = {}
        files = file_evidence([planned_roster_path])
        try:
            analyzer = self.module("release_telemetry_analyzer_v2", telemetry_path / "analyze.py")
            for suite in ("balance", "nav_ring_thorn", "nav_links"):
                folder = self.reports / "telemetry" / suite
                seed_sets = balance_sets if suite == "balance" else "both"
                code = runner.main(["--suite", suite, "--out", str(folder), "--project", str(self.project), "--godot", str(config.GODOT), "--jobs", str(self.options.jobs), "--timeout", "900", "--seed-sets", seed_sets])
                manifest_path = folder / "run_manifest.json"
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                require(code in (0, 1) and manifest.get("complete") is True and manifest.get("source_unchanged") is True,
                        "Telemetry execution is incomplete: " + suite)
                # A complete balance run can return 1 solely for n_team < 200.
                # Preserve that measured gate failure rather than losing its rows.
                require(code == 0 or (suite == "balance" and manifest.get("balance_sample_gate") is False), "Unexpected telemetry runner failure")
                analyzer.main([str(folder), "--out", str(folder), "--label", suite])
                path = folder / f"summary_{suite}.json"
                summaries[suite] = json.loads(path.read_text(encoding="utf-8"))
                raw = list(folder.glob("*.jsonl"))
                require(raw, "Telemetry produced no raw battle evidence: " + suite)
                roster_path = folder / "roster_meta.json"
                roster = json.loads(roster_path.read_text(encoding="utf-8"))
                ids = [row["id"] for row in roster]
                require(ids and len(ids) == len(set(ids)) and all(isinstance(hero, str) and hero for hero in ids), "Invalid telemetry roster")
                require(sorted(ids) == planned_roster, "Measured telemetry roster differs from planning roster")
                require(manifest.get("roster", {}).get("sha256") == sha(roster_path), "Telemetry roster differs from manifest")
                if suite == "balance":
                    summaries["expected_roster"] = sorted(ids)
                else:
                    require(sorted(ids) == summaries["expected_roster"], "Telemetry suites used different rosters")
                files.update(file_evidence([path, roster_path, manifest_path, *raw, *list((folder / "logs").glob("*"))]))
        finally:
            if old_run is None:
                sys.modules.pop("run", None)
            else:
                sys.modules["run"] = old_run
        from telemetry_gates import evaluate
        baseline = json.loads(self.options.baseline_summary.read_text(encoding="utf-8")) if self.options.baseline_summary else None
        result = evaluate(summaries, baseline)
        result["expected_roster"] = summaries["expected_roster"]
        result["sampling_plan"] = dict(roster_count=len(planned_roster), balance_seed_sets=list(range(1, balance_set_count + 1)),
                                       nav_seed_sets=[1, 2], team_appearances_per_balance_set=2592, target_mean_team_appearances=230)
        result["roster_process"] = roster_process
        result["provenance"] = {suite: summaries[suite].get("provenance") for suite in ("balance", "nav_ring_thorn", "nav_links")}
        result["baseline_source"] = dict(path=str(self.options.baseline_summary), sha256=sha(self.options.baseline_summary)) if self.options.baseline_summary else None
        connection = [row for row in self.state["stages"]["S2"]["tests"] if row["suite"] == "map_connectivity_v2"]
        require(len(connection) == 1, "S5 requires separate map connectivity evidence")
        check = connection[0]
        if check["status"] == "PASS":
            result["connectivity_test"] = dict(status="PASS", suite=CONTINUABLE_SUITE, log=check["log"], sha256=sha(check["log"]))
        else:
            require(self.test_failure_policy["enabled"] and not self.options.final and check.get("failure_continuation_allowed") is True,
                    "S5 cannot continue a failed connectivity test without the explicit dry-run assertion policy")
            proof = completed_connectivity_failure(check, check["assertion_report"])
            require(proof == check.get("assertion_failure"), "S2 connectivity assertion evidence changed before S5")
            result["connectivity_test"] = dict(status="FAIL", continued_for_diagnostics=True, **proof)
            result["gates"].append(dict(metric="map_connectivity_v2", observed=len(proof["failed"]), threshold="0 failed assertions", status="FAIL", baseline=None,
                                        unit="assertions", evidence=proof["report"]))
            result["failed_gates"] = sum(gate["status"] == "FAIL" for gate in result["gates"])
            result["passed_gates"] = sum(gate["status"] == "PASS" for gate in result["gates"])
            result["status"] = "FAIL"
        failed = result["status"] != "PASS"
        result["acceptance_status"] = result["status"]
        result["test_failure_policy"] = self.test_failure_policy
        if failed:
            result["status"] = "FAIL" if self.options.final or result.get("errors") else "WARN"
            result.setdefault("warnings", []).append("원격측정 수락 기준 미달을 기록했습니다. dry-run은 나머지 검증을 계속하며 정식 배포는 거부합니다.")
        result["output_hashes"] = files
        return result

    def S6(self):
        current = self.freshness("S6")
        table = self.project / "scripts/data/draft_calibration.gd"
        text = table.read_text(encoding="utf-8")
        stamp = re.search(r'const SIM_SHA[^=]*=\s*"([0-9a-f]+)"', text)
        observed = stamp.group(1) if stamp else "missing"
        equal = observed == current["sim_sha"] and len(observed) == 64
        games = re.search(r"const GAMES[^=]*=\s*(\d+)", text)
        return dict(status="PASS" if equal else ("FAIL" if self.options.final else "WARN"), acceptance_status="PASS" if equal else "FAIL",
                    current=current["sim_sha"], generated=observed, data_fingerprint=current["data_fingerprint"],
                    algorithm=current["algorithm"], simulation_files=current["files"], table=str(table), table_sha256=sha(table),
                    games=int(games.group(1)) if games else 0, holdout_audit="미검사: 이 단계는 SIM_SHA 신선도만 검사합니다.",
                    warnings=[] if equal else ["보정표 SIM_SHA 불일치: 정식 배포 전에 재생성해야 합니다."],
                    output_hashes={**current["output_hashes"], **file_evidence([table])})

    def S7(self):
        exports = {}
        for platform, (preset, relative) in config.PLATFORMS.items():
            target = guard_output(self.out / relative, self.options.final)
            target.parent.mkdir(parents=True, exist_ok=True)
            if platform == "macos":
                directory = self.profiles / "export_macos/Roaming/Godot/export_templates" / config.ENGINE_VERSION
                directory.mkdir(parents=True, exist_ok=True)
                atomic_copy(config.TEMPLATES["macos"], directory / "macos.zip")
                require(sha(directory / "macos.zip") == sha(config.TEMPLATES["macos"]), "macOS export template copy differs")
                atomic_bytes(directory / "version.txt", (config.ENGINE_VERSION + "\n").encode("utf-8"))
            # Remove stale bytes atomically; an old binary must never satisfy export success.
            atomic_bytes(target, b"")
            process = self.godot(["--headless", "--path", self.project, "--export-release", preset, target], "export_"+platform)
            require(target.is_file() and target.stat().st_size > 1_000_000, "Export missing or too small: " + platform)
            exports[platform] = dict(path=str(target), bytes=target.stat().st_size, sha256=sha(target), process=process)
        return dict(exports=exports, output_hashes={value["path"]:value["sha256"] for value in exports.values()})

    def S8(self):
        exports = self.state["stages"]["S7"]["exports"]
        require(all(Path(v["path"]).is_file() and sha(v["path"]) == v["sha256"] for v in exports.values()), "Export bytes changed before binary validation")
        binaries = audit_all(exports)
        require(set(binaries) == {"windows", "linux", "macos"} and all(v["status"] == "PASS" for v in binaries.values()), "Binary audit incomplete or failed")
        smokes = []
        result = self.process([exports["windows"]["path"], "--headless", "--quit-after", "240"], "smoke_windows", cwd=Path(exports["windows"]["path"]).parent)
        result["label"] = "Windows exported EXE, 240 frames"
        smokes.append(result)
        result = self.godot(["--main-pack", exports["linux"]["path"], "--headless", "--quit-after", "120"], "smoke_linux_pack")
        result["label"] = "Linux PCK cross-boot on Windows Godot, 120 frames"
        smokes.append(result)
        pack = self.out / "smoke/mac_game.pck"
        pack = safe_write_path(pack)
        pack.parent.mkdir(parents=True, exist_ok=True)
        atomic_bytes(pack, b"")
        with zipfile.ZipFile(exports["macos"]["path"]) as archive:
            with archive.open(binaries["macos"]["pck_member"]) as source, pack.open("wb") as output:
                shutil.copyfileobj(source, output, 1024*1024)
        result = self.godot(["--main-pack", pack, "--headless", "--quit-after", "120"], "smoke_macos_pack")
        result["label"] = "macOS PCK cross-boot on Windows Godot, 120 frames"
        smokes.append(result)
        shot = self.out / "screenshots/exported_windows.png"
        render_binary = self.profiles / "render_binary/game.exe"
        render_binary.parent.mkdir(parents=True, exist_ok=True)
        atomic_copy(exports["windows"]["path"], render_binary)
        require(sha(render_binary) == exports["windows"]["sha256"], "Rendered smoke copy differs from exported EXE")
        rendered = self.helper("shot", "smoke_windows_rendered", ["-RenderExecutable", render_binary, "-AppArgs", "--demo-battle=classic --warp=12", "-Out", shot, "-Frames", "120", "-Res", "1600x900"])
        screenshot = png_evidence(shot)
        require(sha(render_binary) == exports["windows"]["sha256"], "Rendered EXE changed during execution")
        after = profile_inventory(self.original_appdata, self.profile_names)
        require(after == self.profile_before, "Real profiles changed during isolated checks")
        profile_report = self.reports / "profiles_after_S8.json"
        write_json(profile_report, after)
        return dict(binaries=binaries, smokes=smokes, real_profiles_unchanged=True,
                    profile_names=self.profile_names, screenshot=screenshot, rendered_process=rendered,
                    rendered_binary=dict(path=str(render_binary), sha256=sha(render_binary), export_sha256=exports["windows"]["sha256"]),
                    profiles_before_sha256=digest(self.profile_before), profiles_after_sha256=digest(after),
                    output_hashes={**rendered["output_hashes"], **file_evidence([shot, pack, render_binary, profile_report])})

    def S9(self):
        fresh = config.SCRATCH / "fresh_import" / self.options.run_id / "project"
        copied = copy_project(self.project, fresh, fresh=True)
        require(not (fresh / ".godot").exists(), "Fresh import accidentally inherited cache")
        imported = import_project(fresh, self.logs / "S9_import", self.profiles / "S9_import")
        start = self.godot(["--headless", "--path", fresh, "--quit-after", "120"], "fresh_start")
        test = self.godot(["--headless", "--path", fresh, "--script", "res://tests/deathmatch_15.gd"], "fresh_deathmatch")
        return dict(copy=copied, no_cache_before=True, imports=imported, startup=start, deathmatch=test)

    def S10(self):
        for key in (f"S{i}" for i in range(10)):
            row = self.state["stages"].get(key, {})
            require(row.get("status") in (("PASS",) if self.options.final else ("PASS", "WARN", "SKIP")), "Prior validation stage did not finish: " + key)
            require(row.get("output_hashes") and all(Path(path).is_file() and sha(path) == value for path,value in row["output_hashes"].items()), "Prior evidence missing/changed: " + key)
        validation = self.out / f"VALIDATION_{config.VERSION}_KO.txt"
        prepackage = {f"S{i}": self.state["stages"][f"S{i}"] for i in range(10)}
        write_validation(validation, prepackage, not self.options.final, self.source)
        packages = package_all(self.project, self.out, self.state["stages"]["S7"]["exports"], validation, final=self.options.final)
        source_members = packages["archives"]["source"]["members"]
        for name in ("release.py", "qa_helper.ps1", "qa_process.py"):
            member = "tools/release_v2/" + name
            require(member in source_members and source_members[member]["sha256"] == sha(self.project / member), "Source archive lacks a verified QA bootstrap file: " + member)
        manifest = dict(version=config.VERSION, dry_run=not self.options.final, source=self.source,
                        stages=prepackage, packages=packages, validation={"path":str(validation),"sha256":sha(validation)},
                        status="WARN" if any(s["status"] in ("WARN","SKIP") for s in prepackage.values()) else "PASS")
        manifest.update(acceptance_summary(prepackage), execution_complete=False, test_failure_policy=self.test_failure_policy,
                        known_draft_failure_policy=self.known_draft_failure_policy,
                        known_draft26_failure_policy=self.known_draft26_failure_policy,
                        known_preview_failure_policy=self.known_preview_failure_policy,
                        known_render_failure_policy=self.known_render_failure_policy)
        manifest_path = self.out / "release_manifest_v2.json"
        write_json(manifest_path, manifest)
        outputs = {str(validation):sha(validation),str(manifest_path):sha(manifest_path)}
        outputs.update({entry["path"]:entry["sha256"] for entry in packages["archives"].values()})
        outputs.update({entry["path"]:entry["sha256"] for entry in packages["parts"]})
        outputs.update(file_evidence([packages["checksums"]["path"]]))
        split_readme = self.out / "SPLIT_ARCHIVES_KO.txt"
        if packages["parts"]:
            outputs.update(file_evidence([split_readme]))
        return dict(status=manifest["status"], packages=packages, validation=str(validation), manifest=str(manifest_path), output_hashes=outputs)

    def S11(self):
        packages = self.state["stages"]["S10"]["packages"]
        extracted = verify_and_extract(packages, config.SCRATCH / "extracted_releases" / self.options.run_id)
        windows = Path(extracted["archives"]["windows"]["root"]) / Path(self.state["stages"]["S7"]["exports"]["windows"]["path"]).name
        smoke = self.process([windows,"--headless","--quit-after","240"], "extracted_windows_smoke", cwd=windows.parent)
        after_profile = profile_inventory(self.original_appdata, self.profile_names)
        after_legacy = legacy_inventory(self.project.parent, include_release=not self.options.final)
        require(after_profile == self.profile_before, "Real profiles changed")
        require(self.legacy_equal(after_legacy, self.legacy_before), "Read-only legacy files or final release directory changed")
        protected = self.reports / "protected_after.json"
        write_json(protected, {"profiles":after_profile,"legacy":after_legacy})
        return dict(extracted=extracted, windows_smoke=smoke, real_profiles_unchanged=True, legacy_inventory_unchanged=True,
                    profiles_before_sha256=digest(self.profile_before), profiles_after_sha256=digest(after_profile),
                    legacy_before_sha256=digest(self.legacy_before), legacy_after_sha256=digest(after_legacy),
                    final_release_unchanged=True if not self.options.final else "authorized final output excluded",
                    output_hashes=file_evidence([protected, windows]))

    def execute(self):
        for index in range(12):
            key = f"S{index}"
            self.stage(key, getattr(self,key), always=key in ("S0","S6","S8","S10","S11"))
        self.state["complete"] = True
        self.state["execution_complete"] = True
        self.state["status"] = "WARN" if any(row["status"] in ("WARN","SKIP") for row in self.state["stages"].values()) else "PASS"
        acceptance = acceptance_summary(self.state["stages"])
        self.state.update(acceptance)
        self.state["test_failure_policy"] = self.test_failure_policy
        self.state["known_draft_failure_policy"] = self.known_draft_failure_policy
        self.state["known_draft26_failure_policy"] = self.known_draft26_failure_policy
        self.state["known_preview_failure_policy"] = self.known_preview_failure_policy
        self.state["known_render_failure_policy"] = self.known_render_failure_policy
        self.state["exit_code"] = 2 if acceptance["continued_test_failures"] else 0
        write_json(self.state_path,self.state)
        # Post-package evidence remains outside immutable archives.
        write_json(self.out / "post_package_validation.json", {**self.state["stages"]["S11"], **acceptance,
                   "stage":"S11", "execution_complete":True, "test_failure_policy":self.test_failure_policy,
                   "known_draft_failure_policy":self.known_draft_failure_policy,
                   "known_draft26_failure_policy":self.known_draft26_failure_policy,
                   "known_preview_failure_policy":self.known_preview_failure_policy,
                   "known_render_failure_policy":self.known_render_failure_policy})
        post = self.out / f"POST_PACKAGE_VALIDATION_{config.VERSION}_KO.txt"
        write_validation(post, self.state["stages"], not self.options.final, self.source)
        completion = dict(status=self.state["status"], complete=True, execution_complete=True, identity=self.identity,
                          test_failure_policy=self.test_failure_policy, exit_code=self.state["exit_code"], **acceptance,
                          known_draft_failure_policy=self.known_draft_failure_policy,
                          known_draft26_failure_policy=self.known_draft26_failure_policy,
                          known_preview_failure_policy=self.known_preview_failure_policy,
                          known_render_failure_policy=self.known_render_failure_policy,
                          stages={key: dict(status=value["status"], report=str(self.reports / (key + ".json")), sha256=sha(self.reports / (key + ".json"))) for key,value in self.state["stages"].items()},
                          output_hashes=file_evidence([post, self.out / "post_package_validation.json", self.out / "release_manifest_v2.json"]))
        write_json(self.out / "release_completion_v2.json", completion)
        print("RELEASE_EXECUTION_COMPLETE " + self.state["status"] + " ACCEPTANCE=" + acceptance["acceptance_status"] + " RELEASE_ELIGIBLE=" + str(acceptance["release_eligible"]), flush=True)
        return self.state["exit_code"]

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--final", action="store_true")
    mode.add_argument("--install-helper", action="store_true", help="Install bundled QA helper only; no Godot/profile access")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--run-id", default="phase1_dryrun")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--with-telemetry", action="store_true")
    parser.add_argument("--baseline-summary", type=Path)
    parser.add_argument("--resume-final", action="store_true", help="Explicitly resume identical final inputs; only this run's untracked reports may be dirty")
    parser.add_argument("--continue-on-test-failure", action="store_true", help="Dry-run diagnostic continuation for only a fully evidenced map_connectivity_v2 assertion failure; final is forbidden; completed diagnostic exits 2")
    parser.add_argument("--continue-on-known-draft-failure", action="store_true", help="Dry-run diagnostic continuation for only the pinned draft_14 completed six-assertion gap fixture failure; final is forbidden; acceptance remains FAIL and completed diagnostic exits 2")
    parser.add_argument("--continue-on-known-draft26-failure", action="store_true", help="Dry-only pinned 26-hero draft 255/6 evidence policy; mutually exclusive with the 22-hero flag; FAIL retained, final forbidden, completed diagnostic exits 2")
    parser.add_argument("--continue-on-known-preview-failure", action="store_true", help="Dry-run diagnostic continuation for only the pinned preview_ui_14 completed single assertion failure; final is forbidden; acceptance remains FAIL and completed diagnostic exits 2")
    parser.add_argument("--continue-on-known-render-failure", action="store_true", help="Dry-run diagnostic continuation for only the pinned render_v2 completed five-observation failure; final is forbidden; acceptance remains FAIL and completed diagnostic exits 2")
    options = parser.parse_args(argv)
    test_failure_policy(options)  # Reject final/install-helper combinations before any I/O.
    known_draft_failure_policy(options)
    draft26_diagnostic.policy(options)
    preview_diagnostic.policy(options)
    render_diagnostic.policy(options)
    if options.install_helper:
        print(json.dumps(ensure_helper(config.PROJECT), ensure_ascii=False, indent=2))
        return 0
    require(not options.resume_final or options.final, "--resume-final requires --final")
    require(1 <= options.jobs <= 4, "Release validation permits at most four Godot processes")
    require(re.fullmatch(r"[A-Za-z0-9_-]+", options.run_id), "Invalid run id")
    if options.final:
        require(options.with_telemetry, "Final requires full telemetry")
        options.out = options.out or config.RELEASE
    else:
        require(options.out is not None, "Dry-run requires an explicit scratch --out")
    return Release(options).execute()

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print("RELEASE_FAILED " + str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
