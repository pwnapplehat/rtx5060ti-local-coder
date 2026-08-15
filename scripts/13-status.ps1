#Requires -Version 5.1
<#
.SYNOPSIS
  Status for llama.cpp Cursor stack.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig
$root = Get-RepoRoot
$runtime = Join-Path $root "runtime"

Write-Host "=== GPU ==="
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader

Write-Host "`n=== llama.cpp ==="
$ver = Join-Path ([string]$cfg.llamaCppDir) "VERSION.txt"
if (Test-Path $ver) { Get-Content $ver }
$exe = Join-Path ([string]$cfg.llamaCppDir) "llama-server.exe"
Write-Host ("llama-server.exe exists={0}" -f (Test-Path $exe))

Write-Host "`n=== GGUFs ==="
foreach ($id in (Get-ModelIds -Config $cfg)) {
    try {
        $p = Resolve-GgufPath -ModelId $id -Config $cfg
        $len = (Get-Item $p).Length
        Write-Host ("{0}: {1} ({2:N2} GB)" -f $id, $p, ($len / 1GB))
    } catch {
        Write-Host ("{0}: MISSING ({1})" -f $id, $_.Exception.Message)
    }
}
try {
    $cp = Resolve-CompactGgufPath -Config $cfg
    $clen = (Get-Item $cp).Length
    Write-Host ("compact3b: {0} ({1:N2} GB)" -f $cp, ($clen / 1GB))
} catch {
    Write-Host ("compact3b: MISSING ({0})" -f $_.Exception.Message)
}

Write-Host "`n=== runtime ==="
$active = Join-Path $runtime "active-model.txt"
if (Test-Path $active) { Write-Host ("active-model={0}" -f (Get-Content $active -Raw).Trim()) }
$url = Join-Path $runtime "public-base-url.txt"
if (Test-Path $url) { Write-Host ("public-url={0}" -f (Get-Content $url -Raw).Trim()) }

Write-Host "`n=== processes ==="
Get-Process llama-server, node, cloudflared -ErrorAction SilentlyContinue |
    Select-Object ProcessName, Id, @{ n = "MB"; e = { [math]::Round($_.WorkingSet64 / 1MB) } } |
    Format-Table -AutoSize

Write-Host "`n=== health ==="
$llamaBase = "http://{0}:{1}" -f [string]$cfg.llamaServerHost, [int]$cfg.llamaServerPort
$compactPort = 18081
if ($cfg.compactModel -and $null -ne $cfg.compactModel.port) { $compactPort = [int]$cfg.compactModel.port }
$compactBase = "http://{0}:{1}" -f [string]$cfg.llamaServerHost, $compactPort
try { Invoke-RestMethod ("{0}/health" -f $llamaBase) -TimeoutSec 3 | ConvertTo-Json -Compress } catch { Write-Host "llama-server: down" }
try { Invoke-RestMethod ("{0}/health" -f $compactBase) -TimeoutSec 3 | ConvertTo-Json -Compress } catch { Write-Host "compact-server: down" }
try { Invoke-RestMethod ("http://127.0.0.1:{0}/healthz" -f [int]$cfg.authProxyPort) -TimeoutSec 3 | ConvertTo-Json -Compress } catch { Write-Host "auth-proxy: down" }
