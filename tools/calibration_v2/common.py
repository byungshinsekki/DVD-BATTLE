"""Deterministic files and isolated, bounded offline Godot processes."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
try:
    from . import process_control
except ImportError:
    import process_control

process_pool = process_control.process_pool

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path("D:/DVD_BATTLE_1.2.1_RECOVERY_WORK/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
ERRORS = re.compile(r"SCRIPT ERROR|ERROR:|Parse Error|WARNING:.*\.gd|^\s+at:.*\.gd", re.MULTILINE)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def writable_path(path):
    """Reject redirected outputs; source reads and the approved engine are unaffected."""
    path = Path(path).absolute()
    require(not any(re.match(r"DVD_BATTLE_1\.", part, re.IGNORECASE) for part in path.parts), "V1.x paths are read-only")
    for item in (path, *path.parents):
        require(not item.is_symlink() and not item.is_junction(), f"Output path traverses a link: {item}")
    require(not path.is_file() or path.stat().st_nlink == 1, f"Output file is hard-linked: {path}")
    return path.resolve()


def write_json(path, value):
    path = writable_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = writable_path(path.with_suffix(path.suffix + ".partial"))
    temporary.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def terminate_pid_tree(process):
    return process_control.terminate(process)


def run_godot(godot, root, arguments, log, timeout=900):
    """Every invocation is headless; it cannot display a window or use real APPDATA."""
    require(1 <= timeout <= 900, "Timeout must be in 1..900 seconds")
    root, log = Path(root).resolve(), writable_path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    profile = log.parent / "profiles" / log.stem
    env = os.environ.copy()
    for key, name in (("APPDATA", "Roaming"), ("LOCALAPPDATA", "Local")):
        target = writable_path(profile / name)
        target.mkdir(parents=True, exist_ok=True)
        env[key] = str(target)
    command = [str(godot), "--headless", "--path", str(root), *map(str, arguments)]
    started = time.monotonic()
    process = None
    pending = None
    result = {"command": command, "log": str(log), "exit_code": None, "timeout": False,
              "APPDATA": env["APPDATA"], "LOCALAPPDATA": env["LOCALAPPDATA"], "termination": None,
              "cleanup_errors": [], "interrupted": False}
    with log.open("wb") as stream:
        try:
            process = process_control.spawn(command, stdout=stream, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, env=env, cwd=root,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                start_new_session=os.name != "nt")
            result["pid"] = process.pid
            process.wait(timeout=timeout)
            result["exit_code"] = process.returncode
        except subprocess.TimeoutExpired:
            result["timeout"] = True
            result["exit_code"] = 124
        except BaseException as exc:
            pending = exc
            result["interrupted"] = isinstance(exc, KeyboardInterrupt)
            result["exception"] = repr(exc)
            result["exit_code"] = 130 if result["interrupted"] else 125
        finally:
            if process is not None:
                if process.poll() is None:
                    result["termination"] = process_control.cleanup(process)
                    result["cleanup_errors"] = result["termination"]["errors"]
                process_control.release(process)
            result["cancelled"] = process_control.STOP.is_set()
    result["seconds"] = round(time.monotonic() - started, 3)
    text = log.read_text(encoding="utf-8", errors="replace")
    result["errors"] = [line for line in text.splitlines() if ERRORS.search(line)]
    result["status"] = "PASS" if result["exit_code"] == 0 and not result["timeout"] and not result["errors"] and not result["cleanup_errors"] and not result["cancelled"] and pending is None else "FAIL"
    write_json(log.with_suffix(".process.json"), result)
    if pending is not None:
        if result["cleanup_errors"]:pending.add_note("Cleanup also failed: "+repr(result["cleanup_errors"]))
        raise pending
    require(result["status"] == "PASS", f"Godot failed: {log}: {result}")
    return result
