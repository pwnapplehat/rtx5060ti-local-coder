#Requires -Version 5.1
<#
.SYNOPSIS
  Local smoke against llama-server OpenAI API (no tunnel).

.PARAMETER Target
  coding = implement/plan model on :18080
  compact = CPU compact sidecar on :18081
#>
[CmdletBinding()]
param(
    [ValidateSet("coding", "compact")]
    [string]$Target = "coding",
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig
if (-not $Model) { $Model = Get-DefaultModelId -Config $cfg }
else { Assert-KnownModel -ModelId $Model -Config $cfg }

if ($Target -eq "compact") {
    $port = 18081
    if ($cfg.compactModel -and $null -ne $cfg.compactModel.port) {
        $port = [int]$cfg.compactModel.port
    }
    $alias = "compact3b"
    if ($cfg.compactModel -and $cfg.compactModel.alias) {
        $alias = [string]$cfg.compactModel.alias
    }
    $base = "http://{0}:{1}" -f [string]$cfg.llamaServerHost, $port
    $expect = "COMPACT_SMOKE_OK"
    $body = @{
        model = $alias
        messages = @(
            @{ role = "system"; content = "Compress prior coding-agent context. Dense factual brief only." }
            @{ role = "user"; content = ("Continuity brief pad. Reply with exactly {0}" -f $expect) }
        )
        temperature = 0
        max_tokens = 32
        stream = $false
    } | ConvertTo-Json -Depth 5
} else {
    $base = "http://{0}:{1}" -f [string]$cfg.llamaServerHost, [int]$cfg.llamaServerPort
    $expect = "SMOKE_OK"
    $body = @{
        model = $Model
        messages = @(@{ role = "user"; content = ("Reply with exactly {0}" -f $expect) })
        temperature = 0
        max_tokens = 32
        stream = $false
    } | ConvertTo-Json -Depth 5
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod -Uri ($base + "/v1/chat/completions") -Method Post -Body $body -ContentType "application/json" -TimeoutSec 600
$sw.Stop()
$reply = [string]$r.choices[0].message.content
Write-Host ("target={0} base={1} ms={2} reply={3}" -f $Target, $base, $sw.ElapsedMilliseconds, $reply)
if ($reply -notmatch [regex]::Escape($expect)) {
    Write-Warning ("Reply did not contain {0}" -f $expect)
}
Write-Host "SMOKE_OK"
