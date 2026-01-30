# Changelog

All notable changes to GA-AppLocker will be documented in this file.

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
