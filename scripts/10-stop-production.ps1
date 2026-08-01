#Requires -Version 5.1
<#
.SYNOPSIS
  Stop llama-server + auth proxy + Cloudflare tunnel.
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
. (Join-Path $PSScriptRoot "_common.ps1")

function Stop-PidFile {
    param([string]$Name)
    $file = Join-Path $runtime $Name
    if (-not (Test-Path $file)) { return }
    $old = 0
    [void][int]::TryParse(((Get-Content $file -Raw).Trim()), [ref]$old)
    if ($old -gt 0 -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) { Write-Host ("Stopped {0} pid={1}" -f $Name, $old) }
    }
    Remove-Item $file -Force -ErrorAction SilentlyContinue
}

Stop-PidFile "cloudflared.pid"
Stop-PidFile "auth-proxy.pid"
Stop-LlamaServer -RuntimeDir $runtime
Stop-CompactServer -RuntimeDir $runtime

Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "127\.0\.0\.1:1143[45]" } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) { Write-Host ("Stopped stray cloudflared pid={0}" -f $_.ProcessId) }
    }

Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "auth-proxy\.mjs" } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) { Write-Host ("Stopped stray auth-proxy pid={0}" -f $_.ProcessId) }
    }

Remove-Item (Join-Path $runtime "public-base-url.txt") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $runtime "active-model.txt") -ErrorAction SilentlyContinue
if (-not $Quiet) { Write-Host "PRODUCTION_STACK_DOWN" }
