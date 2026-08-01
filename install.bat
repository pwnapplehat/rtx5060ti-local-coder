@echo off
setlocal
cd /d "%~dp0"
echo Installing llama.cpp + Unsloth UD models (long download)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
if errorlevel 1 exit /b 1
echo.
echo Done. Run start.bat next.
