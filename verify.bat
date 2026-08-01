@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\14-verify.ps1" %*
exit /b %ERRORLEVEL%
