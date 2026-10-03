"""Korean validation document; every measurement comes from recorded evidence."""
import json
from pathlib import Path
import config
from common import atomic_bytes


def shown(value):
    return "미측정" if value is None else json.dumps(value, ensure_ascii=False, sort_keys=True)


def write_validation(path, stages, dry_run, source):
    origin = stages.get("S0", {})
    telemetry = stages.get("S5", {})
    complete = stages.get("S11", {}).get("status") == "PASS"
    failed_stages = [key for key, value in stages.items() if value.get("acceptance_status", value.get("status")) == "FAIL"]
    continued = stages.get("S2", {}).get("continued_test_failures", []) + stages.get("S3", {}).get("continued_ui_test_failures", [])
    holds = (["C2"] if any(row.get("suite") == "map_connectivity_v2" for row in continued) else []) + (["C6"] if any(row.get("suite") == "draft_14" for row in continued) else []) + (["C7"] if any(row.get("suite") == "preview_ui_14" for row in continued) else []) + (["render_v2"] if any(row.get("suite") == "render_v2" for row in continued) else []) + ["C8"]
    acceptance = "FAIL" if failed_stages else ("PASS" if complete and all(value.get("status") == "PASS" for value in stages.values()) else "UNVERIFIED")
    rows = [f"DVD BATTLE V{config.VERSION} 검증 보고서", "DRY-RUN · 검증용 산출물" if dry_run else "정식 배포 검증", "",
            f"수락 판정: {acceptance}; 전체 검증 실행 완료: {complete}",
            "FAIL | " + "/".join(holds) + " HOLD | 진단 검증만 계속한 결과이며 정식 배포할 수 없습니다." if continued else "명시된 단계별 실패·미검증 항목을 확인하십시오.",
            f"수락 실패 단계: {shown(failed_stages)}",
            f"테스트 실패 계속 정책: {shown(origin.get('test_failure_policy'))}",
            f"알려진 드래프트 실패 진단 정책: {shown(origin.get('known_draft_failure_policy'))}",
            f"26인 드래프트 실패 진단 정책: {shown(origin.get('known_draft26_failure_policy'))}",
            f"알려진 미리보기 실패 진단 정책: {shown(origin.get('known_preview_failure_policy'))}",
            f"알려진 렌더 실패 진단 정책: {shown(origin.get('known_render_failure_policy'))}",
            f"소스 커밋: {source['head']}", f"소스 입력 SHA256: {source['input_sha256']}",
            f"엔진: {origin.get('engine_version', '미검사')}", f"게임 내 버전: {shown(origin.get('versions'))}",
            f"검증 모드: {'dry-run' if dry_run else 'final'}", f"최초 Git 변경 목록: {shown(origin.get('git_status'))}",
            f"Git clean / 재개 정책: {origin.get('clean_policy', '미검사')}",
            f"현재 데이터 지문: {origin.get('fingerprint', {}).get('data_fingerprint', '미검사')}",
            f"런타임 파일 수: {len(source.get('runtime', {}))}, 검증 도구 파일 수: {len(source.get('verification', {}))}, 소스 ZIP 입력 파일 수: {len(source.get('package_files', {}))}", "",
            "엔진·템플릿·Python 바이너리 출처"]
    for name, value in origin.get("binary_inputs", {}).items():
        rows.append(f"{name}: SHA256={value}")
    rows += ["", "단계 결과 (WARN은 수락 기준 통과를 뜻하지 않습니다)"]
    for index in range(12):
        stage = f"S{index}"
        data = stages.get(stage)
        if data is None:
            rows.append(f"{stage}: 미실행 (패키징 시점의 문서는 S0–S9 결과까지 포함)")
            continue
        rows.append(f"{stage}: 실행={data.get('status', '미검사')}; 수락={data.get('acceptance_status', data.get('status', '미검사'))}; 증거 파일 수={len(data.get('output_hashes', {}))}")
        rows.extend("  " + str(warning) for warning in data.get("warnings", []))
        if data.get("error"):
            rows.append("  오류: " + str(data["error"]))
    rows += ["", "헤드리스 테스트 (자동 탐색, 격리 QA 사본)", "스위트 | 결과 | 종료 코드 | 실행 초 | 로그"]
    for test in stages.get("S2", {}).get("tests", []):
        rows.append(f"{test['suite']} | {test['status']} | {test['code']} | {test['seconds']} | {test['log']}")
        if test.get("assertion_report"):
            rows.append("  결과 JSON: " + test["assertion_report"])
        if test.get("assertion_evidence_error"):
            rows.append("  증거 오류: " + test["assertion_evidence_error"])
    if continued:
        rows += ["", "FAIL 상태를 보존하고 후속 검증만 수행한 테스트"]
        for failure in continued:
            rows.append(f"{failure['suite']}: FAIL; passed={failure['passed']}; failed={len(failure['failed'])}; infrastructure_errors={failure['infrastructure_error_count']}")
            rows.extend("  FAIL: " + message for message in failure["failed"])
            rows.append(f"  결과 JSON={failure['report']}; SHA256={failure['report_sha256']}")
            rows.append(f"  로그={failure['log']}; SHA256={failure['log_sha256']}")
            rows.append(f"  프로세스 증거={failure['process_report']}; SHA256={failure['process_report_sha256']}")
            if failure.get("fixture_sha256"):
                rows.append(f"  고정 테스트 SHA256={failure['fixture_sha256']}; 정책={failure['policy']}")
                label = "native stdout JSON에서 추출한 파생 증거 캡처" if failure.get("capture_kind") == "native_stdout_json" else "고정 경로 결과 캡처"
                rows.append(f"  {label}={failure['capture_receipt']}; SHA256={failure['capture_receipt_sha256']}")
                if failure.get("suite") == "render_v2":
                    rows.append("  실제 렌더 메트릭=" + shown(failure.get("metrics")))
                    rows.append("  이 payload는 다섯 현상의 미관찰을 기록하며, 단일 이동 함수의 인과나 렌더 수락 통과를 증명하지 않습니다.")
                if "rollout" in failure:
                    rows.append("  관측한 rollout 설정·생략 사유=" + shown(failure["rollout"]))
                if failure.get("scene_sha256"):
                    rows.append(f"  고정 UI scene SHA256={failure['scene_sha256']}")
                    rows.append(f"  QA helper 로그={failure['helper_log']}; SHA256={failure['helper_log_sha256']}")
                    rows.append(f"  QA helper 프로세스={failure['helper_process_report']}; SHA256={failure['helper_process_report_sha256']}")
                    rows.append("  UI 결과 JSON에는 draft 점수 gap/rollout 상세가 없으므로 해당 수치를 이 보고서에서 추정하지 않습니다.")
    rows += ["", "렌더 UI 테스트 (1600×900, 격리 프로필)", "스위트 | 결과 | 종료 코드 | 통과/실패 검사 수 | 증거 JSON"]
    for test in stages.get("S3", {}).get("tests", []):
        checks = test.get("assertions", {})
        failed = checks.get("failed", checks.get("failures"))
        failed = len(failed) if isinstance(failed, list) else failed
        rows.append(f"{test['suite']} | {test['status']} | {test['code']} | {checks.get('passed', '미검사')}/{shown(failed)} | {test.get('report', '미검사')}")
    screenshots = stages.get("S3", {}).get("screenshots", [])
    rows.append(f"필수 화면 스크린샷: {len(screenshots)}장")
    for shot in screenshots:
        rows.append(f"{shot['path']} | {shot['width']}×{shot['height']} | SHA256={shot['sha256']}")
    rows += ["", "냉시작 결정론 (각 케이스를 서로 다른 새 프로세스로 2회 실행)"]
    for item in stages.get("S4", {}).get("cases", []):
        rows.append(f"{item['case_id']}: {'PASS' if item['equal'] else 'FAIL'} | 설정={shown(item['config'])} | 두 서명={shown(item['signatures'])}")
    rows += ["", "원격측정: 시작 커밋 재측정 기준 / 현재 / 수락 기준 / 판정",
             f"실행 상태: {telemetry.get('status', '미실행')}; 수치 수락 판정: {telemetry.get('acceptance_status', '미실행')}",
             f"기준표 출처: {shown(telemetry.get('baseline_source'))}",
             f"동적 로스터: {shown(telemetry.get('expected_roster'))}",
             f"측정량 계획: {shown(telemetry.get('sampling_plan'))}",
             f"통과 게이트: {telemetry.get('passed_gates', '미검사')}; 실패 게이트: {telemetry.get('failed_gates', '미검사')}"]
    for gate in telemetry.get("gates", []):
        detail = {key:gate[key] for key in ("numerator", "denominator", "seed_set", "map", "unit", "error") if key in gate}
        rows.append(f"{gate['metric']} | {shown(gate.get('baseline'))} | {shown(gate.get('observed'))} | {gate['threshold']} | {gate['status']} | {shown(detail)}")
    if telemetry.get("status") == "SKIP":
        rows.append("SKIP: --with-telemetry가 지정되지 않아 원격측정 수락 기준을 검사하지 않았습니다.")
    rows.append("별도 맵 연결성 검사: " + shown(telemetry.get("connectivity_test")))
    rows.append("진단 관측 (수락 기준의 strict pocket과 넓은 pocket region은 서로 다른 지표)")
    rows.extend(shown(value) for value in telemetry.get("observations", []))
    rows.extend("증거 오류: " + shown(value) for value in telemetry.get("errors", []))
    rows += ["", "영웅별 팀전 승률 (개인전 제외; 무승부는 0.5승; Wilson 95%, z=1.96)",
             "영웅 | n_team | 현재 승률 | Wilson 95% | 기준 승률 | 변화량 | 표본 판정"]
    for hero in telemetry.get("heroes", []):
        before = hero.get("baseline") or {}
        rows.append(f"{hero['id']} | {hero['n_team']} | {hero['win_rate']} | {shown(hero['wilson95'])} | {shown(before.get('win_rate'))} | {shown(hero.get('delta_win_rate'))} | {hero.get('sample_status', '미검사')}")
        if hero["wilson95"][1] < .40:
            rows.append("  Wilson 구간 전체가 40% 미만입니다. 이 보고서는 해당 영웅 수치를 자동 조정하지 않습니다.")
    calibration = stages.get("S6", {})
    rows += ["", "보정표 신선도 도장",
             f"판정: {calibration.get('acceptance_status', '미검사')}; 학습 경기 수: {calibration.get('games', '미검사')}",
             f"생성 SIM_SHA: {calibration.get('generated', '미검사')}", f"현재 SIM_SHA: {calibration.get('current', '미검사')}",
             f"알고리즘: {calibration.get('algorithm', '미검사')}; 데이터 지문: {calibration.get('data_fingerprint', '미검사')}",
             f"보정표 파일: {calibration.get('table', '미검사')}; SHA256={calibration.get('table_sha256', '미검사')}",
             calibration.get("holdout_audit", "홀드아웃/첫 픽 감사: 이 배포 보고서에서 별도로 검증하지 않았습니다."),
             "", "내보내기 / 바이너리 검사", "플랫폼 | 파일 | 바이트 수 | SHA256 | 검사 판정 및 구조"]
    for platform, binary in stages.get("S7", {}).get("exports", {}).items():
        audit = stages.get("S8", {}).get("binaries", {}).get(platform)
        rows.append(f"{platform} | {binary['path']} | {binary['bytes']} | {binary['sha256']} | {shown(audit)}")
    smoke_stage = stages.get("S8", {})
    rows += ["", "시험 실행 / 프로필 격리"]
    for smoke in smoke_stage.get("smokes", []):
        rows.append(f"{smoke['label']}: {smoke['status']}, exit={smoke['code']}, APPDATA={smoke['appdata']}, LOCALAPPDATA={smoke['localappdata']}, 로그={smoke['log']}")
    rows.append("창 모드 EXE 사본·원본 SHA 대조: " + shown(smoke_stage.get("rendered_binary")))
    rows.append("창 모드 스크린샷 증거: " + shown(smoke_stage.get("screenshot")))
    rows.append(f"실제 프로필 전후 일치: {shown(smoke_stage.get('real_profiles_unchanged'))}")
    rows.append(f"프로필 비교 대상: {shown(smoke_stage.get('profile_names'))}")
    rows.append(f"프로필 목록·파일 해시 지문: 이전={smoke_stage.get('profiles_before_sha256', '미검사')}, 이후={smoke_stage.get('profiles_after_sha256', '미검사')}")
    fresh = stages.get("S9", {})
    rows.append(f"캐시 없는 새 가져오기/개인전 검사: {fresh.get('status', '미검사')}; 복사={shown(fresh.get('copy'))}; 시작 전 .godot 없음={shown(fresh.get('no_cache_before'))}")
    rows += ["", "압축물 및 추출 후 검사"]
    for name, archive in stages.get("S10", {}).get("packages", {}).get("archives", {}).items():
        rows.append(f"{name}: {archive['path']} | {archive['bytes']} bytes | SHA256={archive['sha256']}")
    if complete:
        post = stages["S11"]
        rows.append("S11 PASS: 모든 압축물을 새 스크래치 폴더에 추출하여 목록·바이트 수·SHA256을 대조했습니다.")
        rows.append("추출된 Windows EXE 시험 실행: " + shown(post.get("windows_smoke")))
        rows.append("분할 조각 재결합: " + shown(post.get("extracted", {}).get("split_reassembly")))
        rows.append(f"실제 프로필 무변경={shown(post.get('real_profiles_unchanged'))}; 기존 릴리스 무변경={shown(post.get('legacy_inventory_unchanged'))}; V2 정식 경로={shown(post.get('final_release_unchanged'))}")
        rows.append(f"보호 대상 목록·파일 해시 지문: 이전={post.get('legacy_before_sha256', '미검사')}, 이후={post.get('legacy_after_sha256', '미검사')}")
    else:
        rows.append("이 문서는 S10 패키징 전에 작성되었습니다. S11 추출·재실행은 아직 증명하지 않았습니다.")
        rows.append(f"완료 여부는 외부 release_completion_v2.json과 POST_PACKAGE_VALIDATION_{config.VERSION}_KO.txt, post_package_validation.json을 함께 확인하십시오.")
    rows += ["", "재현·재개 정책",
             "- --install-helper는 소스에 포함된 qa_helper.ps1/qa_process.py를 zz_work/tools에 설치합니다. 기존 파일은 SHA256 이름의 사본으로 보존한 뒤 갱신합니다.",
             "- 최초 final 실행은 보고서 쓰기 전 전체 Git clean을 요구합니다. --resume-final은 같은 run-id의 최초 clean 기록과 모든 입력 해시가 같을 때만 허용합니다.",
             "- final 재개 시 허용되는 Git 변경은 해당 실행 reports/release_v2/<run-id>/의 untracked 파일뿐입니다. 추적 파일 변경이나 다른 변경은 거부합니다.",
             "- 단계 재사용은 소스·검증 도구·엔진·템플릿·기준표 및 모든 저장된 증거 파일 해시가 일치할 때만 가능합니다. S0/S6/S8/S10/S11은 재검사합니다.",
             "- --continue-on-test-failure는 dry-run에서 map_connectivity_v2 하나의 완료된 assertion FAIL만 후속 검증 진행 대상으로 인정합니다. 다른 실패나 실행·증거 오류에는 적용하지 않습니다.",
             "- 이 옵션은 테스트·지형·수락 기준을 바꾸지 않습니다. 계속 진행한 실패는 FAIL, C2/C8 HOLD, release_eligible=false로 남으며 S11까지 완료해도 명령은 종료 코드 2를 반환합니다.",
             "- --final과 이 옵션을 함께 지정하면 실행 전에 거부합니다. 계속 진행 정책을 바꾸면 별도 run-id를 사용해야 합니다.",
             "- --continue-on-known-draft-failure와 --continue-on-known-preview-failure는 각각 고정된 draft_14/preview_ui_14 완료 실패에만 적용됩니다. 서로 또는 맵 실패 옵션을 대신하지 않습니다.",
             "- --continue-on-known-draft26-failure는 고정 26인·보정표·생성 소스와 draft_14 255 PASS/정확한 6 FAIL, 10개 완전 측정행, 새 캡처 및 정상 프로세스 증거에만 적용됩니다. 기존 22인 드래프트 옵션과 함께 쓸 수 없으며 final/install-helper는 초기화 전에 거부합니다.",
             "- 26인 드래프트 진단을 끝까지 실행해도 원래 테스트와 수락은 FAIL, C6/C8 HOLD, release_eligible=false, 종료 코드 2입니다. 맵·렌더·UI 실패를 허용하지 않으며 각 실패에는 별도의 일치하는 정책이 필요합니다.",
             "- 미리보기 진단은 UI FAIL 105/1, 고정 소스·helper, 새 프로세스·로그·완성 JSON을 검증합니다. 수락은 C7/C8 HOLD, release_eligible=false이며 완료 종료 코드는 2입니다.",
             "- --continue-on-known-render-failure는 고정 render_v2의 native stdout 190 PASS/정확한 5 FAIL과 완전한 메트릭·정상 종료·소스 SHA가 일치할 때만 dry-run을 계속합니다. 테스트 판정은 FAIL, render_v2/C8 HOLD, release_eligible=false이며 완료 종료 코드는 2입니다.",
             "- 렌더 옵션은 다른 실패 옵션을 대신하지 않으며 final/install-helper와 함께 지정하면 초기화 전에 거부합니다. stdout 추출 JSON은 원본 테스트가 쓴 별도 보고서가 아닙니다.",
             "", "검증 불가 항목",
             "- 실제 Linux/macOS 기기에서의 실행, 그래픽 드라이버 및 Gatekeeper 동작은 검증하지 않았습니다.",
             "- Windows Godot의 Linux/macOS 패키지 교차 부팅만으로 해당 운영체제에서의 실행 성공을 주장하지 않습니다.",
             "- macOS는 내장 ad-hoc 서명 구조만 검사하며 Apple 공증·신뢰 검증은 수행하지 않았습니다.",
             "- 운영체제 간 전투 결과의 동일성은 검증하지 않았습니다.",
             "- 수치 기준의 실패나 표본 부족을 50% 승률로 보정하거나 합격으로 바꾸지 않습니다."]
    atomic_bytes(Path(path), ("\n".join(rows) + "\n").encode("utf-8"))
