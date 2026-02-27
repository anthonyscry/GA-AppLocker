# Bundle C Policy Drift and Telemetry Design

## Goal
Add backend-first policy drift reporting and telemetry summary commands that build on Bundles A/B without adding new UI risk.

## Why now
Bundle B added event categorization and candidate scoring. Bundle C now uses that categorization signal to produce drift summaries and operational telemetry, enabling policy health insights while preserving current UI behavior.

## Design overview

### Command 1: Get-PolicyDriftReport
- Module: `GA-AppLocker.Policy`
- Responsibility: Compute current drift posture using event coverage outcomes.
- Inputs:
  - `-Events` (mandatory)
  - `-PolicyId` (optional)
  - `-Rules` (optional)
  - `-RecordTelemetry` (optional)
- Behavior:
  - Resolve rule set from explicit rules, policy rule IDs, or approved rules.
  - Call `Invoke-AppLockerEventCategorization` to get coverage/category outcomes.
  - Build drift summary (coverage, uncovered gaps, staleness).
  - Optionally emit telemetry via `Write-AuditLog` action `PolicyDriftCalculated`.

### Command 2: Get-PolicyTelemetrySummary
- Module: `GA-AppLocker.Policy`
- Responsibility: Aggregate policy telemetry from audit trail.
- Inputs:
  - `-PolicyId` (optional)
  - `-Days` default 30
  - `-Last` default 200
  - `-IncludeEvents` optional
- Behavior:
  - Read policy-category entries via `Get-AuditLog`.
  - Filter by policy id when provided.
  - Aggregate action counts and drift-check totals.
  - Return latest drift-check metadata.

## Safety and reliability notes
- PS 5.1 compatibility only (no `??`, no ternary).
- O(n) list/dictionary aggregation only; no `$array +=` loops.
- No runspace/timer additions in this iteration.
- No changes to policy XML export or Validation module.

## Test strategy
- Behavioral tests with mocked dependencies:
  - Drift report: gap extraction, coverage summary, policy-rule loading.
  - Telemetry summary: action aggregation and policy filtering.
- Keep tests deterministic and independent of AD/GPO/network.
