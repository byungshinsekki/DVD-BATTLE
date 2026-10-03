"""Bundled 26-hero payloads with synthetic processes; no engine/Git/profile use."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import config
import release as r
import draft26_diagnostic as d


class KnownDraft26(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fake-draft26-', dir=HERE)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(patch.stopall)
        self.base = Path(self.temp.name)
        self.project, self.qa = self.base / 'project', self.base / 'qa'
        self.reports = self.base / 'reports'
        self.logs = self.reports / 'logs'
        self.logs.mkdir(parents=True)
        self.report = self.reports / 'headless_assertions/draft_14.json'
        self.log = self.logs / 'headless_draft_14.log'
        self.profiles = self.base / 'scratch/profiles'
        self.profile = self.profiles / 'headless_draft_14'
        self.fixture = HERE / 'test_fixtures/draft_14_roster26_v1'
        patch.multiple(config, QA=self.qa, SCRATCH=self.base / 'scratch', GODOT=self.base / 'FAKE_ENGINE_NEVER_EXECUTED.exe').start()
        for root in (self.project, self.qa):
            for name in d.SOURCES:
                dest = root / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes((self.fixture / (Path(name).name + '.txt')).read_bytes())

    def persist(self, process):
        r.write_json(Path(process['log'] + '.process.json'), process)

    def process(self, log=None, command=None, success=False):
        log = log or self.log
        return dict(suite=d.SUITE, status='PASS' if success else 'FAIL', code=0 if success else 1,
                    timeout=False, pid=123456, seconds=.3, log=str(log),
                    command=command or [str(config.GODOT), '--headless', '--path', str(self.qa), '--script', 'res://tests/draft_14.gd'],
                    problems=[line for line in log.read_text(encoding='utf-8').splitlines() if r.PROBLEMS.search(line)],
                    appdata=str(self.profile / 'Roaming'), localappdata=str(self.profile / 'Local'),
                    cleanup_errors=[], cancelled=False, interrupted=False, exception=None, termination=None)

    def write_outputs(self, success=False):
        value = r.assertion_json((self.fixture / 'report.json').read_text(encoding='utf-8'))
        if success:
            value.update(status='PASS', passed=265, failures=[])
            value['measurements'][8]['search']['rollout'].update(skipped='',games=4,ticks=1200,
                rows=[dict(id=hero,side=side,ticks=300,seconds=10.,value=.2,finished=False) for hero in ('achilles','aphrodite') for side in (0,1)])
            self.log.write_text(d.draft26_payload.HEADER + '\n\nDRAFT 1.4 PASS passed=265 failures=0\n', encoding='utf-8', newline='\n')
        else:
            self.log.write_bytes((self.fixture / 'stdout.txt').read_bytes())
        r.write_json(self.qa / 'reports/draft_14.json', value)

    def fixture_run(self, success=False):
        context = d.prepare(self.project, self.qa, self.report, self.log, self.profile)
        self.write_outputs(success)
        process = self.process(success=success)
        self.persist(process)
        d.capture(context, process, r.assertion_json)
        return process

    def proof(self, process):
        return d.completed_failure(process, self.report, self.project, self.qa, self.profile, r.assertion_json)

    def reject(self, process):
        with self.assertRaises((RuntimeError, ValueError, OSError, KeyError, TypeError)):
            self.proof(process)

    def test_full_observed_payload_fake_lifecycle_still_means_fail(self):
        process = self.fixture_run()
        proof = self.proof(process)
        self.assertEqual((proof['acceptance_status'], proof['passed'], proof['assertion_count'], proof['measurement_count']), ('FAIL', 255, 261, 10))
        self.assertEqual(proof['failed'], list(d.draft26_payload.FAILURES))
        self.assertEqual(proof['sources'], d.SOURCES)
        self.assertEqual(proof['measurements'][9]['search']['candidates'], 17)
        self.assertFalse(self.profile.exists())

    def test_timeout_crash_cancel_cleanup_and_missing_fields_are_rejected(self):
        for key, value in (('timeout',True),('code',-1073741819),('code',0),('code',True),('pid',0),
                           ('cancelled',True),('interrupted',True),('exception','error'),('error','error'),
                           ('termination',{}),('cleanup_errors',['failed']),('seconds',float('inf'))):
            with self.subTest(key=key):
                process = self.fixture_run(); process[key] = value; self.persist(process); self.reject(process)
        for key in ('exception','termination','cancelled','interrupted','cleanup_errors'):
            process = self.fixture_run(); del process[key]; self.persist(process); self.reject(process)

    def test_launch_engine_qa_flags_and_profiles_are_exact(self):
        for index, value in ((0,'py'),(1,'--editor'),(3,str(self.project)),(5,'res://tests/other.gd')):
            process = self.fixture_run(); process['command'][index] = value; self.persist(process); self.reject(process)
        process = self.fixture_run(); process['command'] += ['--','--report=wrong.json']; self.persist(process); self.reject(process)
        for key in ('appdata','localappdata'):
            process = self.fixture_run(); process[key] = str(self.base / 'WRONG_PROFILE_NEVER_READ'); self.persist(process); self.reject(process)

    def test_process_log_report_and_capture_tampering_are_rejected(self):
        for kind in ('process','log','report','capture'):
            process = self.fixture_run()
            if kind == 'process':
                path = Path(str(self.log) + '.process.json'); value = r.assertion_json(path.read_text(encoding='utf-8')); value['pid'] += 1; r.write_json(path,value)
            elif kind == 'capture':
                path = self.report.with_suffix('.capture.json'); value = r.assertion_json(path.read_text(encoding='utf-8')); value['draft26']['source_after'] = {}; r.write_json(path,value)
            else:
                path = self.log if kind == 'log' else self.report; path.write_bytes(path.read_bytes() + b' ')
            self.reject(process)

    def test_each_source_and_table_is_checked_before_and_after(self):
        for root in (self.project,self.qa):
            for name in d.SOURCES:
                path = root / name; original = path.read_bytes()
                path.write_bytes(original + b'\n')
                with self.assertRaisesRegex(RuntimeError,'identity'):
                    d.prepare(self.project,self.qa,self.report,self.log,self.profile)
                path.write_bytes(original)
                context = d.prepare(self.project,self.qa,self.report,self.log,self.profile)
                self.write_outputs(); process = self.process(); self.persist(process)
                path.write_bytes(original + b'\n')
                with self.assertRaisesRegex(RuntimeError,'changed during'):
                    d.capture(context,process,r.assertion_json)
                path.write_bytes(original)

    def test_strict_json_reader_rejects_duplicates_nonfinite_and_truncation(self):
        for text in ('{"status":"FAIL","status":"FAIL"}', '{"value":NaN}', '{"value":1e999}', '{', '[]', 'null'):
            process=self.fixture_run(); self.report.write_text(text,encoding='utf-8',newline='\n')
            path=self.report.with_suffix('.capture.json'); value=r.assertion_json(path.read_text(encoding='utf-8'))
            value['captured_sha256']=r.sha(self.report); value['producer_sha256']=r.sha(self.report)
            value['captured_bytes']=self.report.stat().st_size
            r.write_json(path,value)
            self.reject(process)

    def test_prepare_clears_all_outputs_and_rejects_stale_report(self):
        self.fixture_run()
        context = d.prepare(self.project,self.qa,self.report,self.log,self.profile)
        for path in (self.report,self.qa/'reports/draft_14.json',self.log,Path(str(self.log)+'.process.json')):
            self.assertEqual(path.read_bytes(),b'')
        self.log.write_bytes((self.fixture/'stdout.txt').read_bytes()); process=self.process(); self.persist(process)
        d.capture(context,process,r.assertion_json)  # Raw capture preserves even an empty producer output.
        self.reject(process)  # Evidence classification must reject that empty JSON.

    def test_frozen_proof_survives_later_qa_reuse(self):
        process = self.fixture_run(); expected = self.proof(process)
        for name in d.SOURCES: (self.qa/name).write_bytes(b'later QA copy')
        self.assertEqual(self.proof(process),expected)

    def test_legacy22_reader_rejects26_without_changing_its_policy(self):
        process = self.fixture_run()
        with self.assertRaises(RuntimeError): r.completed_draft_failure(process,self.report,self.qa)
        self.assertEqual(r.known_draft_failure_policy(SimpleNamespace(final=False,dry_run=True))['required_passed'],231)

    def test_true_pass_remains_pass_and_is_not_known_failure(self):
        process = self.fixture_run(success=True)
        data = d.completed_pass(process,self.report,self.project,self.qa,self.profile,r.assertion_json)
        self.assertEqual((data['status'],data['passed'],data['failures']),('PASS',265,[]))
        self.reject(process)
        process = self.fixture_run()
        with self.assertRaises(RuntimeError): d.completed_pass(process,self.report,self.project,self.qa,self.profile,r.assertion_json)

    def test_pass_cannot_claim_zero_games_gap_or_unbalanced_trials(self):
        for invalid in ('gap261','gap265','unbalanced','horizon'):
            context=d.prepare(self.project,self.qa,self.report,self.log,self.profile)
            self.write_outputs(success=True)
            path=self.qa/'reports/draft_14.json'; value=r.assertion_json(path.read_text(encoding='utf-8'))
            rollout=value['measurements'][8]['search']['rollout']
            if invalid.startswith('gap'):
                rollout.update(skipped='gap',games=0,ticks=0,rows=[])
                value['passed']=int(invalid[3:])
                self.log.write_text(d.draft26_payload.HEADER+f"\n\nDRAFT 1.4 PASS passed={value['passed']} failures=0\n",encoding='utf-8',newline='\n')
            elif invalid=='unbalanced': rollout['rows'][1]['side']=0
            else: rollout['horizon_ticks']=400
            r.write_json(path,value); process=self.process(success=True); self.persist(process)
            d.capture(context,process,r.assertion_json)
            with self.assertRaises(RuntimeError): d.completed_pass(process,self.report,self.project,self.qa,self.profile,r.assertion_json)

    def test_final_install_and_two_roster_flags_stop_before_io(self):
        with patch.object(r,'Release') as ctor, patch.object(r,'ensure_helper') as install:
            for mode in ('--final','--install-helper'):
                with self.assertRaises(RuntimeError): r.main([mode,'--continue-on-known-draft26-failure'])
            with self.assertRaises(RuntimeError): r.main(['--dry-run','--continue-on-known-draft26-failure','--continue-on-known-draft-failure'])
            ctor.assert_not_called(); install.assert_not_called()
        with patch.object(r,'git') as git:
            with self.assertRaises(RuntimeError): r.Release(SimpleNamespace(final=True,dry_run=False,continue_on_known_draft26_failure=True))
            git.assert_not_called()

    def test_resume_flag_and_pinned_source_changes_stop_before_profile_read(self):
        pg=self.project/'project.godot'; pg.write_text('synthetic',encoding='utf-8')
        options=SimpleNamespace(final=False,dry_run=True,out=self.base/'scratch/out',run_id='fake_resume',with_telemetry=False,
                                baseline_summary=None,resume_final=False,continue_on_test_failure=False,continue_on_known_draft26_failure=False)
        def fake_git(_root,*args): return '' if args[0]=='status' else 'fakehead'
        with patch.object(config,'PROJECT',self.project),patch.object(config,'RELEASE',self.base/'final'),patch.object(r,'git',side_effect=fake_git), \
             patch.object(r,'runtime_hashes',return_value={}),patch.object(r,'verification_hashes',return_value={}), \
             patch.object(r,'source_paths',return_value=[(pg,'project.godot')]),patch.object(r.Release,'binary_hashes',return_value={}), \
             patch.object(r.Release,'tool_hashes',return_value={}),patch.object(r,'legacy_inventory',return_value={}), \
             patch.dict(os.environ,{'APPDATA':str(self.base/'FAKE_PROFILE_NEVER_READ')}):
            with patch.object(r,'profile_inventory',return_value={}): r.Release(options)
            options.continue_on_known_draft26_failure=True
            with patch.object(r,'profile_inventory',side_effect=AssertionError('must stop before actual profile')):
                with self.assertRaisesRegex(RuntimeError,'Resume input changed'): r.Release(options)
            options.continue_on_known_draft26_failure=False
            with patch.object(d,'SOURCES',{**d.SOURCES,'scripts/data/draft_calibration.gd':'0'*64}), \
                 patch.object(r,'profile_inventory',side_effect=AssertionError('must stop before actual profile')):
                with self.assertRaisesRegex(RuntimeError,'Resume input changed'): r.Release(options)

    def run_s2(self, enabled=True, other=None, success=False, fresh=True, missing=False, map_enabled=False, render_enabled=False):
        obj=object.__new__(r.Release)
        obj.options=SimpleNamespace(final=False,dry_run=True,continue_on_test_failure=map_enabled,continue_on_known_draft26_failure=enabled,
                                    continue_on_known_render_failure=render_enabled,
                                    jobs=1,with_telemetry=True,baseline_summary=None)
        obj.test_failure_policy=r.test_failure_policy(obj.options)
        obj.project,obj.reports,obj.logs,obj.out,obj.profiles=self.project,self.reports,self.logs,self.base/'out',self.profiles
        obj.out.mkdir(exist_ok=True); obj.state_path=self.reports/'run_state.json'
        obj.source=dict(head='fake',input_sha256='f'*64); obj.identity=dict(known_draft26_failure_policy=obj.known_draft26_failure_policy)
        obj.state,obj.unchanged=dict(stages={},complete=False),lambda:None
        def godot(args,name,check=False):
            suite=name.removeprefix('headless_'); log=obj.logs/(name+'.log'); command=[str(config.GODOT),*map(str,args)]
            if suite==d.SUITE:
                self.assertNotIn('--',command)
                if enabled:
                    self.assertEqual(self.report.read_bytes(),b''); self.assertEqual((self.qa/'reports/draft_14.json').read_bytes(),b'')
                if fresh: self.write_outputs(success)
                process=self.process(log,command,success)
            elif suite=='map_connectivity_v2':
                failures=['ruined_gate all radii and gate states: [closed courtyard]','ruined_gate/r28 all radii and gate states: [closed courtyard]']
                value=dict(suite=suite,status='FAIL',passed=33,failed=failures,step=8.0,radii=[14,16,18,20,22,24],
                           maps=[dict(sample=name,seconds=.25,issues=['closed courtyard'] if name in ('ruined_gate','ruined_gate/r28') else []) for name in sorted(r.CONNECTIVITY_SAMPLES)],historical_thorn=['historical corner proof'])
                lines=[f"MAP_CONNECTIVITY_V2 sample={row['sample']} seconds=0.25 problems={len(row['issues'])}" for row in value['maps']]
                lines+=['ERROR: MAP_CONNECTIVITY_V2 '+label for label in failures]+['MAP_CONNECTIVITY_V2 FAIL passed=33 failed=2']
                log.write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
                r.write_json(Path(next(arg[9:] for arg in command if arg.startswith('--report='))),value)
                process=self.process(log,command); process['suite']=suite
            elif suite=='render_v2':
                log.write_bytes((HERE/'test_fixtures/render_v2_known_v1/stdout.txt').read_bytes())
                process=self.process(log,command); process['suite']=suite
                process['appdata']=str(self.profiles/'headless_render_v2/Roaming'); process['localappdata']=str(self.profiles/'headless_render_v2/Local')
            else:
                log.write_text('ERROR: unexpected fixture failure\n',encoding='utf-8'); process=self.process(log,command); process['suite']=suite
            self.persist(process); return process
        obj.godot=godot
        suites=[] if missing else [d.SUITE]
        if other: suites.extend(other if isinstance(other,list) else [other])
        if 'render_v2' in suites:
            for root in (self.project,self.qa): (root/'tests/render_v2.gd').write_bytes((HERE/'test_fixtures/render_v2_known_v1/render_v2.gd.txt').read_bytes())
        with patch.object(r,'copy_project',return_value={}),patch.object(r,'import_project',return_value=[]), \
             patch.object(r,'REQUIRED_HEADLESS',set()),patch.object(r,'discover_tests',return_value=dict(headless=suites)):
            result=obj.S2()
        return obj,result

    def test_default_does_not_create26_exception_or_capture(self):
        _,result=self.run_s2(enabled=False)
        self.assertEqual((result['status'],result['continued_test_failures']),('FAIL',[]))
        self.assertNotIn('assertion_capture',result['tests'][0])

    def test_s2_preserves_failure_and_freezes_raw_process_output_hashes(self):
        obj,result=self.run_s2()
        self.assertEqual((result['status'],result['acceptance_status'],result['release_eligible']),('WARN','FAIL',False))
        test=result['tests'][0]; self.assertEqual(test['status'],'FAIL')
        obj.stage('S2',lambda:result)
        for path in (test['log'],test['log']+'.process.json',test['assertion_report'],test['assertion_capture']):
            self.assertIn(path,obj.state['stages']['S2']['output_hashes'])

    def test_map_render_preview_and_unknown_failure_do_not_inherit_permission(self):
        for other in ('map_connectivity_v2','render_v2','preview_ui_14','environment_153'):
            _,result=self.run_s2(other=other)
            self.assertEqual((result['status'],result['continued_test_failures']),('FAIL',[]))

    def test_all_three_failures_require_all_three_independent_flags(self):
        for mask in range(8):
            with self.subTest(mask=mask):
                _,result=self.run_s2(enabled=bool(mask&1),map_enabled=bool(mask&2),render_enabled=bool(mask&4),other=['map_connectivity_v2','render_v2'])
                self.assertEqual(result['status'],'WARN' if mask==7 else 'FAIL')
                self.assertFalse(result['release_eligible'])
                self.assertEqual(result['acceptance_status'],'FAIL')
                self.assertEqual({row['suite'] for row in result['continued_test_failures']}, {'draft_14','map_connectivity_v2','render_v2'} if mask==7 else set())

    def test_missing_discovery_stale_output_and_real_pass_boundaries(self):
        with self.assertRaisesRegex(RuntimeError,'requires the draft_14 fixture'): self.run_s2(missing=True)
        _,result=self.run_s2(fresh=False)
        self.assertEqual(result['status'],'FAIL'); self.assertIn('assertion_evidence_error',result['tests'][0])
        _,result=self.run_s2(success=True)
        self.assertEqual((result['status'],result['acceptance_status'],result['continued_test_failures']),('PASS','PASS',[]))

    def test_draft26_option_does_not_enable_ui_policy(self):
        obj=object.__new__(r.Release); obj.project=self.project
        obj.options=SimpleNamespace(final=False,dry_run=True,continue_on_known_draft26_failure=True)
        with patch.object(obj,'helper',side_effect=RuntimeError('ordinary UI failure stops')) as helper, \
             patch.object(r,'discover_tests',return_value=dict(rendered=['preview_ui_14'])),patch.object(r,'REQUIRED_RENDERED',{'preview_ui_14'}):
            with self.assertRaisesRegex(RuntimeError,'ordinary UI failure'): obj.S3()
            helper.assert_called_once_with('uitest','rendered_preview_ui_14',['-Suite','preview_ui_14'])

    def test_completed_diagnostic_is_fail_exit_two_with_full_policy_provenance(self):
        obj,result=self.run_s2()
        for index in range(12):
            value=dict(status='PASS')
            if index==0: value.update(known_draft26_failure_policy=obj.known_draft26_failure_policy)
            if index==2: value=result
            if index==10: r.write_json(obj.out/'release_manifest_v2.json',dict(synthetic=True))
            setattr(obj,f'S{index}',lambda item=value:copy.deepcopy(item))
        self.assertEqual(obj.execute(),2)
        completion=r.assertion_json((obj.out/'release_completion_v2.json').read_text(encoding='utf-8'))
        self.assertEqual((completion['complete'],completion['execution_complete'],completion['acceptance_status'],completion['release_eligible'],completion['exit_code']),(True,True,'FAIL',False,2))
        for value in (completion,obj.state,r.assertion_json((obj.out/'post_package_validation.json').read_text(encoding='utf-8'))):
            self.assertEqual(value['known_draft26_failure_policy'],obj.known_draft26_failure_policy)
        text=(obj.out/'POST_PACKAGE_VALIDATION_2.0_KO.txt').read_text(encoding='utf-8')
        for label in d.draft26_payload.FAILURES: self.assertIn('FAIL: '+label,text)
        self.assertIn(d.SOURCES['scripts/data/draft_calibration.gd'],text)
        self.assertIn('26인 드래프트 실패 진단 정책',text)

    def test_infrastructure_stop_never_writes_completed_acceptance(self):
        obj,_=self.run_s2()
        with self.assertRaisesRegex(RuntimeError,'infrastructure blocked'):
            obj.stage('S2',lambda:(_ for _ in ()).throw(RuntimeError('infrastructure blocked')))
        self.assertFalse(obj.state['complete']); self.assertFalse(obj.state['release_eligible'])
        with patch.object(r,'Release',return_value=SimpleNamespace(execute=lambda:2)):
            self.assertEqual(r.main(['--dry-run','--continue-on-known-draft26-failure','--out',str(self.base/'out')]),2)


if __name__=='__main__':
    unittest.main(verbosity=2)
