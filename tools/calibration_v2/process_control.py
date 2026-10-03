"""Owned process trees with race-safe cancellation of one orchestration pool."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import os
from pathlib import Path
import signal
import subprocess
import threading

ACTIVE = {}
LOCK = threading.RLock()
STOP = threading.Event()


def spawn(command, **kwargs):
    # Cancel publishes STOP before taking LOCK; an in-flight spawn registers
    # before the cancellation snapshot and every later spawn is rejected.
    with LOCK:
        if STOP.is_set():raise RuntimeError('Owned process group was cancelled before launch')
        child = subprocess.Popen(command, **kwargs)
        ACTIVE[child.pid] = child
        return child


def release(child):
    if child is not None and child.poll() is not None:
        with LOCK:ACTIVE.pop(child.pid, None)


def terminate(child):
    proof = dict(pid=child.pid, method='already_exited', errors=[], direct_fallback=False)
    if child.poll() is not None:return proof
    if os.name == 'nt':
        proof['method'] = 'taskkill_pid_tree'
        executable = Path(os.environ.get('SystemRoot', 'C:/Windows'))/'System32/taskkill.exe'
        try:
            outcome = subprocess.run([str(executable), '/PID', str(child.pid), '/T', '/F'],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            proof['tree_returncode'] = outcome.returncode
            if outcome.returncode != 0 and child.poll() is None:
                proof['errors'].append('Owned PID tree cleanup failed: '+repr(outcome.stdout))
        except (OSError, subprocess.SubprocessError) as exc:
            proof['errors'].append('Owned PID tree cleanup error: '+repr(exc))
    else:
        proof['method'] = 'owned_process_group'
        try:os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:pass
        except OSError as exc:proof['errors'].append('Owned process group cleanup error: '+repr(exc))
    # Tree cleanup errors remain in evidence even if this exact PID fallback
    # succeeds: direct-parent death does not prove that descendants exited.
    if child.poll() is None:
        proof['direct_fallback'] = True
        try:child.kill()
        except OSError as exc:proof['errors'].append('Exact PID fallback error: '+repr(exc))
    try:child.wait(timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:proof['errors'].append('Owned PID wait error: '+repr(exc))
    if child.poll() is None:proof['errors'].append('Owned PID is still live after cleanup')
    return proof


def cleanup(child):
    try:return terminate(child)
    except BaseException as exc:
        # Preserve the original failure in the caller; cleanup cannot erase it.
        return dict(pid=child.pid, method='cleanup_exception', errors=[repr(exc)], direct_fallback=False)
    finally:release(child)


def cancel_owned():
    STOP.set()
    with LOCK:children=list(ACTIVE.values())
    return [cleanup(child) for child in children]


@contextmanager
def process_pool(max_workers):
    with LOCK:
        if ACTIVE:raise RuntimeError('Cannot start a new pool while prior owned processes remain live')
        STOP.clear()
    pool=ThreadPoolExecutor(max_workers=max_workers)
    try:
        yield pool
    except BaseException as exc:
        proof=cancel_owned()
        errors=[row for row in proof if row['errors']]
        if errors:exc.add_note('Owned process cleanup failures: '+repr(errors))
        pool.shutdown(wait=True,cancel_futures=True)
        raise
    else:
        pool.shutdown(wait=True)
    finally:
        with LOCK:
            if not ACTIVE:STOP.clear()
