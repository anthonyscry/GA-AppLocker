# Project Research Summary

**Project:** GA-AppLocker v1.2.87 Performance milestone
**Domain:** PowerShell 5.1 WPF enterprise AppLocker policy-management tooling (air-gapped)
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

This milestone is a reliability-and-performance hardening effort for an existing enterprise admin product, not a greenfield build. The research is aligned: keep the current PS 5.1 + WPF + local JSON architecture, and fix the failure points that hurt operators at scale (index drift/corruption risk, slow panel transitions, and UI thread blocking). Experts in this space favor deterministic local durability patterns and projection-first UI data access over introducing new infrastructure.

The recommended approach is to strengthen the storage write/read contract first, then migrate UI hot paths to lightweight read models. Specifically: enforce a single-writer atomic index commit path with backup/repair semantics, add startup/watcher health checks before rebuilds, and move Rules/Policy/Dashboard panel reads to projection-based incremental loading with strict dispatcher/runspace boundaries. This sequencing lowers regression risk while creating measurable progress toward the <500ms transition target.

The biggest risks are regressions from scope/runspace mistakes, hidden O(n^2) collection patterns, and workflow breakage from aggressive reliability changes. Mitigation is explicit phase gating: add canonical mutation contract tests early, profile and instrument timing before tuning, and preserve workflow invariants (selection/filter/action behavior) during rollout with targeted regression checks.

## Key Findings

### Recommended Stack

Research points to stack hardening, not stack replacement. Keep runtime pinned to PowerShell 5.1 and .NET Framework 4.7.2+ with existing WPF UI and GA-AppLocker modules. No new runtime/package dependencies are required for this milestone.

**Stack additions/changes for this milestone:**
- **`System.IO.File.Replace` + `.tmp/.bak` strategy:** atomic index commit + rollback safety for `rules-index.json`.
- **`ReaderWriterLockSlim` around in-memory index maps:** prevent race conditions across UI and background paths.
- **`FileSystemWatcher` workflow change:** debounce to dirty-state + health-check-first, not blind rebuild loops.
- **`Stopwatch` + structured logging fields:** enforce measurable panel/filter latency budgets.
- **Projection service in Storage module:** fast counter/grid reads without full rule payload hydration.

### Expected Features

The features research is clear: P1 must restore operator trust (durability + self-heal) and responsiveness (fast navigation/filtering + non-blocking bulk actions). Differentiators should follow only after P1 behavior is stable in real workflows.

**Feature table stakes (must have):**
- Crash-safe index writes with backup/rollback.
- Startup integrity check with guided repair/rebuild.
- Sub-500ms warm panel transitions via virtualization + debounced filtering + projection-first reads.
- Non-blocking bulk operations with progress/cancel and dispatcher-safe updates.

**Feature differentiators (should have after P1):**
- Index Health Center (freshness, drift, last-good snapshot, repair action).
- UI latency telemetry badges (P50/P95 diagnostics for panel/filter operations).

**Defer (v2+):**
- Predictive panel prefetch (high complexity and resource-conflict risk on constrained hosts).
- Auto-tuned safe mode profiles until workload telemetry exists.

### Architecture Approach

The architecture recommendation is to make Storage the reliability authority and make UI panels consumers of explicit projections. New core components are `IndexWriteCoordinator`, `IndexHealth`, and `RulesProjectionService`; modified integration points are `RuleStorage`, `BulkOperations`, `IndexWatcher`, `MainWindow`, `Rules`, `Dashboard`, and deferred-load behavior in `Policy`/`Deploy`.

**Integration architecture/build order:**
1. Introduce `IndexWriteCoordinator` and route all index writes through one commit API.
2. Refactor mutation callsites + add backup recovery path.
3. Add `IndexHealth` for startup and failure-path diagnostics/repair decisions.
4. Rewire watcher flow to health-check-first with conditional repair/rebuild.
5. Add `RulesProjectionService`; migrate counters first, then Rules panel hot paths.
6. Add latency instrumentation, fallback toggles, and regression/perf gates.

### Critical Pitfalls

**Top pitfalls and prevention:**
1. **Non-atomic dual-write drift** - prevent with one canonical mutation pipeline and atomic commit semantics.
2. **O(n^2) data path behavior** - ban `$array +=`; use `List[T]`/`StringBuilder` and perf-check reviews for large loops.
3. **STA thread blocking** - keep UI handlers orchestration-only; move heavy I/O/parse work to background runspaces.
4. **Scope/runspace boundary failures** - define explicit callback scope contracts and avoid implicit `$script:` assumptions.
5. **Pipeline pollution from mutator return values** - enforce `[void]`/`$null =` suppression and strict output-shape tests.

## Implications for Roadmap

Based on combined research, suggested phase structure:

### Phase 1: Baseline, Profiling, and Concurrency Contract
**Rationale:** Establish measurable baselines and lock job/runspace strategy before refactors to avoid tuning blind.
**Delivers:** Hot-path timing baselines, concurrency decision matrix, and performance guardrail checklist.
**Addresses:** P1 responsiveness prerequisites (filter/navigation latency visibility).
**Avoids:** O(n^2) tuning blind spots and job-model mismatch pitfalls.

### Phase 2: Index Reliability Core
**Rationale:** Data correctness is a hard dependency for all UI/perf work; fix durability first.
**Delivers:** Single-writer atomic commit, startup integrity checks, repair/rebuild path, and watcher health-gated flow.
**Addresses:** Crash-safe writes, startup self-heal, canonical mutation behavior.
**Avoids:** Non-atomic divergence, scope/output-contract reliability failures.

### Phase 3: Projection-First UI Throughput
**Rationale:** Once index integrity is deterministic, optimize panel hot paths without destabilizing persistence.
**Delivers:** Projection service, incremental grid refresh, debounced filters, async panel hydration for Rules/Policy/Dashboard.
**Addresses:** Sub-500ms transitions, large-grid usability, non-blocking bulk ops.
**Avoids:** STA blocking and virtualization false-confidence anti-patterns.

### Phase 4: Workflow Regression Hardening + Operator Trust UX
**Rationale:** Reliability/perf changes must preserve operator semantics and explain system actions.
**Delivers:** Workflow invariant tests, selection/filter persistence checks, repair outcome toasts/status messaging.
**Addresses:** Usability stability under background healing/refresh.
**Avoids:** "Button does nothing" regressions and trust loss from silent repair behavior.

### Phase 5: Post-Stability Differentiators
**Rationale:** Add visibility features only after P1-P4 are stable in field-like data conditions.
**Delivers:** Index Health Center and latency SLO badges.
**Addresses:** Faster operations triage and proactive regression detection.
**Avoids:** Scope creep that competes with reliability goals.

### Recommended Milestone Phasing Implications

- Front-load reliability primitives (storage contract) before UI optimizations; this aligns with dependency graph and minimizes rollback risk.
- Group architecture work by ownership boundary (Storage first, then panel consumers) to reduce cross-module breakage.
- Gate each phase with explicit verification artifacts (contract tests, forced-failure recovery checks, latency thresholds, workflow regressions).
- Treat differentiators as conditional scope that only starts after P1-P4 acceptance criteria pass.

### Research Flags

Phases likely needing deeper `/gsd-research-phase` support:
- **Phase 3:** WPF virtualization behavior under real templates + incremental update strategy details for 10k+ rows.
- **Phase 5:** Diagnostics UX calibration (SLO thresholds and alert semantics that are helpful but not noisy).

Phases with standard patterns (likely skip extra research):
- **Phase 2:** Atomic write/backup/recovery and health-check gate patterns are well-documented and directly applicable.
- **Phase 4:** Workflow-regression test harness patterns are already established in repo testing practice.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | In-box .NET/PS 5.1 APIs with strong official documentation and direct fit to current architecture. |
| Features | MEDIUM | Prioritization is strong, but differentiator timing depends on field workload variability. |
| Architecture | HIGH | Build order and boundaries map cleanly to existing modules and known hot paths. |
| Pitfalls | HIGH | Pitfalls align with project incident history and official PS/WPF behavior constraints. |

**Overall confidence:** HIGH

### Gaps to Address

- **Latency thresholds by environment:** Define practical P50/P95 budgets per panel using representative 5k/10k/50k rule datasets before hard pass/fail gates.
- **Repair policy specificity:** Decide when to auto-repair in place vs force explicit operator confirmation in high-assurance environments.
- **Concurrency boundary details:** Finalize exact split of runspace vs job usage per workload type with failure-containment criteria.

## Sources

### Primary (HIGH confidence)
- `.planning/research/STACK.md` - official API-backed stack and integration recommendations.
- `.planning/research/ARCHITECTURE.md` - repository-grounded boundaries, dependency graph, and low-risk build order.
- `.planning/research/PITFALLS.md` - project-specific failure patterns cross-checked with official PS/WPF guidance.
- Microsoft Learn: `System.IO.File.Replace`, `ReaderWriterLockSlim`, `Stopwatch`, WPF threading model, `BindingOperations.EnableCollectionSynchronization`, `DataGrid` virtualization, `FileSystemWatcher`, `about_Scopes`, `about_Jobs`.

### Secondary (MEDIUM confidence)
- `.planning/research/FEATURES.md` - milestone feature prioritization and sequencing.
- SQLite WAL/atomic commit docs - reference patterns for durability trade-off framing.

### Tertiary (LOW confidence)
- AG Grid documentation used only as cross-ecosystem virtualization/paging pattern signal.

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*
