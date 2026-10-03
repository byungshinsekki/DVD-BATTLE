"""Private gd.ps1 process guard: timed, hidden, and isolated from real profiles."""
from __future__ import annotations

import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import time

SCRATCH = Path("D:/DVD20_CODEX_SCRATCH").resolve()


def require_child(path: Path, parent: Path) -> Path:
    resolved = path.resolve()
    if resolved == parent or parent not in resolved.parents:
        raise ValueError(f"Not a child of {parent}: {resolved}")
    return resolved


def terminate_owned(process: subprocess.Popen) -> dict:
    proof = dict(pid=process.pid, method='already_exited', errors=[], direct_fallback=False)
    if process.poll() is not None:return proof
    if os.name == "nt":
        proof['method'] = 'taskkill_pid_tree'
        executable = Path(os.environ.get('SystemRoot', 'C:/Windows'))/'System32/taskkill.exe'
        try:
            result = subprocess.run([str(executable), "/PID", str(process.pid), "/T", "/F"],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
            proof['tree_returncode'] = result.returncode
            if result.returncode != 0 and process.poll() is None:
                proof['errors'].append('Owned PID tree cleanup failed: '+repr(result.stdout))
        except (OSError, subprocess.SubprocessError) as exc:
            proof['errors'].append('Owned PID tree cleanup error: '+repr(exc))
    else:
        proof['method'] = 'owned_process_group'
        try:os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:pass
        except OSError as exc:proof['errors'].append('Owned process group cleanup error: '+repr(exc))
    if process.poll() is None:
        proof['direct_fallback'] = True
        try:process.kill()
        except OSError as exc:proof['errors'].append('Exact PID fallback error: '+repr(exc))
    try:process.wait(timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:proof['errors'].append('Owned PID wait error: '+repr(exc))
    if process.poll() is None:proof['errors'].append('Owned PID is still live after cleanup')
    return proof


def run(request: dict) -> dict:
    timeout = int(request.get("timeout", 900))
    if not 1 <= timeout <= 900:
        raise ValueError("Process timeout must be 1..900 seconds")
    appdata = require_child(Path(request["appdata"]), SCRATCH)
    localdata = require_child(Path(request["localappdata"]), SCRATCH)
    appdata.mkdir(parents=True, exist_ok=True)
    localdata.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"], env["LOCALAPPDATA"] = str(appdata), str(localdata)
    env["PYTHONUTF8"] = "1"
    log = Path(request["log"])
    log.parent.mkdir(parents=True, exist_ok=True)
    result = {"code": 125, "pid": None, "timed_out": False,
              "appdata": str(appdata), "localappdata": str(localdata),
              "timeout_seconds": timeout, "log": str(log), "cleanup_errors": [], "termination": None, "interrupted": False}
    started = time.monotonic()
    process = None
    pending = None
    with log.open("wb") as stream:
        try:
            process = subprocess.Popen([request["executable"], *request["args"]],
                stdout=stream, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                env=env, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                start_new_session=os.name != "nt")
            result["pid"] = process.pid
            process.wait(timeout=timeout)
            result["code"] = process.returncode
            if os.name == "nt" and result["code"] > 0x7fffffff:
                result["code"] -= 0x100000000
        except subprocess.TimeoutExpired:
            result["timed_out"] = True
            result["code"] = 124
            stream.write(f"\nERROR: process PID {result['pid']} exceeded {timeout}s timeout\n".encode())
        except BaseException as exc:
            pending = exc
            result["error"] = str(exc)
            result["exception"] = repr(exc)
            result["interrupted"] = isinstance(exc, KeyboardInterrupt)
            result["code"] = 130 if result["interrupted"] else 125
            stream.write(f"\nERROR: guarded process failed: {exc}\n".encode("utf-8"))
        finally:
            if process is not None and process.poll() is None:
                try:
                    result['termination'] = terminate_owned(process)
                    result['cleanup_errors'] = result['termination']['errors']
                except BaseException as exc:
                    result['cleanup_errors'] = [repr(exc)]
                if result['cleanup_errors']:
                    stream.write(('\nERROR: owned PID cleanup failed: '+repr(result['cleanup_errors'])+'\n').encode('utf-8'))
                    if result['code'] == 0:result['code'] = 125
    result["seconds"] = round(time.monotonic() - started, 3)
    summary = Path(request["summary"])
    temporary = summary.with_suffix(summary.suffix + ".partial")
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, summary)
    if pending is not None and not isinstance(pending, Exception):
        if result['cleanup_errors']:pending.add_note('Cleanup also failed: '+repr(result['cleanup_errors']))
        raise pending
    return result


if __name__ == "__main__":
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    outcome = run(data)
    print(json.dumps(outcome, ensure_ascii=False))
    raise SystemExit(0 if outcome["code"] == 0 else 1)
