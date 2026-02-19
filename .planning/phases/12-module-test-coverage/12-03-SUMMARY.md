---
phase: 12-module-test-coverage
plan: 03
subsystem: testing
tags: [pester, setup, gpo, winrm, active-directory, rsat, mocking, unit-tests]

requires:
  - phase: 12-module-test-coverage/12-01
    provides: test infrastructure pattern (stub-before-import approach)
  - phase: 12-module-test-coverage/12-02
    provides: test infrastructure pattern

provides:
  - Unit tests for GA-AppLocker.Setup module (62 tests, all passing)
  - Pester mocking pattern for RSAT cmdlets without RSAT installed
  - GpoStatus enum stub pattern for GroupPolicy type-dependent code

affects:
  - Future Setup module changes (tests catch regressions)
  - Other modules calling RSAT cmdlets (stub pattern applicable)

tech-stack:
  added: []
  patterns:
    - "Stub RSAT cmdlets globally in BeforeAll before module import — allows Mock to intercept calls to non-existent cmdlets"
    - "GpoStatus Add-Type stub in try/catch — enables enum assignment tests without RSAT"
    - "PSObject with Add-Member for mutable mock GPO objects — required for GpoStatus property assignment"

key-files:
  created:
    - Tests/Unit/Setup.Tests.ps1
  modified:
    - GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Get-SetupStatus.ps1

key-decisions:
  - "Test count 62 (exceeds 15+ minimum) covering all required functional areas"
  - "Set-GPRegistryValue called 6 times in Initialize-WinRMGPO (not 5 as plan stated) — plan description omitted LocalAccountTokenFilterPolicy as a separate call"
  - "Initialize-AppLockerEnvironment tests mock module-internal functions with -ModuleName GA-AppLocker.Setup to intercept calls from within the module"
  - "Rule 1 bug fix: Enable/Disable-WinRMGPO calls inside Initialize-AppLockerEnvironment lacked Out-Null suppression, leaking PSCustomObjects into pipeline"

patterns-established:
  - "Pattern 1: Stub RSAT cmdlets as global functions before module import; Pester Mock then intercepts at module scope with -ModuleName"
  - "Pattern 2: Use New-Object PSObject + Add-Member for mock objects that need property assignment (not [PSCustomObject]@ which is immutable)"
  - "Pattern 3: Add-Type enum stub in try/catch for enum-dependent code that must run without the real assembly"

requirements-completed:
  - TEST-03

duration: 9min
completed: 2026-02-19
---

# Phase 12 Plan 03: Setup Module Unit Tests Summary

**62-test Pester suite for GA-AppLocker.Setup covering GPO creation, WinRM config, AD structure, and status reporting — all mocked for RSAT-free test environments**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-02-19T01:52:52Z
- **Completed:** 2026-02-19T02:01:52Z
- **Tasks:** 1 of 1
- **Files modified:** 2

## Accomplishments

- Created `Tests/Unit/Setup.Tests.ps1` with 62 passing Pester 5 tests covering all Setup module functions
- Established the RSAT-free mocking pattern using global function stubs before module import — enables CI/test machines without RSAT to run Setup tests
- Fixed pipeline output leak bug in `Initialize-AppLockerEnvironment` where `Enable-WinRMGPO` and `Disable-WinRMGPO` calls were polluting function output

## Task Commits

1. **Task 1: Create Setup module unit tests** - `5ed8939` (feat)

**Plan metadata:** (to be committed with SUMMARY.md)

## Files Created/Modified

- `Tests/Unit/Setup.Tests.ps1` - 62 Pester unit tests for GA-AppLocker.Setup module; tests Get-SetupStatus return structure, Initialize-WinRMGPO (create/reuse/6 registry writes), Initialize-AppLockerGPOs (3 GPOs, CreateOnly, reuse existing), Initialize-ADStructure (OU + 6 groups), Initialize-AppLockerEnvironment (OR success logic), Enable/Disable-WinRMGPO (module missing, GPO missing, GPO exists)
- `GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Get-SetupStatus.ps1` - Bug fix: added `| Out-Null` to Enable/Disable-WinRMGPO calls inside Initialize-AppLockerEnvironment

## Decisions Made

- The plan stated "5 registry value writes" for Initialize-WinRMGPO but the actual implementation makes 6 calls (service start, AllowAutoConfig, IPv4Filter, IPv6Filter, LocalAccountTokenFilterPolicy, firewall rule). Test uses the actual count of 6.
- Tests use `Assert-MockCalled` (Pester 5 alias for `Should -Invoke`) to verify call counts, not to assert on parameter values — keeps tests focused on orchestration behavior rather than implementation details.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pipeline output leak in Initialize-AppLockerEnvironment**
- **Found during:** Task 1 (verifying Initialize-AppLockerEnvironment tests)
- **Issue:** `Enable-WinRMGPO` and `Disable-WinRMGPO` calls inside `Initialize-AppLockerEnvironment` were not suppressed, causing their `PSCustomObject` return values to leak into the function's pipeline output. When both succeed, calling code receives an array of 3 items (2 leak PSCustomObjects + 1 actual result) instead of a single result object.
- **Fix:** Added `| Out-Null` to both calls in the try/catch block in `Get-SetupStatus.ps1`
- **Files modified:** `GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Get-SetupStatus.ps1`
- **Verification:** Tests pass and `Initialize-AppLockerEnvironment` returns a single result object
- **Committed in:** `5ed8939` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required to make Initialize-AppLockerEnvironment tests reliable. No scope creep.

## Issues Encountered

- **RSAT cmdlets don't exist without RSAT installed:** Pester 5's `Mock` requires the command to be discoverable. Solution: define stub global functions for all RSAT cmdlets in `BeforeAll` BEFORE module import, then Pester can intercept them via `-ModuleName 'GA-AppLocker.Setup'`.
- **New-MockGPO helper not visible in BeforeEach:** In Pester 5, helper functions defined outside `BeforeAll`/`Describe` blocks aren't in scope for `BeforeEach`. Solution: inline all mock object creation directly in `BeforeEach` blocks.
- **GpoStatus enum assignment requires mutable PSObject:** `[PSCustomObject]@{...}` properties can be reassigned but `$gpo.GpoStatus = [Microsoft.GroupPolicy.GpoStatus]::AllSettingsEnabled` needs the `[Microsoft.GroupPolicy.GpoStatus]` type to exist. Solution: `Add-Type` stub enum in `BeforeAll` with try/catch.

## User Setup Required

None - tests run with `Invoke-Pester -Path Tests/Unit/Setup.Tests.ps1` without any external configuration.

## Next Phase Readiness

- All 3 plans in Phase 12 now have test files (12-01 through 12-03)
- Phase 12 complete — module test coverage milestone achieved
- `Tests/Unit/` directory established with 62 tests; pattern ready for additional unit test files

---
*Phase: 12-module-test-coverage*
*Completed: 2026-02-19*
