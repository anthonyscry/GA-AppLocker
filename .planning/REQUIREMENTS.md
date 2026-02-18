# Requirements: GA-AppLocker v1.2.88 Event Viewer Rule Workbench

**Defined:** 2026-02-17
**Core Value:** Reliable, operator-friendly policy management that stays responsive on large enterprise datasets

## v1 Requirements

### Event Ingestion

- [x] **EVT-01**: Operator can open Event Viewer and load AppLocker events from the local machine.
- [x] **EVT-02**: Operator can load AppLocker events from selected remote machines and see per-host success/failure status.
- [x] **EVT-03**: Operator can run bounded event queries (time window and result cap) to avoid unbounded retrieval.

### Filtering and Search

- [x] **FLT-01**: Operator can filter events by AppLocker event code.
- [x] **FLT-02**: Operator can filter events by key metadata (host, user, action/outcome, and time range).
- [x] **FLT-03**: Operator can use a search bar to find events by path, signer, hash, message text, or host/user text.

### Event Inspection

- [x] **DET-01**: Operator can inspect normalized event details for a selected row (file identity, collection, user, machine, and action context).
- [x] **DET-02**: Operator can view raw event XML/message for forensic verification before taking action.

### Rule Generation

- [ ] **GEN-01**: Operator can generate a single AppLocker rule from one selected event.
- [ ] **GEN-02**: Operator can generate rules from multiple selected events in one bulk action.
- [ ] **GEN-03**: Operator can review deduplicated bulk candidates with frequency counts before creation.
- [ ] **GEN-04**: Operator can create event-derived rules through the existing rules pipeline without bypassing standard review workflow.

## Future Requirements

Deferred capabilities captured during scoping and research:

### Event-Driven Exceptions

- **EXC-01**: Operator can create scoped rule exceptions directly from selected event context.

### Event Enrichment

- **ENR-01**: Operator can enrich selected events with targeted artifact scanning when signer/hash metadata is incomplete.

### Guided Authoring

- **REC-01**: Operator receives guided bulk strategy recommendations (for example publisher-first vs hash fallback) before committing generated rules.

### Filter Workflow Enhancements

- **FLT-04**: Operator can save and re-apply named filter presets for recurring triage workflows.

### Advanced Safety Analytics

- **RISK-01**: Operator can preview likely impact/blast radius of generated rules before policy promotion.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Full SIEM replacement inside GA-AppLocker | Scope explosion beyond milestone intent; this milestone focuses on event-to-rule operations |
| Auto-create and auto-approve rules from all events | Unsafe in secure environments and bypasses operator review controls |
| Unbounded cross-forest remote event crawling | High reliability/auth complexity and not required for v1 milestone outcomes |
| Real-time streaming event UI without bounded refresh windows | Increases UI churn and risk to responsiveness in PS 5.1 WPF workloads |

## Traceability

| Requirement | Phase | Status |
| --- | --- | --- |
| EVT-01 | Phase 7 | Complete |
| EVT-02 | Phase 7 | Complete |
| EVT-03 | Phase 7 | Complete |
| FLT-01 | Phase 8 | Complete |
| FLT-02 | Phase 8 | Complete |
| FLT-03 | Phase 8 | Complete |
| DET-01 | Phase 8 | Complete |
| DET-02 | Phase 8 | Complete |
| GEN-01 | Phase 9 | Pending |
| GEN-02 | Phase 9 | Pending |
| GEN-03 | Phase 9 | Pending |
| GEN-04 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-17 after roadmap mapping for milestone v1.2.88*
