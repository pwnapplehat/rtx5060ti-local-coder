#Requires -Version 5.1
<#
.SYNOPSIS
  Shared helpers for llama.cpp production stack.
#>

function Get-RepoRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-ModelsConfig {
    $path = Join-Path (Get-RepoRoot) "config\models.json"
    if (-not (Test-Path $path)) { throw "Missing $path" }
    return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Resolve-GgufPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId,
        [Parameter(Mandatory = $true)]
        $Config
    )
    $entry = $Config.models.$ModelId
    if (-not $entry) { throw "Unknown model id: $ModelId" }
    $dir = [string]$entry.dir
    if (-not (Test-Path $dir)) { throw "Model directory missing: $dir (run install / pull first)" }
    $glob = [string]$entry.ggufGlob
    if (-not $glob) { $glob = "*UD-Q4_K_XL*.gguf" }
    $files = @(Get-ChildItem -Path $dir -Recurse -Filter $glob -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        # Fallback: any gguf in dir
        $files = @(Get-ChildItem -Path $dir -Recurse -Filter "*.gguf" -File -ErrorAction SilentlyContinue)
    }
    if ($files.Count -eq 0) {
        throw ("No GGUF matching {0} under {1}. Run scripts\\02-pull-models.ps1" -f $glob, $dir)
    }
    return ($files | Sort-Object Length -Descending | Select-Object -First 1).FullName
}

function Resolve-CompactGgufPath {
    param([Parameter(Mandatory = $true)]$Config)
    $c = $Config.compactModel
    if (-not $c) { throw "config.compactModel missing in models.json" }
    $dir = [string]$c.dir
    if (-not (Test-Path $dir)) { throw "Compact model directory missing: $dir" }
    $glob = [string]$c.ggufGlob
    if (-not $glob) { $glob = "*Q4_K_M*.gguf" }
    $files = @(Get-ChildItem -Path $dir -Recurse -Filter $glob -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -Path $dir -Recurse -Filter "*.gguf" -File -ErrorAction SilentlyContinue)
    }
    if ($files.Count -eq 0) {
        throw ("No compact GGUF under {0}. Run scripts\\02-pull-models.ps1 -Target compact" -f $dir)
    }
    return ($files | Sort-Object Length -Descending | Select-Object -First 1).FullName
}

function Get-LlamaServerExe {
    param($Config)
    $exe = Join-Path ([string]$Config.llamaCppDir) "llama-server.exe"
    if (-not (Test-Path $exe)) {
        throw ("llama-server.exe not found at {0}. Run scripts\\01-install-llamacpp.ps1" -f $exe)
    }
    return $exe
}

function Get-PhysicalCoreCount {
    try {
        $sum = (Get-CimInstance Win32_Processor -ErrorAction Stop |
            Measure-Object -Property NumberOfCores -Sum).Sum
        if ($sum -gt 0) { return [int]$sum }
    } catch {}
    return [int][Environment]::ProcessorCount
}

function Resolve-CpuThreadCount {
    <#
      Prefer physical cores (i5-14400 = 10). Hyperthread oversubscription usually
      hurts llama.cpp matmul more than it helps. Config override wins when > 0.
    #>
    param(
        [int]$Configured = 0,
        [int]$Floor = 4
    )
    if ($Configured -gt 0) { return $Configured }
    $cores = Get-PhysicalCoreCount
    $logical = [int][Environment]::ProcessorCount
    # Leave a little headroom on heavily SMT CPUs for OS / Cursor / tunnel.
    if ($logical -gt $cores -and $cores -gt ($Floor + 1)) {
        $cores = [Math]::Max($Floor, $cores)
    }
    return [Math]::Max($Floor, $cores)
}

function Test-TcpPortOpen {
    param([string]$HostName = "127.0.0.1", [int]$Port, [int]$TimeoutMs = 800)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) { $client.Close(); return $false }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Wait-LlamaServerHealthy {
    param(
        [string]$BaseUrl = "http://127.0.0.1:18080",
        [int]$TimeoutSec = 600
    )
    return ((Wait-LlamaServerStartState -BaseUrl $BaseUrl -TimeoutSec $TimeoutSec) -eq "ok")
}

function Wait-LlamaServerStartState {
    param(
        [string]$BaseUrl = "http://127.0.0.1:18080",
        [int]$TimeoutSec = 600,
        [string]$ErrLog = "",
        [int]$ProcessId = 0
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($ProcessId -gt 0 -and -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            return "dead"
        }
        if ($ErrLog -and (Test-Path $ErrLog)) {
            $tail = ""
            try { $tail = Get-Content $ErrLog -Raw -ErrorAction SilentlyContinue } catch {}
            if ($tail -and ($tail -match 'CUDA error|launch_fattn|shared object initialization failed')) {
                return "cuda-crash"
            }
        }
        try {
            $r = Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + "/health") -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return "ok" }
        } catch {}
        Start-Sleep -Seconds 2
    }
    return "timeout"
}

function Stop-LlamaServerByPort {
    param(
        [string]$RuntimeDir,
        [string]$PidFileName,
        [int]$Port,
        [int]$SettleSeconds = 8
    )
    $pidFile = Join-Path $RuntimeDir $PidFileName
    $settleStart = Get-Date
    if (Test-Path $pidFile) {
        $old = 0
        [void][int]::TryParse(((Get-Content $pidFile -Raw).Trim()), [ref]$old)
        if ($old -gt 0) {
            Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match ("--port\s+{0}\b" -f $Port) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    # Blackwell flash-attn init is flaky if the next load races a just-killed CUDA context.
    if ($SettleSeconds -lt 1) { $SettleSeconds = 1 }
    Write-Host ("GPU settle {0}s after stop (port {1})..." -f $SettleSeconds, $Port)
    $portDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $portDeadline) {
        $busy = $false
        if (Test-TcpPortOpen -HostName "127.0.0.1" -Port $Port -TimeoutMs 200) { $busy = $true }
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match ("--port\s+{0}\b" -f $Port) })
        if ($procs.Count -gt 0) { $busy = $true }
        if (-not $busy) { break }
        Start-Sleep -Seconds 1
    }

    $elapsed = ((Get-Date) - $settleStart).TotalSeconds
    $need = [Math]::Ceiling($SettleSeconds - $elapsed)
    if ($need -gt 0) { Start-Sleep -Seconds $need }
}

function Stop-LlamaServer {
    param(
        [string]$RuntimeDir,
        $Config = $null
    )
    $port = 18080
    $settle = 8
    if ($Config -and $null -ne $Config.llamaServerPort) {
        $port = [int]$Config.llamaServerPort
    } elseif (Test-Path (Join-Path (Get-RepoRoot) "config\models.json")) {
        try {
            $c = Get-ModelsConfig
            if ($null -ne $c.llamaServerPort) { $port = [int]$c.llamaServerPort }
            if ($null -ne $c.gpuSettleSeconds) { $settle = [int]$c.gpuSettleSeconds }
            $Config = $c
        } catch {}
    }
    if ($Config -and $null -ne $Config.gpuSettleSeconds) {
        $settle = [int]$Config.gpuSettleSeconds
    }
    Stop-LlamaServerByPort -RuntimeDir $RuntimeDir -PidFileName "llama-server.pid" -Port $port -SettleSeconds $settle
}

function Stop-CompactServer {
    param(
        [string]$RuntimeDir,
        $Config = $null
    )
    $port = 18081
    if ($Config -and $Config.compactModel -and $null -ne $Config.compactModel.port) {
        $port = [int]$Config.compactModel.port
    } elseif (Test-Path (Join-Path (Get-RepoRoot) "config\models.json")) {
        try {
            $c = Get-ModelsConfig
            if ($c.compactModel -and $null -ne $c.compactModel.port) {
                $port = [int]$c.compactModel.port
            }
        } catch {}
    }
    Stop-LlamaServerByPort -RuntimeDir $RuntimeDir -PidFileName "compact-server.pid" -Port $port -SettleSeconds 2
}
