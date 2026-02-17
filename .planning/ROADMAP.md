# Roadmap: GA-AppLocker v1.2.87 Performance

## Overview

This milestone restores operator trust and responsiveness by hardening rules-index reliability first, then optimizing panel data access and navigation hot paths, and finally validating that core workflows remain stable under the new behavior.

## Phases

- [ ] **Phase 7: Canonical Index Commit Path** - Establish one atomic, rollback-safe index mutation path for all index writes.
- [ ] **Phase 8: Index Integrity and Watcher Stability** - Add deterministic startup integrity checks and remove watcher-driven rebuild churn.
- [ ] **Phase 9: Projection-First UI Throughput and Telemetry** - Deliver sub-500ms warm navigation using projection-first reads with operator-visible latency instrumentation.
- [ ] **Phase 10: Workflow Regression Safety** - Confirm selection/filter/action workflows remain stable after reliability and performance changes.

## Phase Details

### Phase 7: Canonical Index Commit Path
**Goal**: Operators can trust index mutations to commit through a single atomic path with rollback-safe behavior.
**Depends on**: Phase 6
**Requirements**: IDX-01
**Success Criteria** (what must be TRUE):
  1. Operator-triggered rule mutations complete without partial index state after interruption scenarios.
  2. Operator can continue normal rule operations after a failed write without manual index file surgery.
  3. Operator sees consistent rule counts/views after repeated add/update/delete operations in one session.
**Plans**: TBD

### Phase 8: Index Integrity and Watcher Stability
**Goal**: Operators get deterministic index health checks at startup and stable watcher behavior during runtime.
**Depends on**: Phase 7
**Requirements**: IDX-02, IDX-03
**Success Criteria** (what must be TRUE):
  1. Operator starts the app and receives deterministic index integrity handling (valid, repaired, or rebuilt) without ambiguous state.
  2. Operator can proceed with Rules/Policy workflows after startup even when prior index corruption/drift existed.
  3. Operator does not experience repeated watcher-triggered rebuild loops or noisy stale-state oscillation while using the app.
**Plans**: TBD

### Phase 9: Projection-First UI Throughput and Telemetry
**Goal**: Operators can navigate high-volume panels quickly using projection-first reads with measurable latency evidence.
**Depends on**: Phase 8
**Requirements**: PERF-01, PERF-02, OBS-01
**Success Criteria** (what must be TRUE):
  1. Operator can warm-navigate Dashboard, Rules, Policy, and Deploy panels in under 500ms on representative large datasets.
  2. Operator sees Rules/Policy initial views load from lightweight projections without full payload hydration delays.
  3. Operator and maintainer can review recorded panel/filter latency metrics to verify target compliance.
**Plans**: TBD

### Phase 10: Workflow Regression Safety
**Goal**: Operators retain stable day-to-day workflow behavior after index and performance hardening.
**Depends on**: Phase 9
**Requirements**: FLOW-01
**Success Criteria** (what must be TRUE):
  1. Operator can keep and act on intended row selections during refreshes and panel transitions without unintended resets.
  2. Operator can apply filters and run common rule/policy actions with results matching pre-hardening workflow expectations.
  3. Operator completes core workflow steps without new reliability/performance regressions blocking routine actions.
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 7. Canonical Index Commit Path | 0/TBD | Not started | - |
| 8. Index Integrity and Watcher Stability | 0/TBD | Not started | - |
| 9. Projection-First UI Throughput and Telemetry | 0/TBD | Not started | - |
| 10. Workflow Regression Safety | 0/TBD | Not started | - |
