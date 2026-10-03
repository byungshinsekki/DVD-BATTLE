"""Explicit dry-only 26-hero draft failure evidence; never an acceptance pass.

The original 22-hero reader is reused without changing its policy or predicates.
This adapter adds a closed source/table identity and exact common.run lifecycle.
"""
from pathlib import Path
import math
import config
from common import PROBLEMS, atomic_bytes, require, safe_write_path, sha, within, write_json
import draft26_payload

SUITE = 'draft_14'
POLICY = 'dry_run_completed_draft14_roster26_gap_six_assertions_only_v1'
SOURCES = {
    'tests/draft_14.gd': '16484c6f07b525066f068ab77d8221d352135a75d24e327a1aeddb1efd84d03f',
    'scripts/core/db.gd': 'e2873b655d5a8161ae0976d345cd864ee35aebdfead955f4c2af3d5fa6d18338',
    'scripts/data/char_data.gd': '9a7ed544b8b4636293cd0a2b3181d80175640c6f6a560a94ee6ef152fde60ce4',
    'scripts/data/draft_calibration.gd': '92bc40abf792a7fa6d3351ca7601ab266cb3c0c7373102ff7f13a96c660f124b',
    'scripts/ai/draft_director.gd': '8d6b5d0104ae7dbba2d8b383db835f7eebdbd8139582bfc3b5cad26522e2d3c3',
    'scripts/ai/draft_search.gd': '4b497125c11414446f9a758772065b6c080fa486074f887f3faf8ddd66574c66',
}
EMPTY_SHA = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'


def policy(options):
    enabled = getattr(options, 'continue_on_known_draft26_failure', False) is True
    require(not enabled or getattr(options, 'continue_on_known_draft_failure', False) is not True,
            '22-hero and 26-hero draft diagnostic policies are mutually exclusive')
    require(not enabled or (not options.final and getattr(options, 'dry_run', False) is True),
            '--continue-on-known-draft26-failure is allowed only with --dry-run; final never permits this option')
    return dict(enabled=enabled, policy=POLICY, allowed_suites=[SUITE] if enabled else [],
                fixture_sha256=SOURCES['tests/draft_14.gd'], required_passed=255, required_failed=6,
                required_assertion_count=261, required_failures=list(draft26_payload.FAILURES),
                roster=list(draft26_payload.ROSTER), sources=SOURCES,
                infrastructure_errors_allowed=0, changes_test_acceptance=False)


def sources(project, qa):
    roots = [Path(project).resolve(), Path(qa).resolve()]
    require(roots[0] != roots[1], 'Draft26 requires a separate QA copy')
    return {str(root): {name: sha(root / name) for name in SOURCES} for root in roots}


def prepare(project, qa, report, log, profile):
    import release
    project, qa = Path(project).resolve(), Path(qa).resolve()
    report, log, profile = (safe_write_path(path) for path in (report, log, profile))
    require(within(profile, config.SCRATCH) and profile != config.SCRATCH.resolve(), 'Draft26 profile must be isolated scratch')
    before = sources(project, qa)
    require(all(value == SOURCES for value in before.values()), 'Draft26 source/table differs from the reviewed current identity')
    context = release.prepare_draft_report(qa, report)
    atomic_bytes(log, b'')
    saved = log.with_suffix(log.suffix + '.process.json')
    atomic_bytes(saved, b'')
    require(log.stat().st_size == saved.stat().st_size == 0, 'Draft26 launch outputs were not cleared')
    context['draft26'] = dict(schema=1, policy=POLICY, suite=SUITE, project=str(project), qa=str(qa),
                             log=str(log), profile=str(profile), engine=str(config.GODOT),
                             roster=list(draft26_payload.ROSTER), source_before=before,
                             cleared_log_sha256=sha(log), cleared_process_sha256=sha(saved))
    write_json(report.with_suffix('.capture.json'), context)
    return context


def normal_process(process, context, parse_json):
    expected = [str(config.GODOT), '--headless', '--path', context['qa'], '--script', 'res://tests/draft_14.gd']
    require(process.get('suite') == SUITE and process.get('command') == expected, 'Draft26 engine/QA/suite arguments differ')
    require(type(process.get('code')) is int and process['code'] in (0, 1)
            and process.get('status') == ('PASS' if process['code'] == 0 else 'FAIL')
            and type(process.get('pid')) is int and process['pid'] > 0
            and process.get('timeout') is False and process.get('cleanup_errors') == []
            and process.get('cancelled') is False and process.get('interrupted') is False
            and process.get('error') in (None, '')
            and process.get('exception', 'missing') is None and process.get('termination', 'missing') is None,
            'Draft26 process is incomplete, crashed, cancelled or timed out')
    require(type(process.get('seconds')) in (int, float) and math.isfinite(process['seconds']) and process['seconds'] >= 0,
            'Draft26 process lacks a finite duration')
    require(process.get('log') == context['log'] and process.get('appdata') == str(Path(context['profile']) / 'Roaming')
            and process.get('localappdata') == str(Path(context['profile']) / 'Local'), 'Draft26 log/profile differs from prepared launch')
    log = Path(context['log']); saved_path = log.with_suffix(log.suffix + '.process.json')
    saved = parse_json(saved_path.read_text(encoding='utf-8'))
    for key in ('command', 'pid', 'code', 'status', 'timeout', 'seconds', 'log', 'problems', 'appdata', 'localappdata',
                'cleanup_errors', 'cancelled', 'interrupted', 'exception', 'termination'):
        require(key in process and key in saved and type(saved[key]) is type(process[key]) and saved[key] == process[key],
                'Persisted draft26 process differs: ' + key)
    return log, saved_path


def capture(context, process, parse_json):
    import release
    require(context.get('status') == 'CLEARED', 'Draft26 fixed producer report was not freshly cleared')
    detail = context['draft26']
    log, saved = normal_process(process, detail, parse_json)
    after = sources(detail['project'], detail['qa'])
    require(after == detail['source_before'] and all(value == SOURCES for value in after.values()), 'Draft26 source/table changed during execution')
    updated = release.capture_draft_report(context)
    updated['draft26'] = dict(detail, source_after=after, log_sha256=sha(log), process_sha256=sha(saved))
    write_json(Path(updated['captured_report']).with_suffix('.capture.json'), updated)
    return updated


def evidence(process, report, project, qa, profile, parse_json):
    import release
    report, project, qa, profile = (Path(path).resolve() for path in (report, project, qa, profile))
    require(within(profile, config.SCRATCH) and profile != config.SCRATCH.resolve(), 'Draft26 profile must be isolated scratch')
    data, lines, receipt = release.draft_report_evidence(process, report, qa)
    detail = receipt.get('draft26')
    expected = dict(schema=1, policy=POLICY, suite=SUITE, project=str(project), qa=str(qa),
                    log=str(report.parent.parent / 'logs/headless_draft_14.log'), profile=str(profile), engine=str(config.GODOT),
                    roster=list(draft26_payload.ROSTER), cleared_log_sha256=EMPTY_SHA, cleared_process_sha256=EMPTY_SHA)
    require(isinstance(detail, dict) and all(key in detail and type(detail[key]) is type(value) and detail[key] == value for key, value in expected.items()),
            'Draft26 capture/launch identity differs')
    expected_sources = {str(project): SOURCES, str(qa): SOURCES}
    require(len(expected_sources) == 2 and detail.get('source_before') == detail.get('source_after') == expected_sources
            and receipt['fixture_before_sha256'] == SOURCES['tests/draft_14.gd'], 'Draft26 source/roster/table evidence is missing or changed')
    log, saved = normal_process(process, detail, parse_json)
    require(detail.get('log_sha256') == sha(log) and detail.get('process_sha256') == sha(saved), 'Draft26 raw process/log changed after capture')
    return data, lines, receipt, saved


def completed_pass(process, report, project, qa, profile, parse_json):
    data, lines, _, _ = evidence(process, report, project, qa, profile, parse_json)
    require(process['code'] == 0 and process['status'] == 'PASS' and process['problems'] == []
            and data['status'] == 'PASS' and data['passed'] == 265 and data['failures'] == []
            and not any(PROBLEMS.search(line) or 'WARNING:' in line or 'ERROR:' in line for line in lines), 'Incomplete draft26 PASS evidence')
    draft26_payload.complete_measurements(data['measurements'])
    # The pinned producer performs one extra horizon assertion per engine row.
    # A real PASS has four trials (261 + 4 assertions), never the zero-game gap case.
    rollout = data['measurements'][8]['search']['rollout']
    pairs = {(row['id'], row['side']) for row in rollout['rows']}
    finalists = {row['id'] for row in rollout['rows']}
    require(rollout['enabled'] is True and rollout['final_pick_only'] is True and rollout['finalists_only'] is True
            and rollout['skipped'] == '' and rollout['games'] == len(rollout['rows']) == 4
            and rollout['tick_budget'] == 1200 and rollout['ticks'] <= 1200
            and rollout['horizon_ticks'] == rollout['min_horizon_ticks'] == 300
            and rollout['sides_per_finalist'] == 2 and rollout['gap_gate'] == 1.0 and rollout['weight'] == .24
            and len(finalists) == 2 and pairs == {(hero, side) for hero in finalists for side in (0, 1)},
            'Draft26 PASS lacks the four balanced engine trials required by the pinned producer')
    return data


def completed_failure(process, report, project, qa, profile, parse_json):
    data, lines, receipt, saved = evidence(process, report, project, qa, profile, parse_json)
    require(process['code'] == 1 and process['status'] == 'FAIL', 'Draft26 known failure requires normal exit 1')
    checked = draft26_payload.validate(data, lines, process['problems'])
    report, log = Path(report).resolve(), Path(process['log'])
    return dict(checked, classification='completed_known_draft26_gap_fixture_failure', acceptance_status='FAIL',
                suite=SUITE, policy=POLICY, fixture_sha256=SOURCES['tests/draft_14.gd'], sources=SOURCES,
                calibration_sha256=SOURCES['scripts/data/draft_calibration.gd'],
                report=str(report), report_sha256=sha(report), log=str(log), log_sha256=sha(log),
                process_report=str(saved), process_report_sha256=sha(saved),
                capture_receipt=str(report.with_suffix('.capture.json')), capture_receipt_sha256=sha(report.with_suffix('.capture.json')))
