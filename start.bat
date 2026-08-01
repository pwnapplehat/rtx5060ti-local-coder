@echo off
setlocal
cd /d "%~dp0"
echo Starting llama.cpp production stack...
echo Implement: qwen3coder30b
echo Planner:   qwen3635b
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\09-start-production.ps1" -Model qwen3coder30b
if errorlevel 1 exit /b 1
