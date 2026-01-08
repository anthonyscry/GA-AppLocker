# GA-AppLocker

Simplified AppLocker deployment scripts for Windows 11/Server 2019+. No external dependencies required.

## Quick Start

```cmd
REM 1. Setup AD structure (on Domain Controller)
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\New-AppLockerADStructure.ps1" -DomainName "YOURDOMAIN"

REM 2. Scan computers
powershell.exe -ExecutionPolicy Bypass -File ".\Invoke-RemoteScan.ps1" -ComputerListPath ".\computers.txt" -SharePath "\\server\share\Scans"

REM 3. Generate policy
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" -TargetType Workstation -DomainName "YOURDOMAIN" -Phase 1

REM 4. Deploy via GPO in Audit mode, review logs, then enforce
```

---

## Scripts

### Core Scripts

| Script | Description |
|--------|-------------|
| `Invoke-RemoteScan.ps1` | Collects AppLocker data from remote computers via WinRM |
| `New-AppLockerPolicyFromGuide.ps1` | Generates policies (Build Guide or Simplified mode) |
| `Merge-AppLockerPolicies.ps1` | Merges multiple policies and removes duplicates |

### Utility Scripts (in `Utilities/`)

| Script | Description |
|--------|-------------|
| `New-AppLockerADStructure.ps1` | Creates AppLocker OU and security groups in AD |
| `Export-ADUserGroups.ps1` | Exports AD users and group memberships to CSV |
| `Import-ADUserGroups.ps1` | Imports group changes from edited CSV back to AD |
| `Compare-SoftwareInventory.ps1` | Compares software between machines |

---

## Workflows

### Workflow A: Enterprise Deployment (Build Guide Mode)

**Step 1: Setup AD Structure**
```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\New-AppLockerADStructure.ps1" ^
    -DomainName "CONTOSO" ^
    -ParentOU "OU=Security,OU=IT,DC=contoso,DC=com"
```

Creates:
- `OU=AppLocker` with Groups and Policies sub-OUs
- `AppLocker-Admins` - Bypass all restrictions
- `AppLocker-StandardUsers` - Standard policy
- `AppLocker-ServiceAccounts` - Service exceptions
- `AppLocker-Installers` - MSI installation rights

**Step 2: Add Members to Groups**
```powershell
Add-ADGroupMember -Identity 'AppLocker-Admins' -Members 'admin1','admin2'
Add-ADGroupMember -Identity 'AppLocker-ServiceAccounts' -Members 'svc_backup','svc_deploy'
Add-ADGroupMember -Identity 'AppLocker-Installers' -Members 'helpdesk1'
```

**Step 3: Scan Computers**
```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\Invoke-RemoteScan.ps1" ^
    -ComputerListPath ".\computers.txt" ^
    -SharePath "\\server\share\Scans" ^
    -ScanUserProfiles
```

**Step 4: Generate Phase 1 Policy**
```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -TargetType Workstation ^
    -DomainName "CONTOSO" ^
    -Phase 1 ^
    -ScanPath "\\server\share\Scans\Scan-20240108"
```

**Step 5: Deploy via GPO**
1. Open Group Policy Management Console
2. Create GPO linked to target OUs
3. Import generated XML policy
4. Set to "Audit only" mode

**Step 6: Monitor**
- Event ID 8003: Allowed (audit)
- Event ID 8004: Would have been blocked (audit)
- Location: `Applications and Services Logs > Microsoft > Windows > AppLocker`

**Step 7: Advance Phases**
```cmd
REM Phase 2: Add Script rules
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -TargetType Workstation -DomainName "CONTOSO" -Phase 2

REM Phase 3: Add MSI rules
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -TargetType Workstation -DomainName "CONTOSO" -Phase 3

REM Phase 4: Full policy including DLL (audit 14+ days before enforcing)
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -TargetType Workstation -DomainName "CONTOSO" -Phase 4
```

**Step 8: Enforce**
```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -TargetType Workstation -DomainName "CONTOSO" -Phase 2 ^
    -EnforcementMode Enabled
```

---

### Workflow B: Quick Deployment (Simplified Mode)

For testing, lab environments, or standalone machines.

```cmd
REM Scan
powershell.exe -ExecutionPolicy Bypass -File ".\Invoke-RemoteScan.ps1" ^
    -ComputerListPath ".\computers.txt" ^
    -SharePath ".\Scans"

REM Generate simplified policy
powershell.exe -ExecutionPolicy Bypass -File ".\New-AppLockerPolicyFromGuide.ps1" ^
    -Simplified ^
    -ScanPath ".\Scans\Scan-20240108" ^
    -TargetUser "BUILTIN\Users" ^
    -IncludeDenyRules ^
    -IncludeHashRules

REM Apply locally (test)
Set-AppLockerPolicy -XmlPolicy ".\AppLockerPolicy-Simplified.xml"
```

---

### Workflow C: Merge Policies

```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\Merge-AppLockerPolicies.ps1" ^
    -InputPath "\\server\share\AllPolicies" ^
    -OutputPath ".\MergedPolicy.xml" ^
    -EnforcementMode AuditOnly
```

---

### Workflow D: Software Comparison

```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\Compare-SoftwareInventory.ps1" ^
    -ReferencePath ".\Scans\BASELINE-PC\Executables.csv" ^
    -ComparePath ".\Scans\TARGET-PC\Executables.csv" ^
    -ExportFormat Both
```

---

### Workflow E: AD Group Management

```cmd
REM Export users
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\Export-ADUserGroups.ps1" ^
    -SearchBase "OU=Employees,DC=contoso,DC=com" ^
    -OutputPath ".\users.csv"

REM Edit CSV (AddToGroups, RemoveFromGroups columns)

REM Preview changes
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\Import-ADUserGroups.ps1" ^
    -InputPath ".\users.csv" -WhatIf

REM Apply changes
powershell.exe -ExecutionPolicy Bypass -File ".\Utilities\Import-ADUserGroups.ps1" ^
    -InputPath ".\users.csv"
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Setup AD structure | `New-AppLockerADStructure.ps1 -DomainName CONTOSO` |
| Scan computers | `Invoke-RemoteScan.ps1 -ComputerListPath .\computers.txt -SharePath \\share\Scans` |
| Build Guide policy | `New-AppLockerPolicyFromGuide.ps1 -TargetType Workstation -DomainName CONTOSO -Phase 1` |
| Simplified policy | `New-AppLockerPolicyFromGuide.ps1 -Simplified -ScanPath .\Scans -IncludeDenyRules` |
| Merge policies | `Merge-AppLockerPolicies.ps1 -InputPath .\Policies -OutputPath .\Merged.xml` |
| Compare software | `Compare-SoftwareInventory.ps1 -ReferencePath .\baseline.csv -ComparePath .\target.csv` |
| Export AD users | `Export-ADUserGroups.ps1 -OutputPath .\users.csv` |
| Import AD changes | `Import-ADUserGroups.ps1 -InputPath .\users.csv -WhatIf` |

---

## Requirements

- PowerShell 5.1+
- Windows 11 / Server 2019+
- WinRM enabled on target computers
- ActiveDirectory module (for AD scripts)
- Admin credentials with remote access

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
