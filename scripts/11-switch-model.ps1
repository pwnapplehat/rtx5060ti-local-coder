#Requires -Version 5.1
<#
.SYNOPSIS
  Switch the hot llama-server model (planner <-> implementer).
.NOTES
  Cursor model dropdown also triggers this via the auth proxy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("qwen3coder30b", "qwen3635b")]
    [string]$Model
)

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "08-start-llama-server.ps1") -Model $Model
Write-Host ("SWITCHED_TO={0}" -f $Model)
