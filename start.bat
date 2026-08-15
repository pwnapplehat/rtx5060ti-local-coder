@echo off
setlocal
cd /d "%~dp0"
echo Starting llama.cpp production stack...
echo Cursor model: qwen3827b
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\09-start-production.ps1"
if errorlevel 1 exit /b 1
