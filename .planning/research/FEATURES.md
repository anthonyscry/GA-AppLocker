# Feature Research

**Domain:** Enterprise AppLocker admin tooling (rules-index reliability and high-performance policy/rule UIs)
**Researched:** 2026-02-17
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Crash-safe index writes with rollback backup | Enterprise operators expect no data loss after power loss, process kill, or host reboot | MEDIUM | Write `rules-index.json.tmp`, atomically replace main file, keep `.bak` using .NET `File.Replace`; depends on existing `GA-AppLocker.Storage` save path |
| Startup index integrity check + guided self-heal | Operators expect corrupt state to be detected immediately, not after silent bad reads | MEDIUM | Validate JSON parse + schema/hash counts + last-write marker on startup; offer one-click rebuild from rule files; depends on existing repository and index rebuild logic |
| Sub-500ms warm panel transitions | Admin UIs are expected to feel immediate for repeated navigation | MEDIUM | Keep cached panel view-models and counts in memory; invalidate by event when rule/policy state changes; depends on existing session/cache/event helpers |
| Virtualized large-grid rendering by default | Large rule/policy datasets must remain usable without freezing | LOW | Keep row/column virtualization on, avoid template-heavy rows, avoid toggles that disable virtualization (for example `CanContentScroll=false`); depends on existing WPF DataGrid panels |
| Debounced filter/search with progressive results | Users expect typing in filters to not stutter, even with 10k+ rows | LOW | 200-300ms debounce, cancel prior query, render first page fast then complete; depends on current text filter patterns and async helpers |
| Non-blocking bulk operations with clear progress | Operators expect large status/group/action changes to run in background with feedback | MEDIUM | Run bulk mutations in background runspace, show progress + cancel, keep UI responsive via dispatcher marshaling; depends on existing `Invoke-AsyncOperation` and toast/overlay helpers |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Index Health Center (freshness, drift, last good snapshot) | Turns reliability from hidden behavior into operator-trust signal | MEDIUM | Add health card with freshness age, file count vs index count drift, last successful write/rebuild, and one-click repair |
| Latency budget telemetry in UI (panel load SLO badges) | Makes performance regressions visible before users complain | MEDIUM | Capture `panel_enter -> first_rows_rendered` and `filter_apply -> paint` timings; show P50/P95 badges in diagnostics view |
| Predictive prefetch of likely next panels | Makes workflow feel instant for common operator sequences | HIGH | Prefetch read-only datasets for next probable step (Rules -> Policy, Discovery -> Scanner) during idle; must honor low-memory safeguards |
| Deterministic "safe mode" fallback for oversized datasets | Preserves operability under extreme dataset size instead of hanging | MEDIUM | Auto-switch to reduced visuals, capped preview rows, and stricter server/index-backed queries with explicit operator banner |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Auto-refresh every panel every few seconds | Feels "real-time" and reassuring | Thrashes disk/CPU, invalidates caches, causes jittery UI and contention on large datasets | Event-driven invalidation + manual refresh + optional scoped refresh only for active panel |
| Rendering full datasets in one DataGrid pass | Seems simpler than paging/windowing | Causes long UI thread blocks, GC pressure, and delayed input handling | Virtualized rendering plus incremental materialization and fast first paint |
| Silent auto-repair of index on any mismatch | Sounds resilient | Can hide true corruption causes and break forensic/audit expectations in secure environments | Guided repair with explicit audit log entry and before/after metrics |
| Adding heavy client-side analytics to Rules/Policy panels in this milestone | Looks like added value | Competes with primary milestone goal (<500ms transitions and reliability), expands scope | Keep milestone focused on reliability/perf foundations; defer advanced analytics |

## Feature Dependencies

```text
[Crash-safe index writes]
    -> requires -> [Atomic file replace + backup strategy]
    -> enables  -> [Startup integrity check + rollback]

[Startup integrity check + guided self-heal]
    -> requires -> [Rule repository scan + rebuild command]
    -> enables  -> [Index Health Center]

[Virtualized rendering + debounced filters]
    -> requires -> [Panel data pipeline that supports incremental materialization]
    -> enables  -> [Sub-500ms warm transitions]

[Latency budget telemetry]
    -> requires -> [Consistent timing hooks in panel navigation and filter actions]
    -> enhances -> [Performance regression detection and tuning]

[Predictive prefetch]
    -> conflicts -> [Aggressive background scans on low-resource hosts]
```

### Dependency Notes

- **Crash-safe writes require atomic replace semantics:** Without atomic swap+backup, partial writes can leave index unreadable after interruption.
- **Health center requires integrity signals first:** Freshness/drift cards are only trustworthy if startup checks and rebuild pathways exist.
- **<500ms navigation depends on both data and render paths:** Fast query alone is insufficient if DataGrid rendering is not virtualized.
- **Predictive prefetch conflicts with constrained hosts:** In air-gapped admin workstations with limited IO, prefetch must be bounded and cancelable.

## MVP Definition

### Launch With (this milestone)

Minimum viable milestone for reliable, fast operator UX.

- [ ] Crash-safe index write path with backup and rollback-on-failure
- [ ] Startup integrity check with explicit repair/rebuild action
- [ ] Virtualized, debounced Rules/Policy list rendering path with non-blocking panel transitions
- [ ] Bulk operation responsiveness safeguards (background execution + progress/cancel)

### Add After Validation (next milestone)

Features to add once core reliability/performance is stable in field usage.

- [ ] Index Health Center dashboard - add after reliability events and operator support tickets are low
- [ ] Latency budget telemetry badges - add after baseline instrumentation is in place and thresholds are calibrated

### Future Consideration (vNext)

Features to defer until reliability/performance foundation proves stable.

- [ ] Predictive prefetch of likely next panels - defer until memory and IO budget telemetry confirms headroom
- [ ] Safe mode auto-profile tuning - defer until workload archetypes are measured in production-like environments

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Crash-safe index writes + backup | HIGH | MEDIUM | P1 |
| Startup integrity check + guided repair | HIGH | MEDIUM | P1 |
| Virtualized/debounced Rules+Policy UI pipeline | HIGH | MEDIUM | P1 |
| Bulk operation responsiveness controls | HIGH | MEDIUM | P1 |
| Index Health Center | MEDIUM | MEDIUM | P2 |
| Latency budget telemetry badges | MEDIUM | MEDIUM | P2 |
| Predictive prefetch | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for milestone success
- P2: Should have after P1 stability
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Typical Enterprise Admin Tools | Common OSS/Admin Grid Pattern | Our Approach |
|---------|-------------------------------|--------------------------------|-------------|
| Large dataset navigation | Virtualized list/grid with lazy loading and filter-first workflows | DOM/window virtualization and row-model strategies | Keep WPF virtualization on, add staged data materialization, and optimize first paint for Rules/Policy |
| Reliability under interrupted writes | Transactional/atomic writes plus recovery markers | Journal/WAL or atomic-replace patterns | Implement atomic replace + backup for index file and startup validation/repair flow |
| Operator trust in data state | Visible health indicators and explicit refresh controls | Basic status banners/logs | Add explicit index freshness/drift indicators after core reliability improvements land |

## Sources

- Microsoft Learn - Optimize control performance (WPF): https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-controls (updated 2025-08-27) [HIGH]
- Microsoft Learn - `DataGrid.EnableRowVirtualization`: https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagrid.enablerowvirtualization (updated 2026-02-11) [HIGH]
- Microsoft Learn - `System.IO.File.Replace`: https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace (updated 2026-02-11) [HIGH]
- SQLite Documentation - Write-Ahead Logging: https://www.sqlite.org/wal.html (updated 2025-05-31) [MEDIUM, used as reliability pattern reference]
- SQLite Documentation - Atomic Commit: https://www.sqlite.org/atomiccommit.html [MEDIUM, durability pattern reference]
- AG Grid Docs - Row Models: https://www.ag-grid.com/javascript-data-grid/row-models/ [LOW-MEDIUM, ecosystem pattern signal]
- AG Grid Docs - DOM Virtualisation: https://www.ag-grid.com/javascript-data-grid/dom-virtualisation/ [LOW-MEDIUM, ecosystem pattern signal]

---
*Feature research for: GA-AppLocker rules-index reliability and high-performance policy/rule UIs milestone*
*Researched: 2026-02-17*
