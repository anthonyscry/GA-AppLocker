# Project Research Summary

**Project:** GA-AppLocker v1.2.88 Event Viewer Rule Workbench
**Domain:** PowerShell 5.1 WPF enterprise AppLocker operations in air-gapped environments
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

This milestone is an event-driven operations expansion inside an existing mature AppLocker platform, not a new product. The recommended expert pattern is to keep the current in-box stack (PS 5.1, .NET 4.7.2+, WPF, existing GA modules), add a dedicated Event Viewer workbench panel, and route all rule/exception actions back through existing Rules and Policy contracts instead of creating parallel engines.

The strongest implementation approach is phased integration: establish bounded and semantically-correct event ingestion first, then build triage UX and candidate mapping, then add generation actions, and finally add policy integration guardrails. This sequence matches architecture dependencies (query object -> normalization -> candidate pipeline -> rules/policy handoff) and minimizes regression risk against trusted workflows.

Primary risk is unsafe or low-quality automation: unbounded event pulls, wrong event-ID semantics, provenance loss, broad exception synthesis, and policy overwrite behavior can all produce false confidence or outages. Mitigation is explicit guardrails at each phase: bounded query contracts, tested taxonomy mapping, provenance persistence, dedupe/thresholded candidate staging, and merge/snapshot/diff gates before any apply path.

## Key Findings

### Recommended Stack

Research is clear: use in-box Microsoft APIs and existing project helpers; do not add runtime dependencies for this milestone.

**Core technologies:**
- `Get-WinEvent` (PS 5.1): primary local/remote AppLocker event retrieval with server-side filtering for performance and PS 5.1 compatibility.
- `System.Diagnostics.Eventing.Reader` (`EventLogReader`, `EventLogSession`, `EventBookmark`): advanced/resumable query path only where `Get-WinEvent` is limiting.
- AppLocker cmdlets (`Get-AppLockerFileInformation`, `New-AppLockerPolicy`): canonical event-to-policy scaffolding where available.
- WPF `CollectionViewSource`/`ICollectionView` + virtualization: responsive in-memory filtering/search without introducing a new UI stack.

**Critical version/compatibility requirements:**
- PowerShell 5.1 only assumptions (no PS 6+ `<named-data>` hashtable filtering).
- .NET Framework 4.7.2+ (already baseline for GA-AppLocker).
- Keep async retrieval on background runspaces using existing `GUI/Helpers/AsyncHelpers.ps1` patterns.

### Expected Features

`FEATURES.md` recommends a focused v1: event ingestion, triage, and safe candidate generation in one workflow, with impact analytics deferred.

**Must have (table stakes):**
- In-window local + selected-remote AppLocker event ingestion.
- Event-code and metadata filtering (ID/time/host/user/path/signer/outcome).
- Event detail pane with normalized fields plus raw XML/message.
- Single and bulk rule generation from selected events using existing rule engine.
- Bulk dedupe/frequency rollup before generation.
- Basic exception creation path from event context.

**Should have (differentiators):**
- Event-to-artifact enrichment for missing signer/hash fields.
- Guided bulk strategy recommendations for safer rule type choices.

**Defer (v2+):**
- Rule impact blast-radius scoring.
- Advanced exception conflict analysis and graph-aware recommendations.

### Architecture Approach

`ARCHITECTURE.md` recommends a new bounded `GA-AppLocker.EventViewer` module plus a new `GUI/Panels/EventViewer.ps1`, while reusing existing Credentials, Discovery, Scanning retrieval primitives, Rules pipeline, and optional Policy exception APIs. The key pattern is a query-object and candidate-adapter architecture: fetch bounded normalized events, map selections to rule/exception candidates, then hand off to existing persistence/mutation paths.

**Major components:**
1. `GUI/MainWindow.xaml` + `GUI/MainWindow.xaml.ps1` updates - add Event Viewer nav/panel routing.
2. `GUI/Panels/EventViewer.ps1` - query/filter UX, grid actions, selection scope behavior.
3. `Modules/GA-AppLocker.EventViewer` - retrieval orchestration, normalization, search/filter, snapshoting, candidate conversion.
4. `Modules/GA-AppLocker.Scanning` reuse (`Get-AppLockerEventLogs`) - shared low-level event retrieval.
5. `Modules/GA-AppLocker.Rules` and optional `Modules/GA-AppLocker.Policy` integration - consume event candidates, avoid duplicate engines.

### Critical Pitfalls

Top pitfalls from `PITFALLS.md` that must shape planning:

1. **Unbounded retrieval freezes UI** - require bounded query contract (`StartTime`, channel/type, `MaxEvents`) and server-side filtering.
2. **Wrong event semantics generate wrong rules** - implement and test a versioned AppLocker event taxonomy (`ID -> mode/action/collection`).
3. **Remote failures look like clean data** - return per-host success/error envelopes; never coerce host failures to zero events.
4. **Bulk generation rule explosion** - dedupe on stable keys + thresholds + candidate staging (not direct approval).
5. **Unsafe exception/policy apply paths** - block broad writable-path exceptions and require snapshot/diff/explicit merge mode before apply.

## Implications for Roadmap

Based on combined research, suggested phase structure:

### Phase 1: Event Ingestion Foundation
**Rationale:** Every downstream feature depends on trustworthy, bounded, and semantically-correct event data.
**Delivers:** Query contract, local retrieval, remote fan-out with per-host diagnostics, normalized taxonomy model.
**Addresses:** Table-stakes ingestion + event-code filtering foundations.
**Avoids:** Unbounded retrieval, false-clean remote results, semantic mapping errors.

### Phase 2: Triage Workbench UX
**Rationale:** Stabilize operator investigation before mutation actions.
**Delivers:** Event Viewer panel, filter/search UX, detail pane (normalized + raw XML), optional query snapshots, provenance model.
**Addresses:** Table-stakes filtering/detail workflow.
**Implements:** UI-thread-thin/background-heavy pattern and `ICollectionView` filtering.
**Avoids:** STA blocking, provenance loss, scanner/event workflow coupling.

### Phase 3: Candidate Generation Engine
**Rationale:** Add value by turning validated event selections into controlled rule/exception candidates.
**Delivers:** Single and bulk generation actions, dedupe/frequency rollup, fallback order (`Publisher -> Hash -> Path`), confidence tagging, staged candidate status.
**Addresses:** Core single/bulk generation and basic exception authoring.
**Uses:** Existing Rules pipeline via event-candidate adapter.
**Avoids:** Rule explosion, weak path-rule overuse, duplicate rule-engine drift.

### Phase 4: Policy Integration and Governance
**Rationale:** Deployment safety gates are required before promotion beyond candidate/review.
**Delivers:** Exception attachment API hardening, merge/replace explicit mode, snapshot+diff preflight, audit-first promotion checklist.
**Addresses:** Safe end-to-end workflow into policy/deploy lifecycle.
**Avoids:** Policy overwrite, premature enforce rollouts, security-signoff failures.

### Phase 5: Post-MVP Differentiators
**Rationale:** Add intelligence only after core ingestion/triage/generation proves stable.
**Delivers:** Event enrichment and guided bulk strategy recommendations; impact preview remains deferred unless telemetry supports it.
**Addresses:** Differentiators from `FEATURES.md` without destabilizing core flow.
**Avoids:** Premature complexity and SIEM-scope creep.

### Phase Ordering Rationale

- Data trust precedes UX convenience: ingestion semantics must be correct before generation is exposed.
- Architecture boundaries are honored: Event Viewer module adapts to existing Rules/Policy contracts rather than replacing them.
- Highest-risk operations (policy apply and exception safety) are intentionally last with explicit governance gates.

### Research Flags

Phases likely needing deeper `/gsd-research-phase` support:
- **Phase 3:** Exception-candidate schema and low-confidence metadata handling need tighter design validation.
- **Phase 4:** Merge/replace safety UX and enforcement-delta presentation need deployment-specific validation.
- **Phase 5:** Strategy recommendation heuristics need evidence from real operator datasets.

Phases with standard patterns (likely skip extra research):
- **Phase 1:** `Get-WinEvent` + bounded filter patterns are well-documented and low ambiguity.
- **Phase 2:** WPF `ICollectionView` + dispatcher/runspace patterns are established in repo and platform docs.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Microsoft docs + in-box APIs + direct fit to PS 5.1/air-gap constraints. |
| Features | MEDIUM | Table stakes are strong; differentiator sequencing depends on real workload telemetry. |
| Architecture | HIGH | Proposed boundaries map cleanly to existing GA modules; exception API area remains medium-risk. |
| Pitfalls | HIGH | Risks align with both platform behavior and this repo's known historical failure modes. |

**Overall confidence:** HIGH

### Gaps to Address

- **Exception integration contract:** finalize exact shape and validation rules for exception candidates before Phase 3 build-out.
- **Remote transport policy:** decide and document fallback behavior between WinRM-based retrieval and direct event-log RPC where environments differ.
- **Snapshot retention limits:** define retention/pruning for `EventQueries` cache to avoid local bloat on long-running operators.

## Sources

### Primary (HIGH confidence)
- `.planning/research/STACK.md` - stack, API, compatibility, and integration recommendations.
- `.planning/research/ARCHITECTURE.md` - module boundaries, dependency graph, and build order.
- `.planning/research/PITFALLS.md` - phase-mapped failure modes and prevention controls.
- Microsoft Learn docs for `Get-WinEvent`, AppLocker Event Viewer usage, `Get-AppLockerFileInformation`, `New-AppLockerPolicy`, WPF threading, and .NET Eventing APIs.

### Secondary (MEDIUM confidence)
- `.planning/research/FEATURES.md` - feature prioritization and competitive differentiation framing.
- Microsoft WEF/WEC operational guidance used for anti-feature scope boundaries.

### Tertiary (LOW confidence)
- None identified in this research cycle.

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*
