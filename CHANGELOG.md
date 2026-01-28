# Changelog

All notable changes to GA-AppLocker will be documented in this file.

## [Unreleased]

### Fixed
- **WPF Event Handler Scope** (`be3c62f`): Added `global:` prefix to 73 functions across 7 panel files, fixing "function not found" errors in WPF button click handlers.

- **Rule Display Issues** (`9bacb82`): 
  - Fixed case-sensitive HashSet in `Remove-RulesFromIndex` causing deleted rules to still appear
  - Added `-Take 100000` parameter to all `Get-AllRules` callers, fixing the 1000-rule display limit
  - Fixed filter button names (`BtnFilterRulesPending` → `BtnFilterPending`) so counts display correctly

- **Select All Checkbox State** (`f7e82c0`): Added `Reset-RulesSelectionState` helper to clear selection state after grid-modifying operations (delete, dedupe, status change, vendor approval).

- **Wizard Refresh** (`4cd8b4e`): Rules created by wizard now appear in Rules panel immediately after wizard closes.

- **Refresh Button Data Loss** (`71231c6`): Replaced `Get-Command` checks with try-catch in storage module functions, fixing the issue where clicking Refresh made rules disappear.

- **Get-Command in WPF Context** (`a85e305`, `c261d61`): Replaced 32 additional `Get-Command` checks across GUI and storage modules. `Get-Command` fails silently in WPF dispatcher context, causing functions to appear unavailable.

### Added
- **GUI Unit Tests** (`1bf23f3`): Added Pester unit tests for GUI logic (`Tests/Unit/GUI.RulesPanel.Tests.ps1`):
  - Selection state management tests
  - Rule operation logic tests
  - Error handling pattern tests
  - Filter button count tests

- **Enhanced UI Automation** (`1bf23f3`): Added new helpers to `FlaUIBot.ps1`:
  - `Wait-ForElement`: Retry logic with configurable timeout
  - `Capture-Screenshot`: Auto-screenshot on test failure
  - `Get-DataGridRowCount`: DataGrid row counting
  - `Assert-Condition`: Assertions with screenshot on failure
  - Bug fix verification tests for recent commits

### Technical Details

#### The Get-Command Problem
`Get-Command -Name 'FunctionName'` returns `$null` in WPF dispatcher context even when the function exists. This affected:
- Function availability checks before calling optional features
- Data path lookups in storage modules
- Cache invalidation calls

**Pattern replaced:**
```powershell
# OLD (fails in WPF)
if (Get-Command -Name 'SomeFunction' -ErrorAction SilentlyContinue) {
    SomeFunction
}

# NEW (works in WPF)
try { SomeFunction } catch { }
```

#### Files Modified
- `GA-AppLocker/GUI/Panels/*.ps1` (7 files)
- `GA-AppLocker/GUI/Wizards/*.ps1` (2 files)
- `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/*.ps1` (4 files)
- `Tests/Unit/GUI.RulesPanel.Tests.ps1` (new)
- `Tests/Automation/UI/FlaUIBot.ps1` (enhanced)

## [1.0.0] - Previous Release

Initial release with full AppLocker policy management capabilities.
