# GA-AppLocker - Prioritized TODO List

Generated from comprehensive review by Architecture, Testing, and UI/UX specialists.

---

## CRITICAL (Must Fix Before Production)

### 1. UI Thread Blocking / DoEvents Anti-Pattern
**Impact**: App freezes during scans, deployments, AD queries
**Location**: `MainWindow.xaml.ps1` (lines ~893, 2390)
**Fix**: 
- Remove all `[System.Windows.Forms.Application]::DoEvents()` calls
- Implement background runspace/job pattern for long operations:
  - `Start-ArtifactScan`
  - `Test-MachineConnectivity`
  - `Start-Deployment`
- Use Dispatcher for UI updates from background threads
**Effort**: Medium (1-2 days)

### 2. Artifact Type Mismatch
**Impact**: UI filters don't work, metrics are wrong
**Location**: 
- `GA-AppLocker.Scanning.psm1` returns: `Executable`, `Library`, `Installer`, etc.
- `MainWindow.xaml.ps1` expects: `EXE`, `DLL`, `MSI`, etc.
**Fix**: Standardize `ArtifactType` values in scanning module to match UI expectations
**Effort**: Quick (30 min)

### 3. Rule/Policy Schema Mismatch
**Impact**: Policy XML export generates malformed or empty XML
**Location**:
- `GA-AppLocker.Rules.psm1` uses: `CollectionType`, `RuleType`
- `Export-PolicyToXml.ps1` expects: `RuleCollection`, `BinaryVersionLow`, etc.
**Fix**: 
- Define canonical rule schema
- Reuse `ConvertTo-AppLockerXmlRule` from Rules module in Policy export
**Effort**: Medium (2-4 hours)

### 4. Deployment Returns False Success
**Impact**: Operators think deployment succeeded when it didn't
**Location**: 
- `GPO-Functions.ps1` - returns `Success=$true` when modules missing
- `Start-Deployment.ps1` - OU linking is stubbed out
**Fix**:
- Return `Success=$false` when GroupPolicy/AD modules unavailable
- Mark deployment as `ManualRequired` if linking not implemented
**Effort**: Quick (1 hour)

---

## HIGH (Should Fix Soon)

### 5. Remote Scanning Not Parallelized
**Impact**: Enterprise scans take hours instead of minutes
**Location**: `Get-RemoteArtifacts.ps1` - sequential foreach loop
**Fix**: Use `Invoke-Command -ComputerName $ComputerName -ThrottleLimit $N`
**Effort**: Medium (2-4 hours)

### 6. Global Scope Pollution
**Impact**: Module import modifies global session, conflicts with other tools
**Location**: `MainWindow.xaml.ps1` - `global:Invoke-ButtonAction`, `global:GA_MainWindow`, etc.
**Fix**: Replace `global:` with `script:`, use single `$script:AppState` object
**Effort**: Medium (2-3 hours)

### 7. Excessive MessageBox Dialogs
**Impact**: Breaks dark theme immersion, interrupts workflow
**Location**: Throughout `MainWindow.xaml.ps1` (~50+ MessageBox calls)
**Fix**: Implement toast/snackbar notification system for non-critical alerts
**Effort**: Medium (3-4 hours)

### 8. Missing Test Coverage (15 Functions)
**Impact**: Bugs ship to production undetected
**Untested Functions**:
- `Test-CredentialProfile`
- `Export-ScanResults`
- `Get-Rule`, `Remove-Rule`, `Set-RuleStatus`, `Export-RulesToXml`
- `Add-RuleToPolicy`, `Remove-RuleFromPolicy`, `Export-PolicyToXml`, `Test-PolicyCompliance`
- `Start-Deployment`, `New-AppLockerGPO`, `Import-PolicyToGPO`, `Get-DeploymentHistory`
**Fix**: Add tests for each function
**Effort**: Medium (3-4 hours)

---

## MEDIUM (Should Address)

### 9. Weak Test Assertions
**Impact**: Tests pass when functions actually fail
**Location**: Tests 6, 7, 14, 19, 21, 22 in `Test-AllModules.ps1`
**Fix**: Change from property existence checks to `$obj.Success -eq $true` + data validation
**Effort**: Quick (1 hour)

### 10. Error Swallowing (Empty Catch Blocks)
**Impact**: Silent failures, broken state persists
**Location**: Multiple catches in `MainWindow.xaml.ps1` and module loaders
**Fix**: Replace empty catches with logging + user notification
**Effort**: Quick (1 hour)

### 11. Missing Edge Case Tests
- Invalid GUIDs to `Get-Policy`, `Get-DeploymentJob`
- Null/empty strings to required parameters
- Large datasets (1000+ artifacts)
- Permission denied scenarios
- Network timeout simulations
**Effort**: Medium (2-3 hours)

### 12. No End-to-End Workflow Tests
Missing integration tests for:
- Scan → Rules → Policy → XML Export
- Create Policy → Create Job → Deploy → Verify
**Effort**: Medium (2-3 hours)

### 13. Hardcoded Configuration Values
**Impact**: Inconsistent behavior across environments
**Location**: Default scan paths duplicated in config, module, and UI
**Fix**: Single source of truth in config; UI/modules read from config
**Effort**: Quick (1 hour)

### 14. AD Tier Classification is Heuristic
**Impact**: Wrong credentials used for scans
**Location**: `Get-OUTree.ps1`, `Get-ComputersByOU.ps1` - regex on OU names
**Fix**: Make tier mapping configurable in settings
**Effort**: Quick (1 hour)

---

## LOW (Nice to Have)

### 15. Accessibility Issues
- No keyboard focus indicators on custom buttons
- Unicode icons unreadable by screen readers
- Contrast may fail WCAG AA for muted text
**Fix**: Add `FocusVisualStyle`, `AutomationProperties.Name`, increase contrast
**Effort**: Medium (2-3 hours)

### 16. Workflow Disconnects
- No visual indicator of staged machines between panels
- Session state lost on app restart
**Fix**: Add breadcrumbs/wizard guide, persist session to disk
**Effort**: Medium (3-4 hours)

### 17. Visual Polish
- "Loading..." text instead of spinners
- DataGrids lack sorting feedback
- Inconsistent margins/padding
**Fix**: Add progress indicators, sorting, standardize spacing
**Effort**: Medium (2-3 hours)

### 18. Module Loader Inconsistency
**Impact**: Function load-order bugs, maintenance burden
**Location**: Different loading patterns across modules
**Fix**: Standardize all modules to same loading pattern
**Effort**: Quick (1 hour)

### 19. Thread-Safety Claims in Logging
**Impact**: Misleading documentation
**Location**: `Write-AppLockerLog.ps1` claims mutex but uses `Add-Content`
**Fix**: Remove claim or implement proper mutex
**Effort**: Quick (30 min)

### 20. README Claims MVVM
**Impact**: Confuses developers
**Location**: `GA-AppLocker.psd1` and documentation
**Fix**: Update docs to match reality (code-behind pattern)
**Effort**: Quick (15 min)

---

## Quick Wins (Can Do Today)

| # | Task | Time | Impact | Status |
|---|------|------|--------|--------|
| 1 | Standardize ArtifactType values | 30 min | Critical | DONE |
| 2 | Fix deployment false success | 1 hr | Critical | DONE |
| 3 | Remove DoEvents() calls | 30 min | Critical | DONE |
| 4 | Strengthen test assertions | 1 hr | High | DONE |
| 5 | Fix empty catch blocks | 1 hr | Medium | DONE |
| 6 | Config as single source of truth | 1 hr | Medium | Pending |
| 7 | Update MVVM claim in docs | 15 min | Low | DONE |

---

## Recommended Priority Order

1. ~~**Day 1**: Quick wins #1-4 (Critical fixes)~~ COMPLETE
2. **Day 2**: Async wrapper for UI operations (Critical #1)
3. **Day 3**: Rule/Policy schema alignment (Critical #3)
4. **Week 2**: Missing tests + edge cases (High #8, Medium #11-12)
5. **Week 3**: UI polish + accessibility (Low items)

---

## Notes

- All Critical items should be addressed before any production deployment
- High items represent significant risk or technical debt
- Testing improvements (items 8-12) will pay dividends long-term
- UI improvements can be done incrementally without breaking functionality
