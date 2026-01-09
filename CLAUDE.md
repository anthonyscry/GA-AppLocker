# CLAUDE.md - GA-AppLocker Project Reference

## Project Overview

**GA-AppLocker** is a simplified AppLocker deployment toolkit for Windows security administrators. Created by Tony Tran (ISSO, GA-ASI), it automates creating and managing Windows AppLocker policies.

**Purpose:**
- Collect application inventory data from Windows machines remotely via WinRM
- Generate enterprise-ready AppLocker policies based on real environment data
- Support phased deployment (low-risk to high-risk enforcement)
- Merge and validate AppLocker policies across organizations
- Compare software inventories to identify drift between systems

**Target Platforms:** Windows 11, Windows Server 2019+

## Technology Stack

- **Pure PowerShell** (5.1+) - no external dependencies
- **WinRM** for remote scanning
- **Active Directory** (optional) for group management
- **AppLocker Policy XML** (native Windows security format)
- **Authenticode signatures** for publisher-based rules

## Project Structure

```
GA-AppLocker/
├── Start-AppLockerWorkflow.ps1      # Main entry point (interactive menu + parameter modes)
├── Invoke-RemoteScan.ps1            # WinRM-based remote data collection
├── New-AppLockerPolicyFromGuide.ps1 # Policy generation (Build Guide + Simplified modes)
├── Merge-AppLockerPolicies.ps1      # Policy consolidation with deduplication
├── computers.txt                    # Target computer list
├── utilities/
│   ├── Common.psm1                  # Shared functions (SID resolution, XML helpers, logging)
│   ├── Config.psd1                  # Centralized configuration (LOLBins, SIDs, paths)
│   ├── Manage-SoftwareLists.ps1     # Software whitelist management (JSON storage)
│   ├── Enable-WinRM-Domain.ps1      # GPO-based WinRM deployment
│   ├── Manage-ADResources.ps1       # AD OU and security group creation
│   ├── Compare-SoftwareInventory.ps1 # Compare executables between machines
│   └── Test-AppLockerDiagnostic.ps1 # Connectivity troubleshooting
└── README.md                        # Full documentation
```

## Key Patterns and Conventions

### Entry Point Pattern
- `Start-AppLockerWorkflow.ps1` is the unified hub for all functionality
- Supports interactive menu mode (default) and direct parameter mode
- Always start here rather than individual scripts

### Configuration Centralization
- `utilities/Config.psd1` contains all settings (SIDs, LOLBins, paths, defaults)
- Modify this file to customize for specific environments

### Two Policy Generation Modes

**Build Guide Mode** (Enterprise):
- Target-specific: Workstation, Server, Domain Controller
- Custom AD group scoping
- Phased deployment (Phase 1-4)
- Proper principal scoping (SYSTEM, LOCAL SERVICE, etc.)

**Simplified Mode** (Quick Deployment):
- Single target user/group
- Good for labs, testing, or standalone machines

### Data Formats
- **Policies:** AppLocker XML format
- **Software Lists:** JSON format
- **Scan Results:** CSV files (per-computer subdirectories)
- **Computer Lists:** Plain text (one per line, # for comments)

### Output Organization
- Scans: `./Scans/Scan-YYYYMMDD-HHMMSS/[COMPUTERNAME]/`
- Policies: `./Outputs/AppLockerPolicy-[Mode].xml`
- Software Lists: `./SoftwareLists/[ListName].json`

## Common Commands

### Interactive Mode
```powershell
.\Start-AppLockerWorkflow.ps1
```

### Direct Parameter Mode
```powershell
# Quick scan
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt

# Generate simplified policy
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified

# Generate Build Guide policy
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans\Scan-20260109 `
    -TargetType Workstation -DomainName CONTOSO -Phase 1

# Validate policy
.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml

# Full workflow (Scan + Generate)
.\Start-AppLockerWorkflow.ps1 -Mode Full -ComputerList .\computers.txt
```

### Utility Scripts
```powershell
# Software list management
.\utilities\Manage-SoftwareLists.ps1

# Compare inventories
.\utilities\Compare-SoftwareInventory.ps1 -ReferencePath .\baseline.csv -ComparePath .\target.csv

# Diagnostics
.\utilities\Test-AppLockerDiagnostic.ps1 -ComputerName TARGET-PC

# WinRM setup
.\utilities\Enable-WinRM-Domain.ps1
```

## Important Parameters

| Parameter | Description |
|-----------|-------------|
| `-Phase 1-4` | Build Guide deployment phases (1=EXE only, 4=All+DLL) |
| `-TargetType` | Workstation, Server, or DomainController |
| `-Simplified` | Quick deployment mode |
| `-IncludeDenyRules` | Add LOLBins deny rules |
| `-IncludeVendorPublishers` | Trust vendor publishers from scan |
| `-ScanUserProfiles` | Include user profile scanning |
| `-ThrottleLimit` | Concurrent remote connections (default: 10) |

## Security Principles

The toolkit follows these security principles:
- "Allow who may run trusted code, deny where code can never run"
- Explicit deny rules for user-writable paths (%TEMP%, Downloads, AppData)
- LOLBins (mshta.exe, wscript.exe, powershell.exe, etc.) explicitly denied when enabled
- Publisher-based rules use correct principal scoping (not Everyone)

## Development Notes

### When Modifying Scripts
- Import `Common.psm1` for shared functions
- Reference `Config.psd1` for configurable values
- Follow existing parameter patterns for consistency
- Use `Write-Host` with color for user feedback
- Support both interactive and parameter-driven modes

### Config.psd1 Key Sections
- `WellKnownSids` - Windows security identifiers
- `LOLBins` - High-risk executables for deny rules
- `DefaultDenyPaths` - User-writable locations
- `DefaultAllowPaths` - Protected system paths
- `TrustedMicrosoftPublishers` - Microsoft certificate subjects
- `DefaultScanPaths` - Paths to scan for executables
- `FileExtensions` - Grouped by type (Exe, Dll, Script, Installer)

### Testing Changes
```powershell
# Test connectivity
Test-WSMan -ComputerName "TARGET-PC"

# Local policy test
Set-AppLockerPolicy -XmlPolicy .\Outputs\AppLockerPolicy.xml

# Diagnostic mode
.\utilities\Test-AppLockerDiagnostic.ps1 -ComputerName TARGET-PC
```

## Workflow for Enterprise Deployment

1. **Setup WinRM** organization-wide
2. **Scan** 14+ machines to collect inventory
3. **Generate Phase 1** policies (EXE only - lowest risk)
4. **Deploy via GPO** in Audit mode for 14+ days
5. **Monitor Event Viewer** (Event IDs 8003/8004)
6. **Advance through phases** progressively

## File Naming Conventions

- Scripts: PascalCase with Verb-Noun pattern (e.g., `Start-AppLockerWorkflow.ps1`)
- Modules: PascalCase (e.g., `Common.psm1`)
- Data files: PascalCase (e.g., `Config.psd1`)
- Output files: Descriptive with timestamps when applicable
