"""Narrow dry-run continuation for a completed, pinned preview UI assertion.

All rendering remains in the approved QA helper. This module only prepares and
checks its evidence; a recognized failure always remains acceptance FAIL.
"""
from pathlib import Path
import re
import sys
import config
from common import PROBLEMS, atomic_bytes, require, safe_write_path, sha, write_json
import preview_payload

SUITE = "preview_ui_14"
POLICY = "dry_run_completed_preview14_engine_verification_assertion_only_v1"
FAILURE = "final pick uses actual battle verification"
SOURCE_SHA = "541b966a3ebaf753ea20e0507caf9e94b60050b2ce4cf64cf58332248047e30e"
SCENE_SHA = "8907a7970567ac839bb667ce05e8eb183402160b020e7df61e0191da3f2fb787"
TEMPLATES = {"gd.ps1":"5ca9f6786542dc4354a890ae8fadf700d89b1750bd509db940fc360d792232ba",
             "gd_process.py":"cba85680fd387120e1dbf3729181939bc130b56097345ff3ca83d32754d765d1"}
EMPTY_SHA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
ARTIFACTS = (SUITE + ".json",) + tuple(stem + suffix for stem in ("uitest_"+SUITE,"import_qa_attempt1","import_qa_attempt2","import_qa_attempt3")
                                     for suffix in (".log",".log.request.json",".log.process.json"))


def policy(options):
    enabled = getattr(options,"continue_on_known_preview_failure",False) is True
    require(not enabled or (not options.final and getattr(options,"dry_run",False) is True),
            "--continue-on-known-preview-failure is allowed only with --dry-run; final never permits this option")
    return dict(enabled=enabled,policy=POLICY,allowed_suites=[SUITE] if enabled else [],
                fixture_sha256=SOURCE_SHA,scene_sha256=SCENE_SHA,helper_template_sha256=TEMPLATES,
                required_passed=105,required_failed=1,required_assertion_count=106,required_failure=FAILURE,
                infrastructure_errors_allowed=0,changes_test_acceptance=False)


def locations(project):
    project = Path(project).resolve()
    leaf = re.sub(r"[:\\/ ]","_",str(project)).strip("_")[-60:]
    return dict(project=str(project),leaf=leaf,origin=str(project / "zz_work/logs" / leaf),
                qa=str(Path(config.QA).resolve().parents[1] / leaf / "project"),
                profile_root=str(config.SCRATCH / "godot_profiles" / leaf))


def source_hashes(project):
    project = Path(project)
    return {"gd":sha(project / "tests/preview_ui_14.gd"),"scene":sha(project / "tests/preview_ui_14.tscn")}


def prepare(project, proof_path):
    context = locations(project)
    context.update(schema=1,status="CLEARED",source_before=source_hashes(project),cleared={})
    require(context["source_before"] == {"gd":SOURCE_SHA,"scene":SCENE_SHA}, "Preview fixture changed; diagnostic policy requires review")
    for name in ARTIFACTS:
        path = safe_write_path(Path(context["origin"]) / name)
        atomic_bytes(path,b"")
        context["cleared"][name] = dict(bytes=path.stat().st_size,sha256=sha(path))
    context["proof_path"] = str(safe_write_path(proof_path))
    write_json(Path(context["proof_path"]),context)
    return context


def capture(context, frozen, installed):
    require(context.get("status") == "CLEARED", "Preview evidence was not cleared before helper launch")
    context = dict(context,status="CAPTURED",frozen=str(Path(frozen).resolve()),
                   source_after=source_hashes(context["project"]),qa_sources=source_hashes(context["qa"]),
                   helper_templates={key:value["sha256"] for key,value in installed.items()},captured={})
    for name in ARTIFACTS:
        original,target = Path(context["origin"]) / name,Path(frozen) / name
        require(original.is_file() and target.is_file(), "Missing preview/import capture artifact: "+name)
        require(sha(original) == sha(target), "Preview evidence changed during capture: "+name)
        context["captured"][name] = dict(bytes=target.stat().st_size,sha256=sha(target))
    write_json(Path(context["proof_path"]),context)
    return context


def _normal_outer(process, parse_json):
    require(process.get("suite") == SUITE and process.get("status") == "FAIL"
            and type(process.get("code")) is int and process["code"] == 1
            and type(process.get("pid")) is int and process["pid"] > 0
            and process.get("timeout") is False and process.get("cleanup_errors") == []
            and process.get("cancelled") is False and process.get("interrupted") is False
            and process.get("exception","missing") is None and process.get("termination","missing") is None,
            "Preview helper did not end as a normal, complete assertion failure")
    path = Path(process["log"])
    saved = parse_json(path.with_suffix(path.suffix+".process.json").read_text(encoding="utf-8"))
    for key in ("status","code","pid","timeout","cleanup_errors","cancelled","interrupted","exception","termination","command","log","problems"):
        require(key in process and saved.get(key,object()) == process[key], "Outer preview process evidence disagrees: "+key)
    return path


def _inner(context, stem, expected_code, expected_args, parse_json):
    frozen,origin = Path(context["frozen"]),Path(context["origin"])
    request = parse_json((frozen / (stem+".log.request.json")).read_text(encoding="utf-8"))
    state = parse_json((frozen / (stem+".log.process.json")).read_text(encoding="utf-8"))
    expected_request = dict(executable=str(config.GODOT),args=expected_args,log=str(origin / (stem+".log")),
                            summary=str(origin / (stem+".log.process.json")),timeout=900,
                            appdata=str(Path(context["profile_root"]) / stem / "Roaming"),
                            localappdata=str(Path(context["profile_root"]) / stem / "Local"))
    require(request == expected_request and type(request.get("timeout")) is int, "Unexpected preview/import launch, profile or timeout contract")
    require(isinstance(state,dict) and set(state) == {"code","pid","timed_out","appdata","localappdata","timeout_seconds","log","cleanup_errors","termination","interrupted","seconds"}
            and type(state["code"]) is int and state["code"] == expected_code
            and type(state["pid"]) is int and state["pid"] > 0 and state["timed_out"] is False
            and state["cleanup_errors"] == [] and state["termination"] is None and state["interrupted"] is False
            and type(state["seconds"]) in (int,float) and 0 <= state["seconds"] <= 900
            and type(state["timeout_seconds"]) is int and state["timeout_seconds"] == 900
            and all(state[key] == expected_request[key] for key in ("log","appdata","localappdata")),
            "Preview/import process lifecycle evidence is incomplete or failed")
    return state,(frozen / (stem+".log")).read_text(encoding="utf-8",errors="strict").splitlines()


def completed_failure(process, project, parse_json):
    """Verify the full helper -> isolated engine -> report chain, without rendering."""
    outer_log = _normal_outer(process,parse_json)
    proof_path = Path(process["preview_capture"])
    context = parse_json(proof_path.read_text(encoding="utf-8"))
    expected_locations = locations(project)
    require(isinstance(context,dict) and context.get("schema") == 1 and context.get("status") == "CAPTURED"
            and all(context.get(key) == value for key,value in expected_locations.items())
            and context.get("proof_path") == str(proof_path.resolve())
            and context.get("frozen") == str(Path(process["helper_evidence_dir"]).resolve())
            and context.get("source_before") == context.get("source_after") == context.get("qa_sources") == {"gd":SOURCE_SHA,"scene":SCENE_SHA}
            and context.get("helper_templates") == TEMPLATES,
            "Preview source, helper or capture provenance changed")
    require(isinstance(context.get("cleared"),dict) and set(context["cleared"]) == set(ARTIFACTS)
            and all(row == {"bytes":0,"sha256":EMPTY_SHA} for row in context["cleared"].values()), "Preview report/process/import files were not all cleared before launch")
    captured = context.get("captured")
    require(isinstance(captured,dict) and set(captured) == set(ARTIFACTS), "Incomplete preview evidence capture")
    frozen = Path(context["frozen"])
    for name in ARTIFACTS:
        path = frozen / name
        require(path.is_file() and captured[name] == {"bytes":path.stat().st_size,"sha256":sha(path)}, "Changed preview evidence artifact: "+name)
        if name.startswith(("import_qa_attempt2","import_qa_attempt3")):
            require(captured[name] == {"bytes":0,"sha256":EMPTY_SHA}, "Import retry/infrastructure failure is outside this diagnostic policy")
        else:
            require(captured[name]["bytes"] > 0, "Missing fresh preview/import artifact: "+name)
    expected_command = ["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(Path(project).resolve() / "zz_work/tools/gd.ps1"),
                        "-PythonExe",sys.executable,"-Mode","uitest","-Root",str(Path(project).resolve()),"-Suite",SUITE]
    require(process.get("command") == expected_command, "Preview was not run through the exact approved UI helper mode")
    report_origin = (Path(context["origin"]) / (SUITE+".json")).as_posix()
    engine,lines = _inner(context,"uitest_"+SUITE,1,["--path",context["qa"],"--resolution","1600x900",
                         "res://tests/preview_ui_14.tscn","--","--ui-report="+report_origin],parse_json)
    _,import_lines = _inner(context,"import_qa_attempt1",0,["--headless","--path",context["qa"],"--editor","--quit"],parse_json)
    severity = re.compile(r"SCRIPT ERROR|Parse Error|\bERROR:|\bWARNING:",re.IGNORECASE)
    require(any(line.startswith("Godot Engine v"+config.ENGINE_VERSION) for line in import_lines)
            and not any(severity.search(line) or re.search(r"\bFAIL(?:ED|URE)?\b",line,re.IGNORECASE) for line in import_lines),
            "QA import log is incomplete or contains infrastructure failures")
    report_path,engine_log = frozen / (SUITE+".json"),frozen / ("uitest_"+SUITE+".log")
    payload = preview_payload.validate(report_path,engine_log,parse_json)
    # Reproduce exactly the reviewed helper's public output: last 40 matching
    # engine lines, Show-Problems diagnostics, then its terminal UITEST summary.
    matching = [line for line in lines if re.search(r"FAIL|PASS|passed|failed",line,re.IGNORECASE)]
    problems = [line for line in lines if re.search(r"SCRIPT ERROR|^ERROR:|Parse Error|^\s+at: |WARNING: .*\.gd",line,re.IGNORECASE)]
    expected_outer = ["  "+line for line in matching[-40:]] + ["  "+line for line in problems]
    expected_outer += [f"UITEST {SUITE} exit=1 problems={len(problems)} log={Path(context['origin']) / ('uitest_'+SUITE+'.log')} report={report_origin}"]
    actual_outer = outer_log.read_text(encoding="utf-8",errors="strict").splitlines()
    require(actual_outer == expected_outer and process["problems"] == [line for line in actual_outer if PROBLEMS.search(line)] == [],
            "Unexpected helper output, extra error, or contradictory summary")
    return dict(classification="completed_known_preview_assertion_failure",suite=SUITE,policy=POLICY,
                acceptance_status="FAIL",passed=105,failed=[FAILURE],assertion_count=106,
                fixture_sha256=SOURCE_SHA,scene_sha256=SCENE_SHA,report=str(report_path),report_sha256=sha(report_path),
                log=str(engine_log),log_sha256=sha(engine_log),process_report=str(engine_log.with_suffix(".log.process.json")),
                process_report_sha256=sha(engine_log.with_suffix(".log.process.json")),
                helper_log=str(outer_log),helper_log_sha256=sha(outer_log),
                helper_process_report=str(outer_log.with_suffix(outer_log.suffix+".process.json")),
                helper_process_report_sha256=sha(outer_log.with_suffix(outer_log.suffix+".process.json")),
                capture_receipt=str(proof_path),capture_receipt_sha256=sha(proof_path),
                engine_pid=engine["pid"],infrastructure_errors=[],infrastructure_error_count=0,
                payload=payload,evidence_files={str(frozen / name):captured[name]["sha256"] for name in ARTIFACTS})
