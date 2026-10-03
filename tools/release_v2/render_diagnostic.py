"""Narrow dry-run continuation for one complete render_v2 assertion failure.

The unmodified producer writes its final JSON only to native stdout.  Captured
JSON is explicitly derived evidence, never represented as a producer file.
"""
from pathlib import Path
import math
import config
from common import PROBLEMS, atomic_bytes, require, safe_write_path, sha, within, write_json
import render_payload

SUITE = "render_v2"
POLICY = "dry_run_completed_render_v2_five_demo_observations_only_v1"
SOURCE_SHA = "dedaabfe84a650811eebfff68238ed759cb4a103fd0b0deb667ac1525b96ca92"
EMPTY_SHA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
FAILURES = (
    "the demo battle shows TANK_DESTROYED",
    "the demo battle shows OVERDRIVE",
    "the demo battle draws the overdrive state",
    "the demo battle draws the charge state",
    "the demo battle draws the missileBarrage state",
)


def policy(options):
    enabled = getattr(options, "continue_on_known_render_failure", False) is True
    require(not enabled or (not options.final and getattr(options, "dry_run", False) is True),
            "--continue-on-known-render-failure is allowed only with --dry-run; final never permits this option")
    return dict(enabled=enabled, policy=POLICY, allowed_suites=[SUITE] if enabled else [],
                fixture_sha256=SOURCE_SHA, required_passed=190, required_failed=5,
                required_assertion_count=195, required_failures=list(FAILURES),
                infrastructure_errors_allowed=0, changes_test_acceptance=False)


def _sources(project, qa):
    return {str(Path(root).resolve() / "tests/render_v2.gd"): sha(Path(root) / "tests/render_v2.gd")
            for root in (project, qa)}


def prepare(project, qa, report, log, profile):
    project, qa = Path(project).resolve(), Path(qa).resolve()
    report, log, profile = (safe_write_path(path) for path in (report, log, profile))
    require(within(profile, config.SCRATCH) and profile != config.SCRATCH.resolve(), "Render profile must be isolated scratch")
    sources = _sources(project, qa)
    require(len(sources) == 2 and all(value == SOURCE_SHA for value in sources.values()),
            "Render fixture changed; diagnostic policy requires review")
    atomic_bytes(report, b"")
    atomic_bytes(log, b"")
    context = dict(schema=1, status="CLEARED", capture_kind="native_stdout_json", suite=SUITE,
                   project=str(project), qa=str(qa), captured_report=str(report), log=str(log), profile=str(profile),
                   engine=str(config.GODOT), fixture_before=sources, cleared_bytes=0, cleared_sha256=EMPTY_SHA)
    write_json(report.with_suffix(".capture.json"), context)
    return context


def _normal_process(process, context, parse_json):
    expected = [context["engine"], "--headless", "--path", context["qa"], "--script", "res://tests/render_v2.gd"]
    require(process.get("suite") == SUITE and process.get("command") == expected,
            "Render process has the wrong suite, engine, QA path or arguments")
    require(type(process.get("code")) is int and process["code"] in (0, 1)
            and process.get("status") == ("PASS" if process["code"] == 0 else "FAIL")
            and type(process.get("pid")) is int and process["pid"] > 0
            and process.get("timeout") is False and process.get("cleanup_errors") == []
            and process.get("cancelled") is False and process.get("interrupted") is False
            and process.get("exception", "missing") is None and process.get("termination", "missing") is None,
            "Render process is incomplete, crashed, cancelled, timed out or has cleanup errors")
    elapsed = process.get("seconds")
    require(type(elapsed) in (int, float) and math.isfinite(elapsed) and elapsed >= 0,
            "Render process lacks a finite duration")
    require(process.get("log") == context["log"]
            and process.get("appdata") == str(Path(context["profile"]) / "Roaming")
            and process.get("localappdata") == str(Path(context["profile"]) / "Local"),
            "Render log/profile binding differs from the prepared launch")
    log = Path(context["log"])
    saved_path = log.with_suffix(log.suffix + ".process.json")
    saved = parse_json(saved_path.read_text(encoding="utf-8"))
    for key in ("command", "pid", "code", "status", "timeout", "seconds", "log", "problems", "appdata", "localappdata",
                "cleanup_errors", "cancelled", "interrupted", "exception", "termination"):
        require(key in process and key in saved and type(saved[key]) is type(process[key]) and saved[key] == process[key],
                "Persisted render process evidence disagrees: " + key)
    return log, saved_path


def _payload(log):
    raw = log.read_bytes()
    lines = raw.decode("utf-8", errors="strict").splitlines()
    summaries = [line for line in lines if line.startswith("RENDER_V2 ")]
    require(len(summaries) == 1, "Render requires exactly one final native stdout JSON")
    return (summaries[0][len("RENDER_V2 "):] + "\n").encode("utf-8"), lines


def capture(context, process, parse_json):
    require(context.get("status") == "CLEARED", "Render native stdout was not cleared for this run")
    log, saved = _normal_process(process, context, parse_json)
    report = safe_write_path(context["captured_report"])
    raw, _ = _payload(log)
    parse_json(raw.decode("utf-8"))
    atomic_bytes(report, raw)
    sources = _sources(context["project"], context["qa"])
    require(sources == context["fixture_before"], "Render fixture changed during execution")
    updated = dict(context, status="CAPTURED", fixture_after=sources, captured_sha256=sha(report),
                   captured_bytes=report.stat().st_size, log_sha256=sha(log), process_sha256=sha(saved))
    write_json(report.with_suffix(".capture.json"), updated)
    return updated


def evidence(process, report, project, qa, profile, parse_json):
    report = Path(report).resolve()
    receipt_path = report.with_suffix(".capture.json")
    context = parse_json(receipt_path.read_text(encoding="utf-8"))
    expected = dict(schema=1, status="CAPTURED", capture_kind="native_stdout_json", suite=SUITE,
                    project=str(Path(project).resolve()), qa=str(Path(qa).resolve()), captured_report=str(report),
                    log=str(report.parent.parent / "logs/headless_render_v2.log"),
                    profile=str(Path(profile).resolve()), engine=str(config.GODOT), cleared_bytes=0, cleared_sha256=EMPTY_SHA)
    require(isinstance(context, dict) and all(key in context and type(context[key]) is type(value) and context[key] == value
                                           for key, value in expected.items()), "Render capture/launch contract differs")
    source_names = {str(Path(project).resolve() / "tests/render_v2.gd"), str(Path(qa).resolve() / "tests/render_v2.gd")}
    require(context.get("fixture_before") == context.get("fixture_after") == dict.fromkeys(source_names, SOURCE_SHA),
            "Render capture has a changed or unpinned fixture")
    log, saved = _normal_process(process, context, parse_json)
    require(context.get("log_sha256") == sha(log) and context.get("process_sha256") == sha(saved)
            and context.get("captured_sha256") == sha(report)
            and type(context.get("captured_bytes")) is int and context["captured_bytes"] == report.stat().st_size > 0,
            "Render native log/process/capture bytes changed")
    raw, lines = _payload(log)
    require(report.read_bytes() == raw, "Captured JSON does not match the actual native stdout")
    data = parse_json(raw.decode("utf-8"))
    require(isinstance(data, dict) and set(data) == {"status", "passed", "failed", "metrics"}
            and type(data.get("passed")) is int and isinstance(data.get("failed"), list)
            and isinstance(data.get("metrics"), dict), "Incomplete render stdout JSON")
    return data, lines, context, saved


def completed_pass(process, report, project, qa, profile, parse_json):
    data, lines, _, _ = evidence(process, report, project, qa, profile, parse_json)
    require(process["code"] == 0 and process["status"] == "PASS" and process["problems"] == []
            and data["status"] == "PASS" and data["passed"] == 195 and data["failed"] == []
            and set(data["metrics"]) == {"patterns", "live", "showcase"}
            and not any(PROBLEMS.search(line) or "WARNING:" in line or "ERROR:" in line for line in lines),
            "Incomplete or contradictory render PASS evidence")
    return data


def completed_failure(process, report, project, qa, profile, parse_json):
    data, lines, context, saved = evidence(process, report, project, qa, profile, parse_json)
    require(process["code"] == 1 and process["status"] == "FAIL", "Known render failure requires normal exit 1")
    checked = render_payload.validate(Path(process["log"]), parse_json)
    require(checked["payload"] == data, "Render payload changed during evidence validation")
    expected_errors = ["ERROR: FAIL " + failure for failure in FAILURES]
    require(process["problems"] == [line for line in lines if PROBLEMS.search(line)] == expected_errors,
            "Additional/missing native render process errors")
    report = Path(report).resolve()
    return dict(classification="completed_known_render_demo_observation_failure", acceptance_status="FAIL", suite=SUITE,
                policy=POLICY, passed=checked["passed"], failed=checked["failed_checks"], assertion_count=195,
                fixture_sha256=SOURCE_SHA, metrics=checked["metrics"], assertion_error_lines=expected_errors,
                infrastructure_errors=[], infrastructure_error_count=0, cause="NOT_DETERMINED_BY_PAYLOAD",
                report=str(report), report_sha256=sha(report), log=process["log"], log_sha256=context["log_sha256"],
                process_report=str(saved), process_report_sha256=context["process_sha256"], capture_kind="native_stdout_json",
                capture_receipt=str(report.with_suffix(".capture.json")), capture_receipt_sha256=sha(report.with_suffix(".capture.json")))
