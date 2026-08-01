#Requires -Version 5.1
<#
.SYNOPSIS
  Start CPU-only compact sidecar (Qwen2.5-3B) for context summarization.

.NOTES
  Runs on :18081 with -ngl 0 so it never fights the 16GB coding model for VRAM.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")

$cfg = Get-ModelsConfig
$root = Get-RepoRoot
$runtime = Join-Path $root "runtime"
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$compact = $cfg.compactModel
if (-not $compact) { throw "config.compactModel missing" }

$hostName = [string]$cfg.llamaServerHost
$port = 18081
if ($null -ne $compact.port) { $port = [int]$compact.port }
$base = "http://{0}:{1}" -f $hostName, $port
$exe = Get-LlamaServerExe -Config $cfg
$gguf = Resolve-CompactGgufPath -Config $cfg
$alias = "compact3b"
if ($compact.alias) { $alias = [string]$compact.alias }
$ctx = 8192
if ($null -ne $compact.contextSize) { $ctx = [int]$compact.contextSize }
$configuredThreads = 0
if ($null -ne $compact.threads) { $configuredThreads = [int]$compact.threads }
elseif ($null -ne $cfg.cpuThreads) { $configuredThreads = [int]$cfg.cpuThreads }
$threads = Resolve-CpuThreadCount -Configured $configuredThreads

Write-Host "Stopping previous compact-server..."
Stop-CompactServer -RuntimeDir $runtime

if (Test-TcpPortOpen -HostName $hostName -Port $port) {
    throw ("Compact port {0}:{1} already in use." -f $hostName, $port)
}

$outLog = Join-Path $runtime "compact-server-out.log"
$errLog = Join-Path $runtime "compact-server-err.log"
Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue

# CPU-only: do not touch RTX VRAM while coder/planner is loaded.
$args = @(
    "-m", $gguf,
    "--host", $hostName,
    "--port", "$port",
    "--alias", $alias,
    "-c", "$ctx",
    "-ngl", "0",
    "-t", "$threads",
    "-np", "1",
    "--jinja",
    "--load-mode", "mmap"
)

Write-Host ("Starting compact-server alias={0} (CPU-only) threads={1}" -f $alias, $threads)
Write-Host ("GGUF={0}" -f $gguf)
Write-Host ("Args: {0}" -f ($args -join " "))

$proc = Start-Process -FilePath $exe `
    -ArgumentList $args `
    -WorkingDirectory ([string]$cfg.llamaCppDir) `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog

$proc.Id | Set-Content (Join-Path $runtime "compact-server.pid") -Encoding ascii

Write-Host "Waiting for compact /health..."
if (-not (Wait-LlamaServerHealthy -BaseUrl $base -TimeoutSec 180)) {
    throw ("compact-server failed to become healthy. See {0} and {1}" -f $outLog, $errLog)
}

Write-Host ("COMPACT_SERVER_OK pid={0} url={1}" -f $proc.Id, $base)
