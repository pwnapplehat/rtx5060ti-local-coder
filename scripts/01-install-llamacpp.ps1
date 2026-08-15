#Requires -Version 5.1
<#
.SYNOPSIS
  Install llama.cpp CUDA Windows binaries into E:\LlamaCpp (or config path).
#>
[CmdletBinding()]
param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig
if (-not $Tag) {
    $Tag = [string]$cfg.llamaCppTag
    if (-not $Tag) { $Tag = "b10437" }
}
$binDir = [string]$cfg.llamaCppDir
$tmp = Join-Path $binDir "_tmp"
New-Item -ItemType Directory -Force -Path $binDir, $tmp | Out-Null

Write-Host ("==> Installing llama.cpp {0} (CUDA 13.3 Windows) -> {1}" -f $Tag, $binDir)
$llamaUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$Tag/llama-$Tag-bin-win-cuda-13.3-x64.zip"
$cudartUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$Tag/cudart-llama-bin-win-cuda-13.3-x64.zip"
$llamaZip = Join-Path $tmp "llama-cuda.zip"
$cudartZip = Join-Path $tmp "cudart.zip"
& curl.exe -L --retry 5 --retry-delay 2 -o $llamaZip $llamaUrl
if ($LASTEXITCODE -ne 0) { throw "curl llama zip failed" }
& curl.exe -L --retry 5 --retry-delay 2 -o $cudartZip $cudartUrl
if ($LASTEXITCODE -ne 0) { throw "curl cudart zip failed" }
if ((Get-Item $llamaZip).Length -lt 10MB) { throw "llama zip too small" }
if ((Get-Item $cudartZip).Length -lt 1MB) { throw "cudart zip too small" }

$llamaExtract = Join-Path $tmp "llama"
$cudartExtract = Join-Path $tmp "cudart"
if (Test-Path $llamaExtract) { Remove-Item $llamaExtract -Recurse -Force }
if (Test-Path $cudartExtract) { Remove-Item $cudartExtract -Recurse -Force }
Expand-Archive -Path $llamaZip -DestinationPath $llamaExtract -Force
Expand-Archive -Path $cudartZip -DestinationPath $cudartExtract -Force

Get-ChildItem $llamaExtract -Recurse -File | ForEach-Object {
    Copy-Item $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
}
Get-ChildItem $cudartExtract -Recurse -File | ForEach-Object {
    Copy-Item $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
}

Set-Content -Path (Join-Path $binDir "VERSION.txt") -Value $Tag -Encoding ascii
$exe = Join-Path $binDir "llama-server.exe"
if (-not (Test-Path $exe)) { throw "llama-server.exe missing after install" }

Write-Host "==> Devices:"
& $exe --list-devices
Write-Host ("LLAMACPP_OK {0}" -f $Tag)
