#Requires -Version 5.1
<#
.SYNOPSIS
  Expose local auth proxy (llama.cpp) to Cursor via Cloudflare quick tunnel.

.NOTES
  Cursor BYOK routes through Cursor cloud, which blocks private networks
  (127.0.0.1 / LAN) with: "Access to private networks is forbidden".
  A public HTTPS URL is required.
#>
[CmdletBinding()]
param(
    [int]$LocalPort = 11435,
    [string]$CloudflaredPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$pidFile = Join-Path $runtime "cloudflared.pid"
$urlFile = Join-Path $runtime "public-base-url.txt"
$outLog = Join-Path $runtime "cloudflared-out.log"
$errLog = Join-Path $runtime "cloudflared-err.log"

function Resolve-Cloudflared {
    param([string]$Preferred)
    if ($Preferred -and (Test-Path $Preferred)) { return (Resolve-Path $Preferred).Path }
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe",
        "${env:ProgramFiles}\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\cloudflared\cloudflared.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

try {
    $null = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/healthz" -f $LocalPort) -TimeoutSec 3
} catch {
    throw ("Auth proxy not healthy on 127.0.0.1:{0}. Start scripts\\08-start-auth-proxy.ps1 first." -f $LocalPort)
}

$cloudflared = Resolve-Cloudflared -Preferred $CloudflaredPath
if (-not $cloudflared) {
    throw "cloudflared not found. Install from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
}

if (Test-Path $pidFile) {
    $oldPid = [int]((Get-Content $pidFile -Raw).Trim())
    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
        Write-Host ("Stopping previous cloudflared pid={0}" -f $oldPid)
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

Remove-Item $outLog, $errLog, $urlFile -ErrorAction SilentlyContinue

Write-Host ("Using cloudflared: {0}" -f $cloudflared)
Write-Host ("Tunneling http://127.0.0.1:{0} (auth proxy -> llama-server) ..." -f $LocalPort)

$httpHostHeader = ("localhost:{0}" -f $LocalPort)

$proc = Start-Process -FilePath $cloudflared `
    -ArgumentList @(
        "tunnel",
        "--url", ("http://127.0.0.1:{0}" -f $LocalPort),
        "--http-host-header=$httpHostHeader",
        "--no-autoupdate"
    ) `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog

$proc.Id | Set-Content $pidFile -Encoding ascii

$publicOrigin = $null
$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Milliseconds 500
    foreach ($log in @($errLog, $outLog)) {
        if (-not (Test-Path $log)) { continue }
        $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if (-not $text) { continue }
        $m = [regex]::Match($text, "https://[a-zA-Z0-9-]+\.trycloudflare\.com")
        if ($m.Success) {
            $publicOrigin = $m.Value.TrimEnd("/")
            break
        }
    }
    if ($publicOrigin) { break }
    if ($proc.HasExited) {
        throw ("cloudflared exited early. See {0} and {1}" -f $outLog, $errLog)
    }
} while ((Get-Date) -lt $deadline)

if (-not $publicOrigin) {
    throw ("Timed out waiting for trycloudflare URL. See logs in {0}" -f $runtime)
}

$baseUrl = "$publicOrigin/v1"
$baseUrl | Set-Content $urlFile -Encoding ascii

$keyFile = Join-Path $runtime "api-key.txt"
if (-not (Test-Path $keyFile)) {
    throw "Missing runtime/api-key.txt - run scripts/07-ensure-api-key.ps1 (or start.bat) first."
}
$apiKey = (Get-Content $keyFile -Raw).Trim()
if ($apiKey.Length -lt 24) {
    throw "API key in runtime/api-key.txt is too short (<24 chars)."
}

Write-Host ""
Write-Host "PUBLIC_ORIGIN=$publicOrigin"
Write-Host "CURSOR_OVERRIDE_BASE_URL=$baseUrl"
Write-Host "CURSOR_MODEL=qwen3coder30b"
Write-Host ("CURSOR_API_KEY={0}" -f $apiKey)
Write-Host ""
Write-Host "Cursor Settings -> Models:"
Write-Host ("  1) OpenAI API Key = {0}" -f $apiKey)
Write-Host "  2) Override OpenAI Base URL = $baseUrl"
Write-Host "  3) Models: qwen3coder30b (implement) + qwen3635b (plan)"
Write-Host ""
Write-Host ("URL also written to {0}" -f $urlFile)
Write-Host "Leave this tunnel running while using Cursor. Stop with stop.bat"

Start-Sleep -Seconds 3
try {
    $models = Invoke-RestMethod -Uri "$baseUrl/models" -Headers @{ Authorization = ("Bearer {0}" -f $apiKey) } -TimeoutSec 20
    Write-Host ("Public /v1/models OK count={0}" -f @($models.data).Count)
} catch {
    Write-Host "Public probe not ready yet (DNS lag is common). Wait ~60s then retry with the API key above."
}

exit 0
