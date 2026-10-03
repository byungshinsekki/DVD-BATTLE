#!/usr/bin/env bash
# Compatibility entry point. Python owns validation, isolation and failures.
# Explicit installed interpreter only; no python/py discovery or installation.
set -euo pipefail
: "${PYTHON_EXE:?Set PYTHON_EXE to the full path of an already installed Python interpreter}"
python_path="${PYTHON_EXE//\\//}"
case "$python_path" in
  /*|[A-Za-z]:/*) ;;
  *) printf '%s\n' 'PYTHON_EXE must be an absolute interpreter path' >&2; exit 127 ;;
esac
case "${python_path,,}" in
  */windowsapps/*|*/py|*/py.exe)
    printf '%s\n' 'Launchers and Store aliases are unsupported; choose the installed interpreter' >&2
    exit 127 ;;
esac
if [[ ! -f "$PYTHON_EXE" || ! -x "$PYTHON_EXE" ]]; then
  printf '%s\n' 'PYTHON_EXE is missing or not executable; no fallback is attempted' >&2
  exit 127
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$PYTHON_EXE" -B -X utf8 "$script_dir/run_forced.py" "$@"
