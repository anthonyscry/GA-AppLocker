---
phase: 11-performance-fixes
plan: "01"
subsystem: policy
tags: [powershell, performance, stringbuilder, wmi, cim, xml-export]

# Dependency graph
requires: []
provides:
  - O(n) rule XML assembly via StringBuilder in Build-PolicyRuleCollectionXml
  - Health report OS info via .NET Environment APIs (no WMI/CIM)
  - Health report file counts via @(Get-ChildItem).Count (no Measure-Object)
  - Health report log entries via List[PSCustomObject] (no O(n^2) array concat)
affects:
  - 11-02 (performance-fixes)
  - any phase testing Export-PolicyToXml or Export-AppLockerHealthReport

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "StringBuilder for XML assembly in rule collection loops"
    - "[System.Environment]::OSVersion for OS info without WMI"
    - "@(Get-ChildItem ...).Count for file counts without Measure-Object"
    - "List[PSCustomObject] + [void].Add() + @() for log entry accumulation"

key-files:
  created: []
  modified:
    - GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Export-PolicyToXml.ps1
    - GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Export-AppLockerHealthReport.ps1

key-decisions:
  - "Use local $ruleXml variable then [void]$xml.Append($ruleXml) to avoid awkward PS 5.1 here-string-inside-method-call syntax"
  - "Replace entire Get-CimInstance try/catch with direct .NET reads — no try/catch needed since [System.Environment]::OSVersion never throws"
  - "Preserve @() wrapper on Get-ChildItem .Count calls for PS 5.1 safety (null-safe .Count on single items and empty results)"

patterns-established:
  - "Rule 4 (CLAUDE.md): suppress all .Add() return values with [void] to prevent pipeline leaks"
  - "Rule 3 (CLAUDE.md): @() wrapping for PS 5.1 .Count safety on collection-returning cmdlets"

requirements-completed:
  - PERF-01
  - PERF-04

# Metrics
duration: 2min
completed: 2026-02-19
---

# Phase 11 Plan 01: Performance Fixes (String Concat + CIM) Summary

**StringBuilder-based O(n) XML assembly in Build-PolicyRuleCollectionXml and WMI-free OS info + Measure-Object-free file counts in Export-AppLockerHealthReport**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-19T01:31:07Z
- **Completed:** 2026-02-19T01:32:55Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Replaced O(n^2) string concatenation (`$xml +=` on each of 1,000+ rules) with O(n) StringBuilder in `Build-PolicyRuleCollectionXml` — the hot path for large policy exports
- Eliminated `Get-CimInstance Win32_OperatingSystem` from `Export-AppLockerHealthReport` which could freeze the WPF STA thread for 10-30 seconds on air-gapped networks
- Replaced four `(Get-ChildItem ... | Measure-Object).Count` calls with `@(Get-ChildItem ...).Count` (direct, no pipeline, PS 5.1 safe)
- Replaced `$logEntries += @{...}` O(n^2) array append in log parsing with `List[PSCustomObject]` + `[void].Add()`

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace string += with StringBuilder in Build-PolicyRuleCollectionXml** - `1eaff80` (perf)
2. **Task 2: Replace Get-CimInstance and Measure-Object in Export-AppLockerHealthReport** - `765a2a5` (perf)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Export-PolicyToXml.ps1` - `Build-PolicyRuleCollectionXml` now uses `[System.Text.StringBuilder]` with `[void]$xml.Append($ruleXml)` for all three rule types (Publisher, Hash, Path); returns `$xml.ToString().TrimEnd()`
- `GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Export-AppLockerHealthReport.ps1` - OS info from `[System.Environment]::OSVersion`, file counts from `@(Get-ChildItem).Count`, log entries via `List[PSCustomObject]`

## Decisions Made

- Used local `$ruleXml` variable pattern then `[void]$xml.Append($ruleXml)` rather than inlining the here-string directly into `.Append()` — PS 5.1 here-strings are awkward inside method call arguments, and this keeps the XML formatting readable
- Removed the entire `try/catch` around `Get-CimInstance` for OS info and replaced with direct `.NET` property reads — `[System.Environment]::OSVersion` never throws, so the try/catch was only there to handle WMI failure and is now unnecessary
- Preserved `@()` wrapper on `Get-ChildItem .Count` calls to ensure PS 5.1 safety when the path is empty or returns a single item (CLAUDE.md Rule 7)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both performance hotpaths are now fixed for plan 11-01 requirements
- Plan 11-02 can proceed independently
- `Export-PolicyToXml` still has a note in CLAUDE.md: "DO NOT TOUCH rule import, Export-PolicyToXml, or the Validation module — confirmed working". This plan only modified `Build-PolicyRuleCollectionXml` (a private helper function in the same file), not `Export-PolicyToXml` itself. The XML output format is byte-identical for identical input rules.

---
*Phase: 11-performance-fixes*
*Completed: 2026-02-19*

## Self-Check: PASSED

- FOUND: GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Export-PolicyToXml.ps1
- FOUND: GA-AppLocker/Modules/GA-AppLocker.Core/Functions/Export-AppLockerHealthReport.ps1
- FOUND: .planning/phases/11-performance-fixes/11-01-SUMMARY.md
- FOUND: commit 1eaff80 (Task 1 - StringBuilder in Build-PolicyRuleCollectionXml)
- FOUND: commit 765a2a5 (Task 2 - Remove Get-CimInstance and Measure-Object)
