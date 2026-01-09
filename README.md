# GA-AppLocker

Simplified AppLocker deployment toolkit for Windows 11/Server 2019+. No external dependencies required.

---

## First-Time Setup

If you downloaded these scripts from the internet, unblock them before use:

```powershell
# Set execution policy (allows local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Unblock all downloaded files
Get-ChildItem -Path "C:\GA-AppLocker" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

---

## Requirements

- PowerShell 5.1+
- Windows 11 / Server 2019+
- WinRM enabled on target computers (for remote scans)
- Admin credentials with remote access

---

## Quick Start

```powershell
# Interactive mode (recommended for first-time users)
.\Start-AppLockerWorkflow.ps1

# Direct mode examples:
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified
.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml
```

---

## WinRM Setup (Required for Remote Scans)

### Domain Environments (Recommended)

Use the integrated WinRM GPO deployment:

```powershell
# Via interactive menu
.\Start-AppLockerWorkflow.ps1
# Select [W] WinRM → [1] Deploy

# Or directly (requires Domain Admin on DC)
.\utilities\Enable-WinRM-Domain.ps1
```

This creates a GPO named "Enable-WinRM" that configures WinRM and firewall rules domain-wide.

**To remove:**
```powershell
.\utilities\Enable-WinRM-Domain.ps1 -Remove
```

### Individual Machines

Run PowerShell as Administrator:

```powershell
Enable-PSRemoting -Force
```

### Workgroup/Non-Domain Machines

Trust target machines on the scanning computer:

```powershell
# Trust specific machines
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "PC01,PC02"

# Or trust all (less secure)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*"
```

**Test connectivity:**
```powershell
Test-WSMan -ComputerName "TARGET-PC"
```

---

## Interactive Menu

The interactive menu provides guided access to all features:

```powershell
.\Start-AppLockerWorkflow.ps1

# Main Menu:
[1] Scan       - Collect data from remote computers
[2] Generate   - Create AppLocker policy (Simplified or Build Guide)
[3] Merge      - Combine multiple policy files
[4] Validate   - Check policy XML for issues
[5] Full       - Complete workflow (Scan → Generate)
[6] Compare    - Compare software inventories
[S] Software   - Manage software lists for rule generation
[7] AD Setup   - Create AppLocker OUs and groups
[8] AD Export  - Export user group memberships
[9] AD Import  - Apply group membership changes
[W] WinRM      - Deploy/Remove WinRM GPO
[D] Diagnostic - Troubleshoot remote scanning
[Q] Quit
```

---

## Common Workflows

### Enterprise Deployment (Build Guide Mode)

**Step 1: Scan**
```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt
```

**Step 2: Generate Phase 1**
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

**Step 4: Monitor Events (14+ days)**
- Event ID 8003: Allowed
- Event ID 8004: Would have been blocked
- Location: Applications and Services Logs → Microsoft → Windows → AppLocker

**Step 5: Advance Through Phases**
```powershell
# Progressively add more rule collections
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

### Software List Management

Create curated software lists for targeted rule generation:

```powershell
# Via interactive menu
.\Start-AppLockerWorkflow.ps1
# Select [S] Software

# Features:
- Import from scan data or executables
- Filter by signed/unsigned
- Auto-approve or manual review
- Generate policies from approved lists
- Export to CSV for documentation
```

---

## Project Structure

```
GA-AppLocker/
├── Start-AppLockerWorkflow.ps1         # Main entry point (menu + direct mode)
├── Invoke-RemoteScan.ps1               # Remote data collection via WinRM
├── New-AppLockerPolicyFromGuide.ps1    # Policy generation engine
├── Merge-AppLockerPolicies.ps1         # Policy consolidation
└── utilities/
    ├── Common.psm1                     # Shared functions (SID, XML, validation)
    ├── Config.psd1                     # Configuration (LOLBins, paths, SIDs)
    ├── Manage-SoftwareLists.ps1        # Software list management
    ├── Enable-WinRM-Domain.ps1         # WinRM GPO deployment
    ├── Manage-ADResources.ps1          # AD group/OU management
    ├── Compare-SoftwareInventory.ps1   # Software inventory comparison
    └── Test-AppLockerDiagnostic.ps1    # Connectivity diagnostics
```

---

## Configuration

Customize `utilities/Config.psd1`:

```powershell
# LOLBins - Binaries to deny (mshta.exe, wscript.exe, etc.)
# DefaultDenyPaths - Block user-writable paths (%TEMP%, Downloads)
# WellKnownSids - Windows security identifiers
# DefaultScanPaths - Paths to scan for executables
# Phases - Build Guide phase definitions
```

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
