@echo off
rem V1.5.1 Windows visual/UI checks only (rendered UI suites incl. codex_ui_151, screenshots copied to reports\visual_151).
cd /d "%~dp0"
echo DVD BATTLE V1.5.1 - Windows visual stage running. Progress: ..\reports\win151_progress_V.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_release_151.ps1" -Stage V > "%~dp0..\reports\win151_console_V.log" 2>&1
echo Visual stage finished.
