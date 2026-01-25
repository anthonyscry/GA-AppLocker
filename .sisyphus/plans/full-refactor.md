# GA-AppLocker2 Full Refactoring Plan (Final v6)

## Context
User requested complete refactoring of GA-AppLocker2 for better performance and maintainability.

### Key Decisions
- Primary Goal: Full overhaul (performance + code quality)
- Risk Tolerance: Aggressive
- Test Strategy: TDD
- Rollback: Feature branch + atomic commits
- Performance Target: GlobalSearch < 1 second

### Research Findings
- Project: ~40,500 LOC, 135 PS files, 182 functions
- God Objects: Rules.ps1 (1,645 LOC), Scanner.ps1 (1,599 LOC)
- Async Pattern: GA-AppLocker/GUI/Helpers/AsyncHelpers.ps1
- Cache API: GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Cache-Manager.ps1

---

## Work Objectives

### Definition of Done
- All tests pass (Test-AllModules.ps1 + Invoke-Pester Tests/Unit/)
- GlobalSearch < 1 second for 35,000 rules
- No UI freezes > 100ms
- Rules.ps1 < 500 LOC
- Scanner.ps1 < 500 LOC

### Guardrails
- NO feature additions (except wiring pre-existing code in 3.3)
- NO scope creep
- NO combined tasks

---

## Verification Procedures

### Test Commands
.\Test-AllModules.ps1
Invoke-Pester -Path Tests/Unit/ -PassThru

### Performance Measurement Procedure
Dataset Setup: Run app with existing rules database (35,000+ rules from production use)
If no data: Generate test rules via Tests/Automation/MockData/New-MockTestData.psm1

Measurement Script:
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Invoke-GlobalSearch -Query "test"
  $sw.Stop()
  Write-Host "GlobalSearch: $($sw.ElapsedMilliseconds)ms"
  # PASS: < 1000ms

### Memory Measurement Procedure
  $baseline = (Get-Process -Id $PID).WorkingSet64 / 1MB
  for ($i = 0; $i -lt 10; $i++) {
    Set-ActivePanel -PanelName "PanelRules"
    Start-Sleep -Milliseconds 100
    Set-ActivePanel -PanelName "PanelScanner"
    Start-Sleep -Milliseconds 100
  }
  $after = (Get-Process -Id $PID).WorkingSet64 / 1MB
  Write-Host "Memory: baseline=${baseline}MB after=${after}MB growth=$($after-$baseline)MB"
  # PASS: growth < 10MB

### Baseline File Format (baselines/*.txt)
  Date: [ISO 8601]
  Git Commit: [git rev-parse --short HEAD]
  Test Results: [PASS]/[TOTAL]
  GlobalSearch Time: [X]ms
  Memory: baseline=[Y]MB after=[Z]MB growth=[delta]MB

---

## TODOs

### Phase 0: Setup and Baselines

- [x] 0.1. Create Feature Branch and Capture Baselines
  What: git checkout -b refactor/full-overhaul; run tests; measure perf/memory
  Steps:
    mkdir baselines
    git checkout -b refactor/full-overhaul
    .\Test-AllModules.ps1 > baselines/test-baseline.txt
    Run perf/memory procedures above, append to file
  Accept: Branch exists, baselines/test-baseline.txt matches schema
  Commit: chore(refactor): capture baselines

### Phase 1: Critical Performance

- [x] 1.1. Add Debouncing to GlobalSearch
  What: Add DispatcherTimer (300ms), create tests
  Timer scope: $script:SearchDebounceTimer

  Test File: Tests/Unit/GlobalSearch.Debounce.Tests.ps1
  Test Strategy: Mock DispatcherTimer, verify callback timing
  Assertions:
    - Invoke-GlobalSearch called 0 times during rapid input
    - Invoke-GlobalSearch called 1 time after 300ms pause
    - Timer reset on each keystroke

  Refs:
    - GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:26 (TextChanged)
    - GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:117 (Invoke-GlobalSearch)

  Accept:
    - Test file exists and passes: Invoke-Pester Tests/Unit/GlobalSearch.Debounce.Tests.ps1
    - Manual: Type "test" rapidly, observe single search after pause
  Commit: perf(search): add 300ms debouncing

- [x] 1.2. Replace Where-Object with .Where Method
  What: Replace Where-Object at lines 139, 150, 162, 176

  Scope: Only these 4 occurrences in Invoke-GlobalSearch function
  Verification Command (scoped):
    Select-String -Path "GA-AppLocker/GUI/Helpers/GlobalSearch.ps1" -Pattern "Where-Object" | 
      Where-Object { $_.LineNumber -ge 117 -and $_.LineNumber -le 200 }
    # PASS: Returns nothing

  Refs: GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:139,150,162,176
  Accept: Scoped verification returns no matches, tests pass
  Commit: perf(search): replace Where-Object with .Where()

- [x] 1.3. Integrate Cache-Manager
  What: Use Get-CachedValue, add invalidation hooks
  TTL: 60s

  Cache Keys: GlobalSearch_AllRules, GlobalSearch_AllPolicies

  Invalidation Hook Locations:
    - GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/Get-Rule.ps1:241 (Remove-Rule)
    - GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/BulkOperations.ps1:10 (Save-RulesBulk)
    - GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/New-Policy.ps1:1 (New-Policy)
    - GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Manage-PolicyRules.ps1:1 (Add-RuleToPolicy)
    - GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Manage-PolicyRules.ps1:73 (Remove-RuleFromPolicy)

  Test File: Tests/Unit/GlobalSearch.Cache.Tests.ps1
  Test Strategy: Mock Get-CachedValue, verify keys and TTL
  Assertions:
    - First search calls Get-AllRules/Get-AllPolicies
    - Repeat search uses cached value (mock verifies no new calls)
    - After mutation, cache is invalidated

  Repeat Search Verification:
    $sw1 = [Diagnostics.Stopwatch]::StartNew(); Invoke-GlobalSearch -Query "a"; $sw1.Stop()
    $sw2 = [Diagnostics.Stopwatch]::StartNew(); Invoke-GlobalSearch -Query "a"; $sw2.Stop()
    # PASS: $sw2.ElapsedMilliseconds < 50

  Accept: Tests pass, repeat search < 50ms
  Commit: perf(search): integrate Cache-Manager

- [ ] 1.4. Move GlobalSearch to Background Runspace
  What: Use Invoke-AsyncOperation from AsyncHelpers.ps1

  AsyncHelpers Contract (splat at line 113):
    $result = & $ScriptBlock @Arguments

  Implementation:
    Invoke-AsyncOperation -ScriptBlock {
      param($Query, $AllRules, $AllPolicies)
      @{
        Rules = $AllRules.Where({ $_.Name -like "*$Query*" })
        Policies = $AllPolicies.Where({ $_.Name -like "*$Query*" })
      }
    } -Arguments @{
      Query = $searchText
      AllRules = (Get-AllRules).Data
      AllPolicies = (Get-AllPolicies).Data
    } -OnComplete {
      param($Result)
      Update-SearchResultsPopup -Results $Result
    } -LoadingMessage "Searching..."

  Loading Indicator: Set $script:SearchPanel.Visibility = "Visible" before, "Collapsed" in OnComplete
  Error Handling: OnComplete receives $null on error, show toast

  Test File: Tests/Unit/GlobalSearch.Async.Tests.ps1
  Test Strategy: Mock Invoke-AsyncOperation, verify args and callback
  Assertions:
    - Invoke-AsyncOperation called with correct Arguments hashtable
    - OnComplete receives Result parameter
    - Update-SearchResultsPopup called with results

  Manual Verification: Type search, observe loading indicator, results appear

  Accept: Tests pass, UI responsive during search
  Commit: perf(search): move to background runspace

- [x] 1.5. Remove Start-Sleep from DragDropHelpers
  What: Replace Start-Sleep (232,237,243) with DispatcherTimer

  Verification (scoped):
    Select-String -Path "GA-AppLocker/GUI/Helpers/DragDropHelpers.ps1" -Pattern "Start-Sleep"
    # PASS: Returns nothing

  Manual Verification: Drag file onto Scanner panel, observe no freeze

  Accept: No Start-Sleep, drag-drop works
  Commit: perf(dragdrop): replace Start-Sleep

### Phase 2: Memory Leak Fixes
- [ ] 2.1. Fix ADDiscovery Handler Accumulation
  What: Add handler cleanup in panel unload/switch
  Problem: btnRefresh and btnTest Click handlers accumulate on panel switches
  Solution: Store handlers in $script: variables, remove before re-adding
  Controls (verified via XAML):
    - btnRefresh (Button)
    - btnTest (Button)
  Pattern:
    # At panel initialization
    $script:ADDiscovery_btnRefresh_Click = { ... }
    $Window.FindName("btnRefresh").Add_Click($script:ADDiscovery_btnRefresh_Click)
    # At panel unload (Set-ActivePanel switching away)
    $Window.FindName("btnRefresh").Remove_Click($script:ADDiscovery_btnRefresh_Click)
  Refs:
    - GA-AppLocker/GUI/Panels/ADDiscovery.ps1:45-80 (handler registrations)
    - GA-AppLocker/GUI/MainWindow.xaml.ps1:187 (Set-ActivePanel)
  Test File: Tests/Unit/ADDiscovery.Handlers.Tests.ps1
  Test Strategy: Mock button controls, verify Add_Click/Remove_Click calls
  Assertions:
    - Remove_Click called before Add_Click on panel re-entry
    - Handler count stays at 1 after 5 panel switches
    - No errors when switching away from uninitialized panel
  Manual Verification:
    1. Open app, navigate to AD Discovery panel
    2. Switch to another panel and back 10 times
    3. Click btnRefresh once
    4. Verify only 1 action occurs (not 10)
  Accept: Tests pass, single handler after multiple switches
  Commit: fix(addiscovery): prevent handler accumulation
- [ ] 2.2. Fix Credentials Handler Accumulation
  What: Same pattern as 2.1 for Credentials panel
  Controls (verified via XAML):
    - btnSave (Button)
    - btnRefresh (Button)
    - btnTest (Button)
    - btnDelete (Button)
    - btnSetDefault (Button)
  Pattern: Same as 2.1 - store in $script:Credentials_btnX_Click, remove before add
  Refs:
    - GA-AppLocker/GUI/Panels/Credentials.ps1:30-120 (handler registrations)
    - GA-AppLocker/GUI/MainWindow.xaml.ps1:187 (Set-ActivePanel)
  Test File: Tests/Unit/Credentials.Handlers.Tests.ps1
  Test Strategy: Mock button controls, verify cleanup sequence
  Assertions:
    - All 5 buttons have Remove_Click called before Add_Click
    - Handler count stays at 1 per button after 5 switches
  Manual Verification: Same as 2.1 but for Credentials panel
  Accept: Tests pass, handlers cleaned up properly
  Commit: fix(credentials): prevent handler accumulation
- [ ] 2.3. Fix GlobalSearch Closure Leaks
  What: Clean up mouse event handlers on popup elements
  Problem: MouseEnter/MouseLeave/MouseLeftButtonDown handlers capture closures
  Events and Lines (verified):
    - MouseEnter: line 314
    - MouseLeave: line 318
    - MouseLeftButtonDown: line 324
  Solution: Store in $script: variables, remove on popup close
  Refs:
    - GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:314 (MouseEnter)
    - GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:318 (MouseLeave)
    - GA-AppLocker/GUI/Helpers/GlobalSearch.ps1:324 (MouseLeftButtonDown)
  Test File: Tests/Unit/GlobalSearch.Memory.Tests.ps1
  Test Strategy: Create mock result items, verify cleanup calls
  Assertions:
    - Remove_MouseEnter called for each item on popup close
    - Remove_MouseLeave called for each item on popup close
    - Remove_MouseLeftButtonDown called for each item on popup close
  Accept: Tests pass, memory growth < 5MB after 20 cycles
  Commit: fix(search): prevent closure leaks in popup
### Phase 3: Code Decomposition
- [ ] 3.1. Extract Rules.ps1 Business Logic
  What: Move business logic from Rules.ps1 (1,645 LOC) to backend module
  Target: GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/RulesUILogic.ps1
  Extraction Contract:
    - NO $Window references in extracted module
    - NO WPF dependencies
    - Pure functions with parameters and return values
    - UI file calls module functions, receives data, updates UI
  Functions to Extract (identified in code):
    - Validate-RuleData (input validation)
    - Format-RuleForDisplay (data transformation)
    - Build-RuleTree (tree structure generation)
    - Filter-RulesByType (filtering logic)
    - Sort-RulesByPriority (sorting logic)
    - Merge-RuleConflicts (conflict resolution)
  Refs:
    - GA-AppLocker/GUI/Panels/Rules.ps1 (full file - identify functions)
    - GA-AppLocker/Modules/GA-AppLocker.Rules/ (target module)
  Test File: Tests/Unit/RulesUILogic.Tests.ps1
  Test Strategy: Unit test pure functions with mock data
  Assertions:
    - Validate-RuleData returns correct validation for valid/invalid input
    - Build-RuleTree produces expected tree structure
    - No $Window or WPF types referenced in module
  Verification Commands:
    Select-String -Path "GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/RulesUILogic.ps1" -Pattern '$Window'
    # PASS: Returns nothing
    (Get-Content "GA-AppLocker/GUI/Panels/Rules.ps1").Count
    # PASS: < 500
  Accept: Tests pass, Rules.ps1 < 500 LOC, no $Window in module
  Commit: refactor(rules): extract business logic to module
- [ ] 3.2. Extract Scanner.ps1 Business Logic
  What: Move business logic from Scanner.ps1 (1,599 LOC) to backend module
  Target: GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/ScannerUILogic.ps1
  Extraction Contract: Same as 3.1 (no $Window, pure functions)
  Functions to Extract:
    - Validate-ScanPath (path validation)
    - Build-ScanResults (result aggregation)
    - Filter-ScanResults (filtering logic)
    - Format-ScanResultForDisplay (data transformation)
    - Calculate-ScanProgress (progress calculation)
    - Aggregate-ScanStatistics (statistics)
  Refs:
    - GA-AppLocker/GUI/Panels/Scanner.ps1 (full file)
    - GA-AppLocker/Modules/GA-AppLocker.Scanning/ (target module)
  Test File: Tests/Unit/ScannerUILogic.Tests.ps1
  Test Strategy: Unit test pure functions
  Assertions:
    - Validate-ScanPath handles valid/invalid/UNC paths
    - Build-ScanResults aggregates correctly
    - No $Window references
  Verification Commands:
    Select-String -Path "GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/ScannerUILogic.ps1" -Pattern '$Window'
    # PASS: Returns nothing
    (Get-Content "GA-AppLocker/GUI/Panels/Scanner.ps1").Count
    # PASS: < 500
  Accept: Tests pass, Scanner.ps1 < 500 LOC, no $Window in module
  Commit: refactor(scanner): extract business logic to module
- [ ] 3.3. Wire Dead Code to UI
  What: Connect existing backend functions to XAML controls
  Guardrail: This is NOT new functionality. The code EXISTS but is not wired.
  Dead Functions (verified to exist in backend):
    - Invoke-Deduplication (GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/Deduplication.ps1)
    - Set-ExclusionFilter (GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Exclusions.ps1)
  XAML Controls to Add (to Scanner.xaml):
    - ComboBox x:Name="CboDedupeMode"
    - Button x:Name="BtnDedupeArtifacts" Content="Deduplicate"
    - CheckBox x:Name="ChkExcludeDll" Content="Exclude DLLs"
    - CheckBox x:Name="ChkExcludeJs" Content="Exclude JS"
    - CheckBox x:Name="ChkExcludeScripts" Content="Exclude Scripts"
    - CheckBox x:Name="ChkExcludeUnsigned" Content="Exclude Unsigned"
    - Button x:Name="BtnApplyExclusions" Content="Apply Exclusions"
  Refs:
    - GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/Deduplication.ps1
    - GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Exclusions.ps1
    - GA-AppLocker/GUI/Panels/Scanner.xaml (add controls)
    - GA-AppLocker/GUI/Panels/Scanner.ps1 (add handlers)
  Test File: Tests/Unit/Scanner.DeadCodeWiring.Tests.ps1
  Test Strategy: Mock controls and backend functions, verify wiring
  Assertions:
    - BtnDedupeArtifacts Click calls Invoke-Deduplication
    - BtnApplyExclusions Click calls Set-ExclusionFilter with correct params
    - Checkbox states correctly passed to filter
  Accept: Tests pass, controls visible and functional
  Commit: feat(scanner): wire dead deduplication and exclusion code
### Phase 4: Code Quality
- [ ] 4.1. Deduplicate DragDropHelpers Registration
  What: Extract common drag-drop registration pattern to shared function
  Current State: 3 identical patterns in DragDropHelpers.ps1
  Extract to:
    function Register-DragDropHandlers {
      param(
        [System.Windows.UIElement]$Target,
        [scriptblock]$OnDrop,
        [scriptblock]$OnDragEnter,
        [scriptblock]$OnDragLeave
      )
      $Target.AllowDrop = $true
      $Target.Add_Drop($OnDrop)
      $Target.Add_DragEnter($OnDragEnter)
      $Target.Add_DragLeave($OnDragLeave)
    }
  Refs:
    - GA-AppLocker/GUI/Helpers/DragDropHelpers.ps1 (full file)
  Test File: Tests/Unit/DragDropHelpers.Tests.ps1
  Test Strategy: Mock UIElement, verify event registration
  Assertions:
    - AllowDrop set to $true
    - Add_Drop called with scriptblock
    - Add_DragEnter called with scriptblock
    - Add_DragLeave called with scriptblock
  Verification:
    (Select-String -Path "GA-AppLocker/GUI/Helpers/DragDropHelpers.ps1" -Pattern "AllowDrop = `$true").Count
    # PASS: 1 (only in the shared function)
  Accept: Single pattern, tests pass
  Commit: refactor(dragdrop): deduplicate registration pattern
- [ ] 4.2. Reduce global: Scope Variables
  What: Convert $global: to $script: where possible
  Strategy: Audit all $global: usages, convert to $script: if module-local
  Candidates (identified in codebase):
    - $global:AppConfig -> $script:AppConfig (if only used in one file)
    - $global:CurrentSession -> $script:CurrentSession
    - $global:Cache -> keep as $global: (cross-module)
  Refs:
    - All .ps1 files (grep for $global:)
  Verification:
    (Select-String -Path "GA-AppLocker/**/*.ps1" -Pattern '$global:' -Recurse).Count
    # Note starting count, reduce by at least 50%
  Accept: 50% reduction in $global: usage, all tests pass
  Commit: refactor(scope): reduce global variables
- [ ] 4.3. Remove Dead/Commented Code
  What: Remove identified dead code and old comments
  Targets:
    - Commented-out code blocks
    - Unused functions (identified via static analysis)
    - TODO/FIXME comments older than 6 months
  Verification:
    Select-String -Path "GA-AppLocker/**/*.ps1" -Pattern '^\s*#\s*(function|if|for|while|$)' -Recurse
    # Reduce count significantly
  Accept: Cleaner codebase, tests pass
  Commit: chore(cleanup): remove dead code and stale comments
### Phase 5: Final Verification
- [ ] 5.1. Integration Testing and Performance Verification
  What: Full test suite + performance measurement
  Steps:
    1. Run all tests: .\Test-AllModules.ps1 && Invoke-Pester Tests/Unit/
    2. Run performance measurement (see Verification Procedures)
    3. Run memory measurement (see Verification Procedures)
    4. Compare to baselines/test-baseline.txt
  Performance Targets:
    - GlobalSearch: < 1000ms (was likely 3000-5000ms)
    - Memory growth after 10 panel switches: < 10MB
    - All tests: PASS
  Create: baselines/post-refactor.txt with same format
  Accept:
    - All tests pass
    - GlobalSearch < 1000ms
    - Memory growth < 10MB
    - baselines/post-refactor.txt created
  Commit: chore(verify): integration testing complete
- [ ] 5.2. Merge to Main
  What: Create PR or merge directly
  Pre-merge Checklist:
    - All tests pass (verified in 5.1)
    - Performance targets met (verified in 5.1)
    - Code review completed (if team)
    - No merge conflicts
  Steps:
    git checkout main
    git merge refactor/full-overhaul --no-ff -m "refactor: complete performance and code quality overhaul"
    git push origin main
  Accept: Merged to main, branch can be deleted
  Commit: N/A (merge commit)
---
## Task Flow and Dependencies
Phase 0: [0.1 Setup]
           |
Phase 1: [1.1 Debounce] -> [1.2 Where] -> [1.3 Cache] -> [1.4 Async]
         [1.5 Sleep] (parallel with 1.1-1.4)
           |
Phase 2: [2.1 ADDiscovery] | [2.2 Credentials] | [2.3 GlobalSearch] (all parallel)
           |
Phase 3: [3.1 Rules] | [3.2 Scanner] (parallel) -> [3.3 Wire Dead Code]
           |
Phase 4: [4.1 DragDrop] | [4.2 Scope] | [4.3 Dead Code] (all parallel)
           |
Phase 5: [5.1 Verify] -> [5.2 Merge]
## Parallelization Summary
| Phase | Parallel Groups |
|-------|-----------------|
| 1 | 1.5 can run parallel with 1.1-1.4 |
| 2 | All tasks (2.1, 2.2, 2.3) parallel |
| 3 | 3.1 and 3.2 parallel, then 3.3 |
| 4 | All tasks (4.1, 4.2, 4.3) parallel |
| 5 | Sequential |
---
## Success Criteria Summary
| Metric | Target | Verification |
|--------|--------|--------------|
| GlobalSearch time | < 1000ms | Performance measurement |
| Memory growth | < 10MB after 10 switches | Memory measurement |
| Rules.ps1 LOC | < 500 | Line count |
| Scanner.ps1 LOC | < 500 | Line count |
| Tests | All pass | Test-AllModules.ps1 |
| Handler accumulation | 0 | Manual + unit tests |
