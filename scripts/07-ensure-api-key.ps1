#Requires -Version 5.1
<#
.SYNOPSIS
  Ensure API key for auth proxy (gitignored runtime/api-key.txt).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$keyFile = Join-Path $runtime "api-key.txt"

if (Test-Path $keyFile) {
    $existing = (Get-Content $keyFile -Raw).Trim()
    if ($existing.Length -ge 24) {
        Write-Host ("API key already present ({0} chars)" -f $existing.Length)
        Write-Output $existing
        exit 0
    }
}

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$key = "sk-qwen3coder-" + ([System.BitConverter]::ToString($bytes) -replace "-", "").ToLowerInvariant()
Set-Content -Path $keyFile -Value $key -Encoding ascii -NoNewline
Write-Host ("Created new API key at {0}" -f $keyFile)
Write-Output $key
