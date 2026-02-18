---
phase: 09-rule-generation-from-event-selections
plan: 01
subsystem: ui
tags: [wpf, xaml, event-viewer, applocker, rule-generation, powershell]

# Dependency graph
requires:
  - phase: 08-event-triage-and-inspection-workbench
    provides: EventViewer panel with filter/inspect workbench and $script:EventViewerFileMetrics populated from query results
provides:
  - RbEvtRuleAllow and RbEvtRuleDeny RadioButtons in Event Viewer panel XAML toolbar
  - CboEvtRuleTargetGroup ComboBox with 5 group targets in Event Viewer panel XAML toolbar
  - Fixed Get-EventViewerRuleDefaults reading new XAML control names with defensive null checks
  - Enhanced Confirm-EventViewerRuleGeneration with candidate frequency summary from $script:EventViewerFileMetrics
affects:
  - 09-02 (rule creation async pipeline uses defaults from Get-EventViewerRuleDefaults)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WPF RadioButton pair for Allow/Deny action selection with RbEvt* prefix to avoid Rules panel collision"
    - "Frequency-annotated confirmation dialog using script-scope hashtable lookup before MessageBox"
    - "Confirm function accepts candidate array (not count) for rich pre-creation summary"

key-files:
  created: []
  modified:
    - GA-AppLocker/GUI/MainWindow.xaml
    - GA-AppLocker/GUI/Panels/EventViewer.ps1

key-decisions:
  - "Use RbEvt*/CboEvt* naming prefix for Event Viewer rule controls to prevent x:Name collisions with Rules panel controls"
  - "Confirm-EventViewerRuleGeneration accepts [PSCustomObject[]]$Candidates (not [int]$Count) so it can show per-file frequency data"
  - "Frequency lookup uses $script:EventViewerFileMetrics (already populated by Update-EventViewerResultBindings) keyed by FilePath.ToLowerInvariant() to avoid runspace scope access"
  - "Display cap at 10 candidate lines with '... and N more' suffix prevents oversized confirmation dialogs on large selections"

patterns-established:
  - "Defensive FindName pattern: check PSObject.Properties.Name contains 'IsChecked' before accessing .IsChecked on RadioButton"
  - "Default-to-Allow logic: only check RbEvtRuleDeny.IsChecked == true; no need to check RbEvtRuleAllow since Allow is the default"

requirements-completed: [GEN-01, GEN-02, GEN-03, GEN-04]

# Metrics
duration: 5min
completed: 2026-02-18
---

# Phase 9 Plan 01: Rule Generation from Event Selections Summary

**Operator-controlled Allow/Deny + target group controls added to Event Viewer XAML toolbar, with frequency-annotated confirmation dialog showing per-file event counts before bulk rule creation**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-18T23:51:23Z
- **Completed:** 2026-02-18T23:56:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added three XAML controls to Event Viewer panel (RbEvtRuleAllow, RbEvtRuleDeny, CboEvtRuleTargetGroup) enabling operator control of rule action and target group
- Fixed Get-EventViewerRuleDefaults to read the new control names (was referencing non-existent RbRuleAllow/CboRuleTargetGroup); added PSObject.Properties defensive null checks
- Enhanced Confirm-EventViewerRuleGeneration to accept the candidate array and display deduplicated per-file frequency counts (Events/Blocked/Audit) from $script:EventViewerFileMetrics, capped at 10 lines

## Task Commits

Each task was committed atomically:

1. **Task 1: Add rule action and target group XAML controls to Event Viewer panel** - `523170a` (feat)
2. **Task 2: Fix Get-EventViewerRuleDefaults and enhance Confirm-EventViewerRuleGeneration** - `ae416a1` (feat)

**Plan metadata:** (docs commit - see below)

## Files Created/Modified

- `GA-AppLocker/GUI/MainWindow.xaml` - Added RbEvtRuleAllow, RbEvtRuleDeny RadioButtons and CboEvtRuleTargetGroup ComboBox to Event Viewer toolbar (11 lines added)
- `GA-AppLocker/GUI/Panels/EventViewer.ps1` - Fixed Get-EventViewerRuleDefaults (new XAML names + defensive checks), enhanced Confirm-EventViewerRuleGeneration (candidates array + frequency block), updated call site

## Decisions Made

- Used `RbEvt*`/`CboEvt*` naming prefix to prevent x:Name collisions with Rules panel controls that use `Rb`/`Cbo` prefixes
- `Confirm-EventViewerRuleGeneration` now accepts `[PSCustomObject[]]$Candidates` instead of `[int]$Count` - the count is derived internally, and the candidate objects enable per-file frequency lookups
- Frequency lookup uses `$script:EventViewerFileMetrics` (populated by `Update-EventViewerResultBindings` when query results bind) keyed by `FilePath.ToLowerInvariant()` - avoids any runspace scope access risk
- Default-to-Allow logic only checks `RbEvtRuleDeny.IsChecked -eq $true`; no need to check Allow radio since Allow is the programmatic default

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - straightforward implementation. The XAML StackPanel at Grid.Row=1 Grid.Column=1 (containing CboEventViewerRuleMode) was extended inline with the three new controls rather than creating a separate StackPanel, which kept the layout compact and consistent.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- XAML controls are in place and wired; `Get-EventViewerRuleDefaults` reads them correctly
- `Confirm-EventViewerRuleGeneration` now shows enriched pre-creation summary
- Ready for Phase 9 Plan 02 (remaining rule generation pipeline wiring or behavioral tests)

---
*Phase: 09-rule-generation-from-event-selections*
*Completed: 2026-02-18*
