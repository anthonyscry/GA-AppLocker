# GA-AppLocker v1.2.6

Enterprise AppLocker policy management for air-gapped, classified, and highly secure Windows environments. Complete workflow from AD discovery through GPO deployment — no internet required.

## Quick Start

```powershell
.\Run-Dashboard.ps1
```

Or import manually:

```powershell
Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force
Start-AppLockerDashboard
```

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows 10 / Server 2019+ |
| PowerShell | 5.1+ |
| .NET Framework | 4.7.2+ |
| RSAT | Required for AD features (graceful fallback via LDAP if missing) |
| GroupPolicy module | Required for GPO deployment (exports XML for manual import if missing) |

## Workflow

```
AD Discovery ──► Artifact Scanning ──► Rule Generation ──► Policy Building ──► GPO Deployment
```

1. **Discover** — Enumerate domain OUs and computers via AD module or LDAP fallback
2. **Scan** — Collect executables (EXE, DLL, MSI, scripts) from local and remote machines via WinRM
3. **Generate** — Create Publisher, Hash, or Path rules with the 3-step wizard or batch operations
4. **Build** — Combine approved rules into policies with phased enforcement (Audit → Enforce)
5. **Deploy** — Push policies to GPOs and link to target OUs
6. **Validate** — 5-stage XML validation pipeline ensures STIG-compliant policy output

## Features

### Core Workflow
- **AD Discovery** with LDAP fallback for environments without RSAT
- **Local & remote artifact scanning** (14 file types) with parallel WinRM collection
- **Three rule types**: Publisher (digital signature), Hash (SHA256), Path (filesystem)
- **3-step Rule Generation Wizard**: Configure → Preview → Generate (10x faster batch processing)
- **Phased policy enforcement**: Phase 1 (EXE only) → Phase 4 (full enforcement)
- **5-stage policy validation**: Schema, GUIDs, SIDs, conditions, live import test
- **Async GPO deployment** with fallback to XML export for manual import

### Management & Operations
- **Rule history & versioning** with rollback capability
- **Bulk operations**: Approve trusted vendors, remove duplicates, batch status changes
- **Policy comparison & snapshots** with restore
- **Tiered credentials** (T0/T1/T2) with DPAPI encryption
- **Scheduled scans** with configurable targets

### User Interface
- **Dark/light theme** toggle
- **8 dedicated panels**: Dashboard, AD Discovery, Credentials, Scanner, Rules, Policy, Deploy, Setup
- **Keyboard shortcuts**: Ctrl+1-9 navigation, F5 refresh, Ctrl+F search, Ctrl+S save
- **Drag-and-drop**: Drop files to scan or import rules/policies
- **Context menus**: Right-click rules for approve/reject/delete/copy
- **Toast notifications** and loading overlays for async operations
- **Session persistence** across restarts (7-day expiry)
- **Global search** across rules, policies, and artifacts
- **Workflow breadcrumb** showing progress through stages

## Architecture

```
GA-AppLocker/
├── GA-AppLocker.psd1              # Module manifest
├── GA-AppLocker.psm1              # Module loader
├── GUI/
│   ├── MainWindow.xaml            # WPF UI (dark theme, 8 panels)
│   ├── MainWindow.xaml.ps1        # Core UI logic
│   ├── ToastHelpers.ps1           # Notifications
│   ├── Helpers/                   # Async, search, theme, keyboard, drag-drop
│   ├── Wizards/                   # Rule generation wizard, setup wizard
│   ├── Dialogs/                   # Rules and scanner dialogs
│   └── Panels/                    # Per-panel event handlers (8 files)
└── Modules/
    ├── GA-AppLocker.Core/         # Logging, config, cache, events, validation helpers
    ├── GA-AppLocker.Discovery/    # AD/LDAP discovery, parallel connectivity testing
    ├── GA-AppLocker.Credentials/  # DPAPI credential storage, tiered access
    ├── GA-AppLocker.Scanning/     # Local/remote artifact collection, scheduled scans
    ├── GA-AppLocker.Rules/        # Rule generation, history, bulk ops, templates
    ├── GA-AppLocker.Policy/       # Policy builder, comparison, snapshots, XML export
    ├── GA-AppLocker.Deployment/   # GPO deployment with fallback
    ├── GA-AppLocker.Setup/        # Environment initialization
    ├── GA-AppLocker.Storage/      # JSON index with O(1) lookups (35k+ rules)
    └── GA-AppLocker.Validation/   # 5-stage policy XML validation pipeline
```

**10 sub-modules**, ~195 exported functions. All functions return standardized result objects:

```powershell
@{ Success = $true; Data = <result>; Error = $null }
```

## Performance

Optimized for large enterprise environments:

| Operation | Performance |
|-----------|-------------|
| Rule loading (35k+) | ~100ms (indexed) |
| Hash / Publisher lookup | O(1) hashtable |
| Batch rule generation (1k artifacts) | ~30 seconds |
| Connectivity test (100 machines) | Parallel via WMI jobs |
| UI during long operations | Non-blocking (background runspaces) |

## Data Storage

All data stored locally in `%LOCALAPPDATA%\GA-AppLocker\`:

| Path | Purpose |
|------|---------|
| `config.json` | Application settings |
| `session.json` | UI state (7-day expiry) |
| `Credentials\` | DPAPI-encrypted credential profiles |
| `Scans\` | Scan results |
| `Rules\` | Generated rules + JSON index |
| `Policies\` | Policy definitions + snapshots |
| `Deployments\` | Deployment job history |
| `Logs\` | Daily log files |

## Testing

```powershell
# Pester unit tests (378 passing)
Invoke-Pester -Path Tests\Unit\ -Output Detailed

# UI automation (requires interactive PowerShell session)
.\Tests\Automation\UI\FlaUIBot.ps1 -TestMode Standard

# Full automated suite with mock data
.\Tests\Automation\Run-AutomatedTests.ps1 -All -UseMockData
```

## Air-Gap Deployment

GA-AppLocker is designed for networks with no internet access:

1. Copy the `GA-AppLocker\` folder and `Run-Dashboard.ps1` to the target machine
2. Run `.\Run-Dashboard.ps1` from PowerShell
3. No external package managers, no NuGet, no internet calls at runtime

## License

Proprietary — internal enterprise use only.
