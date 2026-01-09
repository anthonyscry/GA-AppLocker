# GA-AppLocker

Simplified AppLocker deployment scripts for Windows 11/Server 2019+. No external dependencies required.

---

## First-Time Setup

If you downloaded these scripts from the internet, run these commands **once** before using:

```powershell
# Set execution policy (allows running local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Unblock downloaded files (removes internet zone identifier)
Get-ChildItem -Path "C:\GA-AppLocker" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

---

## WinRM Setup (Required for Remote Scans)

Remote scanning requires WinRM to be enabled on each target machine.

**For domain environments**, use the integrated WinRM GPO deployment:

```powershell
# Option 1: Via interactive menu
.\Start-AppLockerWorkflow.ps1
# Select [6] WinRM

# Option 2: Run utility directly (requires Domain Admin on a DC)
.\utilities\Enable-WinRM-Domain.ps1
```

This creates a GPO that enables WinRM, configures firewall rules, and can force GP refresh across the domain.

**On individual machines** (run PowerShell as Administrator):

```powershell
# Enable PS Remoting (configures WinRM, firewall, and service)
Enable-PSRemoting -Force
```

**Manual GPO setup** (alternative):
- Computer Configuration → Administrative Templates → Windows Components → Windows Remote Management → WinRM Service
- Enable "Allow remote server management through WinRM"

**For workgroup/non-domain machines**, you may also need to trust targets on the scanning machine:

```powershell
# Trust specific machines
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "PC01,PC02,PC03"

# Or trust all (less secure)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*"
```

**Test connectivity:**

```powershell
Test-WSMan -ComputerName "TARGET-PC"
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
# Interactive workflow - guides you through all steps
.\Start-AppLockerWorkflow.ps1

# Or use direct mode commands:
.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt -OutputPath .\Scans
.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified
.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Interactive mode | `.\Start-AppLockerWorkflow.ps1` |
| Scan computers | `.\Start-AppLockerWorkflow.ps1 -Mode Scan -ComputerList .\computers.txt` |
| Build Guide policy | `.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -TargetType Workstation -DomainName CONTOSO` |
| Simplified policy | `.\Start-AppLockerWorkflow.ps1 -Mode Generate -ScanPath .\Scans -Simplified` |
| Merge policies | `.\Start-AppLockerWorkflow.ps1 -Mode Merge -ScanPath .\Policies` |
| Validate policy | `.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath .\policy.xml` |

---

## Project Structure

```
GA-AppLocker/
├── Start-AppLockerWorkflow.ps1     # Single entry point (recommended)
├── Invoke-RemoteScan.ps1           # Remote data collection
├── New-AppLockerPolicyFromGuide.ps1 # Policy generation
├── Merge-AppLockerPolicies.ps1     # Policy merging
├── utilities/
│   ├── Common.psm1                 # Shared functions (SID, XML helpers)
│   ├── Config.psd1                 # Central configuration (LOLBins, paths)
│   ├── Enable-WinRM-Domain.ps1     # WinRM GPO deployment for domains
│   └── Validators.ps1              # Policy validation functions
└── README.md
```

---

## Scripts

### Main Entry Point

| Script | Description |
|--------|-------------|
| `Start-AppLockerWorkflow.ps1` | **Unified workflow** - Interactive menu or direct mode |

### Core Scripts

| Script | Description |
|--------|-------------|
| `Invoke-RemoteScan.ps1` | Collects AppLocker data from remote computers via WinRM |
| `New-AppLockerPolicyFromGuide.ps1` | Generates policies (Build Guide or Simplified mode) |
| `Merge-AppLockerPolicies.ps1` | Merges multiple policies and removes duplicates |

### Utilities (`utilities/`)

| File | Description |
|------|-------------|
| `Common.psm1` | Shared functions: SID resolution, XML generation, logging |
| `Config.psd1` | Central configuration: LOLBins, deny paths, scan paths, SIDs |
| `Enable-WinRM-Domain.ps1` | Creates GPO to enable WinRM across domain computers |
| `Validators.ps1` | Policy and scan data validation functions |

---

## Workflows

### Workflow A: Interactive Mode (Easiest)

```powershell
# Launch interactive menu
.\Start-AppLockerWorkflow.ps1

# Menu options:
# [1] Scan       - Collect data from remote computers
# [2] Generate   - Create AppLocker policy from scan data
# [3] Merge      - Combine multiple policy files
# [4] Validate   - Check a policy file for issues
# [5] Full       - Complete workflow (Scan + Generate)
# [6] WinRM      - Deploy WinRM GPO for domain computers
```

### Workflow B: Enterprise Deployment (Build Guide Mode)

**Step 1: Scan Computers**
```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Scan `
    -ComputerList ".\computers.txt" `
    -OutputPath "\\server\share\Scans"
```

**Step 2: Generate Phase 1 Policy**
```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Generate `
    -ScanPath "\\server\share\Scans\Scan-20240108" `
    -TargetType Workstation `
    -DomainName "CONTOSO" `
    -Phase 1
```

**Step 3: Deploy via GPO**
1. Open Group Policy Management Console
2. Create GPO linked to target OUs
3. Import generated XML policy
4. Set to "Audit only" mode

**Step 4: Monitor Events**
- Event ID 8003: Allowed (audit)
- Event ID 8004: Would have been blocked (audit)
- Location: `Applications and Services Logs > Microsoft > Windows > AppLocker`

**Step 5: Advance Phases**
```powershell
# Phase 2: Add Script rules
.\New-AppLockerPolicyFromGuide.ps1 -TargetType Workstation -DomainName "CONTOSO" -Phase 2

# Phase 3: Add MSI rules
.\New-AppLockerPolicyFromGuide.ps1 -TargetType Workstation -DomainName "CONTOSO" -Phase 3

# Phase 4: Full policy including DLL (audit 14+ days before enforcing)
.\New-AppLockerPolicyFromGuide.ps1 -TargetType Workstation -DomainName "CONTOSO" -Phase 4
```

### Workflow C: Quick Deployment (Simplified Mode)

For testing, lab environments, or standalone machines.

```powershell
# One command: Scan + Generate simplified policy
.\Start-AppLockerWorkflow.ps1 -Mode Generate `
    -ScanPath ".\Scans" `
    -Simplified

# Or with deny rules for LOLBins
.\New-AppLockerPolicyFromGuide.ps1 -Simplified `
    -ScanPath ".\Scans" `
    -TargetUser "BUILTIN\Users" `
    -IncludeDenyRules `
    -IncludeHashRules

# Apply locally (test)
Set-AppLockerPolicy -XmlPolicy ".\Outputs\AppLockerPolicy-Simplified.xml"
```

### Workflow D: Merge Policies

```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Merge `
    -ScanPath "\\server\share\AllPolicies" `
    -OutputPath ".\MergedPolicy.xml"

# Or directly:
.\Merge-AppLockerPolicies.ps1 `
    -InputPath "\\server\share\AllPolicies" `
    -OutputPath ".\MergedPolicy.xml" `
    -EnforcementMode AuditOnly
```

### Workflow E: Validate Policy

```powershell
.\Start-AppLockerWorkflow.ps1 -Mode Validate -PolicyPath ".\policy.xml"
```

---

## Configuration

Edit `utilities/Config.psd1` to customize:

- **LOLBins** - Binaries to block (mshta.exe, wscript.exe, etc.)
- **DefaultDenyPaths** - User-writable paths to block (%TEMP%, Downloads, etc.)
- **ServerDenyPaths** - Additional paths for servers (inetpub, etc.)
- **WellKnownSids** - Windows security identifiers
- **DefaultScanPaths** - Paths to scan for executables
- **Phases** - Build Guide phase definitions

Example customization:
```powershell
# Add a custom LOLBin
LOLBins = @(
    @{ Name = "mshta.exe"; Description = "HTML Application Host" }
    @{ Name = "custom.exe"; Description = "Your custom entry" }
    # ...
)
```

---

## Phased Deployment

| Phase | Collections | Notes |
|-------|-------------|-------|
| 1 | EXE only | Start here, lowest risk |
| 2 | EXE + Script | Scripts are highest risk |
| 3 | EXE + Script + MSI | Test installation workflows |
| 4 | All including DLL | Audit 14+ days before enforcing |

---

## License

See parent repository for license information.
