# Scheduled Scan Event Logs Design

Date: 2026-02-27
Status: Approved
Owner: GA-AppLocker

## Summary

- Goal: allow scheduled scans to persist and honor an `IncludeEventLogs` setting, so scheduled executions can collect AppLocker event logs the same way manual scans do.
- Decision: reuse existing Scanner checkbox (`ChkIncludeEventLogs`) during schedule creation, persist the value in scheduled scan JSON, and pass it through `Invoke-ScheduledScan` into `Start-ArtifactScan`.
- Scope: backend scheduling flow + Scanner create-schedule wiring + targeted behavioral tests.

## Problem

- Manual scans already support event collection via `Start-ArtifactScan -IncludeEventLogs`.
- Scheduled scans currently persist options like `SkipDllScanning`, but do not persist/pass `IncludeEventLogs`.
- Result: operators cannot enable event collection for recurring scheduled scan jobs.

## Constraints

- PowerShell 5.1 compatibility rules apply.
- Preserve existing scheduled scan behavior for legacy JSON files that do not contain `IncludeEventLogs`.
- Keep UI changes minimal and avoid new XAML controls in this increment.
- Do not alter validated policy export/import/validation flows.

## Approaches Considered

### A) Reuse existing Include Event Logs checkbox (selected)

- Read `ChkIncludeEventLogs` in `Invoke-CreateScheduledScan` and pass it to `New-ScheduledScan`.
- Add `IncludeEventLogs` switch/property in `ScheduledScans.ps1` create + invoke paths.

Pros:
- Minimal code changes and risk.
- No XAML churn.
- Consistent operator experience with existing scanner options.

Cons:
- Checkbox meaning spans immediate and scheduled creation contexts.

### B) Add dedicated scheduled-scan checkbox

Pros:
- More explicit schedule-specific UX.

Cons:
- Requires XAML and extra event wiring for marginal value.

### C) Always include events for all schedules

Pros:
- No UI/config complexity.

Cons:
- Removes operator control; can increase scan duration/noise.

## Selected Design

### Data contract

- Extend persisted scheduled-scan object in `New-ScheduledScan` with:
  - `IncludeEventLogs = $IncludeEventLogs.IsPresent`

### Runtime behavior

- In `Invoke-ScheduledScan`, when schedule has `IncludeEventLogs = $true`, set:
  - `$scanParams.IncludeEventLogs = $true`
- Existing `Start-ArtifactScan` behavior handles local/remote event retrieval.

### UI behavior

- In `Invoke-CreateScheduledScan` (Scanner panel), when `ChkIncludeEventLogs` is checked:
  - add `$params.IncludeEventLogs = $true` before calling `New-ScheduledScan`.

### Backward compatibility

- Legacy schedule files lacking `IncludeEventLogs` continue to run without event collection.
- Conditional check in invoke path defaults effectively to false when property is missing.

## Validation Plan

- Add behavioral tests for scheduled scan create/run paths:
  - persists `IncludeEventLogs` true/false on creation.
  - forwards `IncludeEventLogs` to `Start-ArtifactScan` when enabled.
  - preserves legacy behavior when property is absent.
- Add/extend Scanner panel test to verify `Invoke-CreateScheduledScan` passes `IncludeEventLogs` from checkbox state.

## Exit Criteria

- Creating a scheduled scan with Include Event Logs checked persists the setting.
- Invoking that scheduled scan passes `-IncludeEventLogs` to `Start-ArtifactScan`.
- Existing scheduled scans without the new field still run successfully.
- Targeted behavioral tests pass.
