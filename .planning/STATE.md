# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-19)

**Core value:** Reliable, operator-friendly policy management that stays responsive on large enterprise datasets
**Current focus:** v1.2.90 Production Hardening — Phase 12: Module Test Coverage

## Current Position

Phase: 12 of 13 (Module Test Coverage)
Plan: 1 of 3 complete in current phase
Status: In progress — 12-01 complete, 12-02 and 12-03 pending
Last activity: 2026-02-19 — Completed 12-01: Credentials module unit tests (27 tests)

Progress: [██████░░░░] 60% (7 plans complete across v1.2.90)

## Performance Metrics

**Velocity:**
- Total plans completed: 16 (across v1.2.86 + v1.2.88 milestones)
- Average duration: ~45 min
- Total execution time: ~12 hours (prior milestones)

**By Phase (v1.2.90):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 (Error Handling) | 4 complete | ~12 min | ~3 min |

**Recent Trend:**
- Last milestone (v1.2.88): 7 plans, 1-day window
- Trend: Stable

*Updated after each plan completion*
| Phase 10-error-handling-hardening P02 | 6 | 2 tasks | 5 files |
| Phase 10 P01 | 10 | 2 tasks | 9 files |
| Phase 10 P04 | 3 | 2 tasks | 2 files |
| Phase 11 P01 | 2 | 2 tasks | 2 files |
| Phase 11 P02 | 2 | 2 tasks | 11 files |
| Phase 12 P01 | 2 | 1 task | 1 file |

## Accumulated Context

### Decisions

Decisions are logged in `.planning/PROJECT.md`.

Recent decisions affecting v1.2.90:
- Error handling phases before test phases — tests validate hardened code, not legacy silent-failure paths
- Performance fixes before tests — avoids writing tests that assert on pre-fix behavior
- Validation module and rule import core path are locked — no changes in this milestone
- [10-03] Catches wrapping Write-AppLockerLog get intentional-suppression comments (not Write-AppLockerLog) to prevent recursive logging failure
- [10-03] Runspace boundary: never call Write-AppLockerLog inside scriptblocks sent to runspace pools or Invoke-Command
- [10-03] Fallback-chain catches use DEBUG level (expected by design in air-gapped SID resolution)
- [Phase 10-error-handling-hardening]: Intentional empty catches preserved in logging fallback chains (Write-Log/Show-Toast guards inside error handlers cannot have recursive logging added)
- [Phase 10-error-handling-hardening]: All GUI infrastructure empty catches now have contextual DEBUG logging with component prefixes ([UIHelpers], [AsyncHelpers], [GlobalSearch], [MainWindow], [RuleWizard])
- [Phase 10]: GUI panel catch blocks use DEBUG level for UI cosmetic operations and WARN/ERROR for data operations
- [Phase 10]: Remote scriptblock error handling uses Write-Warning instead of Write-AppLockerLog since module is unavailable on remote machines
- [Phase 10]: Backend functions (Invoke-BatchRuleGeneration, Get-AppLockerEventLogs, Remove-DuplicateRules) were already ERR-04 compliant with structured returns; return-null only in private script: helpers with skip/filter semantics
- [Phase 10]: Deploy and Credentials panels needed Show-Toast Error on operator-triggered failures alongside existing MessageBox calls; Scanner/Rules/Policy panels already had comprehensive toast coverage
- [Phase 11]: Use local ruleXml variable then [void]xml.Append(ruleXml) for PS 5.1 compatible StringBuilder XML assembly
- [Phase 11]: Replace Get-CimInstance OS info try/catch with direct [System.Environment]::OSVersion reads — never throws, eliminates WMI timeout risk on air-gapped networks
- [11-02]: ConvertTo-Json -Depth 3 sufficient for all serialized objects (max 2-3 nesting levels); Validation module depth change authorized as safe mechanical replacement
- [11-02]: DragDropHelpers $script:CurrentScanArtifacts += lines left as-is (single appends outside loops, variable type not owned by that file)
- [12-01]: Mock Get-AppLockerDataPath with -ModuleName 'GA-AppLocker.Credentials' to intercept module-internal calls; without -ModuleName the mock is invisible inside the module
- [12-01]: Tests/Unit/ established for module-level unit tests separate from Tests/Behavioral/ integration tests
- [12-01]: Test-CredentialProfile covered with existence check only — function requires live WinRM which is unavailable in unit test context

### Pending Todos

- Remote transport fallback details (WinRM versus event log RPC) — deferred DEBT-03
- Event query snapshot retention/pruning policy — deferred DEBT-04
- CollectionType field gap in event retrieval backend — deferred DEBT-01
- Promote script:-scoped functions to global: — deferred DEBT-02

### Blockers/Concerns

None active.

## Session Continuity

Last session: 2026-02-19
Stopped at: Completed 12-01-PLAN.md (Credentials unit tests — 27 tests passing)
Resume file: None
