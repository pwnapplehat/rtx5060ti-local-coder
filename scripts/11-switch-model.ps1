#Requires -Version 5.1
<#
.SYNOPSIS
  Reload llama-server with a known Cursor model id from config/models.json.
.NOTES
  Cursor model dropdown also triggers this via the auth proxy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Model
)

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "08-start-llama-server.ps1") -Model $Model
Write-Host ("SWITCHED_TO={0}" -f $Model)
