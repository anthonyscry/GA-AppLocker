# GA-AppLocker Dashboard Launcher
# Copy and paste this entire block into PowerShell to run the dashboard
# Log file: %LOCALAPPDATA%\GA-AppLocker\Logs\GA-AppLocker_YYYY-MM-DD.log
# Troubleshooting scripts: .\Troubleshooting\
# Usage: .\Run-Dashboard.ps1

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Remove any previously loaded version so we always get the latest
if (Get-Module GA-AppLocker -ErrorAction SilentlyContinue) {
    Remove-Module GA-AppLocker -Force -ErrorAction SilentlyContinue
}
# Also remove sub-modules that may be cached from a prior version
Get-Module GA-AppLocker.* -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue

# Support both layouts:
# 1. Dev/repo:  PSScriptRoot\GA-AppLocker\GA-AppLocker.psd1
# 2. Flat zip:  PSScriptRoot\GA-AppLocker.psd1
$modulePath = "$PSScriptRoot\GA-AppLocker\GA-AppLocker.psd1"
if (-not (Test-Path $modulePath)) {
    $modulePath = "$PSScriptRoot\GA-AppLocker.psd1"
}

if (-not (Test-Path $modulePath)) {
    Write-Host "ERROR: Module manifest not found. Expected one of:" -ForegroundColor Red
    Write-Host "  $PSScriptRoot\GA-AppLocker\GA-AppLocker.psd1" -ForegroundColor Red
    Write-Host "  $PSScriptRoot\GA-AppLocker.psd1" -ForegroundColor Red
    exit 1
}

try {
    Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Failed to import module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command -Name 'Start-AppLockerDashboard' -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Start-AppLockerDashboard command was not exported after module import." -ForegroundColor Red
    exit 1
}

try {
    Start-AppLockerDashboard -SkipPrerequisites
}
catch {
    Write-Host "ERROR: Dashboard failed to start: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
