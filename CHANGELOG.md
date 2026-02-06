# Changelog

All notable changes to GA-AppLocker will be documented in this file.

## [1.2.79] - 2026-02-06

### Fixed
- **Rule Generation Settings dialog lockup on Generate** -- scanner fallback generation paths now run with `-NoLoadingOverlay`, preventing global overlay click-blocking while generation is running.
- **RESOLVE:* target group deadlock risk in background generation** -- moved `Resolve-GroupSid` execution into background runspace so Generate click does not block UI on AD/LDAP resolution latency.
- **Run-Dashboard launcher hard-fail diagnostics** -- added explicit manifest existence checks, import error handling, command export validation, and dashboard start try/catch to surface startup errors clearly.

---

## [1.2.78] - 2026-02-06

### Fixed
- **Dashboard GPO toggles no-op** -- switched Dashboard toggle interlock state from script scope to global scope so WPF click handlers and callback scope always see/update the same busy/snapshot values.
- **Policy Builder navigation freeze** -- Policy panel auto-load on navigation now runs asynchronously via dispatcher background invoke (`Update-PoliciesDataGrid -Async -NoOverlay`) instead of synchronous load on panel switch.

---

## [1.2.77] - 2026-02-06

### Fixed
- **Wizard Generate lockup** -- Rule Generation Wizard preview/generate background jobs now run with `-NoLoadingOverlay`, so the global overlay no longer blocks wizard interaction while generation runs.
- **Overlay cross-job blocking** -- `Invoke-BackgroundWork` now tracks per-job overlay usage and only keeps the global overlay visible while overlay-enabled jobs remain.

---

## [1.2.76] - 2026-02-06

### Fixed
- **Post-minimize UI no-op after Service/Admin allow actions** -- hardened `Show-AppLockerMessageBox` to always use the main window as owner and reactivate/restore it before showing dialogs.
- **Hidden modal dialog trap** -- prevents off-screen/unowned MessageBox states (common in VM/RDP minimize/restore flows) that can make the app appear clickable while all commands are blocked.

---

## [1.2.75] - 2026-02-06

### Fixed
- **Rules grid appears empty after successful generation** -- added `Refresh-RulesPanelAfterGeneration` to reset Rules view state after generation/import flows.
- **Post-generation visibility hardening** -- Rules panel refresh now clears text filter, resets type/status filters to `All`, resets index cache, and reloads the grid so new rules are immediately visible.
- **Scanner/Wizard handoff consistency** -- scanner direct generation callbacks and wizard close path now use the same Rules refresh helper to avoid stale/filtered UI state.

---

## [1.2.74] - 2026-02-06

### Fixed
- **AD Discovery false WinRM failures** -- connectivity test now uses per-host wait timeouts inside the runspace pool (instead of a shared shrinking deadline), preventing later hosts from being marked unavailable due to earlier slow hosts.
- **Connectivity test timeout stability** -- added in-progress guard, empty-host guard, improved dynamic timeout sizing by batch count, and explicit timeout cleanup via `OnTimeout` callback.
- **Background engine timeout cleanup gap** -- `Invoke-BackgroundWork` now supports `OnTimeout`, returns a job id, and adds `Stop-BackgroundWork` for explicit cancellation; overlay hide now occurs when all jobs are complete instead of per-job completion.
- **Wizard preview stuck-loading failure path** -- preview step now handles null/timeout results with a safe fallback preview object and warning toast instead of remaining in loading state.
- **Wizard cancel semantics** -- closing the wizard while preview/generation is running now cancels the active background job(s) and clears wizard job state.
- **Rules bulk operations timeout hygiene** -- migrated operations now provide `OnTimeout` cleanup to clear operation-scoped globals and reset selection/UI safely.

---

## [1.2.72] - 2026-02-06

### Fixed
- **Rule Generation Wizard freeze** -- `Invoke-BatchRuleGeneration` ran synchronously on WPF STA thread. Both `Invoke-DirectRuleGenerationWithSettings` and `Invoke-DirectRuleGeneration` now use `Invoke-BackgroundWork` with only 3 sub-module imports (Core + Storage + Rules) in a background runspace. 5-minute timeout.

---

## [1.2.71] - 2026-02-06

### Redesigned - Centralized Background Work Engine
Complete rethink of how background operations work in the WPF UI. Replaces all ad-hoc runspace + DispatcherTimer + `.GetNewClosure()` patterns with a single reliable `Invoke-BackgroundWork` engine.

**Architecture:**
- New `global:Invoke-BackgroundWork` function in UIHelpers.ps1
- ALL job state stored in `$global:GA_BackgroundJobs` (zero `$script:` in callbacks -- eliminates PS scope bug)
- ONE shared `DispatcherTimer` monitors all background jobs (no per-job timers)
- NO `.GetNewClosure()` on the timer tick (the root cause of every previous failure)
- Bare MTA runspaces with NO module imports (instant startup vs 10-30s hangs)
- OnComplete callbacks run on UI thread using `$global:` for cross-scope data

**Operations fixed:**
- **Test Connectivity** -- rewired to `Invoke-BackgroundWork` with inline ping/WinRM (30s deadline)
- **Bulk Delete** (1400+ rules) -- file I/O in background runspace, index update on UI thread (60s deadline)
- **Local/Remote Scanner** -- runspace changed from STA to MTA, imports only 3 sub-modules (Core + Scanning + Credentials) instead of all 10

---

## [1.2.70] - 2026-02-06

### Fixed
- **CRITICAL**: Fix connectivity test timer callback using `$script:DiscoveredMachines` inside `.GetNewClosure()` -- resolves to `$null` because the closure creates its own module scope (PS Lesson #2). All cross-scope data now passed through `$ctx` hashtable instead.
- Fix `Add-Member` null crash in `Update-MachineDataGrid` -- null machine objects in the pipeline now filtered out with `Where-Object { $_ -ne $null }`.
- **Bulk delete** of 1400+ rules no longer freezes UI -- file deletion moved to background runspace with DispatcherTimer (60s deadline), index update and grid refresh run on UI thread after files are deleted.

---

## [1.2.69] - 2026-02-05

### Fixed
- **CRITICAL**: Fix permanent UI freeze when clicking "Test Connectivity" in AD Discovery panel.
  Root cause: `Invoke-AsyncOperation` imported the entire GA-AppLocker module (10 sub-modules, ~195 functions) into a background runspace -- this could hang indefinitely during module load. If it failed, a synchronous fallback ran `Test-MachineConnectivity` directly on the WPF STA thread, blocking the UI permanently (Test-WSMan has no built-in timeout on air-gapped networks).
  Fix: Replaced with a lightweight direct runspace that embeds ping (WMI Win32_PingStatus) and WinRM (Test-WSMan) logic inline -- zero module imports needed. DispatcherTimer polls every 200ms with a hard 30-second deadline. Background work uses nested RunspacePools with per-host deadlines (5s ping, 15s WinRM). If the 30s deadline is exceeded, the runspace is killed and the overlay is dismissed with a timeout toast.

---

## [1.2.68] - 2026-02-05

### Fixed
- WinRM connectivity tests now enforce a hard timeout and avoid UI freezes during AD Discovery.
- Connectivity test async UI timeout is clamped to 30 seconds to prevent hangs.

---

## [1.2.67] - 2026-02-05

### Fixed
- Includes local software scan freeze fix that was omitted from v1.2.66 package.

---

## [1.2.66] - 2026-02-05

### Fixed
- Fixed UI freeze after local software scan results populated.
- Local software scan now runs in background runspace with live loading status.
- Prevent duplicate local scans while one is in progress.

---

## [1.2.65] - 2026-02-05

### Fixed
- Scanner Start Scan now displays loading overlay with live status and wait cursor during scan execution.
- Connectivity test bounded timeout improvements to prevent indefinite hangs on unreachable hosts.
- AD Discovery OU Select All/Clear buttons removed to simplify UI and prevent accidental bulk operations.

---

## [1.2.64] - 2026-02-05

### Fixed
- Fixed startup crash caused by missing `catch` block on `try` statement in Rules panel (`GUI\Panels\Rules.ps1` line 828). The outer `try` in `Set-SelectedRuleStatus` (small-batch path) was missing its error handler.

---

## [1.2.63] - 2026-02-05

### Fixed
- Dedupe now preserves rules for different principals even when index entries miss `UserOrGroupSid` by resolving SID from full rule JSON before grouping.
- AD Discovery connectivity updates now render WinRM status immediately (including filtered views) without requiring manual refresh.
- Dashboard GPO/WinRM toggles now use a busy interlock to prevent accidental double-toggle while operations are in flight.

### Performance
- Rules panel bulk status/action/group updates run asynchronously for larger selections to keep the UI responsive.
- Scanning avoids duplicate artifact processing for overlapping scan paths.
- Connectivity/WinRM checks skip duplicate hostnames and use lower-overhead property updates in hot loops.

### Added
- Curated high-signal must-pass test gate and workflow E2E coverage (`Tests/Run-MustPass.ps1`, `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`).
- Packaging now includes `Run-Dashboard-ForceFresh.ps1` in release archives.

### Removed
- Obsolete tracked release artifacts (`.zip`), dead-code placeholders (`*.dead`), and superseded one-off phase/urgent/readiness report files from repository root.

---

## [1.2.60] - 2026-02-03

### Fixed
- **Bug 1: WinRM button label now stays constant**
  - Dashboard "Enable WinRM" button label no longer changes to "Disable WinRM" when toggled
  - Toggle state (IsChecked) indicates status, label stays "Enable WinRM" for clarity
  - File: `GA-AppLocker\GUI\Panels\Dashboard.ps1` line 103

- **Bug 2: AD Discovery DataGrid auto-refreshes after connectivity test**
  - After "Test Connectivity" completes, DataGrid now automatically updates
  - No longer requires manual "Refresh" button click to see updated WinRM status
  - Added `$dataGrid.Items.Refresh()` call after connectivity test
  - File: `GA-AppLocker\GUI\Panels\ADDiscovery.ps1` lines 717-724

- **Bug 3: Rules panel bulk buttons no longer crash**
  - Fixed "The term 'Write-StorageLog' is not recognized" error
  - Fixed "The term 'Initialize-JsonIndex' is not recognized" error
  - Removed `script:` scope prefix from internal Storage module functions
  - Functions now accessible to all dot-sourced files within the module
  - Files: `GA-AppLocker\Modules\GA-AppLocker.Storage\GA-AppLocker.Storage.psm1` line 16, `GA-AppLocker\Modules\GA-AppLocker.Storage\Functions\RuleStorage.ps1` line 73

### Added
- **Behavioral tests for v1.2.60 bug fixes** (10 tests, all passing)
  - `Tests/Behavioral/GUI/Dashboard.WinRMButton.Tests.ps1` - Verify button label consistency
  - `Tests/Behavioral/GUI/ADDiscovery.AutoRefresh.Tests.ps1` - Verify auto-refresh behavior
  - `Tests/Behavioral/GUI/RulesPanel.BulkButtons.Tests.ps1` - Verify Storage module scope fix

---

## [1.2.59] - 2026-02-03

### Added
- **AD Discovery panel UI improvements**
  - Added "Selected: N" count label (updates in real-time as selection changes)
  - Added "Refresh" button to manually refresh machine list after connectivity tests
  - File: `GA-AppLocker\GUI\MainWindow.xaml` lines 1104-1119
  - File: `GA-AppLocker\GUI\Panels\ADDiscovery.ps1` (handlers added after line 25)

### Changed
- **Standardized filter textbox heights across all panels**
  - Changed AD Discovery filter from `Padding="8,5"` to `Padding="6,4"` with `FontSize="11"`
  - Changed "Filter:" label to "Search:" for consistency with Rules/Policy panels
  - File: `GA-AppLocker\GUI\MainWindow.xaml` lines 1092-1103

---

## [1.2.58] - 2026-02-03

### Fixed
- **Bug 1: Test Connectivity now correctly tests only selected machines**
  - Fixed `Get-CheckedMachines` return value being lost in pipeline
  - Changed `return @($selected)` to `return $selected.ToArray()`
  - PowerShell 5.1 doesn't properly enumerate `List<T>` wrapped in `@()`
  - File: `GA-AppLocker\GUI\Panels\ADDiscovery.ps1` line 631

- **Bug 2: Dashboard GPO toggles now enable after initialization**
  - Fixed null comparison that always evaluated to true with PSCustomObjects
  - Changed `if ($null -eq $Status)` to `if (-not $Status)`
  - File: `GA-AppLocker\GUI\Panels\Dashboard.ps1` line 64

- **Bug 3: Local scan now blocks when not elevated (clearer UX)**
  - Changed confusing "Continue anyway?" warning to hard block with clear instructions
  - Prevents "Access Denied" errors after user clicks "Continue"
  - Suggests using Remote Scan as alternative
  - File: `GA-AppLocker\GUI\Panels\Scanner.ps1` lines 298-308

### Added
- **Run-Dashboard-ForceFresh.ps1** - Aggressive module cache clearing script
  - Use this if you see old version numbers in logs (e.g., v1.2.55 when v1.2.58 is installed)
  - Clears PowerShell module analysis cache
  - Verifies version match before starting
  - Warns if version mismatch detected

### Changed
- Improved error messages for elevation requirements
- Enhanced diagnostic logging for connectivity testing

---

## [1.2.57] - 2026-02-03

### Notes
- This version had correct fixes in code but users experienced module caching issues
- PowerShell served v1.2.55 from cache despite v1.2.57 being on disk
- v1.2.58 includes `Run-Dashboard-ForceFresh.ps1` to prevent this issue
- Superseded by v1.2.58

---

## [1.2.56] - 2026-02-03

### Fixed
- Test Connectivity selection bug (attempted fix - superseded by v1.2.58)
- Dashboard GPO toggles bug (attempted fix - superseded by v1.2.58)
- Scanner elevation check (attempted fix - superseded by v1.2.58)

---

## [1.2.55] - 2026-02-03

### Fixed
- Test Connectivity ignores machine selection
- Connectivity test performance improvements
- Update-SetupStatus startup errors
- Dashboard layout fixes
- GPO toggle initialization

---

## [1.2.54] - 2026-02-03

### Fixed
- Dashboard GPO toggles stay grey after setup
- Test Connectivity UI freeze

---

## [1.2.53] - 2026-02-02

### UI/UX

- **Dashboard GPO toggles** — New on/off switches for Enable WinRM and AppLocker GPOs (DC/Servers/Workstations). Toggles are disabled when RSAT/GroupPolicy is unavailable or GPOs don’t exist. Enable WinRM label flips between Enable/Disable based on status.
- **Policy Builder actions** — Rules actions moved into the bottom action row (Add/Import/Remove), policy actions grouped alongside (Activate/Archive/Delete/Deploy). Export XML removed from Policy Builder (use Deploy backup/export instead).
- **Policy selection** — Multi-select enabled with bulk delete support and a live “Selected: X” counter.
- **Deploy panel** — Create and Actions tabs restored (split), with target GPO now read from the policy.
- **Scanner config** — Remote machines managed in Config only, shown when Remote scan checked; WinRM-available count and gating; quick link to run Test Connectivity when none are available.

### Performance

- **Policy refresh** — Refresh no longer blocks navigation (no loading overlay for Refresh).

### Stats

- **Version:** 1.2.53
- **Tests:** not run (not requested)
- **Exported Commands:** ~195

## [1.2.50] - 2026-02-02

### Bug Fixes

- **White screen on startup** -- WPF wasn't triggering its initial render pass. Fixed by adding deferred `InvalidateVisual()` + `UpdateLayout()` in the `window.Loaded` event at `Render` dispatcher priority.
- **"Loading policies..." overlay stuck forever** -- Policy panel's `Initialize-PolicyPanel` was firing `Update-PoliciesDataGrid -Async` during `Initialize-MainWindow` even though the Policy panel wasn't visible, spawning an async runspace that showed the loading overlay on startup. Removed async load from init; policies now load on first navigation to the Policy panel. Also added 60-second safety timeout to `Invoke-AsyncOperation` that auto-hides overlay, stops the runspace, and shows a warning toast if any async operation hangs.
- **App always starts on Dashboard** -- Removed session panel restore (`Set-ActivePanel -PanelName $session.activePanel`) that was navigating to the last panel on startup. This triggered async policy loading before the UI was ready. Session still restores machines, credentials, selected policy/deployment -- just not the active panel.

### Performance

- **Deploy/Setup panel deferred loading** -- Wrapped Deploy panel refresh (policy combo, jobs DataGrid, GPO link status) and Setup panel status update in `Dispatcher.BeginInvoke` at `Background` priority so panels render immediately instead of blocking the STA thread (Deploy was loading 1142+ policies into its combo dropdown synchronously).

### UI Changes

- **Sidebar reorder** -- Software Inventory moved above Settings. Order below separator: Software Inventory, Settings, Setup, About.

### Stats

- **Version:** 1.2.50
- **Tests:** 1282/1282 passing (100%)
- **Exported Commands:** ~194

## [1.2.49] - 2026-02-02

### Bug Fixes

- **Software Inventory no longer auto-populates remote machines** -- Removed auto-populate from AD Discovery on panel navigation. Machine list starts blank; user enters hostnames manually or uses Scanner machine list as fallback.
- **Admin Allow button creates Appx rule** -- Template now includes all 5 collection types (was missing Appx). Creates EXE, DLL, MSI, Script, and Appx allow-all rules for AppLocker-Admins.
- **Dedupe no longer merges rules for different principals** -- Duplicate detection key now includes `UserOrGroupSid` and `Action`. Rules for SYSTEM, Local Service, Network Service, and Administrators with the same path/hash are NOT duplicates. Previously, dedupe treated `*` path rules for all SIDs as duplicates and removed all but one.
- **Policy Builder phase message shows correct phase** -- When rules are excluded by phase filter, message now shows which phase includes each excluded type (e.g., "Dll: 5 rule(s) (included at Phase 5)") instead of generic "excluded by Phase 4 filter".
- **Scanner DataGrid horizontal scrollbar** -- Artifact DataGrid now shows horizontal scrollbar when columns exceed visible width, allowing user to scroll right to see all columns.
- **Scanner scan paths textbox restored** -- Config tab now shows the scan paths TextBox with default paths (Program Files, System32, etc.) pre-populated from config. Users can add additional paths on new lines.

## [1.2.48] - 2026-02-02

### Features

- **Service Allow button** -- New `+ Service Allow` button on Rules panel creates 20 mandatory baseline allow-all path rules for the 4 principals that must never be blocked: SYSTEM (S-1-5-18), Local Service (S-1-5-19), Network Service (S-1-5-20), and BUILTIN\Administrators (S-1-5-32-544). Each gets allow-all path rules (`*`) across all 5 collection types (Exe, Dll, Msi, Script, Appx). All created with Status: Approved. Blocking any of these breaks Windows services, updates, and system management.

### UI Changes

- **Rules panel button reorder** -- Buttons now ordered: `+ Service Allow`, `+ Admin Allow`, `+ Deny Paths`, `+ Deny Browsers`, `- Dedupe`, `Delete`. Allow rules grouped first (green), deny rules second (red), utility last.

## [1.2.47] - 2026-02-01

### Performance

- **Save-JsonIndex rewrite** -- Replaced `ConvertTo-Json -Depth 10 -Compress` with `StringBuilder`-based manual JSON serialization for the rules index. PS 5.1's `ConvertTo-Json` has O(n^2) internal string concatenation for large arrays -- extremely slow for 3000+ rule indexes. New implementation writes safe values (GUIDs, enums, ISO dates, SIDs, hex hashes) directly, and JSON-escapes only values that need it (Name, PublisherName, ProductName, Path, GroupVendor, FilePath). Uses `[System.IO.File]::WriteAllText()` instead of `Set-Content`. Estimated 10-50x faster for large indexes.
- **Remove-DuplicateRules uses Remove-RulesBulk** -- Replaced manual per-file deletion loop (`Test-Path` + `Remove-Item` + `Get-RuleStoragePath` per iteration + separate `Remove-RulesFromIndex`) with single `Remove-RulesBulk` call. Collects all duplicate IDs into a `List[string]` and removes in one batch operation.
- **ConvertTo-Json depth reduced** -- Changed `-Depth 10` to `-Depth 5` across Storage module (`Save-RulesBulk`, `Add-Rule`, `Update-RuleInStorage`). Rule objects are flat PSCustomObjects that don't need deep serialization.

## [1.2.46] - 2026-02-01

### UI Changes

- **Remove Deploy Edit tab entirely** -- Deploy panel now has 3 tabs: Create, Actions, GPO Status. Removed `TxtDeployEditPolicyName`, `CboDeployEditGPO`, `TxtDeployEditCustomGPO`, `BtnSaveDeployPolicyChanges` from XAML. Removed `Update-DeployPolicyEditTab`, `Invoke-SaveDeployPolicyChanges` functions and all Edit tab wiring from Deploy.ps1. Removed `SaveDeployPolicyChanges` dispatcher entry from MainWindow.xaml.ps1.
- **Policy Create description box height aligned** -- `TxtPolicyDescription` Height changed from 60 to 50 to match `TxtEditPolicyDescription` on Edit tab.

### Bug Fixes

- **Deploy XML import preserves Approved status** -- `Import-RulesFromXml` on Deploy panel now called with `-Status 'Approved'` so imported rules are immediately usable for deployment. Previously imported as Pending, requiring manual approval before deployment.

### Test Cleanup

- **V1229Session.Tests.ps1 rewritten behavioral-only** -- Reduced from 1489 lines / ~350 tests to 670 lines / 63 tests. Removed all fragile regex pattern-matching tests that asserted source code strings (`$script:DeployPs1 | Should -Match 'pattern'`). Kept only behavioral tests that call real functions and verify return values. Added Deploy 3-tab ordering tests.
- **V1228Regression.Tests.ps1 deleted** -- Behavioral software comparison tests (re-run, null guards, slot detection) merged into V1229Session.Tests.ps1. All regex tests removed.
- **GUI.DeployPanel.Tests.ps1 updated** -- Removed Edit Tab Job Wiring test block (2 tests referencing removed `Update-DeployPolicyEditTab` and `Invoke-SaveDeployPolicyChanges` functions).
- **Test count: 1548 -> 1282** -- Net removal of ~266 fragile regex pattern-matching tests. Zero lost behavioral coverage.

## [1.2.45] - 2026-02-01

### Bug Fixes

- **Fix Resolve-GroupSid ADSI/LDAP fallback for SID resolution** -- Added Method 3 (ADSISearcher query for objectSid) and Method 4 (explicit LDAP via RootDSE defaultNamingContext). Now uses 4-method chain: NTAccount bare, NTAccount domain-prefixed, ADSISearcher, explicit LDAP. Early return if input already looks like a SID. Stopped caching UNRESOLVED values so retries can succeed when domain connectivity is restored. Cache validation ensures cached values match `^S-1-` pattern.
- **XML export SID guard** -- Both `Export-PolicyToXml.ps1` and `GA-AppLocker.Rules.psm1` now validate SIDs match `^S-1-\d+(-\d+)+$` before emitting to XML. Invalid SIDs (e.g., `UNRESOLVED:AppLocker-Users`) trigger re-resolution via `Resolve-GroupSid`. Falls back to `S-1-5-11` (Authenticated Users) or `S-1-1-0` (Everyone) if resolution fails.
- **GPO status refresh on panel navigation** -- Setup panel calls `Update-SetupStatus` and Deploy panel calls `Update-AppLockerGpoLinkStatus` when navigated to, so GPO status is always current. Added error logging in `Update-SetupStatus` catch blocks (was silently returning). `Get-SetupStatus` uses `-ErrorAction Stop` for GroupPolicy module import with logging.

### UI Changes

- **Policy Create tab: Target GPO dropdown** -- Added `CboPolicyTargetGPO` ComboBox (None, AppLocker-DC, AppLocker-Servers, AppLocker-Workstations, Custom GPO...) with `TxtPolicyCustomGPO` TextBox. GPO is set via `Update-Policy` after policy creation.
- **Deploy Create tab: Schedule removed** -- Removed `CboDeploySchedule` ComboBox. Deployment jobs now always created with Schedule = 'Manual'.
- **Deploy Edit tab: Stripped to name+GPO only** -- Removed `CboDeployEditPolicy`, `TxtDeployEditJobId`, `CboDeployEditSchedule`, `TxtDeployEditTargetOUs`, `TxtDeployEditPolicyDesc`. Edit tab now reads policy from `CboDeployPolicy` (Create tab). Only editable fields: policy name and target GPO.

### Test Fixes

- Fixed GUI.DeployPanel.Tests.ps1 (removed orphaned old test code for deleted XAML elements)
- Updated V1229Session.Tests.ps1 Deploy Edit tests for simplified edit tab (removed references to `CboDeployEditPolicy`, `TxtDeployEditJobId`, `CboDeployEditSchedule`, `TxtDeployEditTargetOUs`)

### Stats

- **Version:** 1.2.45
- **Tests:** 1548/1548 passing (100%)
- **Exported Commands:** ~194

## [1.2.44] - 2026-02-01

### Bug Fixes

- **CRITICAL: Fix RunspacePool scriptblock silently dropping ALL unsigned files from scan results** -- The parallel scanning code in `Get-LocalArtifacts.ps1` (used when file count > 100) had `Write-AppLockerLog` calls inside `catch` blocks within the RunspacePool scriptblock. Module functions are NOT available inside RunspacePool context, so calling `Write-AppLockerLog` threw a terminating `CommandNotFoundException` in PS 5.1. When this happened inside a `catch` block (e.g., catching the expected exception from `[X509Certificate]::CreateFromSignedFile()` on unsigned files), the error propagated up and silently skipped the entire artifact. Result: only signed files survived the parallel scan path -- all unsigned files were dropped with no error visible to the user.
- **Root cause of missing hash rules explained** -- Since only signed files survived scanning, only publisher rules could be generated. Hash rules (which require unsigned files) were never created. This fix restores unsigned file collection, enabling proper hash rule generation.
- **Fix:** Replaced `Write-AppLockerLog` calls inside RunspacePool `$processBlock` catch blocks with empty catches + explanatory comments. Sequential path and remote scan path were unaffected (they run in module scope where `Write-AppLockerLog` is available).

### Stats

- **Version:** 1.2.44
- **Tests:** 1548/1548 passing (100%)
- **Exported Commands:** ~194

## [1.2.43] - 2026-02-01

### Improvements

- **Setup panel shows actual linked OU paths** -- GPO cards now display the real linked OU paths (e.g., `lab.local/Member Servers`) instead of hardcoded labels like "Servers OU". `Get-SetupStatus` now adds `LinkedOUs` property via `Get-GPOReport` XML parsing, and Setup.ps1 populates `TxtGPO_{Type}_OU` TextBlocks
- **V1229Session.Tests.ps1 refactor** -- Reduced fragile source-code regex assertions:
  - Removed 5 redundant regex tests (ValidateRange, safety pattern checks already covered behaviorally)
  - Converted `Get-PhaseCollectionTypes` tests from regex to behavioral calls via dot-sourced Policy.ps1
  - Converted Software.ps1 global function existence checks from regex to `Get-Command`
  - Added explanatory comments on remaining source-pattern tests

### Stats

- **Version:** 1.2.43
- **Tests:** 1548/1548 passing (100%)
- **Exported Commands:** ~194

## [1.2.42] - 2026-02-01

### Bug Fixes & Features

- **Fix hash rules not created from CSV-imported artifacts** -- `Import-Csv` returns all values as strings, so `IsSigned = "False"` was truthy in PowerShell, making ALL artifacts appear signed. Added boolean coercion after CSV import + defensive check in `Get-RuleTypeForArtifact`
- **Fix Deploy Edit tab OU splitting** -- Target OUs containing commas (e.g., `OU=Servers,DC=example,DC=com`) were incorrectly split on commas. Changed split regex from `[,\r\n]+` to `[\r\n]+` (newlines only)
- **WinRM GPOs toggle settings instead of links** -- Enable/Disable WinRM GPO buttons now set `GpoStatus = AllSettingsEnabled/AllSettingsDisabled` instead of toggling link state. Both GPOs stay linked at all times; mutual exclusivity preserved (enabling one auto-disables the other)
- **Policy/Deploy column width adjustments** -- Policy Name column narrowed from 180 to 150; Deployment Jobs Policy column set to fixed 180

## [1.2.41] - 2026-02-01

### Bug Fixes & Features

- **Wire BtnClearCompletedJobs click handler** -- Clear Completed Jobs button was unresponsive because it was missing from the `$actionButtons` wiring array in `Initialize-DeploymentPanel`
- **GPO Link Control rewrite** -- Replaced direct `Get-GPO` calls (which failed silently in global function scope) with `Get-SetupStatus` (proven reliable from Setup panel). Now correctly shows Enabled/Disabled/Not Created status for all 3 GPOs
- **Deploy Edit tab save refreshes jobs DataGrid** -- After saving policy changes, the deployment jobs list now refreshes immediately
- **Setup panel AD group badges** -- 6 group badges (Admins, Exempt, Audit, Users, Installers, Developers) turn green when AD groups exist
- **Software Compare tab Export Comparison Results** -- New button exports comparison data to CSV with Source column (Match/Only in Scan/Only in Import/Version Diff)
- **Fix 7 tests for GPO Link rewrite** -- Updated V1229Session.Tests.ps1 source-code assertions to match new `Get-SetupStatus` based implementation

### Stats

- **Version:** 1.2.41
- **Tests:** 1547/1547 passing (100%)
- **Exported Commands:** ~193

---

## [1.2.40] - 2026-02-01

### Features & Fixes

- **Setup GPO status shows Enabled/Disabled state** -- "Configured - Enabled" (green) / "Configured - Disabled" (orange) instead of just "Configured"
- **Wire BtnStartDeployment click handler** -- Create Deployment Job button was unresponsive
- **GPO Link Control per-GPO error isolation** -- One failing `Get-GPO` no longer breaks all three pills; `Import-Module -ErrorAction Stop` with fallback
- **Initialize All creates Disable-WinRM GPO** -- Was missing from `Initialize-AppLockerEnvironment`
- **Software Inventory panel split into Scan + Compare tabs** -- Clearer workflow with step-by-step compare guide showing baseline/comparison file info

### Stats

- **Version:** 1.2.40
- **Tests:** 1547/1547 passing (100%)
- **Exported Commands:** ~193

---

## [1.2.39] - 2026-02-01

### Bug Fixes (Live DC01 Testing)

- **Deploy phase dropdown labels** -- Create tab phase dropdown showed wrong labels ("Audit & Discovery", "Enforcement Prep", etc.) instead of matching Edit tab ("Phase 1: EXE Only", "Phase 2: EXE + Script", etc.)

- **Deploy Policy button did nothing** -- `BtnStartDeployment` Tag was `"DeployPolicy"` but dispatcher expected `"CreateDeploymentJob"`. Fixed Tag and updated button Content to "Create Deployment Job"

- **Clear Completed Jobs** -- Added `Remove-DeploymentJob` function (accepts `-JobId` or `-Status`, deletes JSON files from Deployments folder), `BtnClearCompletedJobs` button in XAML, `Invoke-ClearCompletedJobs` handler in Deploy panel, dispatcher entry for `ClearCompletedJobs`

- **Software Inventory DataGrid unreadable** -- Selection used system default bright-blue which was unreadable on dark theme. Added standalone dark-theme RowStyle with `#0078D4` selected background and white foreground, plus `#2D2D30` hover

- **GPO Link Control rewrite** -- Replaced OU-specific link check (`Get-GPInheritance` + `Set-GPLink`/`New-GPLink`) with GPO status approach (`GpoStatus` enable/disable + `Get-GPOReport` XML for linked OU display). Added `TxtGpoLinkedOU*` subtitle TextBlocks under each GPO pill name showing linked OUs

- **Default OU targets on GPO creation** -- Added OU resolution logic: tries `OU=Member Servers` and `OU=Workstations` first, falls back to `CN=Computers`. DC always uses `OU=Domain Controllers`

- **GPOs disabled by default** -- After `New-GPO`, sets `GpoStatus = AllSettingsDisabled` so new GPOs don't take effect until explicitly enabled

### Stats

- **Version:** 1.2.39
- **Tests:** 1547/1547 passing (100%)
- **Exported Commands:** ~193

---

## [1.2.38] - 2026-02-01

### Bug Fixes

- **XAML duplicate name prevented app startup** -- `BtnDeployPolicy` was defined twice in MainWindow.xaml (Policy panel line 2046, Deploy panel line 2146). `XamlReader.Load()` threw "Cannot register duplicate name" and the window never appeared. Introduced in v1.2.34 when Deploy panel button was added. Renamed Deploy panel button to `BtnStartDeployment`. Neither panel references this button by `x:Name` (both use Tag-based dispatch), so renaming is safe.

### Code Quality

- **Suppress 51 `.Add()` pipeline leaks across 21 files** -- Every unsuppressed `.Add()` call on `List<T>`, `ObservableCollection`, WPF `Children`, `Items`, or `ColumnDefinitions` returns an integer that leaks into the PowerShell pipeline, corrupting function return values. Added `[void]` prefix to all 51 remaining instances across modules (Core, Scanning, Rules, Storage) and GUI (Panels, Dialogs, Wizards, Helpers, ToastHelpers).

- **ReportingExport.ps1 StringBuilder conversion** -- Converted 11 `$html += @"..."@` string concatenation instances in `Export-AppLockerReport` to `[System.Text.StringBuilder]` pattern. Eliminates O(n^2) string copying during HTML report generation.

- **RuleRepository.ps1 DEBUG logging in 12 catch blocks** -- Replaced 12 empty `catch { }` blocks with context-specific `Write-AppLockerLog -Level 'DEBUG'` messages covering cache lookup/store failures, event publish failures, cache invalidation failures, and bulk operation failures. Errors were previously swallowed silently.

### Stats

- **Version:** 1.2.38
- **Tests:** 1545/1545 passing (100%)
- **Exported Commands:** ~192

---

## [1.2.30] - 2026-01-31

### New Features

- **Phase 5 support (APPX + DLL phased rollout)** -- Policy pipeline expanded from 4 to 5 phases: Phase 4 adds APPX (AuditOnly), Phase 5 enables all collections including DLL (respects user enforcement mode). Updated New-Policy, Update-Policy, Export-PolicyToXml, and all XAML dropdowns.
- **GPO Link pill toggles** -- Deploy Actions tab GPO link status replaced with interactive pill-style toggle buttons (green=Enabled, orange=Disabled, grey=Not Linked/Not Created). Removes separate status TextBlocks.
- **Software Import split (Baseline vs Comparison)** -- Single "Import CSV" button replaced with "Import Baseline CSV" and "Import Comparison CSV" for clearer cross-system comparison workflow.
- **Server roles & features in software scan** -- Local and remote software scans now enumerate installed Windows Server roles and features via Get-WindowsFeature.
- **Deploy Edit tab policy dropdown** -- Deploy Edit tab gets its own policy ComboBox (CboDeployEditPolicy), synced with Create tab dropdown.

### Enhanced

- **Filter visual consistency (grey pill pattern)** -- Rules, Policy, and Deploy panels all use consistent grey pill toggle buttons (#3E3E42 bg + white fg for active, transparent + color fg for inactive). Replaces opacity-based toggling.
- **AD Discovery refresh preserves connectivity** -- Domain refresh merges new AD data with existing connectivity test results (IsOnline, WinRMStatus) instead of replacing them. Machine count shows online/WinRM summary.
- **AD Discovery first-visit auto-populates DataGrid** -- Navigating to Discovery panel with session-restored machines immediately populates the DataGrid and OU tree without requiring a manual refresh.
- **WinRM GPO mutual exclusivity** -- Enabling AppLocker-EnableWinRM automatically disables AppLocker-DisableWinRM (and vice versa) to prevent conflicting GPOs.
- **Policy tab reordering** -- Tabs reordered from Create→Rules→Edit to Create→Edit→Rules for better workflow.
- **Deploy tab reordering** -- Tabs reordered from Create→Actions→Edit→Status to Create→Edit→Actions→Status.
- **Deploy message area scrollable** -- Deployment message TextBlock now wrapped in ScrollViewer with MaxHeight constraint.

### Bug Fixes

- **Import XML missing dashboard refresh** -- Importing rules from XML now triggers Update-DashboardStats, Update-WorkflowBreadcrumb, and Reset-RulesSelectionState.
- **Pending rules invisible after session restore** -- Rules panel filter buttons now dynamically sync with CurrentRulesFilter on initialization instead of always highlighting "All".

### Tests

- **Comprehensive V1229 session tests** -- ~260 new test lines covering filter consistency, GPO pill states, AD Discovery merge logic, count consistency across Dashboard/breadcrumb/panels, and XAML stat element verification.
- **Phase 5 policy tests** -- Updated Policy.Phase.Tests.ps1 for 5-phase model with Phase 4 APPX and Phase 5 full enforcement tests.

### Stats

- **Version:** 1.2.30
- **Tests:** 550/550 passing (100%)
- **Exported Commands:** ~200

---

## [1.2.29] - 2026-01-31

### Documentation

- **Version bump to 1.2.29** -- Updated module manifest, CLAUDE.md, README.md, TODO.md, CHANGELOG.md, and DEVELOPMENT.md.
- **Test count update** -- 550/550 tests passing (100%), up from 397. 17 unit test files covering all 10 sub-modules. New test files include SoftwareComparison.Tests.ps1 and V1228Regression.Tests.ps1.

### Stats

- **Tests:** 550/550 passing (100%)
- **Test files:** 17
- **Exported Commands:** ~200

---

## [1.2.28] - 2026-01-31

### Bug Fixes

- **Deployment: Pass file path not XML content to Set-AppLockerPolicy** -- Fixed deployment error where XML string content was passed instead of the file path.
- **Per-host CSV export null ComputerName crash** -- Fixed null reference when ComputerName was missing during per-host CSV artifact export.

### Enhanced

- **Software Inventory: Background runspace for remote scan** -- Remote software scan now runs in a background runspace so the UI no longer freezes.
- **Software panel: Auto-populate remote machines from AD Discovery** -- Machines that are online and have WinRM available are automatically listed.
- **Deploy panel: Auto-refresh on navigation** -- Policy combo and jobs list refresh every time the Deploy panel is navigated to.

### Stats

- **Tests:** 550/550 passing (100%)
- **Exported Commands:** ~200

---

## [1.2.27] - 2026-01-31

### Features

- **Auto-export per-host CSV artifact files** -- After every scan, per-host CSV files are saved as `{HostName}_artifacts_{date}.csv` in the Scans folder.

### Stats

- **Tests:** 550/550 passing (100%)

---

## [1.2.26] - 2026-01-31

### Bug Fixes & Code Quality

- **Code quality sweep (17 fixes)** -- Remove destructive startup rule deletion, fix .psd1/.psm1 export mismatches, fix scheduled scan hardcoded dev paths, consolidate Get-MachineTypeFromOU, fix Backup-AppLockerData settings path, fix AuditTrail APPDATA fallback, Event System global->script scope, Test-Prerequisites .NET domain check, Test-CredentialProfile WMI ping, scanning scriptblock sync, ConvertFrom-Artifact O(1) List growth, Setup module .psd1 manifest, Remove-Rule export ambiguity, LDAP RequireSSL config option, scheduled scan runner ACL, Write-AuditLog JSONL format, dynamic APP_VERSION from manifest.

### Stats

- **Tests:** 550/550 passing (100%)

---

## [1.2.25] - 2026-01-31

### Bug Fixes

- **Deployment: Fix XML import to GPO** -- `Set-AppLockerPolicy -XmlPolicy` failed with "The following file cannot be resolved" because PS 5.1's `Set-Content -Encoding UTF8` writes a UTF-8 BOM, causing `Set-AppLockerPolicy` to misinterpret the content. `Export-PolicyToXml` now writes BOM-free UTF-8 via `[System.IO.File]::WriteAllText()`. `Import-PolicyToGPO` reads with `[System.IO.File]::ReadAllText()` and falls back to LDAP RootDSE for domain DN when `Get-ADDomain` is unavailable.

### Features

- **Setup: AppLocker-DisableWinRM GPO (tattoo removal)** -- New `Initialize-DisableWinRMGPO` creates a counter-GPO that actively reverses all WinRM settings from AppLocker-EnableWinRM: sets WinRM service to Manual (reverses auto-start tattoo), disables AllowAutoConfig, restores UAC remote filtering (LocalAccountTokenFilterPolicy=0), blocks port 5985. Also disables the EnableWinRM link to prevent conflict. "Disable GPO" button in Setup panel.
- **Software Inventory: Remote machine textbox** -- Enter hostnames directly (one per line or comma-separated) instead of requiring AD Discovery selection. Falls back to Scanner machine list when empty. Live count hint shows parsed hostnames.

### Enhanced

- **Deployment: Detailed logging** -- `Import-PolicyToGPO` now logs LDAP path and XML content length for debugging.

### Stats

- **Tests:** 397/397 passing (100%)
- **Exported Commands:** ~200

## [1.2.24] - 2026-01-31

### Bug Fixes

- **Software Inventory: Fix remote scan credentials** -- `Invoke-ScanRemoteSoftware` called `Get-DefaultCredential` which **does not exist** anywhere in the codebase. The silent `catch {}` meant credentials were never passed to `Invoke-Command`, so remote scans relied on implicit Windows authentication. Replaced with tier-based fallback chain: `Get-CredentialForTier` T2 -> T1 -> T0, then implicit Windows auth. Logs credential source.

### Features

- **Software Inventory: Auto-save CSVs** -- Both local and remote scans auto-save per-hostname CSVs to `%LOCALAPPDATA%\GA-AppLocker\Scans\` as `{HOSTNAME}_softwarelist_{ddMMMYY}.csv`. Created immediately after each machine scan.

### Enhanced

- **Deploy: Policy combo auto-refresh** -- `Refresh-DeployPolicyCombo` now auto-fires on every navigation to the Deploy panel (via `Set-ActivePanel`). Added detailed logging, proper error handling, `Out-Null` on `Items.Add()`.
- **Setup: WinRM toggle button label** -- Dynamically shows "Disable Link" when GPO is enabled, "Enable Link" when disabled, instead of static "Toggle Link".

### Stats

- **Tests:** 397/397 passing (100%)
- **Exported Commands:** ~198

## [1.2.23] - 2026-01-31

### Bug Fixes

- **WPF dispatcher crash fix** -- Unhandled dispatcher exception handler in `GA-AppLocker.psm1` used `Write-Warning` (a cmdlet!) as fallback logging in WPF timer/closure contexts where cmdlets are unavailable. Set `$e.Handled = $false` which propagated the exception and killed the entire window. Rewrote to use pure .NET `[System.IO.File]::AppendAllText()` for logging, set `$e.Handled = $true` to swallow non-fatal timer scope errors. Window closing handlers and post-ShowDialog calls also hardened with pure .NET I/O.

- **Fix "+ Policy" dialog scope bug** -- `Show-AddRulesToPolicyDialog` used `$script:DialogSelectedPolicyId` set inside `.GetNewClosure()` click handler, which created a separate scope. Outer function never saw the value. Fixed by reading `$listBox.SelectedItem.Tag` directly after dialog closes (local variable, still in scope).

- **Fix duplicate `Invoke-AddSelectedRulesToPolicy`** -- Two definitions existed: line 430 (correct, using `Get-SelectedRules`) and line ~1198 (broken, using `$dg.SelectedItems.Count` which is always 0 with virtual select-all for >500 items). Removed the broken second definition.

- **SID display cache fix** -- Added handler for `RESOLVE:` prefix in the Rules DataGrid SID cache (alongside existing `UNRESOLVED:` handler): strips prefix, displays clean group name.

### Features

- **Deploy panel: Edit tab** -- New "Edit" tab in the Deploy panel between Actions and Status. Edit policy Name, Description, and Target GPO (dropdown: None/AppLocker-DC/AppLocker-Servers/AppLocker-Workstations/Custom with custom text field). Save changes button calls `Update-Policy` and refreshes the combo. Policy combo now uses proper `ComboBoxItem` objects with `.Tag` for the policy object.

- **Deploy panel: Backup/Export/Import** -- Three new functions: `Invoke-BackupGpoPolicy` (backs up GPO to filesystem), `Invoke-ExportDeployPolicyXml` (exports policy XML), `Invoke-ImportDeployPolicyXml` (imports policy XML). Actions tab split into "JOB ACTIONS" and "POLICY BACKUP" sections.

- **"+ Admin Allow" button** -- Replaces old "Trusted Vendors" button. Creates 4 allow-all path rules for AppLocker-Admins across EXE, DLL, MSI, and Script collection types using the `AppLocker-Admins Default (Allow All)` template. One-click admin baseline.

- **"+ Deny Browsers" button** -- New red button creates 8 deny path rules blocking IE, Edge, Chrome, and Firefox (2 paths each: `%PROGRAMFILES%` and `%PROGRAMFILES(x86)%`) targeting AppLocker-Admins.

- **Dark title bar** -- P/Invoke `DwmSetWindowAttribute` with `DWMWA_USE_IMMERSIVE_DARK_MODE` (attr 20, fallback 19) for native Windows dark title bar. Type compiled once and cached in `$script:DwmApiType`.

- **Target group dropdowns reordered** -- All 3 target group dropdowns (Manual Rule, Scanner, Rules) now show AppLocker groups first with `AppLocker-Users` as default. Order: AppLocker-Users, AppLocker-Admins, AppLocker-Exempt, AppLocker-Audit, AppLocker-Installers, AppLocker-Developers, Everyone, Administrators, Users, Authenticated Users, Domain Users, Domain Admins.

- **Common Deny Path Rules target changed** -- `Invoke-AddCommonDenyRules` now targets `AppLocker-Users` (via `Resolve-GroupSid`) instead of Everyone (S-1-1-0).

- **Window size increased** -- 1450x1000 (was 1200x1050) for better content visibility.

- **Action column coloring** -- Rules DataGrid Action column now uses colored text: Allow=#4CAF50 green, Deny=#EF5350 red, SemiBold.

- **Unified filter bars** -- Rules, Policy, Deploy, and Software panels all use consistent DockPanel pattern with title left, Search+TextBox right, and transparent colored filter buttons below.

### Enhanced

- **Resolve-GroupSid cache** -- Added `$script:ResolvedGroupCache` hashtable that caches all lookups (successful SIDs, UNRESOLVED fallbacks, nulls). Eliminates repeated NTAccount translation attempts. Only logs one warning per failed group name instead of 4+.

- **Troubleshooting scripts updated** -- `Enable-WinRM.ps1` and `Disable-WinRM.ps1` now apply/revert the exact same 4 settings as `Initialize-WinRMGPO`: WinRM service auto-start, AllowAutoConfig with IPv4/IPv6 filters, LocalAccountTokenFilterPolicy, and firewall port 5985. Previously only configured basic WinRM listener.

- **Force-GPOSync.ps1 rewritten** -- Previous version had multiple bugs: `try/catch` on `repadmin` (native exe never throws), `Get-ADComputer -Filter *` returning disabled/stale accounts, no ping check before `Invoke-GPUpdate` (wall of RPC errors on offline machines), em dashes in string literals. Rewrite adds: `-Target`/`-OU`/`-SkipOffline` parameters, filters disabled accounts and 90-day stale machines, ping check with `Win32_PingStatus`, `Invoke-GPUpdate` (RPC) with `Invoke-Command` (WinRM) fallback per machine, excludes local DC from remote list, and clear summary with troubleshooting tips.

- **Unicode em dash cleanup** -- Replaced 8 remaining Unicode em dashes (U+2014) in comments across `GA-AppLocker.psm1`, `Rules.ps1`, and `Scanner.ps1` with ASCII double hyphens. While comments don't break PS 5.1 parsing, they display as garbled characters in Windows-1252 editors.

### Removed

- **Removed "+ Policy" button from Rules panel bottom bar** -- Was redundant (Policy panel has its own "Add Rules").
- **Removed Modules card from About page** -- Removed the 10 colored module badges WrapPanel.

### Stats

- **Tests:** 397/397 passing (100%)
- **Exported Commands:** ~198

---

## [1.2.22] - 2026-01-31

### Bug Fixes

- **Dashboard: Fix Pending Approval list empty** — Software.ps1 had UTF-8 em dashes in string literals that broke PowerShell 5.1 parsing (reads files as Windows-1252). This crashed the entire GUI initialization. Replaced with ASCII hyphens. Also improved pending list to use ObservableCollection for robust WPF binding.

- **DataGrid headers unreadable on some panels** — Software Inventory had no header style (WPF defaults = invisible). Machine/Artifact/Credentials DataGrids had muted gray headers. All 7 DataGrids now use the shared DataGridStyle with white semibold headers matching the Rules panel.

### Enhanced

- **Setup: Remove WinRM GPO button** — New "Remove GPO" button (red text) on the WinRM Configuration card. Calls existing Remove-WinRMGPO with confirmation dialog. The function existed since v1.2.12 but had no UI.

- **About panel redesign** — Added author credit (Tony Tran, CISSP / ISSO, General Atomics), app purpose description for air-gapped/classified/SIPR environments, workflow visualization, key capabilities list, all 10 module badges, and ScrollViewer for content overflow.

### Stats

- **Tests:** 397/397 passing (100%)

---

## [1.2.21] - 2026-01-31

### Enhanced

- **Scanner: Add Product Name column** — The artifact DataGrid now shows a "Product" column after Publisher, displaying the `ProductName` from file version info. Data was already collected by `Get-LocalArtifacts` and `Get-RemoteArtifacts` but not displayed.

- **Scanner: Appx/MSIX checked by default** — "Include Appx/MSIX Packages" is now checked by default in the Scanner Config panel and reordered above Event Logs for better visibility.

### Stats

- **Tests:** 397/397 passing (100%)

---

## [1.2.20] - 2026-01-31

### Bug Fixes

- **Policy Builder: Remove dead Export tab** — The Export tab had `BtnExportPolicyXml` and `BtnExportPolicyCsv` buttons with no dispatcher handlers (completely non-functional). The bottom action bar already had a working Export Policy button. Removed the entire Export tab (4 tabs → 3: Create, Rules, Edit).

- **Policy Builder: Fix Modified date column showing nothing** — DataGrid column was bound to `ModifiedDisplay` but only `ModifiedAt` (raw ISO string) existed. Added date parsing and formatting to produce `MM/dd HH:mm` display values.

- **Policy Builder: Enable editing policy Name and Description** — Edit tab only had Enforcement Mode and Phase dropdowns with a read-only name TextBlock. Changed to editable TextBox, added Description TextBox, and wired `Invoke-SavePolicyChanges` to pass Name/Description to `Update-Policy`.

- **Policy Builder: Add Target GPO selection** — `TxtTargetGPO`, `PolicyTargetOUsList`, `BtnSelectTargetOUs`, and `BtnSaveTargets` were all referenced in code but **never existed in the XAML** — completely phantom UI elements. Added `CboEditTargetGPO` ComboBox with presets (AppLocker-DC, AppLocker-Servers, AppLocker-Workstations, Custom) and custom GPO TextBox. Wired selection, population, and save logic.

- **Policy Builder: Unblock Deploy button** — Deploy always failed with "Please set a Target GPO" because `$policy.TargetGPO` was always null (the UI to set it never existed). Now navigates to Deployment panel instead of blocking.

- **Policy Builder: Remove dead code** — Removed `Invoke-SelectTargetOUs` and `Invoke-SavePolicyTargets` functions, their dispatcher entries, and button references that pointed to non-existent XAML elements.

- **Rules/Policy/Deploy: Fix column header sorting** — `DataGridTemplateColumn` (used for colored circles and status badges) does not support automatic WPF sorting. Added `SortMemberPath` to Group column, Status column on Rules panel, Status column on Policy panel, and Status column on Deploy panel.

### Enhanced

- **Update-Policy** now accepts `-Name`, `-Description`, and `-TargetGPO` parameters in addition to existing `-EnforcementMode` and `-Phase`.

### Stats

- **Tests:** 397/397 passing (100%)

---

## [1.2.19] - 2026-01-31

### Features

- **Software Inventory panel** — New 9th dedicated panel for scanning installed software across local and remote machines. Registry-based detection (HKLM Uninstall + WOW6432Node) returns DisplayName, DisplayVersion, Publisher, InstallDate, Architecture, and Source. Remote scanning via WinRM with credential support from the Credentials panel.

- **CSV export/import** — Export scanned software inventory to CSV with auto-generated filenames. Import CSV files from other systems with column validation and normalization for cross-system comparison workflows.

- **Software comparison engine** — Compare scan results against imported CSV data by DisplayName (case-insensitive). Produces three categories: "Only in Scan" (software missing from import), "Only in Import" (software missing from scan), and "Version Diff" (shows `scanVer → importVer`). Useful for baseline drift detection across air-gapped machines.

- **Full UI integration** — Sidebar navigation (📋 icon), keyboard-accessible, DataGrid with 7 columns (Machine, Name, Version, Publisher, Install Date, Arch, Source), text filter, stats card (Last Scan + Total Count), and status bar. Dark/light theme support.

### Stats

- **Tests:** 397/397 passing (100%)
- **Panels:** 9 (was 8)
- **Test files:** 15

---

## [1.2.18] - 2026-01-30

### Bug Fixes

- **Fix Change Group/Action silent error swallowing** — Both `Invoke-ChangeSelectedRulesGroup` and `Invoke-ChangeSelectedRulesAction` had empty `catch { }` blocks that silently swallowed errors during JSON write and index rebuild operations. Added `Write-AppLockerLog -Level 'ERROR'` calls so failures are now visible in the log file, making the "rules disappear" bug diagnosable.

- **Consistent ISO 8601 date serialization** — Fixed 8 locations across the codebase where `ModifiedDate = Get-Date` or `CreatedDate = Get-Date` produced verbose DateTime JSON objects (with `value`, `DisplayHint`, `DateTime` sub-properties) instead of clean ISO 8601 strings. All rule CRUD operations now use `Get-Date -Format 'o'` consistently, matching `Invoke-BatchRuleGeneration` which already used ISO format. Affected files: `New-HashRule.ps1`, `New-PathRule.ps1`, `New-PublisherRule.ps1`, `Get-Rule.ps1` (Set-RuleStatus), `RuleHistory.ps1` (Restore-RuleVersion), `Set-BulkRuleStatus.ps1`, and `Rules.ps1` (Change Action/Group/Status context menu handlers).

### Features

- **AppLocker-Admins default template** — Added "AppLocker-Admins Default (Allow All)" template to `RuleTemplates.json` with 4 path rules allowing all execution across Exe, DLL, MSI, and Script collection types for the AppLocker-Admins group.

- **RESOLVE: prefix handling in template engine** — `New-RulesFromTemplate` now detects `RESOLVE:GroupName` prefixes in template `UserOrGroup` fields and calls `Resolve-GroupSid` to translate them to real SIDs at rule creation time. Falls back to `UNRESOLVED:GroupName` when not domain-joined.

### Stats

- **Tests:** 397/397 passing (100%)
- **Test files:** 15

---

## [1.2.17] - 2026-01-30

### Features

- **Granular script type filters** — Split the single "Skip Scripts" checkbox into two independent filters: **Skip WSH Scripts** (.js, .vbs, .wsf — legacy Windows Script Host, default ON/checked) and **Skip Shell Scripts** (.ps1, .bat, .cmd — admin tools, default OFF/unchecked). Applied across the entire pipeline: Scanner panel, rule generation dialog, `Get-LocalArtifacts`, `Get-RemoteArtifacts`, `Start-ArtifactScan`, `ScheduledScans`, `Invoke-BatchRuleGeneration`, and the Rule Generation Wizard.

- **Increased window height** — MainWindow height increased from 800px to 1050px for better content visibility.

### Bug Fixes

- **Fix WPF dispatcher scope bugs** — Three functions called from the Scanner panel's DispatcherTimer tick handler (`Update-ScanProgress`, `Update-ScanUIState`, `Update-ArtifactDataGrid`) were not visible from WPF dispatcher context because they lacked `global:` scope prefix. This caused "not recognized as a command" errors during scan progress updates and when loading saved scans. All three functions now use `function global:` declarations.

### Stats

- **Tests:** 397/404 passing (98.3%) — 7 pre-existing GUI type-cast failures
- **Test files:** 15

---

## [1.2.16] - 2026-01-30

### Tests

- **New Import/Export tests** — Created `Tests/Unit/ImportExport.Tests.ps1` with 8 tests covering the v1.2.15 filename fallback chain in `Import-RulesFromXml`: empty SourceFileName with Name fallback, "Unknown" SourceFileName override, empty Name/SourceFileName hash-prefix fallback, Description-based filename extraction, and a full Export→Import roundtrip verifying filename preservation through the XML pipeline.

- **Hash rule name generation tests** — Added 4 tests to `Rules.Tests.ps1` verifying `New-HashRule` produces hash-prefix names (e.g., `Hash:DEADBEEF1234...`) when SourceFileName is 'Unknown', and standard names (e.g., `notepad.exe (Hash)`) when a real filename is provided.

- **ConvertFrom-Artifact filename resolution tests** — Added 3 tests to `Rules.Tests.ps1` verifying artifact-to-rule conversion extracts filenames from `FilePath` when `FileName` is null/empty, and gracefully falls back to hash-prefix names when both are unavailable.

- **Policy export filename extraction test** — Added test to `Policy.Phase.Tests.ps1` verifying `Build-PolicyRuleCollectionXml` extracts real filenames from rule Name fields when SourceFileName is 'Unknown', preventing `SourceFileName="Unknown"` in exported XML.

- **Test-PingConnectivity export verification** — Added 2 tests to `AD.Discovery.Mock.Tests.ps1` confirming the function is exported and accepts the `Hostnames` parameter (v1.2.14 fix).

- **Module loading verification** — Added 2 tests to `EdgeCases.Tests.ps1` verifying no manual `Import-Module` calls exist in `GA-AppLocker.psm1` and that all 10 sub-modules are declared in `.psd1` `NestedModules`.

### Documentation

- **DEVELOPMENT.md** — Updated module list from 7 to 10 sub-modules (added Storage, Setup, Validation). Removed obsolete "Avoid DoEvents()" tip. Added Critical Warnings section covering: never use manual Import-Module in .psm1, never use Get-CimInstance in WPF STA thread code, and SID-to-friendly-name resolver pattern from v1.2.11.

- **TODO.md** — Updated test count from 67 to 398+. Added v1.2.11–v1.2.15 work summary table.

- **README.md** — Updated test count to reflect 398+ passing (out of 405 total, 7 pre-existing GUI type-cast failures).

### Stats

- **Tests:** 393/400 passing (98.3%) — 15 new tests, 7 pre-existing GUI failures
- **Test files:** 15 (new: `ImportExport.Tests.ps1`)

---

## [1.2.15] - 2026-01-30

### Bug Fixes

- **Hash rules show "Unknown (Hash)" after XML import** — `Import-RulesFromXml` only checked `FileHash/@SourceFileName` for the filename, which is often empty in AppLocker XML exports. Now uses a robust fallback chain: `FileHash/@SourceFileName` → `FileHashRule/@Name` (stripping `(Hash)` prefixes) → `FileHashRule/@Description` (regex-extracting filenames) → `'Unknown'`. Rules previously showing "Unknown (Hash)" will now show the actual filename like "notepad.exe (Hash)".

- **ConvertFrom-Artifact produces "Unknown (Hash)" when FileName is missing** — If a scan artifact had a null `FileName` property (edge case with certain file types), the rule got `SourceFileName = $null` which cascaded to "Unknown (Hash)" in the display. Now falls back to extracting the filename from `FilePath` via `[System.IO.Path]::GetFileName()`.

- **New-HashRule shows "Unknown (Hash)" instead of useful identifier** — When `SourceFileName` is genuinely unknown (empty or 'Unknown'), the generated rule name is now `"Hash:ABCDEF012345..."` (truncated hash) instead of `"Unknown (Hash)"`, making rules distinguishable in the DataGrid.

- **XML export writes 'Unknown' as SourceFileName** — `Build-PolicyRuleCollectionXml` wrote `SourceFileName="Unknown"` when the field was empty. Now extracts the filename from the rule's `Name` field (pattern `"filename.ext (Hash)"`) before falling back to 'Unknown', preventing the bad data from propagating through export→import cycles.

---

## [1.2.14] - 2026-01-30

### Bug Fixes

- **Dashboard window not appearing on startup** — `Get-CimInstance -ClassName Win32_ComputerSystem` was called on the WPF STA thread during `Initialize-MainWindow` to detect domain membership. This WMI call **times out after 5-60+ seconds** in many environments, blocking `ShowDialog()` from ever executing. Replaced with `.NET` `[System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()` which returns in **0-1ms**. Computer name, user, and domain still populated via `$env:` variables.

- **Redundant nested module loading causing double-import** — `GA-AppLocker.psm1` had 10 manual `Import-Module` calls for all sub-modules (Core, Storage, Discovery, etc.) even though `GA-AppLocker.psd1` `NestedModules` already loads them automatically. This caused every module to load twice, producing a duplicate "All nested modules loaded successfully" log entry and unnecessary overhead. Removed all manual imports — `.psd1` `NestedModules` is now the single source of truth for sub-module loading.

- **`Test-PingConnectivity` not exported from Discovery module** — The function was declared in `GA-AppLocker.Discovery.psd1` `FunctionsToExport` but missing from `GA-AppLocker.Discovery.psm1` `Export-ModuleMember`. This was masked by the old manual `Import-Module` approach which bypassed the `.psm1` export list. Now properly exported.

---

## [1.2.13] - 2026-01-30

### Performance

- **Replace `Get-FileHash` with .NET SHA256 (4.4x faster per file)** — Direct `[System.Security.Cryptography.SHA256]::Create()` with `[System.IO.File]::OpenRead()` eliminates PowerShell cmdlet overhead. Applied to both local scanning (`Get-FileArtifact`) and remote scanning (`Get-RemoteFileArtifact`). Identical hash output, zero compatibility risk.

- **RunspacePool parallel file processing (3.5x faster)** — Local artifact scanning now processes files across all CPU cores (up to 8 threads) using `[runspacefactory]::CreateRunspacePool()`. Files are split into batches (~50-200 files each) and processed simultaneously. Self-contained scriptblock handles hash, cert, version info, and artifact type mapping independently per runspace. Falls back to sequential processing for small file sets (≤100 files) where pool overhead exceeds benefit. **Combined with .NET SHA256: ~80-90 second scans now complete in ~14 seconds.**

### Enhancements

- **"Skip Scripts" scanner filter checkbox** — New `ChkSkipScriptScanning` checkbox in Scanner panel PERFORMANCE FILTERS section. Filters out `.ps1`, `.psm1`, `.psd1`, `.bat`, `.cmd`, `.vbs`, `.js`, `.wsf` extensions before scanning. Wired through `Start-ArtifactScan` → `Get-LocalArtifacts` / `Get-RemoteArtifacts`. Pattern follows existing "Skip DLLs" filter. Defaults unchecked.

### Bug Fixes

- **Progress bar overlap when both local and remote scan active** — Local scan progress (26-88%) and remote scan progress (30-85%) overlapped, causing a jarring 88%→30% jump mid-scan. `Start-ArtifactScan` now configures progress ranges in `$SyncHash` based on scan mode: Both active → Local 10-45%, Remote 45-85%; Local only → 10-88%; Remote only → 10-88%. `Get-LocalArtifacts` reads range from `$SyncHash.LocalProgressMin`/`LocalProgressMax` and scales discovery + processing phases within it.

## [1.2.12] - 2026-01-30

### Bug Fixes

- **Publisher rules display junk OID/serial data** — Raw X.509 certificate subjects contain data after the country code (e.g., `SERIALNUMBER=232927, OID.2.5.4.15=Private Organization`). Publisher rules now truncate `PublisherName` at `C=XX` (country code) both at creation time in `New-PublisherRule` and at display time in `Update-RulesDataGrid`. Raw cert data on disk for existing rules is cleaned on display; new rules are stored clean.

- **Saved scans not loading in Scanner History tab** — Two issues: (1) `Update-SavedScansList` had a `Get-Command -Name 'Get-ScanResults'` guard that silently fails in WPF context, replaced with try/catch. (2) `Get-ScanResults` list mode parsed entire multi-MB JSON files (22MB = 2.7s per file) just to read metadata. Rewrote to read only first 1KB via `[System.IO.File]::OpenRead()` and extract fields via regex. **Performance: 2679ms → 103ms (26x faster).**

- **Rule export capped at 1000 rules** — `Export-RulesToXml` called `Get-AllRules` without `-Take`, which defaults to 1000. Added `-Take 100000` to export all rules.

- **Rule XML import extremely slow (1-by-1 saves)** — `Import-RulesFromXml` was saving each rule individually to disk and rebuilding the index after each one. Rewrote to: create rules in memory (no `-Save`), use `List<T>` instead of `@()` array concat, set `-Status` directly on creation, and batch-save all rules with single `Save-RulesBulk` call at the end. Single disk write + single index rebuild.

### Enhancements

- **WinRM GPO enhanced for reliable remote scanning** — `Initialize-WinRMGPO` now configures all settings needed for PowerShell remoting:
  - `AllowAutoConfig` with IPv4/IPv6 filters (enables WinRM listener via policy)
  - `LocalAccountTokenFilterPolicy` (allows local admin accounts to have full remote access — **#1 cause of "Access Denied" when credentials are correct**)
  - Firewall port 5985 inbound allow
  - WinRM service auto-start
  - New `-Enforced` parameter (default: `$true`) — enforced at domain root overrides all lower-level GPOs
  - All policy settings revert automatically when GPO is unlinked/removed (next `gpupdate`)

- **New `Remove-WinRMGPO` function** — Completely removes the WinRM GPO and all its links. Exported from Setup module.

- **Rules cleared on startup** — Previous session rules are deleted from `%LOCALAPPDATA%\GA-AppLocker\Rules\` on every app launch for faster loading and clean state.

- **Enhanced scan credential logging** — Tier scan logs now include the exact username being used and which machines (with their MachineType classification) are in each tier group. Visible in `%LOCALAPPDATA%\GA-AppLocker\Logs\` for credential troubleshooting.

---

## [1.2.11] - 2026-01-30

### Bug Fixes

- **Rules DataGrid Group column was blank (grey circle, no text)** — The Group column binds to `GroupName` and `GroupRiskLevel` properties, but these were never derived from the `UserOrGroupSid` stored on each rule. Rules generated targeting AppLocker-Users, Administrators, or any group showed only a grey circle with no label. Fixed by adding a SID-to-friendly-name resolver in `Update-RulesDataGrid` that caches well-known SIDs (Everyone, Administrators, Users, etc.), resolves domain SIDs via .NET `NTAccount.Translate()`, and handles `UNRESOLVED:` prefixes. Circle color now indicates scope: green (targeted groups), orange (Users/Domain Users), red (Everyone/Guests). Tooltip shows the raw SID on hover.

- **Startup log showed hardcoded v1.2.0** — `$script:APP_VERSION` in `GA-AppLocker.psm1` was hardcoded to `'1.2.0'` and never updated. Startup log now reads version dynamically from `(Get-Module GA-AppLocker).Version`.

- **Unapproved verb warnings on import** — `Import-Module` showed two warnings about `Rebuild-RulesIndex` using the unapproved verb `Rebuild`. Added `-DisableNameChecking` to Storage module import and `Run-Dashboard.ps1`.

---

## [1.2.10] - 2026-01-30

### Performance

- **Air-gap scan speedup (5-100x faster)** — Replaced `Get-AuthenticodeSignature` with `.NET X509Certificate.CreateFromSignedFile()` in both local and remote scanning. The old cmdlet triggers CRL/OCSP revocation checks that timeout on air-gapped networks, causing scans to hang for 10-30+ minutes. The .NET method extracts the embedded certificate instantly with zero network calls. Benchmarked at 5x faster even with internet; on air-gapped machines the improvement is 50-100x.

- **WinRM connection timeout (30s)** — Added `New-PSSessionOption -OpenTimeout 30000` to `Invoke-Command` in `Get-RemoteArtifacts`. Previously, unreachable machines (WinRM not configured) caused infinite hangs. Now fails fast in 30 seconds with a clear error in the log.

- **Increased ThrottleLimit and BatchSize defaults** — ThrottleLimit: 5 → 32 concurrent WinRM sessions. BatchSize: 50 → 100 machines per batch. Better utilization for environments with many machines.

- **Better scan logging** — Added "Connecting to: host1, host2, host3" before `Invoke-Command` and result count / warning after each batch completes. Added progress logging every 500 files in `Get-LocalArtifacts`. Visible in the log file for troubleshooting.

### Bug Fixes

- **Remote scan nested array bug (critical)** — `Invoke-Command` targeting multiple machines returned nested arrays (one per machine) instead of individual artifacts. A scan of 2 machines returning 5,000 artifacts each showed "2 artifacts" in the summary (counting arrays, not items). Rule generator saw 2 items without artifact properties and created 0 rules. Fixed by removing the `@(,...)` array wrapper from the remote scriptblock return and adding a flatten safety net in the batch result processing loop.

- **No-machines graceful error** — Clicking "Start Remote Scan" without adding machines from AD Discovery threw a null reference exception on `$script:SelectedScanMachines.Count`. Now shows a detailed MessageBox explaining how to add machines first.

- **Module reload on dashboard launch** — `Import-Module -Force` doesn't remove sub-modules. `Run-Dashboard.ps1` now calls `Remove-Module GA-AppLocker -Force` and `Get-Module GA-AppLocker.* | Remove-Module -Force` before import, ensuring the latest code is always loaded.

### Added

- **Troubleshooting scripts** — Three new admin scripts in `Troubleshooting/`: `Enable-WinRM.ps1` (enables WinRM service, configures listener, opens firewall ports 5985/5986), `Disable-WinRM.ps1` (reverts all WinRM changes), and `Force-GPOSync.ps1` (forces AD replication via `repadmin /syncall`, `Invoke-GPUpdate` on all domain computers, local `gpupdate /force`).

---

## [1.2.9] - 2026-01-30

### Bug Fixes

- **OU tree showed no children (only root node)** — Depth calculation `($dn -split ',OU=').Count - 1` gave top-level OUs Depth 0, same as the root domain object. `Add-ChildOUsToTreeItem` searched for children at `parentDepth + 1 = 1` and found nothing. Fixed to `([regex]::Matches($dn, 'OU=')).Count` which correctly counts OU segments (top-level = 1, nested = 2, etc.). Fixed in both AD module and LDAP paths.

- **OU tree stuck at "Loading..." when enumeration failed** — If `Get-OUTree` returned `Success=$false`, the `$onComplete` handler had no `else` clause for the OU result, so the XAML placeholder was never cleared. Now shows the actual error message in the tree.

- **Last Logon column blank via LDAP** — `Get-ComputersByOUViaLdap` did not query `lastLogonTimestamp` and did not include a `LastLogon` property on the computer object. Added `lastLogonTimestamp` and `description` to the LDAP query, parsing Windows FILETIME to DateTime. Also added `Description` property.

- **"Domain: Not connected" label** — Null-safety issue: `$errorMsg.Length` could fail if `$Result.DomainResult.Error` was null, silently preventing the domain label from updating. Added null guards and a fallback `'Unknown error'` default.

- **Scan progress stuck at 25% with no machine visibility** — `Start-ArtifactScan` never updated the SyncHash during remote scanning. The runspace set progress to 25% ("Scanning files...") and then nothing until 90% when all machines finished. Now shows per-tier progress with machine names (e.g., "Scanning Tier 1 (1/2): SRV01, SRV02") and completion status per tier. Progress scales from 30–85% across tier groups.

---

## [1.2.8] - 2026-01-30

### Bug Fixes

- **Dynamic version display** — About panel showed hardcoded "1.0.0". Now reads `ModuleVersion` from the GA-AppLocker module manifest at startup and sets both the About panel and sidebar subtitle dynamically. Version is always correct regardless of which file gets bumped.

- **Hide workflow breadcrumb on sidebar collapse** — When the sidebar was collapsed to icon-only mode, the Workflow Progress indicator (4 stage circles with counts) stayed visible and got squished into 60px, showing as an unreadable jumble of numbers. Now hidden on collapse and restored on expand.

- **APPX scanning returned zero artifacts** — `Get-AppxArtifacts` filtered out all system/framework packages by default (`-IncludeSystemApps=$false`, `-IncludeFrameworks=$false`, `-AllUsers=$false`), leaving zero results on Server 2019 and most Windows 10 machines. Now includes system apps, frameworks, and all-user packages by default with robust `-AllUsers` fallback (tries `Get-AppxPackage -AllUsers` first, falls back to current-user on permission error). Fixed progress bar overwrite where APPX phase set progress to 100% while remote scans were still running (now uses 89-95% range). Added missing `ArtifactType`, `Extension`, `Publisher`, `SHA256Hash`, `SizeBytes`, `CollectedDate` properties to APPX artifact objects so DataGrid columns display correctly. Added `.appx`/`.msix` to artifact type mappings in both local (`Get-ArtifactType`) and remote (`Get-RemoteArtifactType`) — was falling through to `'Unknown'`. `ConvertFrom-Artifact` now respects pre-set `CollectionType` on APPX artifacts instead of re-deriving from extension.

---

## [1.2.7] - 2026-01-30

### Bug Fix

- **Action column was blank in Rules DataGrid** — The JSON index entries created by `Rebuild-RulesIndex`, `Add-Rule`, and `Add-RulesToIndex` did not include `Action` or `UserOrGroupSid` fields. Since `Get-AllRules` reads from the index (not individual files), these columns displayed as blank in the UI. Added both fields to all 3 index entry creation points, and `Update-Rule` now syncs both fields to the index.

### New Features

- **Bulk Change Action** — New "Action" button in the Rules panel status actions bar. Select one or more rules (Shift+Click / Ctrl+Click), click "Action", and set all selected rules to Allow or Deny via a dialog.

- **Bulk Change Group** — New "Group" button in the Rules panel status actions bar. Select one or more rules, click "Group", and reassign all selected rules to a different target group (Everyone, Administrators, Users, Domain Users, AppLocker-* AD groups, etc.) via a dropdown dialog with `RESOLVE:` prefix SID resolution.

---

## [1.2.6] - 2026-01-30

### New Features

- **Common Deny Path Rules** — New "+ Deny Paths" button in the Rules panel bulk actions toolbar. One click creates 21 deny rules (7 user-writable directories × 3 collection types: Exe, Msi, Script) with Action=Deny, Status=Approved, SID=Everyone (S-1-1-0). Covers: `%OSDRIVE%\Users\*\AppData\Local\Temp\*`, `Downloads\*`, `Desktop\*`, `Documents\*`, `Users\Public\*`, `Windows\Temp\*`, `PerfLogs\*`.

- **AppLocker AD groups in target group dropdowns** — Manual Rule and Scanner Batch Config target group ComboBoxes now include 6 AppLocker AD groups (AppLocker-Users, AppLocker-Admins, AppLocker-Exempt, AppLocker-Audit, AppLocker-Installers, AppLocker-Developers) with `RESOLVE:` prefix tags for lazy SID resolution.

- **Resolve-GroupSid helper** — New Core module function for .NET-based AD group SID resolution. Strips `RESOLVE:` prefix, checks well-known SIDs, tries `NTAccount.Translate()` without domain prefix then with `$env:USERDOMAIN\` prefix. Falls back to `UNRESOLVED:GroupName` placeholder when group cannot be resolved.

---

## [1.2.5] - 2026-01-30

### AD Discovery & UX Fixes

- **Filter buttons and text search now work** — Filter handlers used `.GetNewClosure()` which creates a separate module scope. Inside the closure, `$script:DiscoveredMachines` and `$script:MainWindow` resolved to the closure's empty scope (always `$null`), so every filter silently returned immediately. Removed `.GetNewClosure()` and added `$global:GA_MainWindow` fallback.

- **Removed checkboxes from AD Discovery** — Checkbox column removed from DataGrid. `Get-CheckedMachines` now uses DataGrid's built-in `SelectedItems` (blue highlight via click/Shift/Ctrl) instead of `IsChecked` binding.

- **Fixed connectivity test crash** — `Test-MachineConnectivity` used direct property assignment (`$machine.IsOnline = $value`) which fails if the property doesn't exist on the object. Changed to `Add-Member -Force` which creates or overwrites the property safely.

- **Scanner button labels simplified** — "Add from AD Discovery" → "Add", "Remove Selected" → "Remove".

---

## [1.2.4] - 2026-01-30

### Critical Fix — WPF Dispatcher Crash (`Get-Date` not recognized)

- **Write-AppLockerLog now uses only .NET methods** — After ~9 minutes of runtime, WPF delegate/dispatcher contexts in PowerShell 5.1 can lose cmdlet resolution for `Microsoft.PowerShell.Utility` commands. `Get-Date`, `Join-Path`, `Test-Path`, `New-Item`, and `Add-Content` were all replaced with .NET equivalents (`[DateTime]::Now`, `[IO.Path]::Combine()`, `[IO.Directory]::Exists()`, `[IO.Directory]::CreateDirectory()`, `[IO.File]::AppendAllText()`). Also added try/catch fallback for `Get-AppLockerDataPath`.

- **Write-Log safe wrapper hardened** — `global:Write-Log` (UIHelpers.ps1) now wraps the entire call in try/catch. If even `Get-Command` fails in the degraded dispatcher context, falls back to pure .NET file write. Logging must never crash the UI.

---

## [1.2.3] - 2026-01-29

### Remote Scanning & UX Fixes (lab.local continued testing)

- **Credential fallback chain for remote scans** — `Start-ArtifactScan` silently skipped entire tier groups when no stored credential matched (e.g., T1 servers skipped if only T0 credential existed). Now implements 3-level fallback: (1) exact tier credential, (2) try other tiers in order T0→T1→T2, (3) fall back to implicit Windows auth (no `-Credential` parameter). All lab machines now scan regardless of credential configuration.

- **Scan failure feedback UI** — `Invoke-Command` with `ErrorAction SilentlyContinue` silently dropped WinRM failures. Users saw "Scan complete: X artifacts" with no indication machines were skipped. Now shows a `MessageBox` listing failed machines with reasons and troubleshooting tips (WinRM, firewall, credentials). Toast changes from 'Success' to 'Warning' when partial failures occur.

- **AD Discovery auto-refresh on first visit** — `Initialize-DiscoveryPanel` only wired buttons but never loaded data. Users saw an empty panel until manually clicking Refresh. Now auto-triggers domain discovery when navigating to the Discovery panel for the first time.

- **Scanner machine management buttons** — Scanner Machines tab had "Select from AD Discovery" but no way to remove machines. Added "Remove Selected" and "Clear All" buttons. Also added `SelectionMode="Extended"` for Shift+Click and Ctrl+Click multi-select.

- **AD Discovery filter fix** — Filter buttons and text search used `$_.Type` but machine objects from `Get-ComputersByOU` have `$_.MachineType`. Changed to correct property name.

---

## [1.2.2] - 2026-01-29

### Fixes from Lab Testing (lab.local — DC01, SRV01, SRV02)

- **Phantom machine items (0, 1, 2) in Scanner** — `CurrentCellChanged` event on DataGrid fired during internal cell navigation, producing phantom items in the checked machines list. Replaced with `PreviewMouseLeftButtonUp` that walks the WPF visual tree to find the actual `DataGridRow`.

- **Scan crash: "array index evaluated to null"** — Phantom items (integers, not machine objects) were passed to `Start-ArtifactScan` which tried to access `.Hostname` on them. Added validation in both `Get-CheckedMachines` and `Invoke-SelectMachinesForScan` to filter out non-machine objects.

- **Connectivity test hides untested machines** — When testing only checked machines, `$script:DiscoveredMachines` was overwritten with just the tested subset. Now merges results back into the full list by hostname.

- **Machine filter buttons (All/Workstations/Servers/DCs/Online)** — Buttons existed in XAML but had no click handlers. Now wired with filtering logic and active-button highlighting.

- **Machine text filter box** — `MachineFilterBox` existed in XAML but was never wired. Now filters live as you type by Hostname, Type, OS, or OU path.

---

## [1.2.1] - 2026-01-29

### Critical Fixes — User Testing v1.2.0

- **App freeze during connectivity test** (Bug 1): `Test-PingConnectivity` parallel path had unvoided `List<T>.Remove()` calls that leaked `$true` booleans into the pipeline. Function returned `@($true, ..., [hashtable])` instead of just the hashtable, causing `ContainsKey()` to crash on the boolean values. Fixed with `[void]$jobs.Remove($job)`.

- **Machine selection dialog always returned null** (Bug 2): `Show-MachineSelectionDialog` used `$script:DialogResult` inside a `.GetNewClosure()` callback, but closures create a separate module scope — the variable written inside the closure was different from the one read after `ShowDialog()`. Fixed by storing results on `$dialog.Tag` (shared object reference). Added defensive `Hostname` fallback in Scanner.ps1.

### New Features

- **OU TreeView filters machines** (Bug 3): Clicking an OU in the tree now filters the machine DataGrid to show only machines under that OU. Displays "X of Y machines (filtered by OU)" in the count label.

- **Row-click toggles checkbox** (Bug 6): Clicking any cell in a DataGrid row now toggles the machine's checkbox, instead of requiring a direct click on the checkbox cell.

### UI Fixes

- **TreeView white-on-white selection** (Bug 4): Overrode WPF `SystemColors` highlight keys (`HighlightBrushKey`, `HighlightTextBrushKey`, `InactiveSelectionHighlightBrushKey`, `InactiveSelectionHighlightTextBrushKey`) inside the OUTreeView resources for dark-theme-compatible selection colors.

### Testing

- **378/385 tests passing** (same 7 pre-existing GUI type-casting failures — no regressions).

---

## [1.2.0] - 2026-01-29

### Critical Fixes — Remote Scanning & AD Discovery

- **Remote scanning was returning empty data** (C1): `Get-RemoteArtifacts` collected results via `Invoke-Command` but never processed them back into the return object. Added full result processing loop with per-machine tracking, success/failure counts, and error aggregation.

- **Remote scan extension coverage** (C2): Default extensions expanded from 4 types (`.exe .dll .msi .ps1`) to 14 types matching local scan coverage via shared `$script:ArtifactExtensions`.

- **`-Include` without `-Recurse` silent failure** (C3): PowerShell 5.1 quirk where `-Include` is ignored without `-Recurse`. Non-recursive scans now enumerate all files and filter with a `HashSet<string>` of extensions.

- **`Invoke-ScheduledScan` wrong parameter names** (C4): Was using `ScanPaths`/`ScanRemote`/`Computers` — corrected to `Paths`/`ScanLocal`/`Machines` with proper object conversion.

### Performance Improvements

- **Parallel connectivity testing** (H1): `Test-MachineConnectivity` rewritten from sequential `Test-Connection` (~4s timeout per offline machine) to WMI `Win32_PingStatus` with actual timeout control. For >5 machines, uses throttled `Start-Job` parallelism (default 20 concurrent). Extracted `Test-PingConnectivity` for testability.

- **Cached tier mapping** (H2): `Get-MachineTypeFromComputer` was calling `Get-AppLockerConfig` per-machine inside a loop. Added 60-second TTL module-level cache.

- **O(n²) → O(n) array concatenation** (H3): Replaced `$array += $item` patterns with `[System.Collections.Generic.List[object]]` in remote scan scriptblocks and `Get-AppLockerEventLogs`.

### GUI Bug Fixes

- **Emoji crash on PS 5.1**: Replaced codepoints above U+FFFF with BMP-safe characters in AD Discovery panel.
- **Machine checkbox binding**: Fixed XAML `IsChecked` binding, per-column `IsReadOnly`, and duplicate `$_` output.
- **Connectivity test**: Now uses checked machines first, falls back to all machines.
- **Scan target selection**: Scanner uses checked machines from Discovery grid with defensive null fallbacks for `$Extensions`/`$Paths` in runspace contexts.

### Other Fixes

- **Hardcoded module path** (M3): Fixed scheduled scan runner referencing `GA-AppLocker2` instead of current install path.

### Testing

- Updated 10 tests from `Test-Connection` mocks to `Get-WmiObject Win32_PingStatus` mocks.
- Large dataset tests now mock `Test-PingConnectivity` for the parallel job path.
- **378/385 tests passing** (7 pre-existing GUI type-casting failures unrelated to changes).

### Project Cleanup

- Removed stale dev artifacts: `.planning/`, `.sisyphus/`, `baselines/`, `GA-AppLocker/.context/`, `nul`, `docs/archive/`, `docs/project-meta/`, old design/prompt docs
- Updated `.gitignore` to prevent dev artifacts from returning
- Streamlined `Package-Release.ps1` to include only runtime files
- Updated all version references to v1.2.0 across manifests, XAML sidebar, and launcher
- Rewrote README.md to match current feature set

---

## [1.1.1] - 2026-01-29

### AD Discovery LDAP Hardening

- **Centralized LDAP resolution**: New `Resolve-LdapServer` function with priority chain (Parameter → Config → Environment → Domain-joined).
- **Null server crash fix**: All 4 `ViaLdap` functions now validate server before connecting.
- **Removed duplicated resolution logic** from `Get-DomainInfoViaLdap`, `Get-OUTreeViaLdap`, `Get-ComputersByOUViaLdap`, `Test-LdapConnection`.
- **Null-safe RootDSE attributes**: Guard against null returns from LDAP queries.
- **Paged LDAP searches**: Replaced hardcoded `SizeLimit` with `PageSize` for large directories.
- **Credential validation**: Added guard against using credentials without a server target.
- **Cached `Get-ADDomain`**: Avoids redundant AD module calls.
- **Fixed `Set-LdapConfiguration`**: Corrected parameter set for `-Server`/`-Port` usage.
- **Expanded Discovery tests**: 15 → 36 unit tests, plus `verify-discovery.ps1` (27/27 checks).

---

## [1.1.0] - 2026-01-28

### Added
- **Validation Module** (`GA-AppLocker.Validation`): 5-stage policy XML validation pipeline (Schema, GUIDs, SIDs, Conditions, Live Import).
- **Auto-Validation on Policy Export**: `Export-PolicyToXml` runs validation automatically. Use `-SkipValidation` to opt out.
- **Build Script** (`build.ps1`): Air-gapped CI/CD with Analyze → Test → Build → Validate → Package stages.
- **PolicyValidation Unit Tests**: 28 Pester 5 tests covering all 5 validation stages.

---

## [1.0.0] - 2026-01-27

### Fixed
- WPF event handler scope (`global:` prefix on 73 functions across 7 panel files)
- Rule display issues (case-sensitive HashSet, 1000-rule limit, filter button names)
- Select All checkbox state after grid-modifying operations
- Wizard refresh (rules appear immediately after wizard closes)
- Refresh button data loss (`Get-Command` replaced with try-catch in WPF context)

### Added
- GUI unit tests for selection state, rule operations, error handling, filter counts
- Enhanced UI automation helpers (Wait-ForElement, Capture-Screenshot, Assert-Condition)

---

**Full Changelog**: https://github.com/anthonyscry/GA-AppLocker2/commits/main
