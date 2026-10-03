"""Fake-data release regression tests. No Godot, downloads, Git mutation or real profiles.

Run with: py -X utf8 -m unittest discover -s zz_work/c8_prepare -p test_infrastructure.py -v
"""
from contextlib import ExitStack
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import random
import stat
import struct
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import zipfile

import audit
import common
import config
import package
import release


def pck(engine=(4, 7, 2)):
    return b"GDPC" + struct.pack("<5I", 3, *engine, 0) + bytes(40)


def embedded(binary):
    payload = pck()
    return binary + payload + struct.pack("<Q", len(payload)) + b"GDPC"


def pe():
    data = bytearray(576)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 132, 0x8664, 1, 0, 0, 0, 112, 2)
    struct.pack_into("<H", data, 152, 0x20B)
    struct.pack_into("<I", data, 152 + 60, 512)
    data[264:272] = b".text\0\0\0"
    struct.pack_into("<II", data, 264 + 16, 64, 512)
    return embedded(data)


def elf():
    data = bytearray(136)
    data[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHI", data, 16, 2, 62, 1)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HHH", data, 52, 64, 56, 1)
    struct.pack_into("<II6Q", data, 64, 1, 5, 120, 0, 0, 16, 16, 8)
    return embedded(data)


def macho_slice(cpu):
    # Deliberately synthetic signature: tests structure only, not Apple's verifier.
    directory = bytearray(80)
    struct.pack_into(">9I4BI", directory, 0, 0xFADE0C02, 80, 0x20001, 2, 48, 44, 0, 1, 64, 32, 2, 0, 12, 0)
    directory[44:48] = b"app\0"
    directory[48:80] = hashlib.sha256(b"fake signature fixture").digest()
    blob = struct.pack(">IIIII", 0xFADE0CC0, 100, 1, 0, 20) + directory
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 16, 0, 0)
    return header + struct.pack("<4I", 0x1D, 16, 64, len(blob)) + bytes(16) + blob


def macho():
    first, second = macho_slice(0x1000007), macho_slice(0x100000C)
    data = bytearray(256 + len(second))
    struct.pack_into(">II", data, 0, 0xCAFEBABE, 2)
    struct.pack_into(">5I", data, 8, 0x1000007, 0, 64, len(first), 4)
    struct.pack_into(">5I", data, 28, 0x100000C, 0, 256, len(second), 4)
    data[64:64 + len(first)] = first
    data[256:] = second
    return data


def zip_bytes(path, entries):
    """entries: (name, bytes, Unix mode), supporting intentionally unsafe names."""
    with zipfile.ZipFile(path, "w") as archive:
        for name, payload, mode in entries:
            info = zipfile.ZipInfo(name, config.ARCHIVE_TIME)
            info.create_system = 3
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload)


def mac_entries(binary=None, executable_mode=0o755, version="2.0.0"):
    base = "DVD.app/Contents/"
    plist = dict(CFBundleShortVersionString=version, CFBundleVersion=version,
                 CFBundleExecutable="DVD", CFBundleIdentifier="local.dvd.fixture")
    return [(base + "Info.plist", plistlib.dumps(plist), stat.S_IFREG | 0o644),
            (base + "MacOS/DVD", bytes(binary if binary is not None else macho()), stat.S_IFREG | executable_mode),
            (base + "Resources/DVD.pck", pck(), stat.S_IFREG | 0o644),
            (base + "_CodeSignature/CodeResources", plistlib.dumps({"files": {}}), stat.S_IFREG | 0o644)]


class ScratchTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory(prefix="test-fixture-", dir=Path(__file__).parent)))
        self.scratch = self.root / "scratch"
        self.project = self.root / "source"
        self.out = self.scratch / "release"
        self.qa_root = self.root / "qa"
        self.release = self.root / "DVD_BATTLE_2.0_RELEASE"
        self.stack.enter_context(patch.multiple(config, SCRATCH=self.scratch, QA=self.qa_root / "release_v2/project", RELEASE=self.release))

    def put(self, relative, payload=b"fixture"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path


class PathAndProcessTests(ScratchTest):
    def test_output_boundaries_and_final_root(self):
        self.assertEqual(common.guard_output(self.out), self.out.resolve())
        self.assertEqual(common.guard_output(self.release, final=True), self.release.resolve())
        self.assertEqual(common.guard_output(self.release / "nested", final=True), (self.release / "nested").resolve())
        for path in (self.scratch, self.root, self.release, self.scratch / ".." / "outside"):
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                common.guard_output(path)
        for path in (self.root / "DVD_BATTLE_1.5.3/file", self.scratch / "DVD_BATTLE_1.2.1_RECOVERY_WORK/file"):
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, "Legacy"):
                common.safe_write_path(path)

    def test_symlink_or_junction_redirect_is_rejected(self):
        target = self.root / "target"
        target.mkdir()
        link = self.root / "link"
        try:
            link.symlink_to(target, target_is_directory=True)
        except OSError:
            if os.name != "nt":
                raise
            import subprocess
            result = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True)
            if result.returncode:
                self.skipTest("Host does not allow either symbolic links or junctions")
        self.addCleanup(lambda: link.rmdir() if link.exists() and not link.is_symlink() else link.unlink(missing_ok=True))
        with self.assertRaisesRegex(RuntimeError, "symlink/junction"):
            common.safe_write_path(link / "file")

    def test_atomic_replacement_failure_preserves_old_file_and_cleans_temp(self):
        target = self.put("scratch/result.json", b"old")
        with patch.object(common.os, "replace", side_effect=OSError("fixture interruption")):
            with self.assertRaises(OSError):
                common.atomic_bytes(target, b"new")
        self.assertEqual(target.read_bytes(), b"old")
        self.assertEqual(list(target.parent.iterdir()), [target])

    def test_atomic_copy_preserves_source_and_hardlinked_target(self):
        protected = self.put("original", b"original")
        target = self.root / "hardlink"
        os.link(protected, target)
        source = self.put("new", b"replacement")
        common.atomic_copy(source, target)
        self.assertEqual(target.read_bytes(), b"replacement")
        self.assertEqual(protected.read_bytes(), b"original")

    def test_copy_project_is_disjoint_excludes_tools_scratch_and_replaces_stale(self):
        self.put("source/project.godot", b'config/custom_user_dir_name="REAL_PROFILE"\n')
        self.put("source/scripts/game.gd", b"extends Node\n")
        self.put("source/zz_work/secret", b"do not copy")
        self.put("source/.git/config", b"do not copy")
        self.put("source/reports/stale.json", b"do not copy")
        self.put("qa/release_v2/project/stale.txt")
        destination = config.QA
        common.copy_project(self.project, destination, fresh=True)
        self.assertIn(config.QA_PROFILE, (destination / "project.godot").read_text())
        self.assertFalse((destination / "stale.txt").exists())
        self.assertFalse((destination / "zz_work").exists())
        self.assertFalse((destination / "reports/stale.json").exists())
        self.assertTrue((destination / "reports/.gdignore").is_file())
        self.assertIn("REAL_PROFILE", (self.project / "project.godot").read_text())
        for bad in (self.qa_root, self.root, self.project, self.project / "copy"):
            with self.subTest(destination=bad), self.assertRaises(RuntimeError):
                common.copy_project(self.project, bad)
        # Even a scratch tree cannot be an ancestor of its source.
        nested_source = self.scratch / "parent/source"
        nested_source.mkdir(parents=True)
        with self.assertRaisesRegex(RuntimeError, "disjoint"):
            common.copy_project(nested_source, nested_source.parent)

    def test_process_redirects_both_profiles_and_records_pid_and_errors(self):
        code = "import json,os;print(json.dumps({k:os.environ[k] for k in ('APPDATA','LOCALAPPDATA')}))"
        profile, log = self.scratch / "profile", self.out / "process.log"
        result = common.run([sys.executable, "-c", code], log, profile, timeout=10)
        env = json.loads(log.read_text())
        self.assertEqual(env["APPDATA"], str(profile / "Roaming"))
        self.assertEqual(env["LOCALAPPDATA"], str(profile / "Local"))
        self.assertGreater(result["pid"], 0)
        self.assertEqual(result["status"], "PASS")
        with self.assertRaisesRegex(RuntimeError, "Process failed"):
            common.run([sys.executable, "-c", "print('SCRIPT ERROR: fake')"], log, profile, timeout=10)
        self.assertEqual(json.loads(log.with_suffix(".log.process.json").read_text())["status"], "FAIL")

    def test_process_timeout_is_bounded_and_not_a_pass(self):
        start = time.monotonic()
        result = common.run([sys.executable, "-c", "import time;time.sleep(30)"], self.out / "timeout.log", self.scratch / "profile", timeout=0.2, check=False)
        self.assertLess(time.monotonic() - start, 10)
        self.assertTrue(result["timeout"])
        self.assertEqual(result["code"], 124)
        self.assertEqual(result["status"], "FAIL")
        for seconds in (0, -1, 901):
            with self.subTest(seconds=seconds), self.assertRaisesRegex(RuntimeError, "Timeout"):
                common.run([], self.out / "invalid.log", self.scratch / "profile", timeout=seconds)

    @unittest.skipUnless(os.name == "nt", "Windows PID tree fallback")
    def test_windows_tree_timeout_still_kills_own_child(self):
        import subprocess
        child = Mock(pid=123456789)
        child.wait.side_effect = [subprocess.TimeoutExpired("fixture", 0.1), 0]
        child.poll.return_value = None
        child.kill.side_effect = lambda: setattr(child.poll, 'return_value', 0)
        with patch.object(common.subprocess, "Popen", return_value=child), patch.object(common.subprocess, "run", side_effect=subprocess.TimeoutExpired("taskkill", 25)) as killer:
            result = common.run(["fake-never-executed"], self.out / "timeout.log", self.scratch / "profile", timeout=0.1, check=False)
        executable = Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32/taskkill.exe'
        self.assertEqual(killer.call_args.args[0], [str(executable), "/PID", "123456789", "/T", "/F"])
        child.kill.assert_called_once_with()
        self.assertEqual(result["code"], 124)
        self.assertEqual(result['status'], 'FAIL')
        self.assertTrue(result['cleanup_errors'])

    def test_inventory_detects_new_profiles_content_and_empty_directories(self):
        appdata = self.root / "appdata"
        self.put("appdata/DVD_BATTLE_V20_DEVELOPER/settings", b"before")
        before = common.profile_inventory(appdata, ["DVD_BATTLE_MISSING"])
        self.put("appdata/DVD_BATTLE_NEW/settings", b"new")
        (appdata / "DVD_BATTLE_V20_DEVELOPER/empty").mkdir()
        after = common.profile_inventory(appdata, ["DVD_BATTLE_MISSING"])
        self.assertNotEqual(before, after)
        self.assertIn("DVD_BATTLE_NEW", after)
        self.assertEqual(after["DVD_BATTLE_V20_DEVELOPER"]["directories"], ["empty"])
        self.assertFalse(before["DVD_BATTLE_MISSING"]["exists"])

    def test_release_inventory_detects_existing_content_changes(self):
        path = self.put("DVD_BATTLE_2.0_RELEASE/existing", b"one")
        before = common.legacy_inventory(self.root)
        path.write_bytes(b"two")
        after = common.legacy_inventory(self.root)
        self.assertNotEqual(before, after)
        self.assertNotIn(config.RELEASE.name, common.legacy_inventory(self.root, include_release=False))

    def test_resource_import_uid_and_powershell_are_fingerprinted(self):
        self.put("source/scripts/node.gd.uid", b"uid://before")
        self.put("source/assets/fonts/font.otf.import", b"allow_system_fallback=false")
        self.put("source/tools/runner.ps1", b"# fixture")
        runtime = common.runtime_hashes(self.project)
        verification = common.verification_hashes(self.project)
        self.assertIn("scripts/node.gd.uid", runtime)
        self.assertIn("assets/fonts/font.otf.import", runtime)
        self.assertIn("tools/runner.ps1", verification)


class ArchiveTests(ScratchTest):
    def test_portable_members_and_adversarial_names(self):
        self.assertEqual(package.valid_member("디렉터리/문서 with spaces.gd").as_posix(), "디렉터리/문서 with spaces.gd")
        for name in ("", "/absolute", "../escape", "a/../b", "a//b", "./x", "a\\b", "C:/x", "a\0x", "a/x.", "x ", "con", "NUL.txt", "a/COM1.txt", "a/LPT9", "x\ny"):
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                package.valid_member(name)

    def test_zip_collisions_links_and_shadowing_are_rejected(self):
        target = self.root / "bad.zip"
        bad_sets = [
            [("Readme", b"x", stat.S_IFREG | 0o644), ("README", b"y", stat.S_IFREG | 0o644)],
            [("a", b"b", stat.S_IFLNK | 0o777)],
            [("../escape", b"x", stat.S_IFREG | 0o644)],
            [("a", b"x", stat.S_IFREG | 0o644), ("a/b", b"y", stat.S_IFREG | 0o644)],
            [("a/b", b"x", stat.S_IFREG | 0o644), ("a", b"y", stat.S_IFREG | 0o644)],
            [("fifo", b"x", stat.S_IFIFO | 0o644)],
        ]
        for entries in bad_sets:
            with self.subTest(entries=entries):
                zip_bytes(target, entries)
                with self.assertRaises(RuntimeError):
                    package.inspect_archive(target)

    def test_tar_links_and_wrong_executable_permissions_are_rejected(self):
        target = self.root / "bad.tar.gz"
        for mode, kind in ((0o644, tarfile.REGTYPE), (0o755, tarfile.SYMTYPE)):
            with self.subTest(mode=mode, kind=kind):
                with tarfile.open(target, "w:gz") as archive:
                    info = tarfile.TarInfo("game.x86_64")
                    info.mode, info.type, info.size, info.linkname = mode, kind, 1 if kind == tarfile.REGTYPE else 0, "../x"
                    archive.addfile(info, io.BytesIO(b"x") if info.size else None)
                with self.assertRaises(RuntimeError):
                    package.inspect_archive(target)

    def test_source_path_listing_uses_nul_for_unicode_and_excludes_private_files(self):
        self.put("source/scripts/한글 with spaces.gd")
        self.put("source/.git/config")
        self.put("source/zz_work/private")
        self.put("source/AGENTS.md")
        names = "scripts/한글 with spaces.gd\0.git/config\0zz_work/private\0AGENTS.md\0"
        with patch.object(package, "git", return_value=names) as git_mock:
            paths = package.source_paths(self.project)
        self.assertEqual([name for _, name in paths], ["scripts/한글 with spaces.gd"])
        self.assertIn("-z", git_mock.call_args.args)
        with patch.object(package, "git", return_value="../outside\0"), self.assertRaises(RuntimeError):
            package.source_paths(self.project)


class PackagingTests(ScratchTest):
    def setUp(self):
        super().setUp()
        self.stack.enter_context(patch.multiple(config, MAX_ATTACHMENT_BYTES=1000, SPLIT_BYTES=600))
        self.put("source/project.godot", b'config/custom_user_dir_name="FIXTURE"\n')
        self.put("source/tools/한글 script.py", b"#!/usr/bin/env python3\nprint('hello')\n")
        rng = random.Random(2048)
        self.put("source/icon.svg", rng.randbytes(3500))
        self.source_names = ["icon.svg", "project.godot", "tools/한글 script.py"]
        self.exports = {}
        for kind, relative in (("windows", "windows/DVD.exe"), ("linux", "linux/DVD.x86_64")):
            path = self.put("scratch/release/" + relative, rng.randbytes(4096))
            self.exports[kind] = {"path": str(path), "sha256": common.sha(path)}
        mac = self.out / "macos/DVD.zip"
        mac.parent.mkdir()
        zip_bytes(mac, mac_entries())
        self.exports["macos"] = {"path": str(mac), "sha256": common.sha(mac)}
        self.validation = self.put("scratch/release/VALIDATION_2.0_KO.txt", "가짜 자료 검증 보고서\n".encode())
        self.stack.enter_context(patch.object(package, "git", side_effect=self.fake_git))

    def fake_git(self, _project, *args):
        if "--stage" in args:
            return "\0".join(("100755" if name.startswith("tools/") else "100644") + " " + "0" * 40 + " 0\t" + name for name in self.source_names) + "\0"
        return "\0".join(self.source_names) + "\0"

    def build(self):
        return package.package_all(self.project, self.out, self.exports, self.validation)

    def test_archives_are_reproducible_preserve_modes_and_split_hashes(self):
        first = self.build()
        second = self.build()
        self.assertEqual(first, second)
        self.assertEqual(first["archives"]["source"]["members"]["tools/한글 script.py"]["mode"], 0o755)
        self.assertEqual(first["archives"]["linux"]["members"]["DVD.x86_64"]["mode"], 0o755)
        self.assertEqual(first["archives"]["macos"]["sha256"], self.exports["macos"]["sha256"])
        self.assertTrue(first["parts"])
        self.assertTrue(all(part["bytes"] < config.MAX_ATTACHMENT_BYTES for part in first["parts"]))
        result = package.verify_and_extract(first, self.scratch / "extraction")
        self.assertEqual(set(result["archives"]), {"windows", "linux", "macos", "source"})
        self.assertTrue(all(entry["status"] == "PASS" for entry in result["split_reassembly"].values()))

    def test_repeated_extraction_is_fresh_and_does_not_reuse_stale_files(self):
        packages = self.build()
        first = package.verify_and_extract(packages, self.scratch / "extraction")
        first_root = Path(first["archives"]["windows"]["root"])
        (first_root / "DVD.exe").unlink()
        (first_root / "unrelated-stale").write_bytes(b"bad")
        second = package.verify_and_extract(packages, self.scratch / "extraction")
        self.assertNotEqual(first["extraction_session"], second["extraction_session"])
        self.assertTrue((Path(second["archives"]["windows"]["root"]) / "DVD.exe").is_file())

    def test_staging_failure_does_not_replace_previous_archives(self):
        previous = self.build()
        previous_hashes = {name: common.sha(entry["path"]) for name, entry in previous["archives"].items()}
        inspect = package.inspect_archive
        def mutate_source(path):
            result = inspect(path)
            if Path(path).name.endswith("_Windows.zip"):
                (self.project / "icon.svg").write_bytes(b"changed concurrently")
            return result
        with patch.object(package, "inspect_archive", side_effect=mutate_source), self.assertRaisesRegex(RuntimeError, "Source files changed"):
            self.build()
        self.assertEqual(previous_hashes, {name: common.sha(entry["path"]) for name, entry in previous["archives"].items()})
        self.assertFalse(list(self.out.glob(".package-stage-*")))

    def test_validation_or_source_set_changes_fail_before_publication(self):
        inspect = package.inspect_archive
        def mutate_validation(path):
            result = inspect(path)
            if Path(path).name.endswith("_Windows.zip"):
                self.validation.write_bytes(b"changed concurrently")
            return result
        with patch.object(package, "inspect_archive", side_effect=mutate_validation), self.assertRaisesRegex(RuntimeError, "Validation document changed"):
            self.build()
        self.assertFalse(list(self.out.glob("DVD_BATTLE*.zip")))
        original_list = package.source_paths(self.project)
        added = self.put("source/new.txt")
        with patch.object(package, "source_paths", side_effect=[original_list, original_list + [(added, "new.txt")]]), self.assertRaisesRegex(RuntimeError, "Source file list changed"):
            self.build()

    def test_export_changed_before_packaging_is_rejected(self):
        Path(self.exports["windows"]["path"]).write_bytes(b"changed")
        with self.assertRaisesRegex(RuntimeError, "Export changed"):
            self.build()

    def test_archive_and_checksum_tampering_are_detected(self):
        packages = self.build()
        checksum = Path(packages["checksums"]["path"])
        original = checksum.read_bytes()
        checksum.write_bytes(b"forged\n")
        with self.assertRaisesRegex(RuntimeError, "Checksum listing changed"):
            package.verify_and_extract(packages, self.scratch / "extraction")
        packages["checksums"]["sha256"] = common.sha(checksum)
        with self.assertRaisesRegex(RuntimeError, "disagrees"):
            package.verify_and_extract(packages, self.scratch / "extraction")
        checksum.write_bytes(original)
        packages["checksums"]["sha256"] = common.sha(checksum)
        archive = Path(packages["archives"]["windows"]["path"])
        with zipfile.ZipFile(archive, "a") as stream:
            stream.writestr("forged", b"extra")
        with self.assertRaisesRegex(RuntimeError, "Archive metadata or bytes changed"):
            package.verify_and_extract(packages, self.scratch / "extraction")

    def test_split_tampering_and_duplicate_indices_are_detected(self):
        packages = self.build()
        part = packages["parts"][0]
        path = Path(part["path"])
        original = path.read_bytes()
        path.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        with self.assertRaisesRegex(RuntimeError, "Split part byte/hash mismatch"):
            package.verify_and_extract(packages, self.scratch / "extraction")
        path.write_bytes(original)
        malformed = copy.deepcopy(packages)
        malformed["parts"][1]["index"] = malformed["parts"][0]["index"]
        with self.assertRaisesRegex(RuntimeError, "Missing/duplicate split index"):
            package.verify_and_extract(malformed, self.scratch / "extraction")

    def test_rebuild_removes_only_its_stale_split_files(self):
        packages = self.build()
        own = Path(packages["archives"]["windows"]["path"] + ".part999")
        own.write_bytes(b"stale")
        unrelated = self.put("scratch/release/other.zip.part999", b"keep")
        ambiguous = self.put("scratch/release/DVD_BATTLE_2.0_Windows.zip.part-note", b"keep")
        self.build()
        self.assertFalse(own.exists())
        self.assertEqual(unrelated.read_bytes(), b"keep")
        self.assertEqual(ambiguous.read_bytes(), b"keep")


class BinaryAuditTests(ScratchTest):
    def test_valid_minimal_pe_elf_and_pck_structures(self):
        windows = self.put("windows.exe", pe())
        linux = self.put("linux.x86_64", elf())
        self.assertEqual(audit.inspect_binary("windows", windows)["architecture"], "x86_64")
        self.assertEqual(audit.inspect_binary("linux", linux)["load_segments"], 1)
        for path in (windows, linux):
            result = audit.audit_pck(path)
            self.assertEqual(result["embedded_pck"]["engine_version"], "4.7.2")
            self.assertFalse(result["native_execution_tested_by_this_audit"])
        with self.assertRaisesRegex(RuntimeError, "Unknown binary platform"):
            audit.inspect_binary("unknown", windows)

    def test_binary_audit_rejects_stale_export_hash_before_running_checks(self):
        path = self.put("windows.exe", pe())
        exports = {kind: {"path": str(path), "sha256": "0" * 64} for kind in ("windows", "linux", "macos")}
        with patch.object(audit, "inspect_binary") as inspector, self.assertRaisesRegex(RuntimeError, "Export changed before binary audit"):
            audit.audit_all(exports)
        inspector.assert_not_called()

    def test_pe_machine_sections_offsets_and_truncation_fail(self):
        for offset, fmt, value in ((60, "<I", 999999), (132, "<H", 0x14C), (134, "<H", 0), (152, "<H", 0x10B), (212, "<I", 10), (284, "<I", 999999)):
            data = bytearray(pe())
            struct.pack_into(fmt, data, offset, value)
            with self.subTest(offset=offset), self.assertRaises(RuntimeError):
                audit.inspect_binary("windows", self.put("bad.exe", data))
        with self.assertRaises(RuntimeError):
            audit.inspect_binary("windows", self.put("truncated.exe", b"MZ"))

    def test_elf_machine_table_and_load_bounds_fail(self):
        for offset, fmt, value in ((4, "B", 1), (18, "<H", 3), (32, "<Q", 999999), (54, "<H", 1), (56, "<H", 0), (64 + 32, "<Q", 999999), (64 + 40, "<Q", 0)):
            data = bytearray(elf())
            struct.pack_into(fmt, data, offset, value)
            with self.subTest(offset=offset), self.assertRaises(RuntimeError):
                audit.inspect_binary("linux", self.put("bad.x86_64", data))

    def test_pck_rejects_invalid_magic_size_and_engine(self):
        binary = pe()
        cases = [binary[:-4] + b"xxxx", binary[:-12] + struct.pack("<Q", len(binary) * 2) + b"GDPC",
                 b"stub" + pck((4, 7, 1)) + struct.pack("<Q", len(pck())) + b"GDPC", b"short"]
        for index, data in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(RuntimeError):
                audit.audit_pck(self.put("bad.exe", data))

    def test_macos_structure_versions_permissions_and_platform_limitations(self):
        path = self.root / "mac.zip"
        zip_bytes(path, mac_entries())
        result = audit.audit_macos(path)
        self.assertEqual({entry["architecture"] for entry in result["architectures"]}, {"x86_64", "arm64"})
        self.assertEqual(result["execute_permissions"], "0755")
        self.assertEqual(result["signing"], "ad-hoc structure only")
        self.assertFalse(result["apple_codesign_validation_executed"])
        self.assertFalse(result["apple_notarization_verified"])
        for entries in (mac_entries(executable_mode=0o644), mac_entries(version="1.5.3")):
            zip_bytes(path, entries)
            with self.assertRaises(RuntimeError):
                audit.audit_macos(path)

    def test_macho_slice_and_signature_malformations_fail(self):
        # Header architecture, bounds, duplicate architecture, command length,
        # signature range, non-ad-hoc flags, hash slot bounds, slot index overlap.
        mutations = [(8, ">I", 7), (16, ">I", 999999), (28, ">I", 0x1000007),
                     (64 + 36, "<I", 0), (64 + 40, "<I", 999999),
                     (64 + 64 + 20 + 12, ">I", 0),
                     (64 + 64 + 20 + 16, ">I", 999999),
                     (64 + 64 + 16, ">I", 0)]
        path = self.root / "bad.zip"
        for offset, fmt, value in mutations:
            binary = macho()
            struct.pack_into(fmt, binary, offset, value)
            zip_bytes(path, mac_entries(binary))
            with self.subTest(offset=offset), self.assertRaises(RuntimeError):
                audit.audit_macos(path)


class HeadlessReportTests(ScratchTest):
    """Producer-shaped JSON/stdout fixtures; no engines or real profiles."""
    def report(self, suite):
        base = dict(status="PASS", passed=1, failed=[])
        if suite == "backlog_v2":
            return dict(base, suite=suite, metrics={"fixture": {"passed": True}})
        if suite == "fonts_v2":
            faces = ["res://assets/fonts/glyph_serif.otf", "res://assets/fonts/ui_black.otf", "res://assets/fonts/symbols.ttf"]
            return dict(base, suite=suite, unique_codepoints=1, faces=faces,
                        coverage={"fixture U+653F 政": [faces[0]]}, system_fallback=False, resource_fallbacks=False)
        return dict(base, passed=2, calibration=dict(status="PASS", passed=1, failed=[], games=4572, duel_pairs=231, roster_count=22),
                    fresh=True, current_sim_sha="a" * 64, stored_sim_sha="a" * 64,
                    freshness_policy="warn in Phase 1; final release rejects stale data")

    def stdout(self, suite, report):
        if suite == "backlog_v2":
            return f"BACKLOG_V2 PASS passed={report['passed']} failed=0\n"
        if suite == "fonts_v2":
            return f"FONTS_V2 PASS passed={report['passed']} failed=0 unique_codepoints={report['unique_codepoints']}\n"
        warning = "" if report["fresh"] else f"CALIBRATION_V2 WARN stale calibration: stored={report['stored_sim_sha']} current={report['current_sim_sha']}\n"
        return warning + "CALIBRATION_V2 " + json.dumps(report) + "\n"

    def evidence(self, suite, report=None, text=None):
        report = self.report(suite) if report is None else report
        path = self.put(suite + ".json", json.dumps(report).encode())
        log = self.put(suite + ".log", (self.stdout(suite, report) if text is None else text).encode())
        process = dict(status="PASS", code=0, timeout=False, problems=[], log=str(log))
        return path, process

    def test_three_current_producer_contracts_pass(self):
        for suite in sorted(release.STRUCTURED_HEADLESS):
            with self.subTest(suite=suite):
                path, process = self.evidence(suite)
                self.assertEqual(release.headless_assertion_report(path, suite, process), self.report(suite))

    def test_calibration_stale_warning_remains_accepted(self):
        value = self.report("calibration_v2")
        value.update(fresh=False, stored_sim_sha="b" * 64)
        path, process = self.evidence("calibration_v2", value)
        self.assertFalse(release.headless_assertion_report(path, "calibration_v2", process)["fresh"])
        Path(process["log"]).write_text("CALIBRATION_V2 " + json.dumps(value), encoding="utf-8")
        with self.assertRaises(RuntimeError):
            release.headless_assertion_report(path, "calibration_v2", process)

    def test_missing_truncated_duplicate_or_nonfinite_report_fails(self):
        path, process = self.evidence("backlog_v2")
        for payload in ("", "{}", '{"status":', '{"status":"PASS","status":"PASS"}',
                        '{"x":NaN}', '{"x":1e9999}'):
            with self.subTest(payload=payload):
                path.write_text(payload, encoding="utf-8")
                with self.assertRaises((RuntimeError, ValueError)):
                    release.headless_assertion_report(path, "backlog_v2", process)
        path.unlink()
        with self.assertRaises(OSError):
            release.headless_assertion_report(path, "backlog_v2", process)

    def test_failed_status_counts_and_missing_schema_are_rejected(self):
        for suite in sorted(release.STRUCTURED_HEADLESS):
            original = self.report(suite)
            for key, value in (("status", "FAIL"), ("failed", ["failed check"]),
                               ("failed", 0), ("passed", True), ("passed", 0)):
                with self.subTest(suite=suite, field=key, value=value):
                    path, process = self.evidence(suite, {**original, key: value})
                    with self.assertRaises(RuntimeError):
                        release.headless_assertion_report(path, suite, process)
            path, process = self.evidence(suite)
            removed = dict(original)
            del removed["status"]
            path.write_text(json.dumps(removed), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                release.headless_assertion_report(path, suite, process)

    def test_stdout_mismatch_duplicate_and_engine_error_fail(self):
        for suite in sorted(release.STRUCTURED_HEADLESS):
            normal = self.stdout(suite, self.report(suite))
            for text in ("", normal + normal, normal + "ERROR: hidden crash\n", "WRONG " + normal):
                with self.subTest(suite=suite, text=text):
                    path, process = self.evidence(suite, text=text)
                    with self.assertRaises(RuntimeError):
                        release.headless_assertion_report(path, suite, process)

    def test_process_failure_or_timeout_cannot_be_hidden_by_report(self):
        path, process = self.evidence("backlog_v2")
        for key, value in (("code", 1), ("timeout", True), ("status", "FAIL"),
                           ("cleanup_errors", ["cleanup failed"]), ("cancelled", True)):
            with self.subTest(field=key):
                with self.assertRaises(RuntimeError):
                    release.headless_assertion_report(path, "backlog_v2", {**process, key: value})

    def test_font_fallback_and_calibration_nested_failures_rejected(self):
        value = self.report("fonts_v2")
        path, process = self.evidence("fonts_v2", {**value, "system_fallback": True})
        with self.assertRaises(RuntimeError):
            release.headless_assertion_report(path, "fonts_v2", process)
        for changes in ({"failed": ["bad"]}, {"games": 1}, {"roster_count": 26}):
            value = self.report("calibration_v2")
            value["calibration"].update(changes)
            path, process = self.evidence("calibration_v2", value)
            with self.assertRaises(RuntimeError):
                release.headless_assertion_report(path, "calibration_v2", process)

    def test_S2_passes_explicit_report_to_three_new_suites_and_preserves_hashes(self):
        self.qa_root.mkdir(parents=True)
        config.QA.mkdir(parents=True)
        runner = object.__new__(release.Release)
        runner.project, runner.reports = self.project, self.root / "reports"
        runner.logs, runner.profiles = self.root / "logs", self.scratch / "profiles"
        runner.options = Mock(jobs=1)
        runner.test_failure_policy = dict(enabled=False)
        calls = []
        def godot(args, name, check=False):
            suite = name.removeprefix("headless_")
            paths = [arg.removeprefix("--report=") for arg in args if isinstance(arg, str) and arg.startswith("--report=")]
            self.assertEqual(len(paths), 1)
            path = Path(paths[0])
            self.assertTrue(path.is_relative_to(runner.reports))
            self.assertEqual(path.read_bytes(), b"")
            value = self.report(suite)
            path.write_text(json.dumps(value), encoding="utf-8")
            log = self.put("logs/" + suite + ".log", self.stdout(suite, value).encode())
            calls.append(suite)
            return dict(status="PASS", code=0, timeout=False, problems=[], log=str(log))
        runner.godot = godot
        with patch.object(release, "copy_project", return_value={}), \
                patch.object(release, "import_project", return_value=[]), \
                patch.object(release, "discover_tests", return_value={"headless": sorted(release.STRUCTURED_HEADLESS)}), \
                patch.object(release, "REQUIRED_HEADLESS", release.STRUCTURED_HEADLESS):
            result = runner.S2()
        self.assertEqual(set(calls), release.STRUCTURED_HEADLESS)
        self.assertEqual(result["status"], "PASS")
        for row in result["tests"]:
            self.assertEqual(row["assertions"]["status"], "PASS")
            path = Path(row["assertion_report"])
            self.assertEqual(result["output_hashes"][str(path.resolve())], common.sha(path))

    def test_S2_ordinary_report_failure_cannot_use_connectivity_continuation(self):
        config.QA.mkdir(parents=True)
        runner = object.__new__(release.Release)
        runner.project, runner.reports = self.project, self.root / "reports"
        runner.logs, runner.profiles = self.root / "logs", self.scratch / "profiles"
        runner.options = Mock(jobs=1)
        runner.test_failure_policy = dict(enabled=True)
        def godot(args, name, check=False):
            path = Path(next(arg.removeprefix("--report=") for arg in args
                             if isinstance(arg, str) and arg.startswith("--report=")))
            value = self.report("backlog_v2")
            value.update(status="FAIL", failed=["actual failed assertion"])
            path.write_text(json.dumps(value), encoding="utf-8")
            log = self.put("logs/backlog_v2.log", b"BACKLOG_V2 FAIL passed=1 failed=1\n")
            return dict(status="FAIL", code=1, timeout=False, problems=[], log=str(log))
        runner.godot = godot
        with patch.object(release, "copy_project", return_value={}), \
                patch.object(release, "import_project", return_value=[]), \
                patch.object(release, "discover_tests", return_value={"headless": ["backlog_v2"]}), \
                patch.object(release, "REQUIRED_HEADLESS", {"backlog_v2"}):
            result = runner.S2()
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["acceptance_status"], "FAIL")
        self.assertFalse(result["release_eligible"])
        self.assertEqual(result["continued_test_failures"], [])
        self.assertFalse(result["tests"][0]["failure_continuation_allowed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
