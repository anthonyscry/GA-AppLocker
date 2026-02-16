# Scanner UI Speed Optimizations Design

Date: 2026-02-15
Status: Approved for planning
Owner: GA-AppLocker

## Summary

- Goal: improve Scanner workflow speed with low-risk UI changes.
- Primary success outcomes: reduce clicks from Event Metrics to rule generation and improve perceived filter responsiveness.
- Constraints: preserve existing Scanner layout and behavior patterns; avoid major redesign.

## Inputs and Constraints

- User priorities:
  - Focus area: Scanner workflow speed.
  - Change scope: low risk tweaks.
  - Success metric: both fewer clicks and lower UI latency.
- Existing implementation references:
  - Scanner result tabs and Event Metrics UI in `GA-AppLocker/GUI/MainWindow.xaml`.
  - Scanner wiring and debounce behavior in `GA-AppLocker/GUI/Panels/Scanner.ps1`.
  - Event-based generation handler in `Invoke-GenerateRuleFromSelectedEvent`.
- Technical constraints:
  - PowerShell 5.1 compatibility.
  - WPF callback scope rules (global handlers where required).
  - Keep existing event-to-rule generation semantics intact.

## Approaches Considered

### 1) Scanner Quick-Action Hot Path (Selected)

- Add explicit quick action in Event Metrics and keyboard/mouse shortcuts.
- Keep context menu path as fallback.
- Optimize filter refresh to prioritize active results tab.

Pros:

- Best click reduction with minimal layout risk.
- Leverages existing generation function and settings controls.

Cons:

- Requires careful trigger deduplication to avoid duplicate generation calls.

### 2) Filter Engine Only

- Keep UX unchanged; optimize debounce, caching, and refresh sequencing.

Pros:

- Lowest visual change risk.

Cons:

- Smaller user-visible click reduction.

### 3) Workflow Compression via Last-Used Preset

- Add one-click default generation profile for event rows.

Pros:

- Strong click-count reduction.

Cons:

- Introduces additional state behavior and user expectation management.

## Selected Design

### 1) Architecture

- Preserve current Scanner layout and tab structure.
- Add a visible Event Metrics quick action while preserving the existing context menu item.
- Route all event->rule triggers through one handler (`Invoke-GenerateRuleFromSelectedEvent`) to keep behavior consistent.
- Improve shared search behavior by refreshing the active results tab first, then syncing passive tab state without full redundant recompute.

### 2) Components and Data Flow

- Event Metrics quick action control:
  - Add a visible "Generate Rule" action near Event Metrics mode controls.
  - Keep right-click context menu action unchanged for compatibility.
- Multi-input trigger support:
  - Support double-click and Enter on `EventMetricsDataGrid`.
  - All triggers call the same generation path.
- Active-tab filter refresh:
  - Shared search text remains synchronized between artifacts and events.
  - Debounce applies active-tab-first updates to reduce perceived lag.
- Rule generation flow:
  - Selected event -> artifact metadata match from current scan artifacts -> read generation controls -> invoke direct generation with settings.
- Post-action feedback:
  - Keep toast + Rules panel refresh, avoid redundant Scanner refresh calls unless data changed.

### 3) Error Handling and Guardrails

- Prevent duplicate submissions:
  - Add in-flight guard for event-based generation triggers.
  - Temporarily disable quick-action trigger while generation is active.
- Selection safety:
  - Standardize no-selection guard for button, double-click, Enter, and context menu paths.
- Metadata mismatch behavior:
  - Preserve warning when no matching artifact metadata exists.
  - Keep message actionable and avoid repeated warning spam for identical failed attempts.
- Stale selection safety:
  - If debounce/filter changes invalidate selection, fail safe as no-selection.
- Non-blocking feedback:
  - Show concise in-context status for generation start/end and restore keyboard focus flow.

## Testing and Validation

- Behavioral tests in `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`:
  - Add coverage for quick-action trigger paths (button, double-click, Enter).
  - Verify each trigger calls generation exactly once.
  - Verify in-flight guard suppresses duplicate trigger execution.
  - Verify trigger/UI re-enable on completion/failure.
- Filter responsiveness tests:
  - Validate active-tab-first refresh behavior.
  - Validate no unnecessary hidden-tab full recompute per keystroke.
- Manual acceptance:
  - Confirm fewer interactions from event selection to rule generation.
  - Confirm snappier search/filter updates on larger result sets.
  - Confirm existing context-menu flow remains functional.

## Rollout Sequence

1. Add tests for trigger pathways and in-flight guard expectations.
2. Add Event Metrics visible quick action and unified trigger wiring.
3. Implement in-flight dedupe guard and selection safety normalization.
4. Optimize debounce refresh sequencing for active-tab-first updates.
5. Run focused behavioral tests and perform manual Scanner workflow check.

## Exit Criteria

- Event Metrics supports quick rule generation with fewer interactions.
- Trigger pathways (button/double-click/Enter/context menu) behave consistently.
- Duplicate trigger spam does not create duplicate generation jobs.
- Scanner filter interactions feel faster without feature regression.
- Existing event-based generation behavior remains intact.
