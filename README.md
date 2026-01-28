# GA-AppLocker

GA-AppLocker is a PowerShell WPF application designed for enterprise AppLocker policy management in air-gapped, classified, or highly secure environments. It provides a modular framework for discovering network assets, scanning for artifacts, generating rules, building policies, and deploying them via Group Policy Objects (GPOs).

## Project Overview
GA-AppLocker simplifies the complex process of maintaining AppLocker policies by providing a centralized dashboard with an intuitive dark-themed UI. It follows a tiered credential model and uses DPAPI encryption for secure credential storage, making it suitable for high-security environments where internet access is unavailable.

## Key Features
- **AD Discovery**: Scan the Active Directory domain for Organizational Units (OUs) and computers.
- **Artifact Scanning**: Collect executable artifacts (EXE, MSI, DLL, Script, etc.) from local or remote machines using WinRM.
- **Rule Generation**: Automatically generate Publisher, Hash, and Path rules with an approval workflow.
- **Rule Generation Wizard**: 3-step wizard for 10x faster batch rule creation with preview.
- **Rule History & Versioning**: Track all rule changes with version history and rollback capability.
- **Policy Builder**: Combine approved rules into comprehensive policies with various enforcement modes (Audit, Enforce).
- **Policy Comparison & Snapshots**: Compare policies and create versioned backups with rollback.
- **GPO Deployment**: Deploy generated policies directly to GPOs and link them to targeted OUs (async, non-blocking).
- **Tiered Credentials**: Manage administrative credentials securely using DPAPI encryption.
- **Global Search**: Search across rules, policies, and artifacts with Ctrl+F.
- **Dark/Light Theme**: Toggle between dark and light themes.
- **Keyboard Shortcuts**: Full keyboard navigation (Ctrl+1-9 for panels, F5 refresh, etc.).
- **Drag-and-Drop**: Drop files to scan or import rules/policies.
- **Scheduled Scans**: Configure automated artifact scans on schedule.
- **Workflow Progress**: Visual breadcrumb indicator showing progress through Discovery → Scanner → Rules → Policy stages.
- **Session Persistence**: Automatically saves and restores session state across application restarts (7-day expiry).

## Project Structure
```text
GA-AppLocker2/
├── GA-AppLocker/                    # Main module
│   ├── GA-AppLocker.psd1           # Module manifest (182 exported functions)
│   ├── GA-AppLocker.psm1           # Module loader
│   ├── GUI/
│   │   ├── MainWindow.xaml         # WPF UI definition (dark theme)
│   │   ├── MainWindow.xaml.ps1     # UI event handlers
│   │   ├── ToastHelpers.ps1        # Toast notifications
│   │   ├── Helpers/
│   │   │   ├── UIHelpers.ps1       # Shared UI utilities
│   │   │   ├── AsyncHelpers.ps1    # Async operations (non-blocking UI)
│   │   │   ├── GlobalSearch.ps1    # Global search functionality
│   │   │   ├── ThemeManager.ps1    # Dark/Light theme support
│   │   │   ├── KeyboardShortcuts.ps1 # Keyboard navigation
│   │   │   └── DragDropHelpers.ps1 # Drag-and-drop support
│   │   ├── Wizards/
│   │   │   ├── RuleGenerationWizard.ps1  # 3-step rule wizard
│   │   │   └── SetupWizard.ps1     # First-run setup wizard
│   │   └── Panels/                 # Panel-specific handlers
│   │       ├── Dashboard.ps1       # Dashboard stats, quick actions
│   │       ├── ADDiscovery.ps1     # AD/OU discovery
│   │       ├── Credentials.ps1     # Credential management
│   │       ├── Scanner.ps1         # Artifact scanning
│   │       ├── Rules.ps1           # Rule management
│   │       ├── Policy.ps1          # Policy building
│   │       ├── Deploy.ps1          # GPO deployment
│   │       └── Setup.ps1           # Environment initialization
│   └── Modules/
│       ├── GA-AppLocker.Core/      # Logging, config, cache, events, validation
│       ├── GA-AppLocker.Discovery/ # AD discovery (domain, OU, machines)
│       ├── GA-AppLocker.Credentials/ # Tiered credential management
│       ├── GA-AppLocker.Scanning/  # Artifact collection, scheduled scans
│       ├── GA-AppLocker.Rules/     # Rule generation, history, batch ops
│       ├── GA-AppLocker.Policy/    # Policy management, comparison, snapshots
│       ├── GA-AppLocker.Deployment/ # GPO deployment
│       ├── GA-AppLocker.Setup/     # Environment initialization
│       └── GA-AppLocker.Storage/   # Indexed storage (O(1) lookups)
├── Tests/                          # Test suites
├── Test-AllModules.ps1             # Main test suite (70 tests)
├── Run-Dashboard.ps1               # Quick launcher
└── docs/                           # Design documents
```

## Requirements
- **OS**: Windows 10 or Windows Server 2019+
- **Shell**: PowerShell 5.1+
- **Framework**: .NET Framework 4.7.2+
- **Tools**: RSAT (Remote Server Administration Tools) for AD features
- **Environment**: Domain-joined machine

## Installation
Clone the repository or copy the project files to your local machine:

```powershell
git clone https://github.com/your-repo/GA-AppLocker2.git
cd GA-AppLocker2
```

## Usage
### Quick Start
To launch the GA-AppLocker Dashboard, run the launcher script:

```powershell
.\Run-Dashboard.ps1
```

### Manual Import
You can also import the module manually and start the dashboard:

```powershell
Import-Module .\GA-AppLocker\GA-AppLocker.psd1
Start-AppLockerDashboard
```

## Architecture Notes
- **Modular Design**: 9 specialized sub-modules handle different aspects of the policy lifecycle.
- **Standardized Results**: All functions return a consistent object: `@{ Success = $true/$false; Data = ...; Error = ... }`.
- **UI Architecture**: WPF dark theme with 7 dedicated panels, central button dispatcher pattern, and standardized DataGrid columns across all data views.
- **Security**: DPAPI encryption is used for storing sensitive credentials.
- **Air-Gapped Ready**: No external dependencies or internet access required after initial setup.

## Performance
GA-AppLocker is optimized to handle large enterprise environments with 35,000+ rules:

| Operation | Performance |
|-----------|-------------|
| Rule loading | ~100ms (indexed) |
| Hash/Publisher lookup | O(1) hashtable |
| UI during long operations | Non-blocking (async) |
| Artifact scanning progress | Real-time updates |

Key optimizations:
- **Storage Module**: JSON index with in-memory hashtables for O(1) lookups
- **Async UI**: Background runspaces with dispatcher-safe progress updates
- **Efficient Collections**: `List<T>` and `HashSet<T>` instead of array concatenation

## Module Reference

### Core
Core utilities for logging, configuration, environment validation, and session management.
- `Write-AppLockerLog`: Standardized logging to file and console.
- `Get-AppLockerConfig`: Retrieves application settings.
- `Set-AppLockerConfig`: Updates application settings.
- `Test-Prerequisites`: Validates environment requirements.
- `Get-AppLockerDataPath`: Returns the data storage root path.
- `Save-SessionState`: Persists application state to disk for session recovery.
- `Restore-SessionState`: Loads previously saved session state (with 7-day expiry).
- `Clear-SessionState`: Removes saved session state file.

### Discovery
Discover Active Directory assets.
- `Get-DomainInfo`: Retrieves current AD domain details.
- `Get-OUTree`: Lists all OUs in the domain.
- `Get-ComputersByOU`: Retrieves computers within specific OUs.
- `Test-MachineConnectivity`: Validates WinRM connectivity to target machines.

### Credentials
Secure credential management for tiered administration.
- `New-CredentialProfile`: Creates and encrypts a new credential.
- `Get-CredentialProfile`: Retrieves a specific credential profile.
- `Get-AllCredentialProfiles`: Lists all stored credentials.
- `Remove-CredentialProfile`: Deletes a credential profile.
- `Test-CredentialProfile`: Validates credential against target.
- `Get-CredentialForTier`: Retrieves credential associated with a specific admin tier.
- `Get-CredentialStoragePath`: Returns the path where credentials are saved.

### Scanning
Collect artifacts from targets.
- `Get-LocalArtifacts`: Scans the local machine for executables.
- `Get-RemoteArtifacts`: Scans remote machines via WinRM.
- `Get-AppLockerEventLogs`: Collects AppLocker event logs for analysis.
- `Start-ArtifactScan`: Orchestrates a full scan job.
- `Get-ScanResults`: Retrieves results of previous scans.
- `Export-ScanResults`: Exports scan data to CSV/JSON.

### Rules
Transform artifacts into AppLocker rules.
- `New-PublisherRule`: Creates rules based on digital signatures.
- `New-HashRule`: Creates rules based on file hash.
- `New-PathRule`: Creates rules based on file or folder paths.
- `ConvertFrom-Artifact`: Auto-converts scanned artifacts into suggested rules.
- `Invoke-BatchRuleGeneration`: High-performance batch rule creation (10x faster).
- `Get-Rule`: Retrieves a specific rule.
- `Get-AllRules`: Lists all generated rules.
- `Remove-Rule`: Deletes a rule (with index sync).
- `Set-RuleStatus`: Approves or rejects rules for policy inclusion (with index sync).
- `Set-BulkRuleStatus`: Bulk status changes by pattern/vendor.
- `Remove-DuplicateRules`: Find and remove duplicate rules.
- `Get-RuleHistory`: View rule change history.
- `Restore-RuleVersion`: Rollback to previous rule version.
- `Import-RulesFromXml`: Import rules from AppLocker XML.
- `Export-RulesToXml`: Exports rules to AppLocker XML format.

### Policy
Build and manage AppLocker policies.
- `New-Policy`: Creates a new policy container.
- `Get-Policy`: Retrieves a specific policy.
- `Get-AllPolicies`: Lists all policies.
- `Remove-Policy`: Deletes a policy.
- `Set-PolicyStatus`: Sets policy as Active or Draft.
- `Add-RuleToPolicy`: Links rules to a policy.
- `Remove-RuleFromPolicy`: Unlinks rules from a policy.
- `Set-PolicyTarget`: Defines GPO and OU targets for the policy.
- `Export-PolicyToXml`: Generates the final AppLocker XML.
- `Test-PolicyCompliance`: Validates policy against targets.

### Deployment
Deploy policies to the enterprise.
- `New-DeploymentJob`: Stages a policy for deployment.
- `Get-DeploymentJob`: Retrieves job details.
- `Get-AllDeploymentJobs`: Lists deployment history.
- `Start-Deployment`: Executes GPO import and linking.
- `Stop-Deployment`: Cancels a pending job.
- `Get-DeploymentStatus`: Tracks progress of a deployment.
- `Test-GPOExists`: Verifies target GPO exists.
- `New-AppLockerGPO`: Creates a new GPO for AppLocker policies.
- `Import-PolicyToGPO`: Imports XML into GPO.
- `Get-DeploymentHistory`: Lists past deployment logs.

### Storage
High-performance indexed storage for rules (handles 35k+ rules efficiently).
- `Initialize-RuleDatabase`: Builds or rebuilds the rule index.
- `Find-RuleByHash`: O(1) lookup by file hash.
- `Find-RuleByPublisher`: O(1) lookup by publisher name.
- `Get-RulesFromDatabase`: Paginated rule retrieval with filtering.
- `Get-RuleCounts`: Fast count by status without loading all rules.
- `Start-RuleIndexWatcher`: Auto-rebuild index on file changes.
- `Add-RulesToIndex`: Incremental index updates (no full rebuild).
- `Update-RuleStatusInIndex`: Update rule status in index.
- `Remove-RulesFromIndex`: Remove rules from index.
- `Save-RulesBulk`: Single disk I/O for bulk saves.
- `Remove-RulesBulk`: Bulk rule deletion with index sync.

## Testing
The project includes a comprehensive test suite with unit tests, integration tests, and UI automation.

```powershell
# Quick module tests
.\Test-AllModules.ps1

# Pester unit tests
Invoke-Pester -Path Tests\Unit\ -Output Detailed

# UI automation (requires interactive session)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard

# Full automated suite
.\Tests\Automation\Run-AutomatedTests.ps1 -All
```

**Test Infrastructure:**

| Type | Location | Description |
|------|----------|-------------|
| Unit Tests | `Tests/Unit/` | Pester 5+ tests for module logic |
| Integration | `Tests/Integration/` | AD and E2E tests |
| UI Automation | `Tests/Automation/UI/` | WPF GUI testing with UIAutomation |
| Workflows | `Tests/Automation/Workflows/` | End-to-end workflow tests |
| Performance | `Tests/Performance/` | Benchmarks for large datasets |

**Test Coverage:**
- Core module (logging, config, cache, events, validation)
- Discovery module (AD, OU, machines)
- Credentials module (DPAPI storage)
- Scanning module (local/remote artifacts, scheduled scans)
- Rules module (creation, history, bulk ops)
- Policy module (creation, comparison, snapshots)
- Deployment module (GPO management)
- Storage module (index operations, bulk I/O)
- GUI logic (selection state, filters, navigation)
- E2E workflow tests

See [DEVELOPMENT.md](DEVELOPMENT.md#testing) for detailed testing documentation.

## Data Storage
All application data is stored in: `%LOCALAPPDATA%\GA-AppLocker\`

- **Config**: `config.json`
- **Session**: `session.json` (auto-saved UI state, expires after 7 days)
- **Credentials**: `Credentials\` (DPAPI encrypted)
- **Scans**: `Scans\`
- **Rules**: `Rules\`
- **Policies**: `Policies\`
- **Deployments**: `Deployments\`

## Contributing
Please refer to the internal documentation for coding standards and contribution guidelines.

## License
This project is proprietary and intended for internal enterprise use.
