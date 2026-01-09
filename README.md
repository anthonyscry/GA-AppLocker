# GA-AppLocker

**Author:** Tony Tran, ISSO, GA-ASI

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
```

```
  GA-AppLocker - AppLocker Policy Generation Toolkit
  -------------------------------------------------
  Author: Tony Tran, ISSO, GA-ASI

  Select an option:

  === Core Workflow ===
    [1] Scan       - Collect data from remote computers
    [2] Generate   - Create AppLocker policy from scan data
    [3] Merge      - Combine multiple policy files
    [4] Validate   - Check a policy file for issues
    [5] Full       - Complete workflow (Scan + Generate)

  === Analysis ===
    [6] Compare    - Compare software inventories
    [E] Events     - Collect AppLocker audit events (8003/8004)

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

## Menu Features

### Output Defaults

Several workflows now default to the `.\Outputs` folder:
- **Validate [4]**: Lists XML files in Outputs for quick selection
- **Merge [3]**: Defaults to merging policies from Outputs folder
- **Generate [2]**: Saves policies to Outputs folder

### Interactive Folder Browser

Many workflows now feature an **interactive folder browser** that eliminates the need to manually type paths:

- **Compare [6]**: Browse scan folders to select baseline and comparison files
- **Generate [2]**: Browse and select scan data folders
- **Software Import [S → 3]**: Browse scan folders when importing to software lists

The browser shows:
- Numbered folder/file selection
- Last modified dates
- `[M]` Manual path entry option
- `[B]` Back navigation
- `[C]` Cancel operation

Example flow for Compare:
```
Step 1: Select scan date folder → [1] Scan-20260109-143000
Step 2: Select computer (baseline) → [1] WORKSTATION01
       [Auto-selects InstalledSoftware.csv]
Step 3: Select comparison computer → [2] WORKSTATION02
       [Auto-selects InstalledSoftware.csv]
```

### Software List Management [S]

```
  === Software List Management ===

  === Basic Operations ===
    [1] Create     - Create a new software list
    [2] View       - View/search existing software lists

  === Import Methods ===
    [3] Import     - Import from scan data or executable
    [4] Publishers - Import common trusted publishers
    [5] Policy     - Import from existing AppLocker policy
    [6] Folder     - Import from folder (scan executables)

  === Export & Generate ===
    [7] Export     - Export list to CSV
    [8] Approve    - Bulk approve/unapprove items
    [G] Generate   - Generate policy from software list
    [B] Back
```

**Import Methods:**
- **Scan Data** [3]: Import from remote scan results (CSV files)
- **Publishers** [4]: Add pre-defined trusted publishers (Microsoft, Adobe, Google, etc.) organized by category
- **Policy** [5]: Extract rules from existing AppLocker XML policies
- **Folder** [6]: Scan a local folder for executables and import their signatures

### WinRM Management [W]

```
  === WinRM GPO Options ===
    [1] Deploy  - Create WinRM GPO
    [2] Remove  - Remove WinRM GPO
    [B] Back
```

### Diagnostic Tools [D]

```
  === Diagnostic Types ===
    [1] Connectivity - Test ping, WinRM, sessions
    [2] JobSession   - Test PowerShell job execution
    [3] JobFull      - Full job test with tracing
    [4] SimpleScan   - Scan without parallel jobs
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

Comparison methods:
- **Name**: Match by software name only
- **NameVersion**: Match by name AND version
- **Hash**: Exact file match by SHA256
- **Publisher**: Match by publisher/signer

### AppLocker Event Collection

Collect audit events from computers running AppLocker in Audit mode. This is essential for identifying applications that need allow rules before switching to Enforce mode.

**Event IDs Collected:**
- **8003/8005/8007**: Would have been allowed
- **8004/8006/8008**: Would have been blocked (most useful for rule creation)

```powershell
# Interactive mode
.\Start-AppLockerWorkflow.ps1
# Select [E] Events

# Direct mode - collect blocked events from last 14 days
.\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\computers.txt

# Collect from last 30 days
.\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\computers.txt -DaysBack 30

# Collect all audit events (blocked + allowed)
.\Start-AppLockerWorkflow.ps1 -Mode Events -ComputerList .\computers.txt -IncludeAllowedEvents

# Direct script usage
.\Invoke-RemoteEventCollection.ps1 -ComputerListPath .\computers.txt -OutputPath .\Events -DaysBack 14 -BlockedOnly
```

### Policy Merging with SID Replacement

When merging policies from multiple sources, you can replace broad SIDs (like "Everyone") with specific AD groups for better scoping and management.

```powershell
# Merge and replace "Everyone" SID with a specific AD group
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -TargetGroup "DOMAIN\AppLocker-Workstations"

# Replace "Everyone" and "BUILTIN\Users" with target group
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -TargetGroup "DOMAIN\AppLocker-Workstations" -ReplaceMode Users

# Replace all standard user SIDs (Everyone, Users, Authenticated Users)
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -TargetGroup "DOMAIN\AppLocker-Workstations" -ReplaceMode All

# Use a known SID directly instead of resolving a group name
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -TargetSid "S-1-5-21-123456789-987654321-111111111-1234"

# Remove default AppLocker rules during merge (useful for clean policies)
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies -RemoveDefaultRules

# Combine: merge, replace SIDs, remove defaults, and set audit mode
.\Merge-AppLockerPolicies.ps1 -InputPath .\Policies `
    -TargetGroup "DOMAIN\AppLocker-Workstations" `
    -ReplaceMode All `
    -RemoveDefaultRules `
    -EnforcementMode AuditOnly
```

**ReplaceMode Options:**
| Mode | SIDs Replaced |
|------|---------------|
| `1` or `Everyone` | S-1-1-0 (Everyone) - Default |
| `2` or `Users` | Everyone + BUILTIN\Users |
| `3` or `Multiple` | Custom list via `-ReplaceSids` |
| `4` or `All` | Everyone, Users, Authenticated Users |

**Output Structure:**
```
Events/
├── Events-20260109-143000/
│   ├── EventCollectionResults.csv   # Summary log
│   ├── AllBlockedEvents.csv         # All blocked events consolidated
│   ├── UniqueBlockedApps.csv        # Deduplicated for rule creation
│   ├── WORKSTATION01/
│   │   ├── BlockedEvents.csv        # Per-computer blocked events
│   │   ├── AllowedEvents.csv        # If -IncludeAllowedEvents
│   │   └── EventSummary.csv         # Event counts
│   └── WORKSTATION02/
│       └── ...
```

**Key Output Files:**
- **UniqueBlockedApps.csv**: Deduplicated list of blocked applications with occurrence counts, affected computers, and users. Use this to identify which apps need allow rules.
- **AllBlockedEvents.csv**: Consolidated view across all computers for analysis.

**Recommended Workflow:**
1. Deploy AppLocker in **Audit mode** for 14+ days
2. Collect blocked events: `[E] Events`
3. Review `UniqueBlockedApps.csv` to identify legitimate software
4. Import to software list: `[S] Software → [3] Import`
5. Approve items and generate rules: `[S] Software → [G] Generate`
6. Add rules to policy, continue monitoring before enforcing

### Software Lists Workflow

Create and manage curated software allowlists:

```powershell
# Interactive mode
.\Start-AppLockerWorkflow.ps1
# Select [S] Software

# Create a list and import trusted publishers
# Select [1] Create → name your list
# Select [4] Publishers → choose categories (Microsoft, Adobe, Security, etc.)

# Import from existing scan data
# Select [3] Import → [1] From scan data → browse folders

# Generate policy from approved items
# Select [G] Generate
```

**Pre-defined Publisher Categories:**
- **Microsoft**: Windows OS components, Office, Visual Studio
- **Productivity**: Adobe products
- **Browser/Cloud**: Google Chrome, Google tools
- **Development**: JetBrains, GitHub, Git, Node.js, Python, VSCode
- **Security**: CrowdStrike, Carbon Black, Symantec, McAfee, Trend Micro, SentinelOne, Trellix, Cisco, Forescout, Splunk
- **Communication**: Zoom, Slack, WebEx, Microsoft Teams
- **Remote Access**: Citrix, VMware, Palo Alto GlobalProtect
- **Utilities**: WinZip, MATLAB

---

## AD Group Management

Manage Active Directory groups for AppLocker deployments. Export users, edit group memberships in CSV, and import changes back to AD.

### Export Users

```powershell
# Export all users with their group memberships
.\Start-AppLockerWorkflow.ps1
# Select [8] AD Export

# Direct mode
.\utilities\Manage-ADResources.ps1 -Action ExportUsers -OutputPath .\ADUserGroups-Export.csv
```

The export creates two files:
- `ADUserGroups-Export.csv` - Full export with all columns for editing
- `users.csv` - Simple list with semicolon-separated usernames per group (useful for quick reference)

### Import Users

Two CSV formats are supported for importing group memberships:

**Simple Format (Group-centric)** - Easiest for bulk additions:
```csv
Group,Users
AppLocker-StandardUsers,jsmith;jdoe;asmith
AppLocker-Admins,admin1;admin2
AppLocker-Installers,helpdesk1 helpdesk2
```

Users can be separated by semicolons, commas, or spaces.

**Full Format (User-centric)** - For granular control:
```csv
SamAccountName,DisplayName,CurrentGroups,AddToGroups,RemoveFromGroups
jsmith,John Smith,Domain Users,AppLocker-StandardUsers,
jdoe,Jane Doe,Domain Users;AppLocker-Admins,,AppLocker-Admins
```

```powershell
# Preview changes before applying
.\utilities\Manage-ADResources.ps1 -Action ImportUsers -InputPath .\GroupMembers.csv -WhatIf

# Apply changes
.\utilities\Manage-ADResources.ps1 -Action ImportUsers -InputPath .\GroupMembers.csv
```

### Create AD Structure

```powershell
# Create AppLocker OUs and security groups
.\utilities\Manage-ADResources.ps1 -Action CreateStructure -DomainName "CONTOSO"
```

This creates:
- AppLocker OU with Policies sub-OU
- Security groups: AppLocker-Workstations, AppLocker-Servers, AppLocker-DCs, AppLocker-Exceptions

---

## Project Structure

```
GA-AppLocker/
├── Start-AppLockerWorkflow.ps1         # Main entry point (menu + direct mode)
├── Invoke-RemoteScan.ps1               # Remote data collection via WinRM
├── Invoke-RemoteEventCollection.ps1    # AppLocker audit event collection
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

## Scan Output Structure

```
Scans/
├── Scan-20260109-143000/           # Timestamped scan folder
│   ├── ScanResults.csv             # Summary log
│   ├── WORKSTATION01/              # Per-computer data
│   │   ├── AppLockerPolicy.xml     # Current policy (if any)
│   │   ├── InstalledSoftware.csv
│   │   ├── Executables.csv         # With signature info
│   │   ├── Publishers.csv          # Unique publishers found
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

## Troubleshooting

### Common Issues

**WinRM Connection Failures:**
```powershell
# Test basic connectivity
Test-WSMan -ComputerName "TARGET-PC"

# Run diagnostic
.\Start-AppLockerWorkflow.ps1
# Select [D] Diagnostic -> [1] Connectivity
```

**Scan Returns No Data:**
- Verify WinRM is enabled on targets
- Check firewall allows WinRM (TCP 5985/5986)
- Ensure credentials have local admin rights on targets

**Policy Not Blocking Applications:**
- Confirm AppLocker service (AppIDSvc) is running
- Check enforcement mode is "Enabled" not "AuditOnly"
- Review event logs for rule matches

**AD Group Resolution Fails:**
- Ensure ActiveDirectory PowerShell module is installed
- Verify network connectivity to domain controller
- Check user has permission to query AD

### Getting Help

```powershell
# View detailed help for any script
Get-Help .\Start-AppLockerWorkflow.ps1 -Full
Get-Help .\Merge-AppLockerPolicies.ps1 -Examples
```

---

## License

See parent repository for license information.
