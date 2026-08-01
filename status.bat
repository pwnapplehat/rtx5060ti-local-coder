@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\13-status.ps1"
exit /b %ERRORLEVEL%
