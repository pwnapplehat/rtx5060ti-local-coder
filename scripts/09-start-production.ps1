#Requires -Version 5.1
<#
.SYNOPSIS
  Production start: llama-server + auth proxy + Cloudflare tunnel.
#>
[CmdletBinding()]
param(
    [ValidateSet("qwen3coder30b", "qwen3635b")]
    [string]$Model = "qwen3coder30b"
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

Write-Host "=== stop previous stack ==="
& (Join-Path $here "10-stop-production.ps1") -Quiet

Write-Host "=== llama-server (coding) ==="
& (Join-Path $here "08-start-llama-server.ps1") -Model $Model

Write-Host "=== compact sidecar (CPU Qwen2.5-3B) ==="
& (Join-Path $here "08-start-compact-server.ps1")

Write-Host "=== auth proxy ==="
& (Join-Path $here "08-start-auth-proxy.ps1")

Write-Host "=== cloudflare tunnel -> auth proxy :11435 ==="
& (Join-Path $here "05-start-cloudflare-tunnel.ps1") -LocalPort 11435

Write-Host "PRODUCTION_STACK_UP"
Write-Host "Cursor models: qwen3coder30b (implement) | qwen3635b (plan)"
Write-Host "Compact:       compact3b on :18081 (CPU-only, never touches coding VRAM)"
