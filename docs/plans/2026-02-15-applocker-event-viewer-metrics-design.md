# AppLocker Event Metrics Design

Date: 2026-02-15
Status: Approved for planning
Owner: GA-AppLocker

## Summary

- Goal: add an Event Viewer metrics view to the existing Scanner panel that reports the most common blocked and audited files from AppLocker events.
- Decision: reuse Scanner flow (`ChkIncludeEventLogs`) and render metrics from the latest scan result only.
- Scope: scan execution + in-session result presentation, with clear filters for event type and machine.

## User Story

- As an operator, I want one scan to both collect artifacts and AppLocker events, then immediately show me which files are most often blocked or audited.
- As a defender, I want quick filters for blocked/audit mode and machine, so I can isolate noisy hosts and high-volume events.
- As an analyst, I want counts, last seen time, and file path context in one screen without leaving the Scanner workflow.

## Constraints and Inputs

- Scanner already supports event collection through `Start-ArtifactScan -IncludeEventLogs` and returns:
  - `result.Data.EventLogs` (flat array)
  - `result.Summary.TotalEvents`
  - each event includes `EventId`, `EventType`, `TimeCreated`, `FilePath`, `IsBlocked`, `IsAudit`, `ComputerName`.
- User preference approved in prior step:
  - reuse Scanner window instead of creating a new panel
  - compute metrics from latest scan only
  - separate blocked vs audit presentation
- Keep PS 5.1/WPF rules from CLAUDE constraints (global scope for UI callbacks, no unsafe list patterns, no new UTF-8 artifacts).

## Non-Goals

- No separate Event Viewer menu panel in this first pass.
- No historical aggregation across previous scans.
- No new event log retention schema beyond current `Start-ArtifactScan` JSON output.
- No scheduled-scan event settings UI changes in this pass.

## Approaches Considered

### A) Reuse Scanner panel with inline event section (selected)

- Keep scan configuration and Start/Stop controls unchanged.
- Add a new event-metrics section to Scanner panel, enabled when events were collected in the latest scan.
- Compute metrics in UI from current scan object (`result.Data.EventLogs`).

Pros:

- Immediate path from checkbox -> scan -> report.
- No new navigation path to learn.
- Minimal changes to existing module exports.

Cons:

- Metrics area may grow Scanner complexity.

### B) Add dedicated panel (not selected)

- Add a top-level Event Viewer panel and optional scheduled/history load actions.

Pros:

- More room for advanced reporting.

Cons:

- More migration risk and duplicate data plumbing.

### C) Dual mode (scanner metrics + dedicated panel for history)

- Scanner shows recent-metrics, dedicated panel handles history and drill-in.

Pros:

- Good long-term scalability.

Cons:

- Out of proportion for this delivery, more UI complexity.

## Selected Design

### 1) Data storage for session state

Add in-memory session fields in `Scanner.ps1`:

- `$script:CurrentScanEventLogs` : `PSCustomObject[]` events from the active scan result.
- `$script:CurrentEventFilter` : selected machine/event-view filter state.

Lifecycle:

- On successful scan completion, set `CurrentScanEventLogs` from `$result.Data.EventLogs`.
- Clear to `@()` on scan start and when opening Scanner with no loaded scan.

### 2) UI additions in `MainWindow.xaml`

Inside `PanelScanner`, add an `Event Metrics` area (below Artifact DataGrid or in a new `Grid` row):

- Header with scan-level counters:
  - `Total Events`
  - `Blocked Events`
  - `Audit Events`
- Filter controls:
  - `Event Mode` selector: `All`, `Blocked`, `Audit`
  - `Machine` selector: `All` + distinct `ComputerName` list
  - `Top N` numeric input (default 20)
  - `Search` box for partial file path match
- Result grid (single reusable table):
  - `Rank`
  - `FilePath`
  - `Machine`
  - `EventType`
  - `Count`
  - `Blocked`
  - `Audit`
  - `Last Seen`
- Empty state message when `-IncludeEventLogs` is false or no events returned.

### 3) Metric computation model

- Aggregate from `CurrentScanEventLogs` with deterministic grouping keys:
  - `FilePath` (normalized path string)
  - `ComputerName`
  - `EventType`
- Compute per group:
  - `Count`
  - `BlockedCount` (`IsBlocked`)
  - `AuditCount` (`IsAudit`)
  - `LastSeen` (max `TimeCreated`)
- Respect filters:
  - `Mode=Blocked` → include only blocked events.
  - `Mode=Audit` → include only audit events.
  - `Mode=All` → include both.
  - machine filter by exact `ComputerName`
  - path search by wildcard on `FilePath`
- Sort descending by `Count`, then by `FilePath`.
- Show `Top N` rows.

### 4) Wiring points

- Scan completion block in `Scanner.ps1` (existing timer `Invoke` path):
  - set counters from `result.Summary.TotalEvents`, `BlockedEvents`, `AuditEvents`.
  - assign `script:CurrentScanEventLogs` and invoke metric refresh.
- `Invoke-StartArtifactScan` should continue passing `IncludeEventLogs` exactly as today; no backend contract change.
- New helper functions in `Scanner.ps1` for maintainability:
  - `Initialize-ScanEventMetrics`
  - `Get-ScanEventMetrics`
  - `Update-EventMetricsUI`
- Keep all timer/callback handlers in `global:` scope if they touch WPF timers.

### 5) Edge behavior and fallback

- If `CurrentScanEventLogs` is empty:
  - keep metrics panel visible with zero counters and disabled grid state.
- If `FilePath` is null/empty:
  - aggregate key as `<unknown path>`.
- If include-event checkbox disabled:
  - set counters to zero and show guidance text.
- If `Top N` <= 0:
  - default to 20.

## Validation Plan

- Unit/behavior tests to add:
  - `Start-ArtifactScan` with `-IncludeEventLogs` continues to return `Summary.TotalEvents` and non-empty `Data.EventLogs` when logs exist.
  - `Get-AppLockerEventLogs` event object includes stable `IsBlocked`/`IsAudit` split.
  - New metric function returns deterministic top-N grouping.
- UI-behavior tests (where possible):
  - event metrics panel shows zero-state safely when include event logs is off.
  - blocked/audit filter updates counts and rowset without scan restart.
  - machine filter reduces result set correctly.

## Risks

- Large remote event sets can be slow to aggregate on low-end workstations.
  - Mitigation: compute groups from in-memory events only and keep `Top N` user-configurable.
- Null event fields can break grouping keys.
  - Mitigation: explicit normalizers for file path and machine fields.
- Future scheduled-scan workflows might still miss event inclusion.
  - Mitigation: document as follow-up non-goal and track separately.

## Rollout and Sequence

1. Add UI controls and helper function stubs.
2. Add in-session event-metrics state variables and scan completion binding.
3. Implement filtering and ranking function.
4. Add focused tests for aggregation logic and scanner metadata plumbing.
5. Manual sanity run: local scan with Include Event Logs on/off, remote mixed machine set, empty-event scan.

## Exit Criteria

- A completed scan with events enabled renders top blocked/audited file metrics with filters.
- Existing artifact scanning flow still works when events are disabled.
- No scanner regressions in artifact grid/filter/generation actions.
- Metric output can be refreshed from filter controls without re-running scan.
