# Advanced Features

## GUI Improvements (v1.2.0)

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+1 | Scan Computers |
| Ctrl+2 | Collect Events |
| Ctrl+3 | Generate Policy |
| Ctrl+4 | Merge Policies |
| Ctrl+5 | Compare Inventories |
| Ctrl+6 | Validate Policy |
| F1 | Help |

Keyboard shortcut hints are displayed as tooltips on navigation buttons.

### Operation Cancellation

Long-running operations can be cancelled using the Cancel button that appears in the status bar. Cancellation occurs at the next output line.

### Button State Management

Operation buttons are automatically disabled during long-running tasks to prevent conflicts. They re-enable when the operation completes.

### Progress Indicators

- XML validation progress during merge operations
- File processing counts during scans
- Policy rule processing progress

---

## Credential Validation

Validate WinRM credentials before running operations:

```powershell
# Import ErrorHandling module
Import-Module .\src\Utilities\ErrorHandling.psm1

# Test credentials against a target computer
$cred = Get-Credential
$isValid = Test-CredentialValidity -Credential $cred -ComputerName 'TARGET-PC' -TimeoutSeconds 30
if ($isValid) {
    Write-Host "Credentials validated successfully"
}
```

---

## Monitoring (v1.1.0)

### Continuous Monitoring with Alerts

```powershell
# Basic monitoring
.\src\Utilities\Start-AppLockerMonitor.ps1 -ComputerListPath .\computers.txt -IntervalMinutes 30

# Background monitoring with webhook alerts
.\src\Utilities\Start-AppLockerMonitor.ps1 -ComputerListPath .\computers.txt -AsJob `
    -AlertWebhook "https://teams.webhook.url" -AlertThreshold 5
```

### GPO Export Formats

```powershell
# Export for GPO deployment
.\src\Utilities\Export-AppLockerGPO.ps1 -PolicyPath .\policy.xml -OutputPath .\GPO-Export

# Export for specific deployment method
.\src\Utilities\Export-AppLockerGPO.ps1 -PolicyPath .\policy.xml -Format Intune
```

Supported formats: GPOBackup, PowerShell, Registry, SCCM, Intune

### Impact Analysis

```powershell
# Pre-deployment impact analysis
.\src\Utilities\Get-RuleImpactAnalysis.ps1 -PolicyPath .\new-policy.xml -ScanPath .\Scans

# Detailed impact with current policy comparison
.\src\Utilities\Get-RuleImpactAnalysis.ps1 -PolicyPath .\new-policy.xml -ScanPath .\Scans `
    -CurrentPolicyPath .\current.xml -Detailed
```

---

## Policy Lifecycle (v1.2.0)

### Version Control

```powershell
Import-Module .\src\Utilities\PolicyVersionControl.psm1

# Initialize repository
Initialize-PolicyRepository -Path .\PolicyRepo

# Save a policy version
Save-PolicyVersion -PolicyPath .\policy.xml -Message "Added Chrome rules"

# View history
Show-PolicyLog -Last 10

# Compare versions
Compare-PolicyVersions -Version1 "v1" -Version2 "v2"

# Restore previous version
Restore-PolicyVersion -Version "v3"

# Branch management
New-PolicyBranch -Name "test-dlls"
Switch-PolicyBranch -Name "main"
```

### Industry Templates

```powershell
# List available templates
.\src\Utilities\New-PolicyFromTemplate.ps1 -ListTemplates

# Get detailed template info
.\src\Utilities\New-PolicyFromTemplate.ps1 -TemplateInfo Healthcare

# Generate policy from template
.\src\Utilities\New-PolicyFromTemplate.ps1 -Template FinancialServices -Phase 1

# With custom publishers
.\src\Utilities\New-PolicyFromTemplate.ps1 -Template Government -Phase 2 `
    -CustomPublishers @('O=MY COMPANY*')
```

**Available Templates:**
- **FinancialServices**: SOX/PCI-DSS compliance
- **Healthcare**: HIPAA/HITECH compliance
- **Government**: NIST/CMMC compliance
- **Manufacturing**: ICS/OT integration
- **Education**: FERPA/COPPA compliance
- **Retail**: PCI-DSS for POS systems
- **SmallBusiness**: Balanced productivity/security

### Phase Advancement

```powershell
# Check if ready for next phase
.\src\Utilities\Invoke-PhaseAdvancement.ps1 -CurrentPhase 1 -EventPath .\Events

# With custom thresholds
.\src\Utilities\Invoke-PhaseAdvancement.ps1 -CurrentPhase 2 -EventPath .\Events `
    -Thresholds @{ MaxBlockedPerDay = 5; MinAuditDays = 14 }

# Auto-advance if ready
.\src\Utilities\Invoke-PhaseAdvancement.ps1 -CurrentPhase 1 -EventPath .\Events -AutoAdvance
```

### Rule Health Checking

```powershell
# Basic health check
.\src\Utilities\Test-RuleHealth.ps1 -PolicyPath .\policy.xml

# With scan data for usage analysis
.\src\Utilities\Test-RuleHealth.ps1 -PolicyPath .\policy.xml -ScanPath .\Scans

# Full check with certificate validation
.\src\Utilities\Test-RuleHealth.ps1 -PolicyPath .\policy.xml -CheckCertificates `
    -EventPath .\Events -OutputPath .\Reports
```

**Health Checks:**
- Path validation (broken paths, environment variables)
- Publisher validation (wildcards, certificate expiry)
- Hash validation (matching files exist)
- Rule conflicts (overlapping allow/deny)
- SID validation (resolvable principals)
- Usage analysis (never-matched rules)

### Self-Service Whitelist Requests

```powershell
Import-Module .\src\Utilities\WhitelistRequestManager.psm1

# Initialize request system
Initialize-WhitelistSystem -RequestsPath .\Requests -ApproversGroup "AppLocker-Approvers"

# Submit a whitelist request
New-WhitelistRequest -ApplicationPath "C:\Apps\MyApp.exe" `
    -Justification "Required for daily operations" `
    -Requester "john.doe@company.com"

# List pending requests
Get-WhitelistRequests -Status Pending

# Approve request
Approve-WhitelistRequest -RequestId "REQ-001" -Approver "admin@company.com"

# Reject request
Deny-WhitelistRequest -RequestId "REQ-002" -Reason "Security concern"
```

---

## Building the EXE

To rebuild the standalone executable:

```powershell
# Full build with validation, tests, and packaging
.\build\Build-AppLocker.ps1

# Build just the GUI executable
.\build\Build-GUI.ps1

# Build the CLI executable
.\build\Build-Executable.ps1

# Run validation only (lint + tests)
.\build\Invoke-LocalValidation.ps1
```

---

## PowerShell Gallery

```powershell
# Publish to PowerShell Gallery
.\build\Publish-ToGallery.ps1 -ApiKey "your-api-key"

# Preview what would be published
.\build\Publish-ToGallery.ps1 -WhatIf
```
