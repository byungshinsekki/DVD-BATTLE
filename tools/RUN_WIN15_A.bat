@echo off
rem V1.5 Windows release checks, stage A (tests, regression, export, visual QA, exported EXE start).
cd /d "%~dp0"
echo DVD BATTLE V1.5 - Windows stage A running. Progress: ..\reports\win15_progress_A.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_release_15.ps1" -Stage A > "%~dp0..\reports\win15_console_A.log" 2>&1
echo Stage A finished.
