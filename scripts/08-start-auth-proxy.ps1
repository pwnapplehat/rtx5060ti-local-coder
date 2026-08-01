#Requires -Version 5.1
<#
.SYNOPSIS
  Start bearer-auth proxy on 127.0.0.1:11435 in front of llama-server (port from models.json)
#>
[CmdletBinding()]
param(
    [int]$Port = 11435
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
$pidFile = Join-Path $runtime "auth-proxy.pid"
$outLog = Join-Path $runtime "auth-proxy-out.log"
$errLog = Join-Path $runtime "auth-proxy-err.log"
$proxyJs = Join-Path $root "proxy\auth-proxy.mjs"

. (Join-Path $PSScriptRoot "_common.ps1")
$cfg = Get-ModelsConfig

if (-not (Test-Path $proxyJs)) { throw "Missing $proxyJs" }

$key = & (Join-Path $PSScriptRoot "07-ensure-api-key.ps1")
if (-not $key) { throw "Failed to resolve API key" }

if (Test-Path $pidFile) {
    $old = [int]((Get-Content $pidFile -Raw).Trim())
    if (Get-Process -Id $old -ErrorAction SilentlyContinue) {
        Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

$hostName = [string]$cfg.llamaServerHost
$upstream = "http://{0}:{1}" -f $hostName, [int]$cfg.llamaServerPort
if (-not (Test-TcpPortOpen -HostName $hostName -Port ([int]$cfg.llamaServerPort))) {
    throw ("llama-server is not reachable on {0}. Start scripts\\08-start-llama-server.ps1 first." -f $upstream)
}

$compactPort = 18081
if ($cfg.compactModel -and $null -ne $cfg.compactModel.port) {
    $compactPort = [int]$cfg.compactModel.port
}
$compactUpstream = "http://{0}:{1}" -f $hostName, $compactPort
$useCompact = $true
if ($cfg.contextCompact -and $null -ne $cfg.contextCompact.useCompactSidecar) {
    $useCompact = [bool]$cfg.contextCompact.useCompactSidecar
}
if ($useCompact) {
    if (-not (Test-TcpPortOpen -HostName $hostName -Port $compactPort)) {
        throw ("compact-server is not reachable on {0}. Start scripts\\08-start-compact-server.ps1 first." -f $compactUpstream)
    }
}

$env:AUTH_PROXY_PORT = "$Port"
$env:AUTH_PROXY_SECRET = "$key"
$env:LLAMA_UPSTREAM = $upstream
$env:COMPACT_UPSTREAM = $compactUpstream
$env:COMPACT_MODEL = "compact3b"
if ($cfg.compactModel -and $cfg.compactModel.alias) {
    $env:COMPACT_MODEL = [string]$cfg.compactModel.alias
}
$env:USE_COMPACT_SIDECAR = if ($useCompact) { "1" } else { "0" }
$env:REPO_ROOT = $root

Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath "node" `
    -ArgumentList @($proxyJs) `
    -WorkingDirectory $root `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog

$proc.Id | Set-Content $pidFile -Encoding ascii

$ok = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 250
    try {
        $h = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/healthz" -f $Port) -TimeoutSec 1
        if ($h.status -eq "ok") { $ok = $true; break }
    } catch {}
}
if (-not $ok) {
    throw "auth-proxy failed to become healthy. See $errLog"
}

Write-Host ("AUTH_PROXY_OK http://127.0.0.1:{0} pid={1}" -f $Port, $proc.Id)
Write-Host ("CURSOR_API_KEY={0}" -f $key)
