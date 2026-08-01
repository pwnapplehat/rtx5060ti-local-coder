#Requires -Version 5.1
<#
.SYNOPSIS
  Start (or restart) llama-server with a Cursor model id.

.NOTES
  Do NOT force -ngl when --fit is on. Forcing n_gpu_layers aborts llama.cpp's
  VRAM fitter, which tanks large-prompt eval on 16GB MoE models.
#>
[CmdletBinding()]
param(
    [ValidateSet("qwen3coder30b", "qwen3635b")]
    [string]$Model = "qwen3coder30b"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")

$cfg = Get-ModelsConfig
$root = Get-RepoRoot
$runtime = Join-Path $root "runtime"
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$exe = Get-LlamaServerExe -Config $cfg
$gguf = Resolve-GgufPath -ModelId $Model -Config $cfg
$entry = $cfg.models.$Model
$hostName = [string]$cfg.llamaServerHost
$port = [int]$cfg.llamaServerPort
$base = "http://{0}:{1}" -f $hostName, $port
$useFit = $true
if ($null -ne $cfg.fit) { $useFit = [bool]$cfg.fit }

Write-Host ("Stopping previous llama-server...")
Stop-LlamaServer -RuntimeDir $runtime
Start-Sleep -Seconds 1

if (Test-TcpPortOpen -HostName $hostName -Port $port) {
    throw ("Port {0}:{1} is already in use by another process (Docker/WSL often binds 8080). Change llamaServerPort in config\\models.json or free the port." -f $hostName, $port)
}

$outLog = Join-Path $runtime "llama-server-out.log"
$errLog = Join-Path $runtime "llama-server-err.log"
Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue

$cpuThreads = Resolve-CpuThreadCount -Configured $(
    if ($null -ne $cfg.cpuThreads) { [int]$cfg.cpuThreads } else { 0 }
)
$cpuThreadsBatch = $cpuThreads
if ($null -ne $cfg.cpuThreadsBatch -and [int]$cfg.cpuThreadsBatch -gt 0) {
    $cpuThreadsBatch = [int]$cfg.cpuThreadsBatch
}

$args = @(
    "-m", $gguf,
    "--host", $hostName,
    "--port", "$port",
    "--alias", $Model,
    "-c", ("{0}" -f [int]$cfg.contextSize),
    "-np", ("{0}" -f [int]$cfg.parallelSlots),
    "-t", "$cpuThreads",
    "-tb", "$cpuThreadsBatch",
    "--cache-type-k", ([string]$cfg.cacheTypeK),
    "--cache-type-v", ([string]$cfg.cacheTypeV),
    "--jinja",
    "--load-mode", "none"
)

if ([bool]$cfg.flashAttention) {
    $args += @("-fa", "on")
}

if ($useFit) {
    # Leave -ngl unset so fit can place layers/experts for free VRAM.
    $args += @("--fit", "on")
    $fitTarget = 1024
    if ($null -ne $cfg.fitTargetMiB) { $fitTarget = [int]$cfg.fitTargetMiB }
    $fitCtx = [int]$cfg.contextSize
    if ($null -ne $cfg.fitCtxMin) { $fitCtx = [int]$cfg.fitCtxMin }
    $args += @("--fit-target", "$fitTarget", "--fit-ctx", "$fitCtx")
} else {
    $ngl = 99
    if ($null -ne $cfg.gpuLayers) { $ngl = [int]$cfg.gpuLayers }
    $args += @("-ngl", "$ngl")
    $nCpuMoe = 0
    if ($null -ne $entry.nCpuMoe) { $nCpuMoe = [int]$entry.nCpuMoe }
    if ($nCpuMoe -gt 0) {
        $args += @("-ncmoe", "$nCpuMoe")
    }
}

Write-Host ("Starting llama-server model={0} fit={1} threads={2}/{3}" -f $Model, $useFit, $cpuThreads, $cpuThreadsBatch)
Write-Host ("GGUF={0}" -f $gguf)
Write-Host ("Args: {0}" -f ($args -join " "))

$proc = Start-Process -FilePath $exe `
    -ArgumentList $args `
    -WorkingDirectory ([string]$cfg.llamaCppDir) `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog

$proc.Id | Set-Content (Join-Path $runtime "llama-server.pid") -Encoding ascii
$Model | Set-Content (Join-Path $runtime "active-model.txt") -Encoding ascii -NoNewline

Write-Host "Waiting for /health (model load + fit can take minutes)..."
if (-not (Wait-LlamaServerHealthy -BaseUrl $base -TimeoutSec 900)) {
    throw ("llama-server failed to become healthy. See {0} and {1}" -f $outLog, $errLog)
}

Write-Host ("LLAMA_SERVER_OK model={0} pid={1} url={2}" -f $Model, $proc.Id, $base)
