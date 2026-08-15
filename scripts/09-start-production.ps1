#Requires -Version 5.1
<#
.SYNOPSIS
  Production start: llama-server + auth proxy + Cloudflare tunnel.
#>
[CmdletBinding()]
param(
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
. (Join-Path $here "_common.ps1")
$cfg = Get-ModelsConfig
if (-not $Model) { $Model = Get-DefaultModelId -Config $cfg }
else { Assert-KnownModel -ModelId $Model -Config $cfg }

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
Write-Host ("Cursor model: {0}" -f $Model)
Write-Host "Compact:      compact3b on :18081 (CPU-only, never touches coding VRAM)"
