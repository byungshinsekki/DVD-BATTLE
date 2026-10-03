#!/usr/bin/env python3
"""Verify a draft Linux release, then run five bounded native headless smokes.

Python standard library only. This is startup/short-simulation evidence, not
rendering, full-draft completion, full-battle completion, or performance proof.
No credentials are written to disk, logged, or passed to the game processes.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


PACKAGE = "DVD_BATTLE_V2_PREVIEW_DRAFT_HF1_Linux_x86_64"
EXECUTABLE = "DVD_BATTLE_V2_PREVIEW_DRAFT_HF1.x86_64"
RELEASE_TAG = "v2-preview-draft-hf1-linux"
ARCHIVE = PACKAGE + ".tar.gz"
FILES = frozenset({
    EXECUTABLE, "README_LINUX_KO.txt", "BUILD_INFO.json", "SHA256.txt",
    "THIRD_PARTY_NOTICES.txt", "GODOT_THIRD_PARTY_NOTICES.txt",
    "FONT_SOURCES.md", "OFL_NotoSerifCJK.txt",
})
MAX_ARCHIVE = 512 * 1024 * 1024
MAX_EXPANDED = 1024 * 1024 * 1024
MAX_LOG = 8 * 1024 * 1024
CHILD_TIMEOUT = 120
TOTAL_TIMEOUT = 12 * 60
# These routes are implemented in scripts/ui/app.gd. control_citadel and
# ruined_gate are authored map IDs; DeveloperScreen.MODES includes control.
# Draft only opens the screen: no automatic drafting/completion claim.
CASES = (
    ("home", ["--goto=home"]),
    ("draft_ui", ["--goto=draft", "--ruleset=elimination"]),
    ("ai_battle_start", ["--demo-battle=ruined_gate"]),
    ("control_120_ticks", ["--developer-case=control/control_citadel/20261003/120"]),
    ("torquemada_preview", ["--demo-preview=torquemada/active:0"]),
)
ERRORS = re.compile(
    r"(?:SCRIPT ERROR|Parse Error|ERROR|FATAL):|"
    r"ObjectDB instances leaked|resources still in use|Unreferenced static string|"
    r"leaked at exit|LeakSanitizer|AddressSanitizer|Segmentation fault|core dumped",
    re.IGNORECASE,
)

# Match the existing sound-enabled tests/render_v2.gd teardown. Raw --quit-after
# during an active WAV leaves playback refs on both Windows and Linux headless;
# that diagnostic run remains a documented limitation, not a passed test.
BATTLE_DRIVER = '''extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app: Node = scene.instantiate()
	root.add_child(app)
	current_scene = app
	for _i in 240:
		await process_frame
	var battle: Node = app.get("screens").get("battle")
	var ticks: int = int(battle.get("runner").get("sim").get("tick"))
	var seconds: float = float(battle.get("runner").get("sim").get("time"))
	var sfx: Node = root.get_node("Sfx")
	var audio_cached: int = int(sfx.get("_cache").size())
	var unit_count: int = int(battle.get("runner").get("sim").get("units").size())
	var controller_count: int = int(battle.get("runner").get("sim").get("controllers").size())
	var passed: bool = str(app.get("current")) == "battle" and ticks > 0 and seconds > 0.0 and unit_count == 6 and controller_count == 2 and bool(sfx.get("enabled")) and audio_cached > 0
	print("LINUX_BATTLE_CHECKPOINT=", JSON.stringify({"status": "PASS" if passed else "FAIL", "frames": 240, "ticks": ticks, "simulation_seconds": seconds, "units": unit_count, "ai_controllers": controller_count, "sound_enabled": bool(sfx.get("enabled")), "audio_streams_generated": audio_cached}))
	app.free()
	for player: AudioStreamPlayer in sfx.get("_players"):
		player.stop()
		player.stream = null
	sfx.get("_cache").clear()
	# Audio mixing uses wall clock even when fixed-fps advances frames quickly.
	for _i in 30:
		await process_frame
		OS.delay_msec(10)
	print("LINUX_BATTLE_TEARDOWN=PASS")
	quit(0 if passed else 1)
'''


class SmokeFailure(Exception):
    """Fixed diagnostic code, never an exception carrying headers or URLs."""


def require(condition: bool, code: str) -> None:
    if not condition:
        raise SmokeFailure(code)


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


class AssetRedirect(urllib.request.HTTPRedirectHandler):
    """Never forward API credentials to a release-asset CDN (or back from it)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlsplit(newurl)
        require(target.scheme == "https" and target.port in (None, 443), "unsafe_asset_redirect")
        require(not target.username and not target.password, "unsafe_asset_redirect")
        require(target.hostname in {
            "api.github.com", "release-assets.githubusercontent.com",
            "objects.githubusercontent.com", "github.com",
        }, "unexpected_asset_redirect_host")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        require(redirected is not None, "unsupported_asset_redirect")
        # urllib header keys are case-insensitive in purpose, not in storage.
        # Strip on every redirect, including a later redirect back to the API.
        for collection in (redirected.headers, redirected.unredirected_hdrs):
            for name in list(collection):
                if name.lower() in {"authorization", "cookie", "proxy-authorization"}:
                    del collection[name]
        return redirected


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise SmokeFailure("unexpected_api_redirect")


def api_json(repo: str, suffix: str, token: str) -> dict:
    url = f"https://api.github.com/repos/{repo}/{suffix}"
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json", "Authorization": "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "DVD-Linux-Preview-Smoke",
    })
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
        require(response.status == 200, "api_status_failed")
        content = response.read(2 * 1024 * 1024 + 1)
    require(len(content) <= 2 * 1024 * 1024, "api_response_too_large")
    result = json.loads(content.decode("utf-8"))
    require(isinstance(result, dict), "invalid_api_metadata")
    return result


def download_asset(repo: str, release_id: int, asset_id: int, expected_sha: str, token: str, target: Path) -> dict:
    metadata = api_json(repo, f"releases/assets/{asset_id}", token)
    require(type(metadata.get("id")) is int and metadata["id"] == asset_id, "asset_id_mismatch")
    require(metadata.get("name") == ARCHIVE and metadata.get("state") == "uploaded", "asset_name_or_state_mismatch")
    size = metadata.get("size")
    require(type(size) is int and 0 < size <= MAX_ARCHIVE, "invalid_archive_size")
    # Unpublished draft tags may return 404; bind by the explicit release ID.
    release = api_json(repo, f"releases/{release_id}", token)
    require(type(release.get("id")) is int and release["id"] == release_id, "release_id_mismatch")
    require(release.get("tag_name") == RELEASE_TAG and release.get("draft") is True, "expected_draft_release")
    require(release.get("prerelease") is True, "expected_prerelease")
    matches = [a for a in release.get("assets", []) if a.get("id") == asset_id]
    require(len(matches) == 1 and all(matches[0].get(k) == metadata.get(k) for k in ("id", "name", "size", "state")), "asset_release_binding_mismatch")
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/assets/{asset_id}", headers={
        "Accept": "application/octet-stream", "Authorization": "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "DVD-Linux-Preview-Smoke",
    })
    total = 0
    with urllib.request.build_opener(AssetRedirect()).open(request, timeout=30) as response, target.open("xb") as output:
        require(response.status == 200, "asset_download_status_failed")
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            total += len(block)
            require(total <= size, "archive_download_size_exceeded")
            output.write(block)
    require(total == size, "archive_download_size_mismatch")
    require(sha256(target) == expected_sha, "archive_sha256_mismatch")
    return {"asset_id": asset_id, "name": ARCHIVE, "bytes": size, "sha256": expected_sha,
            "release_id": release["id"], "tag": RELEASE_TAG, "draft_at_validation": True}


def unpack_archive(archive: Path, destination: Path) -> tuple[Path, dict]:
    """Copy only expected regular files; never use tar.extract/extractall."""
    destination.mkdir(mode=0o700)
    root = destination / PACKAGE
    root.mkdir(mode=0o700)
    found = set()
    expanded = 0
    with tarfile.open(archive, "r:gz") as package:
        for item in package:
            parts = PurePosixPath(item.name).parts
            require(len(found) < len(FILES), "archive_file_count_exceeded")
            require(len(parts) == 2 and parts[0] == PACKAGE and parts[1] in FILES,
                    "unexpected_archive_path")
            require(item.name == PACKAGE + "/" + parts[1] and "\\" not in item.name,
                    "noncanonical_archive_path")
            require(item.name not in found, "duplicate_archive_path")
            require(item.type in (tarfile.REGTYPE, tarfile.AREGTYPE) and item.isfile()
                    and not item.issym() and not item.islnk() and not item.issparse()
                    and not item.pax_headers, "nonregular_archive_member")
            require(item.size > 0, "empty_archive_member")
            expanded += item.size
            require(expanded <= MAX_EXPANDED, "expanded_archive_too_large")
            mode = 0o755 if parts[1] == EXECUTABLE else 0o644
            require(item.mode == mode, "archive_mode_mismatch")
            target = root / parts[1]
            with package.extractfile(item) as source, target.open("xb") as output:
                copied = 0
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    copied += len(block)
                    require(copied <= item.size, "archive_member_size_exceeded")
                    output.write(block)
            require(copied == item.size, "archive_member_size_mismatch")
            target.chmod(mode)
            require(stat.S_IMODE(target.stat().st_mode) == mode, "extracted_mode_mismatch")
            found.add(item.name)
    require(found == {PACKAGE + "/" + name for name in FILES}, "archive_file_set_mismatch")
    checksums = {}
    for line in (root / "SHA256.txt").read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        require(match is not None, "invalid_internal_checksum_line")
        digest, name = match.groups()
        require(name in FILES - {"SHA256.txt"} and name not in checksums, "invalid_internal_checksum_file")
        require(sha256(root / name) == digest, "internal_sha256_mismatch")
        checksums[name] = digest
    require(set(checksums) == FILES - {"SHA256.txt"}, "incomplete_internal_checksums")
    executable = root / EXECUTABLE
    with executable.open("rb") as source:
        header = source.read(64)
    require(len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
            and int.from_bytes(header[18:20], "little") == 62
            and int.from_bytes(header[16:18], "little") in (2, 3), "not_linux_x86_64_elf")
    build = json.loads((root / "BUILD_INFO.json").read_text(encoding="utf-8"))
    require(build.get("binary_sha256") == checksums[EXECUTABLE]
            and build.get("binary_bytes") == executable.stat().st_size, "build_binary_binding_mismatch")
    require(build.get("platform") == "Linux x86_64" and build.get("godot_version") == "4.7.2.stable",
            "unexpected_build_platform")
    return executable, {"file_count": len(found), "internal_hashes_verified": len(checksums),
                        "executable_mode": "0755", "binary_bytes": executable.stat().st_size,
                        "binary_sha256": checksums[EXECUTABLE], "elf": "ELF64 little-endian x86_64"}


def isolated_environment(folder: Path) -> dict[str, str]:
    # Construct from nothing: GITHUB_TOKEN, GH_TOKEN, proxy credentials, loader
    # overrides, and the runner's real HOME/XDG values cannot reach the game.
    environment = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
                   "USER": "preview-smoke", "LOGNAME": "preview-smoke"}
    for key, leaf in {
        "HOME": "home", "XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config",
        "XDG_CACHE_HOME": "cache", "XDG_STATE_HOME": "state", "XDG_RUNTIME_DIR": "runtime",
        "XDG_DATA_DIRS": "shared-data", "XDG_CONFIG_DIRS": "shared-config",
        "APPDATA": "roaming", "LOCALAPPDATA": "local", "TMPDIR": "tmp",
    }.items():
        target = folder / leaf
        target.mkdir(mode=0o700, parents=True)
        target.chmod(0o700)
        environment[key] = str(target)
    return environment


def cleanup_group(process: subprocess.Popen) -> bool:
    """Only the process group created with start_new_session=True is touched."""
    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        return False
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return False
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=3)
    return True


def run_case(executable: Path, work: Path, name: str, user_args: list[str]) -> dict:
    folder = work / name
    folder.mkdir(mode=0o700)
    environment = isolated_environment(folder)
    cwd = folder / "work"
    cwd.mkdir(mode=0o700)
    log = folder / "native.log"
    arguments = ["--headless", "--fixed-fps", "60", "--quit-after", "240", "--"] + user_args
    driver = None
    if name == "ai_battle_start":
        driver = folder / "battle_smoke.gd"
        driver.write_text(BATTLE_DRIVER, encoding="utf-8", newline="\n")
        arguments = ["--headless", "--fixed-fps", "60", "--script", str(driver), "--"] + user_args
    started = time.monotonic()
    shown_arguments = ["<qa-battle-driver>" if driver is not None and item == str(driver) else item for item in arguments]
    result = {"case": name, "arguments": shown_arguments, "status": "FAIL", "timeout_seconds": CHILD_TIMEOUT}
    if driver is not None:
        result["teardown"] = "240 sound-enabled frames; free live scene; stop/unset voices; clear cache; drain 30 frames with 10 ms per frame"
        result["driver_sha256"] = sha256(driver)
    process = None
    try:
        with log.open("xb") as output:
            process = subprocess.Popen([str(executable)] + arguments, cwd=cwd, env=environment,
                                       stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                while True:
                    require(time.monotonic() - started < CHILD_TIMEOUT, "child_timeout")
                    require(log.stat().st_size <= MAX_LOG, "native_log_too_large")
                    try:
                        code = process.wait(timeout=0.1)
                        break
                    except subprocess.TimeoutExpired:
                        continue
            finally:
                group_left = cleanup_group(process)
            result["exit_code"] = code
            require(not group_left, "native_process_group_required_cleanup")
        require(log.stat().st_size <= MAX_LOG, "native_log_too_large")
        content = log.read_text(encoding="utf-8")
        result.update({"seconds": round(time.monotonic() - started, 3), "log_bytes": log.stat().st_size,
                       "log_sha256": sha256(log), "error_or_leak_matches": len(ERRORS.findall(content)),
                       "warning_lines": sum("WARNING:" in line for line in content.splitlines())})
        require(code == 0, "native_exit_nonzero")
        require("Godot Engine v4.7.2.stable" in content, "expected_engine_banner_missing")
        require(result["error_or_leak_matches"] == 0, "native_error_or_leak")
        if driver is not None:
            checkpoints = [json.loads(line.split("=", 1)[1]) for line in content.splitlines() if line.startswith("LINUX_BATTLE_CHECKPOINT=")]
            require(len(checkpoints) == 1, "battle_checkpoint_missing")
            checkpoint = checkpoints[0]
            require(checkpoint.get("status") == "PASS" and checkpoint.get("frames") == 240
                    and checkpoint.get("ticks", 0) > 0 and checkpoint.get("simulation_seconds", 0) > 0
                    and checkpoint.get("units") == 6 and checkpoint.get("ai_controllers") == 2
                    and checkpoint.get("sound_enabled") is True and checkpoint.get("audio_streams_generated", 0) > 0,
                    "battle_checkpoint_failed")
            require("LINUX_BATTLE_TEARDOWN=PASS" in content.splitlines(), "battle_teardown_missing")
            result["battle_checkpoint"] = checkpoint
        result["status"] = "PASS"
    except SmokeFailure as exc:
        if str(exc) in {"overall_timeout", "interrupted"}:
            raise
        result["error"] = str(exc)
    except UnicodeDecodeError:
        result["error"] = "native_log_not_utf8"
    except OSError:
        result["error"] = "native_launch_or_io_failed"
    finally:
        if process is not None and process.poll() is None:
            cleanup_group(process)
        result["seconds"] = round(time.monotonic() - started, 3)
        if process is not None:
            result["exit_code"] = process.returncode
        if log.exists():
            result.update({"log_bytes": log.stat().st_size, "log_sha256": sha256(log)})
            if result["status"] != "PASS":
                # A short diagnostic only; no environment or credential dump.
                content = log.read_bytes()[:MAX_LOG].decode("utf-8", errors="replace")
                lines = content.splitlines()
                selected = [line for line in lines if ERRORS.search(line)] or lines[-10:]
                redacted = []
                for line in selected[:10]:
                    line = re.sub(r"\x1b\[[0-9;]*m", "", line)
                    line = line.replace(str(folder), "<isolated-profile>").replace(str(executable.parent), "<package>")
                    if re.search(r"(?i)authorization:|ghp_|ghs_|github_pat_", line):
                        line = "[credential-shaped diagnostic redacted]"
                    redacted.append(line[:240])
                result["diagnostic_lines"] = redacted
    return result


def interrupted(signum, frame):
    raise SmokeFailure("overall_timeout" if signum == signal.SIGALRM else "interrupted")


def publish_result(result: dict) -> None:
    encoded = json.dumps(result, ensure_ascii=True, separators=(",", ":"))
    print("LINUX_SMOKE_RESULT=" + encoded, flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write("### Linux native headless smoke: " + result["status"] + "\n\n")
            output.write("Five bounded startup/short-simulation cases; no rendered UI, full draft, or complete battle claim.\n\n")
            output.write("```json\n" + json.dumps(result, ensure_ascii=True, indent=2) + "\n```\n")


def main() -> int:
    result = {"format": "DVD_LINUX_NATIVE_SMOKE_V1", "status": "FAIL", "cases": [],
              "scope": "native ELF; headless startup and short simulations only",
              "not_verified": ["rendered visuals", "GPU compatibility", "full draft completion", "complete battles", "performance targets"]}
    stage = "inputs"
    try:
        require(sys.platform == "linux" and platform.machine() == "x86_64", "linux_x86_64_runner_required")
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        commit = os.environ.get("GITHUB_SHA", "")
        release_text = os.environ.get("SMOKE_RELEASE_ID", "")
        asset_text = os.environ.get("SMOKE_ASSET_ID", "")
        expected_sha = os.environ.get("SMOKE_ARCHIVE_SHA256", "").lower()
        token = os.environ.pop("GITHUB_TOKEN", "")
        require(bool(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo)), "invalid_repository")
        require(bool(re.fullmatch(r"[0-9a-f]{40}", commit)), "invalid_workflow_commit")
        require(bool(re.fullmatch(r"[1-9][0-9]{0,19}", release_text)), "invalid_release_id")
        require(bool(re.fullmatch(r"[1-9][0-9]{0,19}", asset_text)), "invalid_asset_id")
        require(bool(re.fullmatch(r"[0-9a-f]{64}", expected_sha)), "invalid_archive_sha256")
        require(bool(token), "missing_api_token")
        result.update({"repository": repo, "workflow_sha": commit, "machine": platform.machine(),
                       "runner_image": os.environ.get("ImageOS", "unknown"),
                       "libc": dict(zip(("name", "version"), platform.libc_ver()))})
        os_release = Path("/etc/os-release").read_text(encoding="utf-8")
        pretty = re.search(r'^PRETTY_NAME="([^"\n]+)"$', os_release, re.MULTILINE)
        result["os_pretty_name"] = pretty.group(1) if pretty else "unknown"
        for sig in (signal.SIGALRM, signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, interrupted)
        signal.alarm(TOTAL_TIMEOUT)
        with tempfile.TemporaryDirectory(prefix="dvd-linux-native-smoke-") as temporary:
            work = Path(temporary)
            stage = "download"
            archive = work / ARCHIVE
            result["asset"] = download_asset(repo, int(release_text), int(asset_text), expected_sha, token, archive)
            token = ""
            stage = "archive_verification"
            executable, result["package"] = unpack_archive(archive, work / "unpacked")
            stage = "native_execution"
            for name, arguments in CASES:
                result["cases"].append(run_case(executable, work, name, arguments))
            require(all(case["status"] == "PASS" for case in result["cases"]), "native_cases_failed")
            require(sha256(executable) == result["package"]["binary_sha256"], "binary_changed_during_smoke")
            result["status"] = "PASS"
    except SmokeFailure as exc:
        result.update({"failure_stage": stage, "error": str(exc)})
    except urllib.error.HTTPError as exc:
        result.update({"failure_stage": stage, "error": "github_http_error", "http_status": exc.code})
    except (urllib.error.URLError, TimeoutError):
        result.update({"failure_stage": stage, "error": "network_timeout_or_connection_failed"})
    except Exception:
        result.update({"failure_stage": stage, "error": "verification_or_execution_exception"})
    finally:
        if sys.platform == "linux":
            signal.alarm(0)
    publish_result(result)
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
