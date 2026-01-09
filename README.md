# GA-AppLocker

**Author:** Tony Tran, ISSO, GA-ASI

Simplified AppLocker deployment toolkit for Windows 11/Server 2019+. No external dependencies required.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Setup](#setup)
  - [First-Time Setup](#first-time-setup)
  - [WinRM Setup](#winrm-setup)
- [Interactive Menu](#interactive-menu)
- [Common Workflows](#common-workflows)
  - [Enterprise Deployment](#enterprise-deployment-build-guide-mode)
  - [Quick Deployment](#quick-deployment-simplified-mode)
- [Menu Features](#menu-features)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Phased Deployment Strategy](#phased-deployment-strategy)

---

## Quick Start

```powershell
# Interactive mode (recommended)
.\Start-AppLockerWorkflow.ps1

# Direct mode examples
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified
.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml
```

---

## Requirements

- PowerShell 5.1+
- Windows 11 / Server 2019+
- WinRM enabled on target computers (for remote scans)
- Admin credentials with remote access

---

## Setup

### First-Time Setup

If you downloaded these scripts from the internet, unblock them before use:

```powershell
# Set execution policy (allows local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Unblock all downloaded files
Get-ChildItem -Path "C:\GA-AppLocker" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

### WinRM Setup

WinRM is required for remote scanning.

**Domain Environments (Recommended):**

```powershell
# Via interactive menu
.\Start-AppLockerWorkflow.ps1
# Select [W] WinRM → [1] Deploy

# Or directly (requires Domain Admin on DC)
.\utilities\Enable-WinRM-Domain.ps1
```

This creates a GPO named "Enable-WinRM" that configures WinRM and firewall rules domain-wide.

**To remove the WinRM GPO:**

```powershell
.\utilities\Enable-WinRM-Domain.ps1 -Remove
```

**Individual Machines:**

```powershell
# Run as Administrator
Enable-PSRemoting -Force
```

**Workgroup/Non-Domain Machines:**

```powershell
# Trust specific machines
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "PC01,PC02"

# Or trust all (less secure)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*"

# Test connectivity
Test-WSMan -ComputerName "TARGET-PC"
```

---

## Interactive Menu

Run `.\Start-AppLockerWorkflow.ps1` for the guided interface:

```
  GA-AppLocker - AppLocker Policy Generation Toolkit
  -------------------------------------------------
  Author: Tony Tran, ISSO, GA-ASI

  === Core Workflow ===
    [1] Scan       - Collect data from remote computers
    [2] Generate   - Create AppLocker policy from scan data
    [3] Merge      - Combine multiple policy files
    [4] Validate   - Check a policy file for issues
    [5] Full       - Complete workflow (Scan + Generate)

  === Analysis ===
    [6] Compare    - Compare software inventories

  === Software Lists ===
    [S] Software   - Manage software lists for rule generation

  === AD Management ===
    [7] AD Setup   - Create AppLocker OUs and groups
    [8] AD Export  - Export user group memberships
    [9] AD Import  - Apply group membership changes

  === Infrastructure ===
    [W] WinRM      - Deploy/Remove WinRM GPO
    [D] Diagnostic - Troubleshoot remote scanning

    [Q] Quit
```

---

## Common Workflows

### Enterprise Deployment (Build Guide Mode)

**Step 1: Scan remote computers**

```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt
```

**Step 2: Generate Phase 1 policy**

```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Generate `
    -ScanPath .\Scans\Scan-20260109 `
    -TargetType Workstation -DomainName CONTOSO -Phase 1
```

**Step 3: Deploy via GPO**

1. Open Group Policy Management
2. Create/link GPO to target OUs
3. Import generated XML: Computer Config → Policies → Windows Settings → Security Settings → Application Control Policies
4. Keep in **Audit mode** initially

**Step 4: Monitor events (14+ days recommended)**

| Event ID | Meaning |
|----------|---------|
| 8003 | Execution allowed |
| 8004 | Would have been blocked |

Location: `Applications and Services Logs → Microsoft → Windows → AppLocker`

**Step 5: Advance through phases**

```powershell
-Phase 2  # EXE + Script
-Phase 3  # EXE + Script + MSI
-Phase 4  # All including DLL (audit 14+ days before enforcing!)
```

### Quick Deployment (Simplified Mode)

For testing, labs, or standalone machines:

```powershell
# Generate simple policy from scan
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified

# Apply locally for testing
Set-AppLockerPolicy -XmlPolicy .\Outputs\AppLockerPolicy-Simplified.xml
```

---

## Menu Features

### Interactive Folder Browser

Many workflows feature an interactive folder browser that eliminates manual path typing:

- **Compare [6]**: Browse scan folders to select baseline and comparison files
- **Generate [2]**: Browse and select scan data folders
- **Software Import [S → 4]**: Browse scan folders when importing

The browser shows numbered selections with dates, manual entry `[M]`, back `[B]`, and cancel `[C]` options.

### Software List Management `[S]`

```
  === Basic Operations ===
    [1] Create     - Create a new software list
    [2] View       - View/search existing software lists
    [3] Add        - Add software to a list manually

  === Import Methods ===
    [4] Import     - Import from scan data or executable
    [5] Publishers - Import common trusted publishers
    [6] Policy     - Import from existing AppLocker policy
    [7] Folder     - Import from folder (scan executables)

  === Export & Generate ===
    [8] Export     - Export list to CSV
    [9] Approve    - Bulk approve/unapprove items
    [G] Generate   - Generate policy from software list
```

### Software Inventory Comparison

Compare software between machines to identify drift or unique applications:

```powershell
# Interactive mode with folder browser
.\Start-AppLockerWorkflow.ps1
# Select [6] Compare → [1] Browse scan folders

# Direct mode
.\utilities\Compare-SoftwareInventory.ps1 `
    -ReferencePath .\Scans\Scan-20260109\BASELINE\Executables.csv `
    -ComparePath .\Scans\Scan-20260109\TARGET\Executables.csv `
    -CompareBy Name
```

**Comparison methods:** Name, NameVersion, Hash, Publisher

### WinRM Management `[W]`

```
  [1] Deploy  - Create WinRM GPO
  [2] Remove  - Remove WinRM GPO
```

### Diagnostic Tools `[D]`

```
  [1] Connectivity - Test ping, WinRM, sessions
  [2] JobSession   - Test PowerShell job execution
  [3] JobFull      - Full job test with tracing
  [4] SimpleScan   - Scan without parallel jobs
```

---

## Project Structure

```
GA-AppLocker/
├── Start-AppLockerWorkflow.ps1         # Main entry point (menu + direct mode)
├── Invoke-RemoteScan.ps1               # Remote data collection via WinRM
├── New-AppLockerPolicyFromGuide.ps1    # Policy generation engine
├── Merge-AppLockerPolicies.ps1         # Policy consolidation
├── computers.txt                       # Template computer list
└── utilities/
    ├── Common.psm1                     # Shared functions (SID, XML, validation)
    ├── Config.psd1                     # Configuration (LOLBins, paths, SIDs)
    ├── Manage-SoftwareLists.ps1        # Software list management
    ├── Enable-WinRM-Domain.ps1         # WinRM GPO deployment
    ├── Manage-ADResources.ps1          # AD group/OU management
    ├── Compare-SoftwareInventory.ps1   # Software inventory comparison
    └── Test-AppLockerDiagnostic.ps1    # Connectivity diagnostics
```

### Scan Output Structure

```
Scans/
├── Scan-20260109-143000/               # Timestamped scan folder
│   ├── ScanResults.csv                 # Summary log
│   ├── WORKSTATION01/                  # Per-computer data
│   │   ├── AppLockerPolicy.xml         # Current policy (if any)
│   │   ├── InstalledSoftware.csv
│   │   ├── Executables.csv             # With signature info
│   │   ├── Publishers.csv              # Unique publishers found
│   │   ├── WritableDirectories.csv
│   │   ├── RunningProcesses.csv
│   │   └── SystemInfo.csv
│   └── WORKSTATION02/
│       └── ...
└── Scan-20260110-091500/
    └── ...
```

---

## Configuration

Customize `utilities/Config.psd1`:

| Section | Purpose |
|---------|---------|
| `LOLBins` | Binaries to deny (mshta.exe, wscript.exe, etc.) |
| `DefaultDenyPaths` | Block user-writable paths (%TEMP%, Downloads) |
| `WellKnownSids` | Windows security identifiers |
| `DefaultScanPaths` | Paths to scan for executables |
| `Phases` | Build Guide phase definitions |

---

## Phased Deployment Strategy

| Phase | Collections | Risk | Notes |
|-------|-------------|------|-------|
| **1** | EXE only | ✅ Low | Start here, safest rollout |
| **2** | EXE + Script | ⚠️ High | Scripts are bypass risk - monitor closely |
| **3** | EXE + Script + MSI | ⚠️ Medium | Test software deployments thoroughly |
| **4** | All + DLL | 🔴 Very High | **Audit 14+ days before enforcing!** |

---

## License

See parent repository for license information.
