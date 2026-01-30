# GA-AppLocker Dashboard Launcher
# Copy and paste this entire block into PowerShell to run the dashboard
# Log file: %LOCALAPPDATA%\GA-AppLocker\Logs\GA-AppLocker_YYYY-MM-DD.log

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Import-Module "$PSScriptRoot\GA-AppLocker\GA-AppLocker.psd1" -Force
Start-AppLockerDashboard -SkipPrerequisites
