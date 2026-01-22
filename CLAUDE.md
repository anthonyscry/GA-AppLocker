# GA-AppLocker Development Guide

## Project Overview

GA-AppLocker is a PowerShell WPF application for enterprise AppLocker policy management in air-gapped, classified, or highly secure environments. It provides a complete workflow: AD Discovery → Artifact Scanning → Rule Generation → Policy Building → GPO Deployment.

## Quick Start

```powershell
# Launch the dashboard
.\Run-Dashboard.ps1

# Or import manually
Import-Module .\GA-AppLocker\GA-AppLocker.psd1
Start-AppLockerDashboard

# Run tests
.\Test-AllModules.ps1
```

## Architecture

### Module Structure

```
GA-AppLocker2/
├── GA-AppLocker/                    # Main module
│   ├── GA-AppLocker.psd1           # Module manifest (exports all functions)
│   ├── GA-AppLocker.psm1           # Module loader
│   ├── GUI/
│   │   ├── MainWindow.xaml         # WPF UI (dark theme, 7 panels)
│   │   ├── MainWindow.xaml.ps1     # UI event handlers (code-behind pattern)
│   │   └── ToastHelpers.ps1        # Toast notifications + loading overlay
│   └── Modules/
│       ├── GA-AppLocker.Core/      # Logging, config, session state
│       ├── GA-AppLocker.Discovery/ # AD discovery (domain, OU, machines)
│       ├── GA-AppLocker.Credentials/ # Tiered credential management (DPAPI)
│       ├── GA-AppLocker.Scanning/  # Artifact collection (local/remote)
│       ├── GA-AppLocker.Rules/     # Rule generation (Publisher/Hash/Path)
│       ├── GA-AppLocker.Policy/    # Policy management + XML export
│       ├── GA-AppLocker.Deployment/ # GPO deployment
│       └── GA-AppLocker.Setup/     # Environment initialization
├── Tests/
│   ├── Unit/                       # Unit tests
│   └── Integration/                # AD integration tests
├── docker/                         # AD test environment
├── Test-AllModules.ps1             # Main test suite (67 tests)
└── Run-Dashboard.ps1               # Quick launcher
```

### 8 Sub-Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| **Core** | Logging, config, session | `Write-AppLockerLog`, `Get-AppLockerConfig`, `Save-SessionState` |
| **Discovery** | AD enumeration | `Get-DomainInfo`, `Get-OUTree`, `Get-ComputersByOU` |
| **Credentials** | DPAPI credential storage | `New-CredentialProfile`, `Get-CredentialForTier` |
| **Scanning** | Artifact collection | `Get-LocalArtifacts`, `Get-RemoteArtifacts`, `Start-ArtifactScan` |
| **Rules** | Rule generation | `New-PublisherRule`, `New-HashRule`, `ConvertFrom-Artifact` |
| **Policy** | Policy building | `New-Policy`, `Add-RuleToPolicy`, `Export-PolicyToXml` |
| **Deployment** | GPO deployment | `Start-Deployment`, `Import-PolicyToGPO`, `New-AppLockerGPO` |
| **Setup** | Environment init | `Initialize-AppLockerEnvironment`, `Initialize-WinRMGPO` |

## Code Conventions

### Standardized Return Objects

ALL functions return consistent result objects:

```powershell
# Success
@{ Success = $true; Data = <result>; Error = $null }

# Failure
@{ Success = $false; Data = $null; Error = "Error message" }

# With manual intervention flag
@{ Success = $false; ManualRequired = $true; Error = "AD modules unavailable" }
```

### Logging Pattern

```powershell
Write-AppLockerLog -Message "Operation started" -Level "INFO"
Write-AppLockerLog -Message "Error occurred" -Level "ERROR"
Write-AppLockerLog -Message "Debug info" -Level "DEBUG" -NoConsole
```

Logs go to: `%LOCALAPPDATA%\GA-AppLocker\Logs\GA-AppLocker_YYYY-MM-DD.log`

### Module Loading Pattern

All modules follow the same structure:

```powershell
# 1. Header comment
# 2. Safe logging wrapper (handles module not loaded)
# 3. Helper functions (private)
# 4. Dot-source function files with try/catch
# 5. Export-ModuleMember
```

### UI Pattern (Code-Behind)

- WPF with XAML (dark theme)
- Central button dispatcher: `Invoke-ButtonAction`
- All state in `$script:AppState` (no `global:` scope)
- Toast notifications instead of MessageBox for non-critical alerts
- Loading overlay for long operations

## Data Storage

All data stored in: `%LOCALAPPDATA%\GA-AppLocker\`

| Path | Purpose |
|------|---------|
| `config.json` | Application settings |
| `session.json` | UI state (7-day expiry) |
| `Credentials\` | DPAPI-encrypted credentials |
| `Scans\` | Scan results |
| `Rules\` | Generated rules |
| `Policies\` | Policy definitions |
| `Deployments\` | Deployment job history |
| `Logs\` | Daily log files |

## Key Types

### ArtifactType Values
```
EXE, DLL, MSI, PS1, BAT, CMD, VBS, JS, WSF
```

### Rule CollectionType Values
```
Exe, Msi, Script, Dll, Appx
```

### Tier Model
```
T0 = Domain Controllers
T1 = Servers
T2 = Workstations
```

### Policy Phases
```
Audit → Enforce
```

## Testing

### Unit Tests

```powershell
# Run all unit tests (67 tests)
.\Test-AllModules.ps1

# Run with verbose output
.\Test-AllModules.ps1 -Verbose

# Run Pester unit tests
.\Tests\Run-AllTests.ps1
```

### Automated Testing

```powershell
# Run all automated tests (Workflows + UI)
.\Tests\Automation\Run-AutomatedTests.ps1 -All

# Workflow tests with mock data (no AD required)
.\Tests\Automation\Run-AutomatedTests.ps1 -Workflows -UseMockData

# UI automation tests
.\Tests\Automation\Run-AutomatedTests.ps1 -UI -KeepUIOpen

# Docker AD integration tests
.\Tests\Automation\Run-AutomatedTests.ps1 -DockerAD

# Full test with all options
.\Tests\Automation\Run-AutomatedTests.ps1 -All -UseMockData -UITestMode Full
```

### Test Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Unit Tests | `Test-AllModules.ps1` | Module function tests (67 tests) |
| Mock Data | `Tests/Automation/MockData/` | Generate fake AD data for testing |
| Workflows | `Tests/Automation/Workflows/` | Headless integration tests (5-stage pipeline) |
| UI Bot | `Tests/Automation/UI/` | Windows UIAutomation GUI tests |
| Docker AD | `docker/` | Samba AD DC for realistic AD testing |

### Mock Data Functions

| Function | Purpose |
|----------|---------|
| `New-MockDomainInfo` | Fake domain info (TESTLAB.LOCAL) |
| `New-MockOUTree` | Fake OU structure (8 OUs across T0/T1/T2) |
| `New-MockComputers` | Fake computer objects (DCs, servers, workstations) |
| `New-MockArtifacts` | Fake scan artifacts (EXE, DLL, MSI, PS1) |
| `New-MockCredentialProfile` | Fake tiered credentials |
| `New-MockRules` | Fake AppLocker rules (Hash/Publisher/Path) |
| `New-MockPolicy` | Fake policy objects |
| `New-MockScanResult` | Fake scan results with artifacts |
| `New-MockTestEnvironment` | Complete test environment with all data |

### Workflow Test Stages

1. **Discovery**: Get-DomainInfo, Get-OUTree, Get-ComputersByOU
2. **Scanning**: Get-LocalArtifacts, artifact validation
3. **Rules**: New-HashRule, New-PublisherRule
4. **Policy**: New-Policy, Add-RuleToPolicy, Get-Policy
5. **Export**: Export-PolicyToXml, Test-PolicyCompliance

### UI Test Modes

| Mode | Description |
|------|-------------|
| Quick | Navigation only (9 panels) |
| Standard | Navigation + panel interactions |
| Full | All panels + workflow simulation |

**NOTE:** UI tests MUST be run from an interactive PowerShell session (open PowerShell manually). WPF apps cannot display windows from CI/CD, remote terminals, or non-interactive sessions.

### Test Categories
- Core module tests
- Discovery module tests
- Credentials module tests
- Scanning module tests
- Rules module tests
- Policy module tests
- Deployment module tests
- Edge case tests (invalid GUIDs, empty params)
- E2E workflow tests
- UI automation tests

## Configuration

### Default Config Structure

```json
{
  "ScanPaths": ["C:\\Program Files", "C:\\Program Files (x86)", "C:\\Windows\\System32"],
  "LogLevel": "INFO",
  "ScanThrottleLimit": 10,
  "ScanBatchSize": 50,
  "TierMapping": {
    "T0": ["Domain Controllers"],
    "T1": ["Servers", "Member Servers"],
    "T2": ["Workstations", "Computers"]
  },
  "MachineTypeTiers": {
    "DomainController": "T0",
    "Server": "T1",
    "Workstation": "T2"
  }
}
```

## Common Tasks

### Adding a New Function

1. Create `FunctionName.ps1` in appropriate module's `Functions/` folder
2. Add to module's `.psm1` dot-source list
3. Add to module's `.psd1` `FunctionsToExport`
4. Add to root `GA-AppLocker.psd1` `FunctionsToExport`
5. Add test in `Test-AllModules.ps1`

### Modifying UI

1. Edit `MainWindow.xaml` for layout changes
2. Edit `MainWindow.xaml.ps1` for event handlers
3. Use `Show-Toast` for notifications
4. Use `Show-LoadingOverlay`/`Hide-LoadingOverlay` for long operations

### Adding a New Panel

1. Add panel XAML in `MainWindow.xaml`
2. Add navigation button in sidebar
3. Add `Show-*Panel` function in `MainWindow.xaml.ps1`
4. Add button handler in `Invoke-ButtonAction`
5. Update workflow breadcrumb if needed

## Dependencies

- PowerShell 5.1+
- .NET Framework 4.7.2+
- WPF assemblies (PresentationFramework, PresentationCore, WindowsBase)
- RSAT (for AD features) - graceful fallback if missing
- GroupPolicy module (for GPO deployment) - graceful fallback if missing

## Important Notes

### Air-Gap Ready
- No external dependencies after setup
- No internet access required
- All data stored locally with DPAPI encryption

### AD Module Fallback
- Uses LDAP directly when ActiveDirectory module unavailable
- `Get-DomainInfoViaLdap`, `Get-OUTreeViaLdap`, `Get-ComputersByOUViaLdap`

### GPO Deployment Fallback
- Returns `ManualRequired = $true` when GroupPolicy module unavailable
- Exports XML for manual import via GPMC

### Remote Scanning
- Uses `Invoke-Command` with configurable `ThrottleLimit`
- Requires WinRM enabled on targets
- Uses tiered credentials automatically

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Module won't load | Check PowerShell 5.1+, run as admin |
| AD discovery fails | Verify RSAT installed, domain joined |
| Remote scan fails | Check WinRM enabled, credentials valid |
| GPO deployment fails | Verify GroupPolicy module, run on DC or with RSAT |
| UI freezes | Check for blocking operations (should use async) |

## Version History

See [TODO.md](TODO.md) for completed work and [README.md](README.md) for feature list.

**Current Status:** All 21 TODO items completed. 67 tests passing. Production-ready.
