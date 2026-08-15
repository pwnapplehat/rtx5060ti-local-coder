#Requires -Version 5.1
<#
.SYNOPSIS
  Structure + compact health + optional live chat smoke against auth proxy.
#>
[CmdletBinding()]
param(
    [switch]$SkipPublicChat
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "=== structure ==="
& (Join-Path $PSScriptRoot "..\tests\01-structure.ps1")

. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig
foreach ($id in (Get-ModelIds -Config $cfg)) {
    $null = Resolve-GgufPath -ModelId $id -Config $cfg
}
$null = Resolve-CompactGgufPath -Config $cfg
Write-Host "GGUF_OK (coding + compact)"

$keyFile = Join-Path $root "runtime\api-key.txt"
if (-not (Test-Path $keyFile)) { throw "Missing runtime/api-key.txt - run start.bat once" }
$key = (Get-Content $keyFile -Raw).Trim()

$hostName = [string]$cfg.llamaServerHost
$compactPort = 18081
if ($cfg.compactModel -and $null -ne $cfg.compactModel.port) {
    $compactPort = [int]$cfg.compactModel.port
}
$compactAlias = "compact3b"
if ($cfg.compactModel -and $cfg.compactModel.alias) {
    $compactAlias = [string]$cfg.compactModel.alias
}

Write-Host "=== compact sidecar health ==="
$ch = Invoke-RestMethod -Uri ("http://{0}:{1}/health" -f $hostName, $compactPort) -TimeoutSec 5
Write-Host ($ch | ConvertTo-Json -Compress)

Write-Host "=== auth proxy health ==="
$h = Invoke-RestMethod -Uri "http://127.0.0.1:11435/healthz" -TimeoutSec 5
if ($h.status -ne "ok") { throw "auth-proxy unhealthy" }
if ("$($h.compactUpstreamHealth)" -ne "200") {
    throw ("compact upstream unhealthy: {0}" -f $h.compactUpstreamHealth)
}
if (-not $h.useCompactSidecar) {
    Write-Warning "useCompactSidecar is false - summarization will hit the coding GPU"
}
Write-Host ($h | ConvertTo-Json -Compress)

if (-not $SkipPublicChat) {
    $defaultId = Get-DefaultModelId -Config $cfg
    Write-Host ("=== local chat smoke ({0}) ===" -f $defaultId)
    $body = @{
        model = $defaultId
        messages = @(@{ role = "user"; content = "Reply with exactly READY" })
        temperature = 0
        max_tokens = 16
        stream = $false
    } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:11435/v1/chat/completions" `
        -Method Post -Body $body -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 600
    $content = [string]$r.choices[0].message.content
    Write-Host ("reply={0}" -f $content)
    if ($content -notmatch "READY") {
        Write-Warning "Unexpected reply content (thinking models may wrap text)"
    }

    Write-Host "=== compact sidecar smoke ==="
    $cbody = @{
        model = $compactAlias
        messages = @(
            @{ role = "system"; content = "Compress prior coding-agent context. Dense factual brief only." }
            @{ role = "user"; content = "Continuity brief: stack uses compact3b CPU sidecar. Reply with exactly COMPACT_READY" }
        )
        temperature = 0
        max_tokens = 32
        stream = $false
    } | ConvertTo-Json -Depth 5
    $cr = Invoke-RestMethod -Uri ("http://{0}:{1}/v1/chat/completions" -f $hostName, $compactPort) `
        -Method Post -Body $cbody -ContentType "application/json" -TimeoutSec 120
    $ccontent = [string]$cr.choices[0].message.content
    Write-Host ("compact_reply={0}" -f $ccontent)
    if ($ccontent -notmatch "COMPACT_READY") {
        Write-Warning "Compact sidecar reply unexpected (still usable if non-empty)"
    }
}

Write-Host "VERIFY_OK"
