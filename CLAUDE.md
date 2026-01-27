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
│   │   ├── MainWindow.xaml         # WPF UI (dark theme, 9 panels)
│   │   ├── MainWindow.xaml.ps1     # Core UI (navigation, session state) - 716 lines
│   │   ├── ToastHelpers.ps1        # Toast notifications + loading overlay
│   │   ├── Helpers/
│   │   │   ├── UIHelpers.ps1       # Shared UI utilities
│   │   │   └── AsyncHelpers.ps1    # Async operations (runspaces, progress)
│   │   └── Panels/                 # Panel-specific handlers (extracted)
│   │       ├── Dashboard.ps1       # Dashboard stats, quick actions
│   │       ├── ADDiscovery.ps1     # AD/OU discovery, machine filters
│   │       ├── Credentials.ps1     # Credential management
│   │       ├── Scanner.ps1         # Artifact scanning, type filters
│   │       ├── Rules.ps1           # Rule generation, type/status filters
│   │       ├── Policy.ps1          # Policy building, status filters
│   │       ├── Deploy.ps1          # GPO deployment, job filters
│   │       └── Setup.ps1           # Environment initialization
│   └── Modules/
│       ├── GA-AppLocker.Core/      # Logging, config, session state
│       ├── GA-AppLocker.Discovery/ # AD discovery (domain, OU, machines)
│       ├── GA-AppLocker.Credentials/ # Tiered credential management (DPAPI)
│       ├── GA-AppLocker.Scanning/  # Artifact collection (local/remote)
│       ├── GA-AppLocker.Rules/     # Rule generation (Publisher/Hash/Path)
│       ├── GA-AppLocker.Policy/    # Policy management + XML export
│       ├── GA-AppLocker.Deployment/ # GPO deployment
│       ├── GA-AppLocker.Setup/     # Environment initialization
│       └── GA-AppLocker.Storage/   # Indexed rule storage (O(1) lookups)
├── Tests/
│   ├── Unit/                       # Unit tests
│   └── Integration/                # AD integration tests
├── docker/                         # AD test environment
├── Test-AllModules.ps1             # Main test suite (70 tests, 69 passing)
└── Run-Dashboard.ps1               # Quick launcher
```

### 9 Sub-Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| **Core** | Logging, config, session, cache, events, validation | `Write-AppLockerLog`, `Get-AppLockerConfig`, `Save-SessionState`, `Get-CachedValue`, `Publish-AppLockerEvent`, `Test-ValidHash` |
| **Discovery** | AD enumeration | `Get-DomainInfo`, `Get-OUTree`, `Get-ComputersByOU` |
| **Credentials** | DPAPI credential storage | `New-CredentialProfile`, `Get-CredentialForTier` |
| **Scanning** | Artifact collection | `Get-LocalArtifacts`, `Get-RemoteArtifacts`, `Start-ArtifactScan` |
| **Rules** | Rule generation + templates | `New-PublisherRule`, `New-HashRule`, `ConvertFrom-Artifact`, `Get-RuleTemplates`, `New-RulesFromTemplate` |
| **Policy** | Policy building + comparison + snapshots | `New-Policy`, `Add-RuleToPolicy`, `Export-PolicyToXml`, `Compare-Policies`, `New-PolicySnapshot`, `Restore-PolicySnapshot` |
| **Deployment** | GPO deployment | `Start-Deployment`, `Import-PolicyToGPO`, `New-AppLockerGPO` |
| **Setup** | Environment init | `Initialize-AppLockerEnvironment`, `Initialize-WinRMGPO` |
| **Storage** | Indexed rule storage + repository | `Initialize-RuleDatabase`, `Find-RuleByHash`, `Get-RulesFromDatabase`, `Get-RuleFromRepository`, `Save-RuleToRepository` |

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
# Run all unit tests (70 tests, 69 passing)
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
| Unit Tests | `Test-AllModules.ps1` | Module function tests (70 tests, 69 passing) |
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

## Recent Changes (Jan 2026)

### Performance Optimization (Jan 22, 2026)

Major performance improvements to handle 35k+ rules efficiently:

#### New Storage Module (`GA-AppLocker.Storage`)

Replaces slow JSON file scanning with indexed storage:

```powershell
# Initialize/rebuild index (runs once, ~2 min for 35k rules)
Initialize-RuleDatabase

# O(1) lookups instead of O(n) file scanning
Find-RuleByHash -Hash 'ABC123...'
Find-RuleByPublisher -PublisherName 'O=MICROSOFT'

# Fast paginated queries
Get-RulesFromDatabase -Status 'Pending' -Take 100 -Skip 0

# Get counts without loading all rules
Get-RuleCounts
```

**Storage modes:**
- **SQLite** (when available): Full database with indexes
- **JSON Index Fallback** (air-gapped): `rules-index.json` with in-memory hashtables

#### Async UI Operations (`GUI/Helpers/AsyncHelpers.ps1`)

Non-blocking UI for all long operations:

```powershell
# Basic async with loading overlay
Invoke-AsyncOperation -ScriptBlock { Get-AllRules } -LoadingMessage "Loading..." -OnComplete {
    param($Result)
    $dataGrid.ItemsSource = $Result.Data
}

# Async with progress reporting
Invoke-AsyncWithProgress -ScriptBlock {
    param($Progress)
    $Progress.Total = 100
    for ($i = 1; $i -le 100; $i++) {
        $Progress.Current = $i
        $Progress.Message = "Processing item $i..."
    }
} -LoadingMessage "Processing..."
```

**Async-enabled panels:**
- Rules panel (load, refresh)
- Policy panel (load, refresh)
- Deploy panel (load, refresh)
- AD Discovery (domain refresh, connectivity test)

#### Index Auto-Rebuild (`IndexWatcher.ps1`)

FileSystemWatcher monitors Rules directory:

```powershell
# Start watching (auto-rebuilds on file changes with 2s debounce)
Start-RuleIndexWatcher

# Check status
Get-RuleIndexWatcherStatus

# Manual rebuild
Invoke-RuleIndexRebuild
```

#### O(n²) → O(n) Performance Fixes

| Location | Before | After |
|----------|--------|-------|
| `Remove-DuplicateRules.ps1` | `$allRules += $rule` | `List<T>.Add()` |
| `Scanner.ps1` merge | `-notin` array | `HashSet.Contains()` |
| `Get-LocalArtifacts.ps1` | `$artifacts += $artifact` | `List<T>.Add()` |
| `Policy.ps1` display | `$displayData +=` | `List<T>.Add()` |

#### Performance Impact

| Operation | Before | After |
|-----------|--------|-------|
| Rule loading (35k) | 2-5 min | ~100ms |
| Hash lookup | O(n) scan | O(1) hashtable |
| Publisher lookup | O(n) scan | O(1) hashtable |
| Artifact merge | O(n×m) | O(n+m) |
| UI during loads | Frozen | Responsive |

### GUI Refactoring (Jan 21, 2026)

MainWindow.xaml.ps1 was refactored from **4,605 lines → 716 lines** (84% reduction):

```
GA-AppLocker/GUI/
├── MainWindow.xaml.ps1      (716 lines - core navigation, session state, init)
├── MainWindow.xaml
├── ToastHelpers.ps1
├── Helpers/
│   └── UIHelpers.ps1        (logging, loading overlay)
└── Panels/
    ├── Dashboard.ps1        (dashboard stats, quick actions)
    ├── ADDiscovery.ps1      (AD/OU discovery, machine selection)
    ├── Credentials.ps1      (credential management)
    ├── Scanner.ps1          (artifact scanning)
    ├── Rules.ps1            (rule generation, filtering)
    ├── Policy.ps1           (policy building)
    ├── Deploy.ps1           (GPO deployment)
    └── Setup.ps1            (environment initialization)
```

**Key changes:**
- Panel functions extracted to separate files in `GUI/Panels/`
- MainWindow.xaml.ps1 now dot-sources panel files
- Each panel has its own `Initialize-*Panel` function
- Filter buttons wired with visual feedback (highlighting active filter)

### Filter Button Implementation Status

| Panel | Wired | Visual Feedback | Filter Logic |
|-------|-------|-----------------|--------------|
| Scanner | ✅ | ✅ | ✅ |
| Rules | ✅ | ✅ | ✅ |
| Policy | ✅ | ✅ | ✅ |
| Deploy | ✅ | ✅ | ✅ |
| Discovery | ✅ | ✅ | ✅ |

### New Bulk Operations (Set-BulkRuleStatus.ps1)

```powershell
# Bulk approve rules by vendor/pattern
Set-BulkRuleStatus -PublisherPattern '*MICROSOFT*' -Status Approved -CurrentStatus Pending -WhatIf

# One-click approve all trusted vendors (Microsoft, Adobe, Oracle, Google, etc.)
Approve-TrustedVendorRules -WhatIf
```

### New Deduplication Functions (Remove-DuplicateRules.ps1)

```powershell
# Find and remove duplicate rules
Remove-DuplicateRules -RuleType All -Strategy KeepOldest -WhatIf

# Preview duplicates only
Find-DuplicateRules -RuleType Hash

# Check if rule exists before creating (called internally)
Find-ExistingHashRule -Hash 'ABC123...' -CollectionType Exe
Find-ExistingPublisherRule -PublisherName 'O=MICROSOFT' -ProductName '*'
```

### Dashboard UI Updates (MainWindow.xaml)

- **Quick Actions** now includes:
  - ✅ Approve Trusted (bulk approve trusted vendors)
  - 🗑 Remove Duplicates (cleanup duplicate rules)
  
- **Pending stat card** now shows status breakdown: `Approved✔ | Rejected✘`

### Duplicate Prevention

`New-HashRule` and `New-PublisherRule` now check for existing rules before creating:
- Returns existing rule instead of creating duplicate
- Logs warning when duplicate detected
- Only checks when `-Save` is specified

## Known Data Issues

As of Jan 2026, the Rules database has quality issues:

| Issue | Finding |
|-------|---------|
| **Duplicate Hash Rules** | 19,035 hash rules but only 7,346 unique hashes (61% duplicates) |
| **Duplicate Publisher Rules** | Same publisher appears thousands of times |
| **All Rules Pending** | 35,680 Pending, only 3 Approved |

**Solution:** Use the new bulk operations to clean up:
```powershell
# 1. Approve trusted vendors first
Approve-TrustedVendorRules

# 2. Then remove duplicates
Remove-DuplicateRules -RuleType All -Strategy KeepOldest
```

**Expected after cleanup:**
- Total Rules: ~13,500 (down from 35,683)
- Approved: ~8,000 (Microsoft + trusted vendors)
- Pending: ~5,500 (unsigned + unknown vendors)

## Current Issues / Known Bugs

No critical issues. All major performance issues have been resolved:

- ~~Slow Rule Loading (35k rules)~~ - **FIXED** with Storage module (O(1) lookups)
- ~~Scanner Progress Stuck at 36%~~ - **FIXED** with unified progress tracking
- ~~UI Freezes During Loads~~ - **FIXED** with async operations

## Recent Changes (Jan 23, 2026)

### Batch Rule Generation & 3-Step Wizard (NEW!)

**10x faster rule generation** with new optimized pipeline:

**New Functions:**
- `Invoke-BatchRuleGeneration` - High-performance batch rule creation
- `Save-RulesBulk` - Single disk I/O operation for bulk saves
- `Get-BatchPreview` - Preview what rules will be created
- `Add-RulesToIndex` - Incremental index updates (no full rebuild)

**3-Step Wizard UI:**
1. **Configure** - Set mode (Smart/Publisher/Hash), action, exclusions
2. **Preview** - See exactly what rules will be created before committing
3. **Generate** - Execute batch generation with progress bar

**Performance Improvements:**

| Operation | Before | After |
|-----------|--------|-------|
| 1,000 artifacts → rules | ~5 min | ~30 sec |
| 5,000 artifacts → rules | ~25 min | ~2 min |
| Disk I/O | Per-rule writes | Single batch write |
| Index updates | Full rebuild | Incremental |

**Usage:**
```powershell
# Launch wizard from UI
# Scanner panel → "Generate Rules from Current Scan" button

# Programmatic usage
$result = Invoke-BatchRuleGeneration `
    -Artifacts $scanResult.Data.Artifacts `
    -Mode 'Smart' `
    -SkipDlls `
    -DedupeMode 'Smart' `
    -OnProgress { param($pct, $msg) Write-Host "$pct% - $msg" }

# Returns: RulesCreated, Skipped, Duplicates, Duration, Summary
```

### Skip DLL Scanning Feature

New option to exclude DLL files during artifact scanning for improved performance:

**UI Changes:**
- Added "Skip DLL Scanning" checkbox in Scanner panel Config tab
- Default: **enabled** (checked) for performance optimization

**How it works:**
- When enabled, `.dll` files are excluded from the `$Extensions` list before scanning
- Applies to both local (`Get-LocalArtifacts`) and remote (`Get-RemoteArtifacts`) scans
- Significantly reduces scan time in enterprise environments (System32 alone has 4000+ DLLs)

**Usage:**
```powershell
# Programmatic usage
Start-ArtifactScan -ScanLocal -SkipDllScanning

# Or via functions directly
Get-LocalArtifacts -Paths 'C:\Program Files' -SkipDllScanning
Get-RemoteArtifacts -ComputerName 'Server01' -SkipDllScanning
```

**Note:** DLL rules can still be created manually or from existing artifacts. This feature only affects the initial scan collection phase.

### UI Cleanup - Wizard Consolidation

The Rule Generation Wizard is now the **primary UI** for generating rules from artifacts. Duplicate controls have been removed from both Scanner and Rules panels.

**Removed from Scanner Panel (formerly "Filters" tab, now "Generate" tab):**
- `CboDedupeMode` dropdown and `BtnDedupeArtifacts` button
- `ChkExcludeDll`, `ChkExcludeJs`, `ChkExcludeScripts`, `ChkExcludeUnsigned` checkboxes
- `BtnApplyExclusions` button
- **Replaced with:** Single "Launch Rule Generation Wizard" button

**Removed from Rules Panel "Generate" Tab:**
- `CboRuleGenMode` (generation mode dropdown)
- `CboPublisherLevel` (publisher granularity dropdown)
- `CboUnsignedMode` (unsigned file handling dropdown)
- `RbRuleAllow` / `RbRuleDeny` (action radio buttons)
- `CboRuleTargetGroup` (apply-to dropdown)
- `TxtRuleCollectionName` (collection name textbox)
- **Replaced with:** Single "Launch Rule Generation Wizard" button

**Simplified UI Flow:**
```
OLD: Scan → Go to Rules → Configure 6+ dropdowns → Configure exclusions → Click Generate → Wait
NEW: Scan → Click "Launch Wizard" → 3-step wizard (Configure → Preview → Generate)
```

**Note:** `Invoke-DedupeArtifacts` and `Invoke-ApplyArtifactExclusions` functions are still available for programmatic/scripting use.

### Bug Fix: Get-Rule in JSON Fallback Mode (Jan 23, 2026)

**Issue:** `Get-Rule -Id` was failing in JSON fallback mode (when SQLite not available).

**Root Cause:** In `JsonIndexFallback.ps1`, only `Get-RulesFromDatabase` (plural) was defined, but `Get-Rule.ps1` also called `Get-RuleFromDatabase` (singular) which didn't exist in JSON mode.

**Fix:** Added `Get-RuleFromDatabase` function to JSON fallback mode in `GA-AppLocker.Storage/Functions/JsonIndexFallback.ps1`:

```powershell
function Get-RuleFromDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    
    Initialize-JsonIndex
    
    # O(1) lookup using hashtable
    if ($script:RuleById.ContainsKey($Id)) {
        $indexEntry = $script:RuleById[$Id]
        if ($indexEntry.FilePath -and (Test-Path $indexEntry.FilePath)) {
            return Get-Content $indexEntry.FilePath -Raw | ConvertFrom-Json
        }
        return $indexEntry
    }
    return $null
}
```

**Result:** Tests improved from 67/70 to 69/70 passing (98.6%).

### Rules DataGrid Context Menu

Right-click any rule in the Rules panel for quick actions:

| Action | Description |
|--------|-------------|
| ✓ Approve | Set rule status to Approved |
| ✗ Reject | Set rule status to Rejected |
| ⚑ Mark for Review | Set rule status to Review |
| ➕ Add to Policy | Add selected rule(s) to a policy |
| 🔍 View Details | Show full rule details |
| 📋 Copy Hash | Copy SHA256 hash to clipboard |
| 📋 Copy Publisher | Copy publisher info to clipboard |
| 🗑 Delete | Delete selected rule(s) |

**Usage:**
- Select one or more rules
- Right-click to open context menu
- Select action

## Version History

See [TODO.md](TODO.md) for completed work and [README.md](README.md) for feature list.

**Current Status:** All 21 TODO items completed. **69/70 tests passing (98.6%)**. Performance optimization complete (async UI, O(1) lookups, scanner progress fix) - Jan 2026.

### Architecture Enhancements (Jan 22, 2026)

New infrastructure components in `GA-AppLocker.Core`:

#### Cache Manager (`Cache-Manager.ps1`)

Thread-safe in-memory caching with TTL support:

```powershell
# Get with auto-refresh factory
$data = Get-CachedValue -Key 'RuleCounts' -MaxAgeSeconds 60 -Factory { Get-RuleCounts }

# Manual set/clear
Set-CachedValue -Key 'MyKey' -Value $data -TimeToLive 300
Clear-AppLockerCache -Pattern 'Rule:*'

# Statistics
Get-CacheStatistics
```

#### Event System (`Event-System.ps1`)

Publish/subscribe pattern for loose coupling:

```powershell
# Subscribe to events
Register-AppLockerEvent -EventName 'RuleCreated' -Handler {
    param($EventData)
    Write-Host "New rule: $($EventData.RuleId)"
}

# Publish events
Publish-AppLockerEvent -EventName 'RuleCreated' -EventData @{ RuleId = 'abc123' }

# Standard events: RuleCreated, RuleUpdated, PolicyCreated, ScanCompleted, SnapshotCreated, PolicyRestored
```

#### Validation Helpers (`Validation-Helpers.ps1`)

Centralized input validation:

```powershell
# Type validators
Test-ValidHash -Hash 'ABC123...'
Test-ValidSid -Sid 'S-1-5-21-...'
Test-ValidGuid -Guid '12345678-...'
Test-ValidPath -Path 'C:\Windows'

# Domain validators
Test-ValidCollectionType -CollectionType 'Exe'
Test-ValidRuleAction -Action 'Allow'
Test-ValidRuleStatus -Status 'Approved'

# Assertions (throw on failure)
Assert-NotNullOrEmpty -Value $name -ParameterName 'Name'
Assert-InRange -Value $count -Min 1 -Max 100

# Sanitizers
ConvertTo-SafeFileName -FileName 'My<Invalid>File.txt'
ConvertTo-SafeXmlString -Text '<script>alert(1)</script>'
```

#### Repository Pattern (`GA-AppLocker.Storage/RuleRepository.ps1`)

Abstraction over storage with caching and events:

```powershell
# Uses cache automatically
$rule = Get-RuleFromRepository -RuleId 'abc123'

# Invalidates cache and publishes event
Save-RuleToRepository -Rule $rule

# Batch operations
Invoke-RuleBatchOperation -Operation 'UpdateStatus' -RuleIds @('id1','id2') -Parameters @{ Status = 'Approved' }
```

### New Features (Jan 22, 2026)

#### Rule Templates (`GA-AppLocker.Rules`)

Pre-built rule templates for common applications:

```powershell
# List available templates
Get-RuleTemplates

# Get specific template
Get-RuleTemplates -TemplateName 'Microsoft Office'

# Create rules from template
New-RulesFromTemplate -TemplateName 'Google Chrome' -Status Pending -Save

# Available templates:
# - Microsoft Office, Google Chrome, Mozilla Firefox, Adobe Acrobat Reader
# - 7-Zip, Notepad++, Zoom, Microsoft Teams, Slack, Visual Studio Code
# - Java Runtime, Cisco AnyConnect, Python, Git
# - Windows Default Allow, Block High Risk Locations, Block Script Locations
```

#### Policy Comparison (`GA-AppLocker.Policy/Compare-Policies.ps1`)

Compare two policies and identify differences:

```powershell
# Compare by ID
$diff = Compare-Policies -SourcePolicyId 'abc123' -TargetPolicyId 'def456'

# Compare objects directly
$diff = Compare-Policies -SourcePolicy $oldPolicy -TargetPolicy $newPolicy -IncludeUnchanged

# $diff.Summary: AddedCount, RemovedCount, ModifiedCount, UnchangedCount
# $diff.Added, $diff.Removed, $diff.Modified arrays with details

# Generate formatted report
Get-PolicyDiffReport -SourcePolicyId 'abc123' -TargetPolicyId 'def456' -Format Markdown
# Formats: Text, Html, Markdown
```

#### Policy Snapshots (`GA-AppLocker.Policy/Policy-Snapshots.ps1`)

Versioned backups with rollback capability:

```powershell
# Create snapshot before changes
New-PolicySnapshot -PolicyId 'abc123' -Description 'Before adding Chrome rules'

# List snapshots
Get-PolicySnapshots -PolicyId 'abc123' -Limit 10

# Restore to previous state (auto-creates backup first)
Restore-PolicySnapshot -SnapshotId 'abc123_20260122_143000'

# Cleanup old snapshots
Invoke-PolicySnapshotCleanup -PolicyId 'abc123' -KeepCount 5 -KeepDays 30
```

### UX Enhancements (Jan 22, 2026)

#### Keyboard Shortcuts (`GUI/Helpers/KeyboardShortcuts.ps1`)

| Shortcut | Action |
|----------|--------|
| Ctrl+1-9 | Navigate to panels (Dashboard, Discovery, Scanner, Rules, Policy, Deploy, Settings, Setup, About) |
| F5 / Ctrl+R | Refresh current panel |
| Ctrl+F | Focus search box |
| Ctrl+S | Save (context-dependent) |
| Ctrl+E | Export (context-dependent) |
| Ctrl+N | New item (context-dependent) |
| Ctrl+A | Select all in data grid |
| Escape | Cancel/Clear |
| Delete | Delete selected items |
| F1 | Help/About |

#### Drag-and-Drop (`GUI/Helpers/DragDropHelpers.ps1`)

- **Scanner Panel**: Drop executable files to scan them
- **Rules Panel**: Drop files to create rules, drop XML to import rules
- **Policy Panel**: Drop AppLocker XML files to import policies
- Drop on wrong panel → prompted to redirect

#### Setup Wizard (`GUI/Wizards/SetupWizard.ps1`)

7-step guided first-run wizard:

1. Welcome & Prerequisites Check
2. Domain Configuration (auto-detect)
3. Credential Setup
4. WinRM Configuration
5. AppLocker GPO Setup
6. Initial Scan Target Selection
7. Summary & Launch

```powershell
# Check if wizard should show
Test-ShouldShowWizard

# Show wizard manually
Show-SetupWizard -ParentWindow $mainWindow
```

### New Test Files

```
Tests/Unit/
├── Cache.Tests.ps1           # 25+ cache operation tests
├── Events.Tests.ps1          # 20+ event system tests
├── Validation.Tests.ps1      # 30+ validator tests
└── Repository.Tests.ps1      # 15+ repository pattern tests

Tests/Performance/
└── Benchmark-Storage.ps1     # Performance benchmarks with targets
```

### Bug Fixes (Jan 22, 2026 - Evening Session)

#### Fixed: App Hanging During Initialization

**Symptoms:**
- App would hang after "Loaded JSON index with 8325 rules"
- Dashboard panel initialization never completed
- Timer callbacks failing silently

**Root Causes & Fixes:**

1. **Module Path Resolution** (`AsyncHelpers.ps1`)
   - Changed from deriving path from data directory to using `Get-Module -Name 'GA-AppLocker'`
   - Runspaces now correctly import the module

2. **UI Helper Scope Issues** (`UIHelpers.ps1`, `MainWindow.xaml.ps1`)
   - Changed `Show-LoadingOverlay`, `Hide-LoadingOverlay`, `Update-LoadingText` from `script:` to `global:` scope
   - Timer callbacks run in dispatcher context and need global access

3. **Write-Log Scope** (`UIHelpers.ps1`, `MainWindow.xaml.ps1`)
   - Changed `Write-Log` from `script:` to `global:` scope
   - WPF event handlers need global access

4. **Duplicate Function Definitions**
   - `UIHelpers.ps1` and `MainWindow.xaml.ps1` both defined the same UI helper functions
   - Removed duplicates from `MainWindow.xaml.ps1`, kept in `UIHelpers.ps1`

5. **Missing Handler Registration** (`MainWindow.xaml.ps1`)
   - Added `Register-KeyboardShortcuts` call in `Initialize-MainWindow`
   - Added `Register-DragDropHandlers` call in `Initialize-MainWindow`

**Commits:**
```
f157c04 fix: remove duplicate UI helpers and use global scope for Write-Log
368a749 fix: change UI helpers to global scope for timer callback accessibility
130a00a fix: correct module path resolution and register keyboard/drag-drop handlers
```

#### Known Minor Issues (Non-Blocking)

Async runspace operations occasionally log warnings because isolated runspaces don't have access to the main session's global functions:
- "Write-Log not recognized" in runspace context
- "Get-Command not recognized" in runspace context

These happen in background operations but don't affect app functionality. The main UI thread works correctly.

## App Status History (Jan 24, 2026)

> **Note:** See "Current App Status (Jan 27, 2026)" section below for latest status.

**Working as of Jan 24:**
- All 8 panels initialize (Dashboard, Discovery, Credentials, Scanner, Rules, Policy, Deployment, Setup)
- At that time: 8,177 rules in index (6,097 approved, 2,080 pending)
- Keyboard shortcuts registered (Ctrl+1-9 navigation, F5 refresh, etc.)
- Drag-drop handlers registered
- Session state save/restore
- Navigation between panels
- Toast notifications and loading overlays
- Rule history and versioning
- Global search functionality
- Theme manager (dark/light mode)
- All index sync operations wired (Set-RuleStatus, Remove-Rule, Restore-RuleVersion)

## Debugging Tips

### Check Logs
```powershell
# View today's logs
Get-Content "$env:LOCALAPPDATA\GA-AppLocker\Logs\GA-AppLocker_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 50

# Clear logs for fresh run
Remove-Item "$env:LOCALAPPDATA\GA-AppLocker\Logs\GA-AppLocker_$(Get-Date -Format 'yyyy-MM-dd').log" -ErrorAction SilentlyContinue
```

### Common Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| App hangs after "Loading rules" | Async callback scope issue | Check functions use `global:` scope |
| "Function not recognized" in log | Runspace doesn't have function | Use `global:` scope or pass via arguments |
| Panels don't initialize | Error in panel init code | Check logs for specific panel error |
| Session restore fails | Async runspace can't access functions | Non-critical, app still works |

### Testing Launch
```bash
# From Git Bash
cd /c/Projects/GA-AppLocker2
powershell.exe -ExecutionPolicy Bypass -File Run-Dashboard.ps1

# Check logs
tail -50 "/c/Users/major/AppData/Local/GA-AppLocker/Logs/GA-AppLocker_2026-01-22.log"
```

### WPF Scope Rules

When working with WPF timer callbacks, async operations, or event handlers:

1. **Functions called from timer ticks** must be `global:` scope
2. **Functions called from runspaces** must either be:
   - Defined in the runspace via imported module
   - Or use `global:` scope (less reliable in true runspaces)
3. **MainWindow reference** use `$script:MainWindow` in the main script scope
4. **UI updates from background** use `Invoke-UIUpdate` which marshals to dispatcher

## Recent Changes (Jan 24, 2026)

### Code Review & Cleanup Session

Comprehensive code review addressing module exports, index sync, and error handling.

#### Module Export Fixes

All modules now properly export their functions:

| Module | Key Additions |
|--------|---------------|
| **Core** | Cache Manager (`Get-CachedValue`, `Set-CachedValue`), Event System (`Publish-AppLockerEvent`), Validation Helpers (`Test-Valid*`, `Assert-*`) |
| **Storage** | Index Watcher (`Start-RuleIndexWatcher`), Repository Pattern (`Get-RuleFromRepository`), Bulk Operations (`Save-RulesBulk`, `Remove-RulesBulk`) |
| **Rules** | Removed incorrect exports (`Get-ExistingRuleIndex` belongs to Storage), History functions (`Get-RuleHistory`, `Restore-RuleVersion`) |
| **Main** | Re-exports all sub-module functions (182 total commands) |

#### Index Sync Wiring

All rule modification operations now properly update the JSON index:

```powershell
# These operations now sync to index automatically:
Set-RuleStatus -Id $ruleId -Status Approved    # Updates index
Remove-Rule -Id $ruleId                         # Removes from index
Restore-RuleVersion -RuleId $id -Version 1      # Updates index
New-HashRule -Hash $hash -Save                  # Adds to index
```

**Implementation:**
- `Set-RuleStatus` → calls `Update-RuleStatusInIndex`
- `Remove-Rule` → calls `Remove-RulesFromIndex`
- `Restore-RuleVersion` → calls `Update-RuleStatusInIndex`
- `Save-Rule` (in psm1) → calls `Add-RulesToIndex`

#### Bug Fixes

1. **Dashboard.ps1 Line 45** - Added null-safe check for `$script:DiscoveredMachines.Count`
   ```powershell
   # Before (could crash if null):
   $statMachines.Text = $script:DiscoveredMachines.Count.ToString()
   
   # After (null-safe):
   $machineCount = if ($script:DiscoveredMachines) { $script:DiscoveredMachines.Count } else { 0 }
   ```

2. **Scanner.ps1 Update-ArtifactDataGrid** - Wrapped in try/catch for error resilience

3. **MainWindow.xaml.ps1** - Added `default` case to `Invoke-ButtonAction` switch statement to log unknown actions

4. **Remove-RulesBulk Duplicate** - Removed duplicate from Rules module (consolidated to Storage module)

#### Orphaned Functions Documented

Two functions in Scanner.ps1 are implemented but not yet wired to UI:
- `Invoke-DedupeArtifacts` - Deduplicate artifacts by hash/publisher/smart mode
- `Invoke-ApplyArtifactExclusions` - Apply DLL/JS/Script/Unsigned exclusions

Added documentation comments noting they're ready for future UI integration.

#### E2E Test Results

Full rule lifecycle test passing:
```
1. Create rule (New-HashRule -Save)     ✓ Index +1
2. Verify saved (Get-Rule)              ✓ Status: Pending
3. Approve (Set-RuleStatus)             ✓ Status: Approved
4. Verify change (Get-Rule)             ✓ Index updated
5. Check history (Get-RuleHistory)      ✓ Version 1 available
6. Remove (Remove-Rule)                 ✓ Index -1
7. Verify removed                       ✓ Rule not found
```

#### Current Rule Statistics

```
Total Rules:    8,177
├── Approved:   6,097
├── Pending:    2,080
└── Duplicates: 0 (cleaned up)
```

### Files Modified (Jan 24, 2026)

```
GA-AppLocker/GUI/Panels/Dashboard.ps1           # Null-safe machine count
GA-AppLocker/GUI/Panels/Scanner.ps1             # Error handling, orphaned function docs
GA-AppLocker/GUI/MainWindow.xaml.ps1            # Default case in button dispatcher
GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/Get-Rule.ps1    # Index sync
GA-AppLocker/Modules/GA-AppLocker.Rules/GA-AppLocker.Rules.psm1   # Index sync in Save-Rule
GA-AppLocker/Modules/GA-AppLocker.Rules/GA-AppLocker.Rules.psd1   # Export fixes
GA-AppLocker/Modules/GA-AppLocker.Storage/GA-AppLocker.Storage.psd1  # Export additions
GA-AppLocker/Modules/GA-AppLocker.Core/GA-AppLocker.Core.psd1     # Export additions
GA-AppLocker/GA-AppLocker.psd1                  # Re-export all functions
GA-AppLocker/GA-AppLocker.psm1                  # Re-export all functions
```

### Verification Commands

```powershell
# Verify module loads correctly
Import-Module '.\GA-AppLocker\GA-AppLocker.psd1' -Force
(Get-Command -Module GA-AppLocker).Count  # Should be ~170

# Verify index sync
$rule = New-HashRule -Hash ('A' * 64) -SourceFileName 'test.exe' -SourceFileLength 1000 -Save
Get-RuleCounts  # Should show +1
Set-RuleStatus -Id $rule.Data.Id -Status Approved
(Get-Rule -Id $rule.Data.Id).Data.Status  # Should be 'Approved'
Remove-Rule -Id $rule.Data.Id
Get-RuleCounts  # Should show -1
```

## Recent Changes (Jan 27, 2026)

### Bug Fixes - Module Export and Remove-Rule

**Issue 1: `Get-RuleById` Not Exported**

The Storage module defined `Get-RuleById` but it wasn't re-exported from the main module. This caused `Remove-Rule` to fail with "Get-RuleById is not recognized".

**Root Cause:** The main module's export lists (both `.psd1` and `.psm1`) had outdated SQLite-era function names that didn't match the current JSON-based Storage module.

**Fix:** Updated both `GA-AppLocker.psd1` and `GA-AppLocker.psm1` to export the correct Storage module functions:

```powershell
# Old (SQLite-era - no longer exists):
'Initialize-RuleDatabase', 'Get-RuleDatabasePath', 'Add-RuleToDatabase', ...

# New (JSON-based):
'Get-RuleStoragePath', 'Get-RuleById', 'Add-Rule', 'Update-Rule', ...
```

**Issue 2: `Remove-Rule` Function Conflict**

Both the Storage and Rules modules defined `Remove-Rule` with different signatures:
- **Storage module:** `Remove-Rule -RuleIds @('id1', 'id2')` (bulk delete)
- **Rules module:** `Remove-Rule -Id 'single-id'` (single delete with logging)

The Rules module's version was calling the Storage version incorrectly, causing parameter binding errors.

**Fix:** Changed Rules module's `Remove-Rule` to call `Remove-RulesBulk` instead:

```powershell
# Before (broken - recursive call with wrong params):
$deleteResult = Remove-Rule -RuleIds @($Id)

# After (correct - calls Storage bulk function):
$deleteResult = Remove-RulesBulk -RuleIds @($Id)
```

### Files Modified

```
GA-AppLocker/GA-AppLocker.psd1           # Updated Storage module exports
GA-AppLocker/GA-AppLocker.psm1           # Updated Storage module exports
GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/Get-Rule.ps1  # Fixed Remove-Rule
GA-AppLocker/GUI/MainWindow.xaml         # Cosmetic: bullet character encoding
```

### Current App Status (Jan 27, 2026)

**Working:**
- All 8 panels initialize correctly
- Full CRUD lifecycle works (Create, Read, Update, Delete rules)
- Index sync operations work
- Module loads with ~170 exported commands
- App launches and runs normally

**Data Status:**
- Rules database is empty (user deleted all 8,207 rules on Jan 26)
- This is expected state, not a bug
- Run a new scan to repopulate rules

**Startup Sequence (from logs):**
```
1. All nested modules loaded successfully
2. Starting GA-AppLocker Dashboard v1.0.0
3. Code-behind loaded successfully
4. Toast helpers loaded successfully
5. Main window loaded successfully
6. Navigation initialized
7. [Storage] Loaded JSON index with 0 rules
8. All panels initialized
9. Session state restored
10. Window Loaded event fired
```

### Quick Verification

```powershell
# Test full rule lifecycle
Import-Module '.\GA-AppLocker\GA-AppLocker.psd1' -Force

# Create
$rule = New-HashRule -Hash ('A' * 64) -SourceFileName 'test.exe' -SourceFileLength 1000 -Save
Write-Host "Created: $($rule.Success)"

# Read
$retrieved = Get-Rule -Id $rule.Data.Id
Write-Host "Retrieved: $($retrieved.Success)"

# Update
$updated = Set-RuleStatus -Id $rule.Data.Id -Status 'Approved'
Write-Host "Updated: $($updated.Success)"

# Delete (this was broken before the fix)
$deleted = Remove-Rule -Id $rule.Data.Id
Write-Host "Deleted: $($deleted.Success)"
```
