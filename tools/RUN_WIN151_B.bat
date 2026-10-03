@echo off
rem V1.5.1 Windows release checks, stage B (cache-free copy of the source tree: import, start, deathmatch suite).
cd /d "%~dp0"
echo DVD BATTLE V1.5.1 - Windows stage B running. Progress: ..\reports\win151_progress_B.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_release_151.ps1" -Stage B > "%~dp0..\reports\win151_console_B.log" 2>&1
echo Stage B finished.
