# PowerShell Script Usage

This guide covers using GA-AppLocker via PowerShell scripts instead of the GUI.

## First-Time Setup

```powershell
# Set execution policy (allows local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Unblock downloaded files
Get-ChildItem -Path "C:\GA-AppLocker" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

## Interactive Mode

```powershell
.\src\Core\Start-AppLockerWorkflow.ps1
```

## Direct Parameter Mode

### Scanning

```powershell
# Scan remote computers
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\ADManagement\computers.csv

# Full workflow (Scan + Generate)
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Full -ComputerList .\ADManagement\computers.csv
```

### Policy Generation

```powershell
# Generate simplified policy
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified

# Generate Build Guide policy (enterprise)
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans\Scan-20260109 `
    -TargetType Workstation -DomainName CONTOSO -Phase 1

# Validate a policy file
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml
```

### Event Collection

```powershell
# Collect blocked events from last 14 days
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\ADManagement\computers.csv

# Collect events from last 30 days
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\ADManagement\computers.csv -DaysBack 30

# Include allowed events
.\src\Core\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\ADManagement\computers.csv -IncludeAllowedEvents
```

## Utility Scripts

```powershell
# Compare inventories
.\src\Utilities\Compare-SoftwareInventory.ps1 -ReferencePath .\baseline.csv -ComparePath .\target.csv

# Diagnostics
.\src\Utilities\Test-AppLockerDiagnostic.ps1 -ComputerName TARGET-PC

# WinRM setup
.\src\Utilities\Enable-WinRM-Domain.ps1
```

## Parameters Reference

| Parameter | Description |
|-----------|-------------|
| `-Phase 1-4` | Build Guide deployment phases (1=EXE only, 4=All+DLL) |
| `-TargetType` | Workstation, Server, or DomainController |
| `-Simplified` | Quick deployment mode |
| `-IncludeDenyRules` | Add LOLBins deny rules |
| `-IncludeVendorPublishers` | Trust vendor publishers from scan |
| `-ScanUserProfiles` | Include user profile scanning |
| `-ThrottleLimit` | Concurrent remote connections (default: 10) |
| `-SoftwareListPath` | Path to software list JSON for policy generation |
| `-OutputPath` | Output folder (defaults to `.\Outputs`) |
| `-DaysBack` | Days of events to collect (default: 14, 0=all) |
| `-BlockedOnly` | Only collect "would have been blocked" events |
| `-IncludeAllowedEvents` | Also collect "would have been allowed" events |
