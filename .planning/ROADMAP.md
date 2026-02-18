# Roadmap: GA-AppLocker v1.2.88 Event Viewer Rule Workbench

## Overview

This milestone delivers an end-to-end event-driven operator workflow: ingest bounded AppLocker events from local and selected remote hosts, triage events quickly with focused filters and inspection detail, then convert validated selections into rules through the existing review-safe rules pipeline.

## Phases

- [ ] **Phase 7: Event Ingestion and Bounded Retrieval** - Establish reliable local and selected-remote event loading with bounded query controls.
- [ ] **Phase 8: Event Triage and Inspection Workbench** - Deliver operator filtering/search and event-detail inspection for confident investigation.
- [ ] **Phase 9: Rule Generation from Event Selections** - Convert single or bulk event selections into deduplicated candidates through existing review workflow.

## Phase Details

### Phase 7: Event Ingestion and Bounded Retrieval
**Goal**: Operators can reliably retrieve AppLocker events from local and selected remote machines without unbounded queries.
**Depends on**: Phase 6
**Requirements**: EVT-01, EVT-02, EVT-03
**Success Criteria** (what must be TRUE):
  1. Operator can load AppLocker events from the local machine in the Event Viewer workflow.
  2. Operator can load events from selected remote machines and see per-host success/failure status for each requested host.
  3. Operator can set time window and result-cap bounds, and returned results respect those limits.
  4. Operator can rerun bounded queries during a session without the workflow becoming unresponsive.
**Plans**: 3 plans

Plans:
- [x] 07-01-PLAN.md - Build bounded event retrieval contract and per-host remote envelopes.
- [x] 07-02-PLAN.md - Add Event Viewer navigation and panel shell wiring.
- [x] 07-03-PLAN.md - Implement bounded loading flow and host status rendering in Event Viewer.

### Phase 8: Event Triage and Inspection Workbench
**Goal**: Operators can quickly isolate relevant AppLocker events and validate evidence before generating actions.
**Depends on**: Phase 7
**Requirements**: FLT-01, FLT-02, FLT-03, DET-01, DET-02
**Success Criteria** (what must be TRUE):
  1. Operator can filter loaded events by AppLocker event code and immediately see narrowed results.
  2. Operator can combine metadata filters (host, user, action/outcome, and time range) to isolate targeted events.
  3. Operator can use one search bar to find events by path, signer, hash, message text, and host/user text.
  4. Operator can select an event row and inspect normalized details (file identity, collection, user, machine, action context).
  5. Operator can open raw event XML/message for the selected event to verify forensic fidelity.
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md - Enrich event data pipeline with inspection fields and extend filter function with dimension parameters.
- [ ] 08-02-PLAN.md - Add filter controls, detail pane XAML, panel wiring, and behavioral tests.

### Phase 9: Rule Generation from Event Selections
**Goal**: Operators can safely create rules from validated event selections using existing governance and review controls.
**Depends on**: Phase 8
**Requirements**: GEN-01, GEN-02, GEN-03, GEN-04
**Success Criteria** (what must be TRUE):
  1. Operator can generate one AppLocker rule from a single selected event.
  2. Operator can generate rules from multiple selected events in one bulk action.
  3. Operator can review deduplicated bulk candidates with frequency counts before confirming creation.
  4. Operator sees event-derived rules flow through existing rules pipeline/review status rather than bypassing standard controls.
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 7. Event Ingestion and Bounded Retrieval | 3/3 | Complete | 2026-02-18 |
| 8. Event Triage and Inspection Workbench | 1/2 | In Progress|  |
| 9. Rule Generation from Event Selections | 0/TBD | Not started | - |
