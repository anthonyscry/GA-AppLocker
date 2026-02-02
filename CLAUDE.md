# GA-AppLocker Development Guide

## Project Overview

GA-AppLocker is a PowerShell 5.1 WPF application for enterprise AppLocker policy management in air-gapped, classified, or highly secure environments. Complete workflow: AD Discovery → Artifact Scanning → Rule Generation → Policy Building → GPO Deployment.

**Version:** 1.2.50 | **Tests:** 1282/1282 passing (100%) | **Exported Commands:** ~194

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
│   ├── MainWindow.xaml            # WPF UI (dark theme, 9 panels)
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
│   └── Panels/                    # Per-panel event handlers (9 files)
│       ├── Dashboard.ps1          # Dashboard stats, quick actions
│       ├── ADDiscovery.ps1        # AD/OU discovery, machine selection
│       ├── Credentials.ps1        # Credential management
│       ├── Scanner.ps1            # Artifact scanning, type filters
│       ├── Rules.ps1              # Rule management, context menu, filtering
│       ├── Policy.ps1             # Policy building, status filters
│       ├── Deploy.ps1             # GPO deployment, job filters
│       ├── Software.ps1           # Software inventory, CSV export/import, comparison
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
# Pester unit tests (550/550 passing — 100%)
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

## Lessons Learned (Hard-Won Rules)

These rules were each learned from real bugs that cost significant debugging time. **Violating any of these WILL cause silent failures.**

### 1. PS 5.1 List.AddRange() Fails with Object[]

```powershell
# BROKEN — PS 5.1 can't convert Object[] to IEnumerable<PSObject>
$list = [System.Collections.Generic.List[PSCustomObject]]::new()
$list.AddRange([PSCustomObject[]]@($someArray))   # THROWS
$list.AddRange(@($someArray))                      # ALSO THROWS

# SAFE — always use foreach .Add()
foreach ($item in @($someArray)) { [void]$list.Add($item) }
```

Also: `[List[T]]::new(@(...))` constructor overload fails in PS 5.1. Always use `::new()` then loop.

### 2. $script: Inside global: Functions Resolves to WRONG Scope

```powershell
# BROKEN — $script: refers to global:'s private scope, NOT the module's $script:
function global:MyFunc {
    $script:ModuleVar   # Always $null! Silent failure, no error.
}

# SAFE — use explicit $global: variables for cross-scope data
$global:GA_MyVar = $value                    # Set in module
function global:MyFunc { $global:GA_MyVar }  # Read in global function
```

This is the sneakiest PS scoping bug — zero errors, variables just silently become `$null`.

### 3. $array += $item Is O(n²) — Use List<T>

```powershell
# BROKEN — copies entire array on every append, O(n²) total
$results = @()
foreach ($item in $bigCollection) { $results += $item }

# SAFE — O(1) amortized append
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($item in $bigCollection) { [void]$results.Add($item) }
$arrayResult = @($results)  # Convert back if needed
```

For string building, use `[System.Text.StringBuilder]` instead of `$xml += "<tag>"`.

### 4. .Add() Return Values Leak into Pipeline

```powershell
# BROKEN — .Add() returns the index, polluting function output
function Get-Data {
    $list = [System.Collections.Generic.List[string]]::new()
    $list.Add("item")   # Returns 0 — leaks into pipeline!
    return @{ Data = $list }
    # ACTUAL return: @(0, @{Data=$list})
}

# SAFE — always suppress .Add() return
[void]$list.Add("item")
$null = $hashtable.Remove("key")
```

Applies to: `.Add()`, `.Remove()`, `.Insert()`, `ArrayList.Add()`, `HashSet.Add()`.

### 5. WPF Timer/Dispatcher Callbacks Need global: Scope

```powershell
# BROKEN — timer can't find script-scoped functions (silent failure)
$timer.Add_Tick({ Update-Progress })   # "Command not found" — swallowed

# SAFE — define as global for WPF callbacks
function global:Update-Progress { ... }
```

Applies to: DispatcherTimer ticks, runspace callbacks, event handlers. The WPF dispatcher swallows the error — UI just stops updating with no indication.

### 6. Test Data Persists — Use Unique Identifiers

```powershell
# BROKEN — hash collides with leftover data from other test suites
$rule = New-HashRule -Hash ('11' * 32) -Save  # Returns EXISTING rule!

# SAFE — use truly random identifiers
$uniqueHash = (New-Guid).ToString('N') + (New-Guid).ToString('N')
$rule = New-HashRule -Hash $uniqueHash -Save
```

Tests share `%LOCALAPPDATA%\GA-AppLocker\Rules\`. Duplicate-detection features silently return existing rules instead of creating new ones.

### 7. PS 5.1 Compatibility Traps

| Trap | Impact | Fix |
|------|--------|-----|
| UTF-8 special chars in .ps1 | Breaks entire module parsing | ASCII only in source files |
| No ternary `? :` / `??` | Syntax error | Use `if/else` |
| `Get-ChildItem -Include` without `-Recurse` | Returns nothing (silent) | Use enumerate + HashSet filter |
| `ConvertFrom-Json` objects | Can't cast to `[PSCustomObject[]]` | Use foreach instead of cast |
| `[char]` above 0xFFFF | Not supported | Avoid Unicode supplementary planes |

### 8. MessageBox Calls Hang Tests/Automation

```powershell
# BROKEN — halts execution in non-interactive contexts
[System.Windows.MessageBox]::Show("Sure?", "Confirm", "YesNo")

# SAFE — use testable wrapper
Show-AppLockerMessageBox -Message "Sure?" -Title "Confirm" -Button YesNo -Icon Question
# Auto-returns 'Yes' when $global:GA_TestMode -eq $true
```

Same applies to `Read-Host`, `Out-GridView`, or anything blocking for input.

### 9. Synchronous WMI/CIM on WPF STA Thread Freezes UI

```powershell
# BROKEN — 10-30 second timeout on air-gapped networks
$os = Get-CimInstance Win32_OperatingSystem   # UI frozen!

# SAFE — use .NET APIs that return instantly
$ipProps = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
```

ANY blocking call on the STA thread freezes the entire WPF window. Use `.NET` alternatives or move to background runspaces.

### 10. XAML Element Names Aren't Validated — Typos Fail Silently

```powershell
# BROKEN — FindName returns $null, downstream code just doesn't execute
$window.FindName('RulesSearchBox')      # Actual name: TxtRuleFilter
$window.FindName('MachinesDataGrid')    # Actual name: DiscoveredMachinesDataGrid

# SAFE — validate at startup or use constants
$element = $window.FindName('TxtRuleFilter')
if ($null -eq $element) { Write-AppLockerLog "XAML lookup failed: TxtRuleFilter" -Level ERROR }
```

PowerShell + WPF has zero compile-time safety. Wrong element names produce no errors — features silently stop working.

### Bonus: .psd1/.psm1 Export Mismatches Are Silent

If a function is in `.psd1 FunctionsToExport` but NOT dot-sourced in `.psm1` (or vice versa), the function silently becomes unavailable. No error at import time. Check all 3 locations when adding/removing exports: module `.psd1`, module `.psm1`, root `GA-AppLocker.psd1`, root `GA-AppLocker.psm1`.

### 11. Test Failures After Code Changes — Read the Tests First

When tests fail after YOUR code changes, **do NOT** run the full test suite with Detailed output to diagnose. That dumps hundreds of KB of passing-test noise and burns context. Instead:

1. Run with `-Output Minimal` to get the count and file name
2. **Read the failing test assertions** (the `It`/`Should` blocks) — they're just lines in a `.Tests.ps1` file
3. Compare what the test expects vs. what your code now does
4. Decide: is the **test wrong** (asserting old patterns) or is the **code wrong** (regression)?

```powershell
# WRONG — 500KB of output, truncated, then re-run with filters, then re-run again...
Invoke-Pester -Path '.\Tests\Unit\' -Output Detailed

# RIGHT — get failing test names only (one line each)
Invoke-Pester -Path '.\Tests\Unit\' -Output Detailed 2>&1 | Select-String '\[-\]'

# THEN read the test file directly at those line numbers
# Compare test expectations against your recent code changes
# Fix whichever is wrong (usually the test after a deliberate rewrite)
```

**V1229Session.Tests.ps1 pattern**: Many tests in this file do regex matching against source code (`$script:DeployPs1 | Should -Match 'pattern'`). When you rewrite a function, these tests break because they're asserting old string patterns, NOT testing behavior. Update the regex to match the new code.

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.2.50 | Feb 2, 2026 | Fix 3 startup bugs: (1) White screen on startup fixed by deferred InvalidateVisual+UpdateLayout in Loaded event (WPF wasn't triggering initial render pass), (2) "Loading policies..." overlay that never finishes fixed by adding 60-second safety timeout to Invoke-AsyncOperation (auto-hides overlay, stops runspace, shows warning toast), (3) App always starts on Dashboard now (removed session panel restore that navigated to last panel on startup, which triggered async policy loading before UI was ready) |
| 1.2.49 | Feb 2, 2026 | Fix 6 bugs: (1) Software Inventory no longer auto-populates remote machines from AD Discovery, (2) Admin Allow button now creates Appx rule (5 types, was 4), (3) Dedupe no longer merges rules for different principals/actions (key includes UserOrGroupSid+Action), (4) Policy Builder excluded-rules message shows which phase includes each type (e.g., "Dll: 5 rules (included at Phase 5)"), (5) Scanner DataGrid horizontal scrollbar, (6) Scanner Config tab scan paths textbox restored |
| 1.2.48 | Feb 2, 2026 | Service Allow button on Rules panel -- creates 20 mandatory baseline allow-all path rules (SYSTEM S-1-5-18, Local Service S-1-5-19, Network Service S-1-5-20, BUILTIN\Administrators S-1-5-32-544) across all 5 collection types (Exe, Dll, Msi, Script, Appx), Status Approved, Path *. Button order reordered: Service Allow, Admin Allow, Deny Paths, Deny Browsers, Dedupe, Delete |
| 1.2.47 | Feb 1, 2026 | Performance: Save-JsonIndex rewrite (StringBuilder manual JSON serialization replaces ConvertTo-Json, 10-50x faster for 3000+ rule indexes), Remove-DuplicateRules uses Remove-RulesBulk instead of manual per-file deletion loop, ConvertTo-Json depth reduced from 10 to 5 across Storage module (flat PSCustomObjects don't need deep serialization) |
| 1.2.46 | Feb 1, 2026 | Remove Deploy Edit tab entirely (Deploy panel now 3 tabs: Create, Actions, GPO Status), Deploy XML import preserves Approved status (-Status 'Approved' on Import-RulesFromXml), Policy Create description box height aligned with Edit tab, major test cleanup: V1229Session.Tests.ps1 rewritten behavioral-only (1489->670 lines, ~350->63 tests), V1228Regression.Tests.ps1 deleted (behavioral tests merged into V1229), removed ~266 fragile regex pattern-matching tests (test count 1548->1282, zero lost behavioral coverage) |
| 1.2.45 | Feb 1, 2026 | Fix Resolve-GroupSid ADSI/LDAP fallback for SID resolution (4-method chain: NTAccount, domain-prefix, ADSISearcher, explicit LDAP; stops caching UNRESOLVED values), XML export SID guard (validates SID format before emission, re-resolves invalid SIDs, falls back to S-1-5-11/S-1-1-0), GPO status refresh on panel navigation (Setup/Deploy), Policy Create tab Target GPO dropdown, Deploy Create tab schedule removed, Deploy Edit tab stripped to name+GPO only, test fixes for removed XAML elements |
| 1.2.44 | Feb 1, 2026 | CRITICAL: Fix RunspacePool scriptblock silently dropping ALL unsigned files from scan results (Write-AppLockerLog undefined in runspace context threw terminating CommandNotFoundException inside catch blocks, causing unsigned file artifacts to be skipped entirely -- only signed files survived parallel scanning). Fix: removed module function calls from RunspacePool catch blocks. This also explains why hash rules were never generated from scans (only publisher rules appeared, since only signed files made it through). |
| 1.2.43 | Feb 1, 2026 | Setup panel shows actual linked OU paths instead of hardcoded labels (Get-SetupStatus adds LinkedOUs via Get-GPOReport XML, Setup.ps1 populates TxtGPO_{Type}_OU TextBlocks), V1229Session.Tests.ps1 refactor (5 redundant regex tests removed, Get-PhaseCollectionTypes converted to behavioral calls via dot-sourced Policy.ps1, function-definition regex converted to Get-Command for Software.ps1 global functions) |
| 1.2.42 | Feb 1, 2026 | Fix hash rules not created from CSV-imported artifacts (IsSigned string "False" truthy in PS 5.1, added boolean coercion + defensive check), fix Deploy Edit tab OU splitting (commas in DNs broke split regex, now newlines only), WinRM GPOs toggle settings instead of links (GpoStatus enable/disable, both stay linked, mutual exclusivity preserved), Policy/Deploy column width adjustments |
| 1.2.41 | Feb 1, 2026 | Wire BtnClearCompletedJobs click handler (Clear button was unresponsive), GPO Link Control rewrite to use Get-SetupStatus (proven reliable) instead of direct Get-GPO calls (fixes "Not Created" false negatives), Deploy Edit tab save refreshes jobs DataGrid, Setup panel AD group badges turn green when groups exist (6 badges), Software Compare tab Export Comparison Results button (CSV with Source column), fix 7 tests for GPO Link rewrite |
| 1.2.40 | Feb 1, 2026 | Setup GPO status shows Enabled/Disabled state (Configured - Enabled/Disabled with green/orange color), wire BtnStartDeployment click handler (Create Deployment Job button was unresponsive), GPO Link Control per-GPO error isolation (one failing Get-GPO no longer breaks all three pills, Import-Module -ErrorAction Stop with fallback), Initialize All now creates Disable-WinRM GPO (was missing from Initialize-AppLockerEnvironment), Software Inventory panel split into Scan + Compare tabs (clearer workflow, step-by-step compare guide with baseline/comparison file info) |
| 1.2.39 | Feb 1, 2026 | Fix 7 bugs from live DC01 testing: Deploy phase dropdown labels (wrong phase names on Create tab), Deploy Policy button did nothing (Tag mismatch CreateDeploymentJob), Clear Completed Jobs button+function (Remove-DeploymentJob with -JobId/-Status), Software Inventory DataGrid unreadable selection colors (dark-theme RowStyle), GPO Link Control rewrite (GpoStatus enable/disable instead of OU-specific link, Get-GPOReport XML for linked OU display), default OU targets on GPO creation (OU=Member Servers/OU=Workstations with CN=Computers fallback), GPOs disabled by default at initialization (AllSettingsDisabled) |
| 1.2.38 | Feb 1, 2026 | Anti-pattern sweep & startup fix: suppress 51 .Add() pipeline leaks across 21 files (modules + GUI), ReportingExport.ps1 $html+=@"..."@ (11 locations) converted to [StringBuilder], RuleRepository.ps1 12 empty catch blocks replaced with context-specific DEBUG logging, fix duplicate x:Name BtnDeployPolicy in XAML that prevented app startup (introduced in v1.2.34, renamed Deploy panel button to BtnStartDeployment) |
| 1.2.37 | Feb 1, 2026 | Performance & integration fixes: O(n²) array concat→List in Start-ArtifactScan/RuleStorage/Set-BulkRuleStatus/ConvertFrom-Artifact/Export-RulesToXml (StringBuilder), keyboard shortcut scope fix (script:→global: for panel vars, 6 wrong XAML element names), UI pump in ChangeAction/ChangeGroup (every 100 rules), targeted index updates replace Rebuild-RulesIndex (Update-RuleStatusInIndex extended with -Action/-UserOrGroupSid), dead dispatchers removed, Write-RuleLog scope fix, DEBUG logging in 6 more empty catches, Get-Date hoisted outside 5 loops, PS 5.1 List.AddRange fix (foreach .Add instead of .AddRange cast) |
| 1.2.36 | Jan 31, 2026 | Performance & polish: Rules text filter 300ms debounce, Show-AppLockerMessageBox testable wrapper (replaces all 150+ [System.Windows.MessageBox]::Show calls across 12 GUI files with global:Show-AppLockerMessageBox that auto-returns in $global:GA_TestMode), DEBUG logging in 5 more empty catches, 2 more @() wraps for PS 5.1 .Count safety |
| 1.2.35 | Jan 31, 2026 | Code efficiency sweep: fix 56 unsuppressed .Add() pipeline leaks across 18 files, @() wrapping for PS 5.1 .Count safety on Where-Object (6 locations), DEBUG logging in 10 data-path empty catch blocks, dead code cleanup (~600 lines: EmailNotifications, ReportingExport, Invoke-WithRetry removed from exports, AsyncHelpers 3 unused functions marked), new Scanning.Tests.ps1 (106 tests covering artifact type mapping, collection types, SHA256 hashing, local scan behavior, script type filtering, parameter validation, artifact object structure) |
| 1.2.34 | Jan 31, 2026 | Pipeline leak fixes (17 leaks in 6 files), perf optimizations (DataGrid virtualization, Set-BulkRuleStatus index-based, Remove-DuplicateRules async, uppercase GUIDs), UX polish (orphan buttons wired, null guards, ScrollViewers on 5 panels, Escape key on 4 dialogs, dead code removal), session restore (full machine objects + legacy fallback), automated UI testing framework (MockWpfHelpers, 3-layer test strategy: XAML integrity + panel logic + live smoke, 235 new GUI tests), untyped $Window params for testability |
| 1.2.33 | Jan 31, 2026 | Fix 15 bugs from comprehensive audit — 8 CRITICAL (Approve-TrustedVendorRules broken call, Rule Wizard null data, Setup Wizard config not saving, Get-Rule filter always empty, Scanner exclusion dead code, ThemeManager PS5.1 incompat + frozen brush, BackupHistory always invalid), 7 HIGH (Compare-Policies null IDs, policy Version null crash in 4 places, IndexWatcher scope bug, Validation UniqueGuids wrong, #EF5350→#D13438, GlobalSearch UI freeze, stray Export-ModuleMember) |
| 1.2.32 | Jan 31, 2026 | Fix all 113 test failures (1209/1209 passing) — source bugs (Get-Rule -RuleId→-Id, pipeline output leaks in Set-RuleStatus/Policy-Snapshots/Set-PolicyStatus), test fixes (Save-RuleVersion -RuleId→-Rule, Update-Policy -PolicyId→-Id, Validation -XmlContent→-XmlPath, add -Save to rule creation, V1229Session regex/color fixes, hash collision fix) |
| 1.2.31 | Jan 31, 2026 | Deep polish pass — fix duplicate GUIDs/functions, XAML phantom rows, dispatcher duplicate, test param fixes (Integration+Manifest), code quality (Get-Command→try/catch, null guards, empty catches→logging, dead code removal, O(n²) fix, Read-Host→ShouldContinue, ValidateSet fixes), UX polish (disabled button states, Dashboard/Policy nav refresh, Cursor=Hand on 35 filter pills, filter pill consistency, sidebar version, color standardization #EF5350→#D13438) |
| 1.2.30 | Jan 31, 2026 | Phase 5 support (APPX+DLL phased rollout), GPO Link pill toggles, filter visual consistency (grey pill pattern across Rules/Policy/Deploy), Software Import split (Baseline vs Comparison), server roles/features in software scan, AD Discovery refresh preserves connectivity + auto-populates on first visit, WinRM GPO mutual exclusivity, Deploy/Policy tab reordering, Deploy Edit policy dropdown, comprehensive V1229 tests |
| 1.2.29 | Jan 31, 2026 | Documentation and test count update (550/550 tests passing, up from 397), version bump across all docs |
| 1.2.28 | Jan 31, 2026 | Fix deployment error (pass file path not XML content to Set-AppLockerPolicy), fix per-host CSV export null ComputerName crash, Software Inventory remote scan runs in background runspace (no UI freeze), Software panel auto-populates remote machines from AD Discovery (online+WinRM), Deploy panel refreshes policy combo + jobs list on every navigation |
| 1.2.27 | Jan 31, 2026 | Auto-export per-host CSV artifact files after every scan ({HostName}_artifacts_{date}.csv in Scans folder) |
| 1.2.26 | Jan 31, 2026 | Code quality sweep (17 fixes): Remove destructive startup rule deletion, fix .psd1/.psm1 export mismatches (missing Policy exports, duplicate Storage entries, phantom Rules exports), fix scheduled scan hardcoded dev paths, consolidate Get-MachineTypeFromOU (config-based tier mapping), fix Backup-AppLockerData settings path, fix AuditTrail APPDATA fallback, Event System global->script scope, Test-Prerequisites .NET domain check (no Get-CimInstance), Test-CredentialProfile WMI ping (no Test-Connection), scanning scriptblock sync comments + CollectionType, ConvertFrom-Artifact O(1) List growth, Setup module .psd1 manifest, Remove-Rule export ambiguity (Storage only), LDAP RequireSSL config option, scheduled scan runner ACL + RemoteSigned, Write-AuditLog JSONL append-only format, dynamic APP_VERSION from manifest |
| 1.2.25 | Jan 31, 2026 | Fix deployment error (UTF-8 BOM in exported XML + .NET file read + LDAP fallback for domain DN), AppLocker-DisableWinRM GPO for tattoo removal (reverses WinRM service, listener, UAC, firewall), Software panel remote machine textbox (enter hostnames directly instead of requiring AD Discovery) |
| 1.2.24 | Jan 31, 2026 | Fix Software Inventory credentials (Get-DefaultCredential didn't exist, now uses tier-based fallback), auto-save software CSVs (hostname_softwarelist_ddMMMYY.csv), Deploy policy combo auto-refresh on panel nav + logging/error handling, Setup WinRM toggle button shows Enable/Disable state |
| 1.2.23 | Jan 31, 2026 | Deploy Edit tab (name/desc/GPO), + Admin Allow & + Deny Browsers buttons, WPF dispatcher crash fix (pure .NET exception handler), dark title bar (DwmSetWindowAttribute), target group dropdowns reordered (AppLocker-Users default), Resolve-GroupSid cache, unified filter bars, troubleshooting scripts updated to match WinRM GPO settings, Force-GPOSync rewrite (filtering, ping check, -Target/-OU params) |
| 1.2.22 | Jan 31, 2026 | Fix Dashboard pending list (Software.ps1 UTF-8 em dash broke PS 5.1 parsing), uniform DataGrid headers across all 7 panels, Setup: Remove WinRM GPO button, About panel redesign (author credit, purpose, workflow viz) |
| 1.2.21 | Jan 31, 2026 | Scanner DataGrid: add Product Name column after Publisher (data already collected, just not displayed), Appx/MSIX checked by default and reordered above Event Logs |
| 1.2.20 | Jan 31, 2026 | Policy Builder fixes (edit name/desc/GPO, ModifiedDate display, remove dead Export tab, Deploy button unblocked, dead code cleanup), Rules/Policy/Deploy column sort fix (SortMemberPath on DataGridTemplateColumns), Update-Policy gains -Name/-Description/-TargetGPO params |
| 1.2.19 | Jan 31, 2026 | Software Inventory panel (9th panel) — registry-based local/remote scan, CSV export/import, cross-system comparison engine (Only in Scan/Only in Import/Version Diff), full UI with DataGrid, text filter, stats card |
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
