#Requires -Version 5.1
<#
.SYNOPSIS
  Download Unsloth GGUFs + optional CPU compact sidecar.
#>
[CmdletBinding()]
param(
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig
$ids = Get-ModelIds -Config $cfg

$env:HF_XET_HIGH_PERFORMANCE = "1"
$token = [Environment]::GetEnvironmentVariable("HF_TOKEN", "User")
if (-not $token) { $token = $env:HF_TOKEN }
if ($token) {
    $env:HF_TOKEN = $token
    $env:HUGGING_FACE_HUB_TOKEN = $token
    Write-Host "Using HF_TOKEN from environment (authenticated downloads)."
} else {
    Write-Warning "HF_TOKEN not set - Hub rate limits will be lower. Set User env HF_TOKEN then re-run."
}

function Pull-CodingModel {
    param([string]$Id)
    Assert-KnownModel -ModelId $Id -Config $cfg
    $entry = $cfg.models.$Id
    $dir = [string]$entry.dir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Host ("==> hf download {0} ({1})" -f $entry.repo, $entry.include)
    & hf download $entry.repo --include $entry.include --local-dir $dir
    if ($LASTEXITCODE -ne 0) { throw "hf download failed for $Id (exit $LASTEXITCODE)" }
    $gguf = Resolve-GgufPath -ModelId $Id -Config $cfg
    Write-Host ("OK {0} -> {1}" -f $Id, $gguf)
}

function Pull-CompactModel {
    $c = $cfg.compactModel
    if (-not $c) { throw "config.compactModel missing" }
    $dir = [string]$c.dir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Host ("==> hf download compact {0} ({1})" -f $c.repo, $c.include)
    & hf download $c.repo --include $c.include --local-dir $dir
    if ($LASTEXITCODE -ne 0) { throw "hf download failed for compact model (exit $LASTEXITCODE)" }
    $gguf = Resolve-CompactGgufPath -Config $cfg
    Write-Host ("OK compact -> {0}" -f $gguf)
}

if ($Target -eq "all") {
    foreach ($id in $ids) { Pull-CodingModel $id }
    Pull-CompactModel
} elseif ($Target -eq "compact") {
    Pull-CompactModel
} else {
    Pull-CodingModel $Target
}

Write-Host "PULL_OK"
Get-ChildItem ([string]$cfg.modelsRoot) -Recurse -Filter *.gguf -File |
    Select-Object FullName, @{ n = "GB"; e = { [math]::Round($_.Length / 1GB, 2) } } |
    Format-Table -AutoSize
