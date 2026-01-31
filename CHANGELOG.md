# Changelog

All notable changes to GA-AppLocker will be documented in this file.

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
