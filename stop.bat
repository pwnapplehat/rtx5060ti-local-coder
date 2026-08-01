@echo off
setlocal
cd /d "%~dp0"
echo === stop production stack ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\10-stop-production.ps1"
exit /b %ERRORLEVEL%
