#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$required = @(
    "README.md", "LICENSE",
    "install.bat", "start.bat", "stop.bat", "status.bat", "verify.bat",
    "config\models.json",
    "config\cursor-models.example.json",
    "proxy\auth-proxy.mjs",
    "scripts\install.ps1",
    "scripts\_common.ps1",
    "scripts\01-install-llamacpp.ps1",
    "scripts\02-pull-models.ps1",
    "scripts\04-smoke-test.ps1",
    "scripts\05-start-cloudflare-tunnel.ps1",
    "scripts\06-stop-cloudflare-tunnel.ps1",
    "scripts\07-ensure-api-key.ps1",
    "scripts\08-start-llama-server.ps1",
    "scripts\08-start-compact-server.ps1",
    "scripts\08-start-auth-proxy.ps1",
    "scripts\09-start-production.ps1",
    "scripts\10-stop-production.ps1",
    "scripts\11-switch-model.ps1",
    "scripts\13-status.ps1",
    "scripts\14-verify.ps1",
    "docs\OPS.md", "docs\CURSOR_SETUP.md", "docs\PRODUCTION_AUDIT.md",
    "docs\CONTEXT.md", "docs\MODELS.md", "docs\QUANTIZATION.md"
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path (Join-Path $root $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    Write-Error ("Missing:`n  - " + ($missing -join "`n  - "))
    exit 1
}
Write-Host "STRUCTURE_OK"
exit 0
