#Requires -Version 5.1
<#
.SYNOPSIS
  Stop the Cloudflare quick tunnel started by 05-start-cloudflare-tunnel.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
$pidFile = Join-Path $runtime "cloudflared.pid"

if (Test-Path $pidFile) {
    $oldPid = [int]((Get-Content $pidFile -Raw).Trim())
    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
        Stop-Process -Id $oldPid -Force
        Write-Host ("Stopped cloudflared pid={0}" -f $oldPid)
    } else {
        Write-Host ("No process for pid={0}" -f $oldPid)
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "No pid file. Killing stray cloudflared processes (if any)..."
}

Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "127\.0\.0\.1:1143[45]|localhost:1143[45]" } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ("Stopped cloudflared pid={0}" -f $_.ProcessId)
    }

Remove-Item (Join-Path $runtime "public-base-url.txt") -ErrorAction SilentlyContinue
Write-Host "Tunnel stopped."
