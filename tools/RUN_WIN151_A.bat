@echo off
rem V1.5.1 Windows release checks, stage A (import, data fingerprint vs V1.5, tests, regression, export, visual QA, exported EXE start).
cd /d "%~dp0"
echo DVD BATTLE V1.5.1 - Windows stage A running. Progress: ..\reports\win151_progress_A.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_release_151.ps1" -Stage A > "%~dp0..\reports\win151_console_A.log" 2>&1
echo Stage A finished.
