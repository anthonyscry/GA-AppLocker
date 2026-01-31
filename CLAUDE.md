# GA-AppLocker Development Guide

## Project Overview

GA-AppLocker is a PowerShell 5.1 WPF application for enterprise AppLocker policy management in air-gapped, classified, or highly secure environments. Complete workflow: AD Discovery → Artifact Scanning → Rule Generation → Policy Building → GPO Deployment.

**Version:** 1.2.18 | **Tests:** 397/397 passing (100%) | **Exported Commands:** ~196

## Quick Start

```powershell
# Launch the dashboard
.\Run-Dashboard.ps1

# Or import manually
Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force
Start-AppLockerDashboard

# Run Pester unit tests
Invoke-Pester -Path Tests\Unit\ -Output Detailed
```

## Architecture

### Module Structure

```
GA-AppLocker/
├── GA-AppLocker.psd1              # Module manifest (exports all functions)
├── GA-AppLocker.psm1              # Module loader (re-exports sub-modules)
├── GUI/
│   ├── MainWindow.xaml            # WPF UI (dark theme, 8 panels)
│   ├── MainWindow.xaml.ps1        # Core UI (navigation, session state) - 716 lines
│   ├── ToastHelpers.ps1           # Toast notifications + loading overlay
│   ├── Helpers/
│   │   ├── UIHelpers.ps1          # Shared UI utilities (global: scope for WPF)
│   │   ├── AsyncHelpers.ps1       # Async operations (runspaces, progress)
│   │   ├── KeyboardShortcuts.ps1  # Ctrl+1-9 nav, F5 refresh, etc.
│   │   ├── DragDropHelpers.ps1    # File drop on Scanner/Rules/Policy panels
│   │   ├── SearchHelpers.ps1      # Global search
│   │   └── ThemeManager.ps1       # Dark/light mode toggle
│   ├── Wizards/
│   │   ├── RuleGenerationWizard.ps1  # 3-step wizard (Configure→Preview→Generate)
│   │   └── SetupWizard.ps1        # 7-step first-run setup
│   ├── Dialogs/                   # Rule/scanner detail dialogs
│   └── Panels/                    # Per-panel event handlers (8 files)
│       ├── Dashboard.ps1          # Dashboard stats, quick actions
│       ├── ADDiscovery.ps1        # AD/OU discovery, machine selection
│       ├── Credentials.ps1        # Credential management
│       ├── Scanner.ps1            # Artifact scanning, type filters
│       ├── Rules.ps1              # Rule management, context menu, filtering
│       ├── Policy.ps1             # Policy building, status filters
│       ├── Deploy.ps1             # GPO deployment, job filters
│       └── Setup.ps1              # Environment initialization
└── Modules/
    ├── GA-AppLocker.Core/         # Logging, config, cache, events, validation helpers
    ├── GA-AppLocker.Discovery/    # AD/LDAP discovery, parallel connectivity (Test-PingConnectivity)
    ├── GA-AppLocker.Credentials/  # DPAPI credential storage, tiered access (T0/T1/T2)
    ├── GA-AppLocker.Scanning/     # Local/remote artifact collection (14 file types), scheduled scans
    ├── GA-AppLocker.Rules/        # Rule generation, history, bulk ops, templates, deduplication
    ├── GA-AppLocker.Policy/       # Policy builder, comparison, snapshots, XML export
    ├── GA-AppLocker.Deployment/   # GPO deployment with fallback to XML export
    ├── GA-AppLocker.Setup/        # Environment initialization
    ├── GA-AppLocker.Storage/      # JSON index with O(1) lookups, repository pattern
    └── GA-AppLocker.Validation/   # 5-stage policy XML validation pipeline
```

### 10 Sub-Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| **Core** | Logging, config, session, cache, events, validation | `Write-AppLockerLog`, `Get-AppLockerConfig`, `Get-CachedValue`, `Publish-AppLockerEvent`, `Test-ValidHash` |
| **Discovery** | AD enumeration + LDAP fallback | `Get-DomainInfo`, `Get-OUTree`, `Get-ComputersByOU`, `Resolve-LdapServer`, `Test-PingConnectivity` |
| **Credentials** | DPAPI credential storage | `New-CredentialProfile`, `Get-CredentialForTier` |
| **Scanning** | Artifact collection (14 file types) | `Get-LocalArtifacts`, `Get-RemoteArtifacts`, `Start-ArtifactScan` |
| **Rules** | Rule generation + templates | `New-PublisherRule`, `New-HashRule`, `ConvertFrom-Artifact`, `Get-RuleTemplates`, `Invoke-BatchRuleGeneration` |
| **Policy** | Policy building + comparison + snapshots | `New-Policy`, `Add-RuleToPolicy`, `Export-PolicyToXml`, `Compare-Policies`, `New-PolicySnapshot` |
| **Deployment** | GPO deployment | `Start-Deployment`, `Import-PolicyToGPO`, `New-AppLockerGPO` |
| **Setup** | Environment init | `Initialize-AppLockerEnvironment`, `Initialize-WinRMGPO` |
| **Storage** | Indexed rule storage + repository | `Get-RuleById`, `Find-RuleByHash`, `Get-RulesFromDatabase`, `Save-RuleToRepository`, `Save-RulesBulk` |
| **Validation** | Policy XML validation (5-stage) | `Invoke-AppLockerPolicyValidation`, `Test-AppLockerXmlSchema`, `Test-AppLockerRuleGuids`, `Test-AppLockerRuleSids`, `Test-AppLockerRuleConditions`, `Test-AppLockerPolicyImport` |

## Code Conventions

### Standardized Return Objects

ALL functions return consistent result objects:

```powershell
@{ Success = $true; Data = <result>; Error = $null }
@{ Success = $false; Data = $null; Error = "Error message" }
@{ Success = $false; ManualRequired = $true; Error = "AD modules unavailable" }
```

### Logging

```powershell
Write-AppLockerLog -Message "Operation started" -Level "INFO"
Write-AppLockerLog -Message "Error occurred" -Level "ERROR"
```

Logs: `%LOCALAPPDATA%\GA-AppLocker\Logs\GA-AppLocker_YYYY-MM-DD.log`

### Module Loading Pattern

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
- All state in `$script:AppState` (no `global:` scope for state — but UI helpers like `Show-LoadingOverlay` must be `global:` for WPF timer callbacks)
- Toast notifications via `Show-Toast`
- Loading overlay via `Show-LoadingOverlay`/`Hide-LoadingOverlay`

### WPF Scope Rules

1. **Functions called from timer ticks** → must be `global:` scope
2. **Functions called from runspaces** → must be defined via imported module, or `global:`
3. **MainWindow reference** → `$script:MainWindow`
4. **UI updates from background** → `Invoke-UIUpdate` (marshals to dispatcher)

## Data Storage

All data: `%LOCALAPPDATA%\GA-AppLocker\`

| Path | Purpose |
|------|---------|
| `config.json` | Application settings |
| `session.json` | UI state (7-day expiry) |
| `Credentials\` | DPAPI-encrypted credentials |
| `Scans\` | Scan results |
| `Rules\` | Generated rules + `rules-index.json` |
| `Policies\` | Policy definitions + snapshots |
| `Deployments\` | Deployment job history |
| `Logs\` | Daily log files |

## Key Types

| Type | Values |
|------|--------|
| ArtifactType | EXE, DLL, MSI, PS1, BAT, CMD, VBS, JS, WSF, APPX, MSP, MST, COM, SCR |
| CollectionType | Exe, Msi, Script, Dll, Appx |
| Tier | T0 (Domain Controllers), T1 (Servers), T2 (Workstations) |
| Policy Phase | Audit → Enforce |
| Rule Status | Pending, Approved, Rejected, Review |

## Testing

```powershell
# Pester unit tests (397/397 passing — 100%)
Invoke-Pester -Path Tests\Unit\ -Output Detailed

# Workflow tests with mock data (no AD required)
.\Tests\Automation\Run-AutomatedTests.ps1 -Workflows -UseMockData

# UI automation (requires interactive PowerShell session)
.\Tests\Automation\Run-AutomatedTests.ps1 -UI -KeepUIOpen

# Full suite
.\Tests\Automation\Run-AutomatedTests.ps1 -All -UseMockData
```

**NOTE:** UI tests MUST run from an interactive PowerShell session. WPF cannot display from CI/remote/non-interactive sessions.

## Common Tasks

### Adding a New Function

1. Create `FunctionName.ps1` in appropriate module's `Functions/` folder
2. Add to module's `.psm1` dot-source list
3. Add to module's `.psd1` `FunctionsToExport`
4. Add to root `GA-AppLocker.psd1` `FunctionsToExport`
5. Add to root `GA-AppLocker.psm1` export array
6. Add test in `Tests\Unit\`

### Modifying UI

1. Edit `MainWindow.xaml` for layout changes
2. Edit panel file in `GUI/Panels/` for event handlers
3. Use `Show-Toast` for notifications
4. Use `Show-LoadingOverlay`/`Hide-LoadingOverlay` for long operations

### Index Sync

All rule modifications auto-sync the JSON index:
- `Set-RuleStatus` → `Update-RuleStatusInIndex`
- `Remove-Rule` → `Remove-RulesBulk` (Storage module)
- `Restore-RuleVersion` → `Update-RuleStatusInIndex`
- `Save-Rule` (in psm1) → `Add-RulesToIndex`

## Configuration

```json
{
  "ScanPaths": ["C:\\Program Files", "C:\\Program Files (x86)", "C:\\Windows\\System32"],
  "LogLevel": "INFO",
  "ScanThrottleLimit": 10,
  "ScanBatchSize": 50,
  "TierMapping": { "T0": ["Domain Controllers"], "T1": ["Servers", "Member Servers"], "T2": ["Workstations", "Computers"] },
  "MachineTypeTiers": { "DomainController": "T0", "Server": "T1", "Workstation": "T2" }
}
```

**Important:** `Set-AppLockerConfig` takes `-Key`/`-Value` (single) or `-Settings [hashtable]` — NOT `-Config [PSCustomObject]`.

## Dependencies

- PowerShell 5.1+ (**not PS 7** — no ternary `?:`, no null-coalescing `??`, no `[char]` above `0xFFFF`)
- .NET Framework 4.7.2+
- WPF assemblies (PresentationFramework, PresentationCore, WindowsBase)
- RSAT (for AD features) — graceful LDAP fallback if missing
- GroupPolicy module (for GPO deployment) — exports XML for manual import if missing

## Air-Gap Design

- No external dependencies at runtime
- No internet access required
- All data stored locally with DPAPI encryption
- LDAP fallback when ActiveDirectory module unavailable
- XML export fallback when GroupPolicy module unavailable

## Performance

| Operation | Performance |
|-----------|-------------|
| Rule loading (35k+) | ~100ms (indexed JSON) |
| Hash/Publisher lookup | O(1) hashtable |
| Batch rule generation (1k artifacts) | ~30 seconds |
| Connectivity test (100 machines) | Parallel via WMI jobs |
| UI during long ops | Non-blocking (background runspaces) |

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| Module won't load | Check PS 5.1+, run as admin |
| AD discovery fails | Verify RSAT installed or check LDAP fallback |
| Remote scan fails | Check WinRM enabled, credentials valid |
| GPO deployment fails | Verify GroupPolicy module, or use XML export |
| App hangs on startup | Check `global:` scope on UI helpers — see WPF Scope Rules |
| "Function not recognized" in log | Runspace scope issue — non-blocking, main UI works |

## Important Constraints

- **DO NOT TOUCH** rule import, `Export-PolicyToXml`, or the Validation module — confirmed working
- All functions in `Get-RemoteArtifacts` process `Invoke-Command` batch results into `$allArtifacts` (List<T>)
- `Test-PingConnectivity` is exported from Discovery module, main `.psd1`, and main `.psm1`
- Connectivity testing uses `Get-WmiObject Win32_PingStatus` (not `Test-Connection`) for timeout control
- Large machine sets (>5) use parallel `Start-Job` ping; ≤5 use sequential
- `Resolve-LdapServer` centralizes all LDAP server resolution (no hardcoded servers in ViaLdap functions)
- Non-recursive file scans use enumerate + HashSet filter (PS 5.1 `-Include` requires `-Recurse`)

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.2.18 | Jan 30, 2026 | Fix Change Group/Action silent error swallowing (added error logging), consistent ISO 8601 date serialization across all rule CRUD (fixes verbose DateTime JSON objects), AppLocker-Admins default template (allow-all across 4 collection types), RESOLVE: prefix handling in template engine |
| 1.2.17 | Jan 30, 2026 | Granular script type filters (split "Skip Scripts" into WSH vs Shell across entire pipeline), fix WPF dispatcher scope bugs (Update-ScanProgress, Update-ScanUIState, Update-ArtifactDataGrid → global:), window height increased to 1050px |
| 1.2.16 | Jan 30, 2026 | Tests & docs update — 15 new tests (ImportExport roundtrip, hash name generation, ConvertFrom-Artifact filename resolution, policy export filename extraction, module loading verification), DEVELOPMENT.md updated to 10 modules with critical warnings, TODO.md and README.md test counts updated |
| 1.2.15 | Jan 30, 2026 | Fix "Unknown (Hash)" rule names on import and generation — robust filename extraction from XML attributes, FilePath fallback in ConvertFrom-Artifact, hash-prefix display for truly unknown files |
| 1.2.14 | Jan 30, 2026 | Fix dashboard not appearing (Get-CimInstance WMI timeout blocking WPF STA thread → .NET IPGlobalProperties), remove redundant nested module loading, fix Test-PingConnectivity export |
| 1.2.13 | Jan 30, 2026 | Skip Scripts filter checkbox, .NET SHA256 hash (4.4x faster), RunspacePool parallel scanning (3.5x faster), progress bar overlap fix (local+remote ranges), scan performance filters UI |
| 1.2.12 | Jan 30, 2026 | Fix publisher OID junk (truncate at C=XX), scan history 26x faster, export cap removed, import batch rewrite, WinRM GPO enhanced (AllowAutoConfig, LocalAccountTokenFilterPolicy, Enforced), Remove-WinRMGPO, startup rule clearing, credential logging |
| 1.2.11 | Jan 30, 2026 | Fix Rules DataGrid Group column blank (SID-to-name resolver, circle colors by scope), fix hardcoded v1.2.0 startup log, suppress unapproved verb warnings |
| 1.2.10 | Jan 30, 2026 | Air-gap scan speedup (replace Get-AuthenticodeSignature with .NET), WinRM 30s timeout, throttle/batch defaults, fix remote scan nested array bug, no-machines null guard, module reload, scan progress logging, troubleshooting scripts |
| 1.2.9 | Jan 30, 2026 | Fix OU tree (Depth calc, error handling), LDAP LastLogon, scan per-machine progress |
| 1.2.8 | Jan 30, 2026 | Dynamic version display, hide breadcrumb on sidebar collapse, APPX scanning pipeline fix |
| 1.2.7 | Jan 30, 2026 | Fix blank Action column (index missing Action/SID fields), bulk Change Action + Change Group buttons for selected rules |
| 1.2.6 | Jan 30, 2026 | Common Deny Path Rules button (21 deny rules for user-writable dirs), AppLocker AD groups in target group dropdowns, Resolve-GroupSid helper |
| 1.2.5 | Jan 30, 2026 | Fix AD Discovery filters (.GetNewClosure scope bug), remove checkboxes, fix IsOnline property error, rename scanner buttons |
| 1.2.4 | Jan 30, 2026 | Bulletproof logging — replace all cmdlets with .NET in Write-AppLockerLog to prevent WPF dispatcher crashes |
| 1.2.3 | Jan 29, 2026 | Credential fallback chain, scan failure feedback, auto-refresh Discovery, scanner machine management, filter fix |
| 1.2.2 | Jan 29, 2026 | Fix phantom machine items, filter buttons, text search, connectivity merge, scan null index crash |
| 1.2.1 | Jan 29, 2026 | Fix connectivity freeze (void List.Remove), dialog closure scoping, TreeView selection styling, OU filtering, row-click checkbox toggle |
| 1.2.0 | Jan 29, 2026 | Critical scanning fixes (empty remote results, extension coverage, Include bug), parallel ping, LDAP hardening, GUI bug fixes, code audit |
| 1.1.1 | Jan 28, 2026 | Centralized LDAP resolution, null-safety, paging, credential validation, 36 Discovery tests |
| 1.1.0 | Jan 28, 2026 | PolicyValidation module (5-stage pipeline), build pipeline, project cleanup |
| 1.0.0 | Jan 2026 | Initial release — full workflow, 10 modules, WPF dashboard, async UI, O(1) storage |
