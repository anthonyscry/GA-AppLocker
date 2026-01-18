# GA-AppLocker

GA-AppLocker is a PowerShell WPF application designed for enterprise AppLocker policy management in air-gapped, classified, or highly secure environments. It provides a modular framework for discovering network assets, scanning for artifacts, generating rules, building policies, and deploying them via Group Policy Objects (GPOs).

## Project Overview
GA-AppLocker simplifies the complex process of maintaining AppLocker policies by providing a centralized dashboard with an intuitive dark-themed UI. It follows a tiered credential model and uses DPAPI encryption for secure credential storage, making it suitable for high-security environments where internet access is unavailable.

## Key Features
- **AD Discovery**: Scan the Active Directory domain for Organizational Units (OUs) and computers.
- **Artifact Scanning**: Collect executable artifacts (EXE, MSI, DLL, Script, etc.) from local or remote machines using WinRM.
- **Rule Generation**: Automatically generate Publisher, Hash, and Path rules with an approval workflow.
- **Policy Builder**: Combine approved rules into comprehensive policies with various enforcement modes (Audit, Enforce).
- **GPO Deployment**: Deploy generated policies directly to GPOs and link them to targeted OUs (async, non-blocking).
- **Tiered Credentials**: Manage administrative credentials securely using DPAPI encryption.
- **Workflow Progress**: Visual breadcrumb indicator showing progress through Discovery → Scanner → Rules → Policy stages.
- **Session Persistence**: Automatically saves and restores session state across application restarts (7-day expiry).

## Project Structure
```text
GA-AppLocker2/
├── GA-AppLocker/                    # Main module
│   ├── GA-AppLocker.psd1           # Module manifest
│   ├── GA-AppLocker.psm1           # Module loader
│   ├── GUI/
│   │   ├── MainWindow.xaml         # WPF UI definition
│   │   └── MainWindow.xaml.ps1     # UI event handlers
│   └── Modules/
│       ├── GA-AppLocker.Core/      # Logging, config, prerequisites
│       ├── GA-AppLocker.Discovery/ # AD discovery (domain, OU, machines)
│       ├── GA-AppLocker.Credentials/ # Tiered credential management
│       ├── GA-AppLocker.Scanning/  # Artifact collection
│       ├── GA-AppLocker.Rules/     # Rule generation
│       ├── GA-AppLocker.Policy/    # Policy management
│       └── GA-AppLocker.Deployment/ # GPO deployment
├── Test-AllModules.ps1             # Test suite
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
- **Modular Design**: 7 specialized sub-modules handle different aspects of the policy lifecycle.
- **Standardized Results**: All functions return a consistent object: `@{ Success = $true/$false; Data = ...; Error = ... }`.
- **UI Architecture**: WPF dark theme with 7 dedicated panels and a central button dispatcher pattern.
- **Security**: DPAPI encryption is used for storing sensitive credentials.
- **Air-Gapped Ready**: No external dependencies or internet access required after initial setup.

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
- `Get-Rule`: Retrieves a specific rule.
- `Get-AllRules`: Lists all generated rules.
- `Remove-Rule`: Deletes a rule.
- `Set-RuleStatus`: Approves or rejects rules for policy inclusion.
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

## Testing
The project includes a comprehensive test suite covering all modules.

```powershell
.\Test-AllModules.ps1
```
The suite runs over 40 tests to ensure functional correctness and API consistency.

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
