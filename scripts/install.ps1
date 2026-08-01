#Requires -Version 5.1
<#
.SYNOPSIS
  From-scratch / repair install for llama.cpp + Unsloth UD dual-model Cursor stack.
#>
[CmdletBinding()]
param(
    [switch]$SkipPull,
    [switch]$StartAfter
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

Write-Host "=== 01 install llama.cpp ==="
& (Join-Path $here "01-install-llamacpp.ps1")

if (-not $SkipPull) {
    Write-Host "=== 02 pull models (coding + compact) ==="
    & (Join-Path $here "02-pull-models.ps1") -Target all
}

Write-Host "=== ensure API key ==="
& (Join-Path $here "07-ensure-api-key.ps1") | Out-Null

Write-Host ""
Write-Host "INSTALL_OK"
Write-Host "Implement model : qwen3coder30b  (Qwen3-Coder 30B Unsloth UD-Q4_K_XL)"
Write-Host "Planner model   : qwen3635b      (Qwen3.6 35B-A3B Unsloth UD-Q4_K_XL)"
Write-Host "Compact sidecar : compact3b     (Qwen2.5-3B-Instruct Q4_K_M, CPU :18081)"
Write-Host "Start           : start.bat"

if ($StartAfter) {
    & (Join-Path $here "09-start-production.ps1") -Model qwen3coder30b
}
