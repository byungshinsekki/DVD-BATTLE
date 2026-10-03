@echo off
rem V1.5 Windows visual/UI checks only (rendered UI suites and gameplay screenshots).
cd /d "%~dp0"
echo DVD BATTLE V1.5 - Windows visual stage running. Progress: ..\reports\win15_progress_V.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_release_15.ps1" -Stage V > "%~dp0..\reports\win15_console_V.log" 2>&1
echo Visual stage finished.
