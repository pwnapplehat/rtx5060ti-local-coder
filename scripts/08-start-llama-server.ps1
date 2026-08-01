#Requires -Version 5.1
<#
.SYNOPSIS
  Start (or restart) llama-server with a Cursor model id.

.NOTES
  Do NOT force -ngl when --fit is on. Forcing n_gpu_layers aborts llama.cpp's
  VRAM fitter, which tanks large-prompt eval on 16GB MoE models.

  On RTX 50-series (Blackwell), flash-attn kernel init can fail intermittently
  right after a hot model swap. We settle the GPU, then retry the start.
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

$startRetries = 3
if ($null -ne $cfg.startRetries -and [int]$cfg.startRetries -gt 0) {
    $startRetries = [int]$cfg.startRetries
}
$healthTimeoutSec = 900
if ($null -ne $cfg.healthTimeoutSec -and [int]$cfg.healthTimeoutSec -gt 0) {
    $healthTimeoutSec = [int]$cfg.healthTimeoutSec
}

$cpuThreads = Resolve-CpuThreadCount -Configured $(
    if ($null -ne $cfg.cpuThreads) { [int]$cfg.cpuThreads } else { 0 }
)
$cpuThreadsBatch = $cpuThreads
if ($null -ne $cfg.cpuThreadsBatch -and [int]$cfg.cpuThreadsBatch -gt 0) {
    $cpuThreadsBatch = [int]$cfg.cpuThreadsBatch
}

$serverArgs = @(
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
    $serverArgs += @("-fa", "on")
}

if ($useFit) {
    # Leave -ngl unset so fit can place layers/experts for free VRAM.
    $serverArgs += @("--fit", "on")
    $fitTarget = 1024
    if ($null -ne $cfg.fitTargetMiB) { $fitTarget = [int]$cfg.fitTargetMiB }
    $fitCtx = [int]$cfg.contextSize
    if ($null -ne $cfg.fitCtxMin) { $fitCtx = [int]$cfg.fitCtxMin }
    $serverArgs += @("--fit-target", "$fitTarget", "--fit-ctx", "$fitCtx")
} else {
    $ngl = 99
    if ($null -ne $cfg.gpuLayers) { $ngl = [int]$cfg.gpuLayers }
    $serverArgs += @("-ngl", "$ngl")
    $nCpuMoe = 0
    if ($null -ne $entry.nCpuMoe) { $nCpuMoe = [int]$entry.nCpuMoe }
    if ($nCpuMoe -gt 0) {
        $serverArgs += @("-ncmoe", "$nCpuMoe")
    }
}

$outLog = Join-Path $runtime "llama-server-out.log"
$errLog = Join-Path $runtime "llama-server-err.log"
$ok = $false
$finalPid = 0

for ($attempt = 1; $attempt -le $startRetries; $attempt++) {
    Write-Host ("=== start attempt {0}/{1} ===" -f $attempt, $startRetries)
    Write-Host "Stopping previous llama-server..."
    Stop-LlamaServer -RuntimeDir $runtime -Config $cfg

    if (Test-TcpPortOpen -HostName $hostName -Port $port) {
        throw ("Port {0}:{1} still in use after settle. Free the port or raise gpuSettleSeconds." -f $hostName, $port)
    }

    Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue

    Write-Host ("Starting llama-server model={0} fit={1} threads={2}/{3}" -f $Model, $useFit, $cpuThreads, $cpuThreadsBatch)
    Write-Host ("GGUF={0}" -f $gguf)
    Write-Host ("Args: {0}" -f ($serverArgs -join " "))

    $proc = Start-Process -FilePath $exe `
        -ArgumentList $serverArgs `
        -WorkingDirectory ([string]$cfg.llamaCppDir) `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog

    $finalPid = $proc.Id
    $proc.Id | Set-Content (Join-Path $runtime "llama-server.pid") -Encoding ascii
    $Model | Set-Content (Join-Path $runtime "active-model.txt") -Encoding ascii -NoNewline

    Write-Host "Waiting for /health (model load + fit can take minutes)..."
    $state = Wait-LlamaServerStartState -BaseUrl $base -TimeoutSec $healthTimeoutSec -ErrLog $errLog -ProcessId $proc.Id
    if ($state -eq "ok") {
        $ok = $true
        break
    }

    Write-Warning ("llama-server start attempt {0} failed: {1}" -f $attempt, $state)
    if (Test-Path $errLog) {
        Write-Host "--- llama-server-err.log (tail) ---"
        Get-Content $errLog -Tail 25 -ErrorAction SilentlyContinue
    }
    Stop-LlamaServer -RuntimeDir $runtime -Config $cfg

    if ($attempt -lt $startRetries -and ($state -eq "cuda-crash" -or $state -eq "dead")) {
        Write-Host "Retrying after extra GPU settle (Blackwell flash-attn init can be intermittent)..."
        Start-Sleep -Seconds 5
        continue
    }
    if ($attempt -ge $startRetries) { break }
    Start-Sleep -Seconds 3
}

if (-not $ok) {
    throw ("llama-server failed after {0} attempts. See {1} and {2}" -f $startRetries, $outLog, $errLog)
}

Write-Host ("LLAMA_SERVER_OK model={0} pid={1} url={2}" -f $Model, $finalPid, $base)
