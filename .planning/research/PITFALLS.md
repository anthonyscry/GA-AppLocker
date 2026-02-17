# Pitfalls Research

**Domain:** PowerShell 5.1 WPF enterprise admin tooling (rules-index reliability + panel performance)
**Researched:** 2026-02-17
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Non-atomic rule/index writes create silent divergence

**What goes wrong:**
Rule JSON files and `rules-index.json` drift out of sync after partial failures, interrupted writes, or dual-write paths that update only one side.

**Why it happens:**
Teams add reliability features incrementally (new save paths, bulk update endpoints, dedupe passes) without enforcing one canonical write pipeline and post-write reconciliation.

**How to avoid:**
Adopt a single repository write contract: all rule mutations go through one service that performs (1) rule write, (2) index update, (3) integrity check, (4) compensating repair/retry; add startup reconciliation that repairs known drift patterns.

**Warning signs:**
UI counts differ between panels, hash lookup misses existing rules, duplicate-detection returns false negatives, or user actions report success but list views do not reflect changes after refresh.

**Phase to address:**
Phase 2 - Index reliability foundations (canonical mutation path + reconciliation job).

---

### Pitfall 2: O(n^2) collection patterns in hot paths

**What goes wrong:**
Rules and scan result operations degrade sharply at scale because loops use `$array += $item` and repeated JSON conversion/reparse.

**Why it happens:**
PowerShell-friendly syntax hides algorithmic cost; code that is fast with test data becomes unusable with enterprise-size datasets.

**How to avoid:**
Standardize on `[System.Collections.Generic.List[T]]` for accumulation and `[System.Text.StringBuilder]` for large string/JSON emission; add perf guardrails in review checklist for any loop touching many rules/artifacts.

**Warning signs:**
CPU spikes during bulk status updates, pauses on filter changes, growing latency after each append loop, and operations that scale superlinearly with rule count.

**Phase to address:**
Phase 1 - Baseline and profiling (identify hot paths) and Phase 3 - Panel performance optimization.

---

### Pitfall 3: UI thread blocking from "small" synchronous calls

**What goes wrong:**
Panels freeze because seemingly harmless operations (WMI calls, large JSON parse, full repository reads, synchronous waits) execute on the STA thread.

**Why it happens:**
Incremental feature work wires data refresh directly to button handlers/navigation events, and each call looks cheap in isolation.

**How to avoid:**
Enforce a hard rule: UI handlers only orchestrate; heavy work runs in background runspaces/jobs; marshal minimal result payloads back with dispatcher-safe UI update helpers.

**Warning signs:**
Window stops repainting during refresh, spinner/overlay never updates, click latency exceeds 200-300ms, or panel navigation intermittently hangs.

**Phase to address:**
Phase 3 - UI throughput optimization (event-path audit + async execution model).

---

### Pitfall 4: Scope boundary bugs between script/global/runspace contexts

**What goes wrong:**
Timer callbacks, runspace callbacks, and background actions cannot see expected state/functions, causing silent no-ops or partial UI updates.

**Why it happens:**
PowerShell scope behavior differs across module scope, `global:` functions, and separate runspaces; developers assume `$script:` resolves to module state everywhere.

**How to avoid:**
Define explicit scope contracts: global callback functions only read/write approved global bridge variables; runspace code receives complete input explicitly; avoid implicit state capture.

**Warning signs:**
"Function not recognized" in logs from background paths, timers stop updating with no UI error, and values become `$null` only in callback/runspace execution.

**Phase to address:**
Phase 2 - Reliability hardening (scope contract refactor + callback audit).

---

### Pitfall 5: Pipeline pollution from unsuppressed `.Add()`/`.Remove()` return values

**What goes wrong:**
Functions return unexpected integers mixed with result objects, corrupting downstream logic and sometimes index update pipelines.

**Why it happens:**
In PS 5.1, many mutator methods return values; if not cast to `[void]` (or assigned to `$null`), those values leak to pipeline output.

**How to avoid:**
Make suppression mandatory for mutator methods in all storage/index/UI data functions; add lint/test checks that validate function output shape.

**Warning signs:**
Random `0/1/2...` values in output streams, hashtable/object parsing failures, or intermittent failures only in batched operations.

**Phase to address:**
Phase 2 - Index reliability hardening (output contract enforcement).

---

### Pitfall 6: Over-virtualized assumptions in DataGrid performance tuning

**What goes wrong:**
Team assumes virtualization is "done" while custom row templates, grouping, or frequent full rebinding still force expensive row/materialization churn.

**Why it happens:**
`EnableRowVirtualization` defaults to true, leading to false confidence; real bottlenecks shift to churn from reset-style updates and heavy cell templates.

**How to avoid:**
Optimize update strategy before cosmetics: prefer incremental item updates over full `ItemsSource` resets, keep templates lean, and verify virtualization behavior under realistic row counts.

**Warning signs:**
Scroll jitter at large row counts, frequent GC during filter/sort, and row load/unload storms after minor data changes.

**Phase to address:**
Phase 3 - Panel performance optimization (DataGrid update strategy + template diet).

---

### Pitfall 7: Job model mismatch (serialization vs speed vs isolation)

**What goes wrong:**
Background work either becomes too slow (serialization-heavy jobs) or too fragile (in-process thread failures), producing reliability regressions while chasing speed.

**Why it happens:**
`Start-Job`/remoting-style jobs serialize objects; thread-style execution is faster but shares process risk. Teams pick one model globally instead of per workload.

**How to avoid:**
Split strategy by task: use low-overhead in-process concurrency for high-frequency local compute; isolate risky/long-running operations where crash containment matters; normalize DTOs crossing boundaries.

**Warning signs:**
Large object marshalling overhead, missing methods on deserialized objects, or one background failure cascading into broader UI/process instability.

**Phase to address:**
Phase 1 - Concurrency architecture decision, then Phase 3 execution.

---

### Pitfall 8: Reliability changes that regress operator workflows

**What goes wrong:**
Index healing, background refreshes, or stricter validation degrade operator trust by changing button behavior, status freshness, or workflow timing.

**Why it happens:**
Engineering prioritizes technical correctness without preserving existing workflow contracts (selection persistence, deterministic button actions, status readability).

**How to avoid:**
Define workflow invariants up front (what must never change), gate optimizations behind behavior regression tests, and ship telemetry/toasts that explain self-healing actions.

**Warning signs:**
Operators report "button does nothing," selected rows reset after refresh, or actions require repeated clicks where they were previously one-step.

**Phase to address:**
Phase 4 - Workflow regression hardening and rollout validation.

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Adding a second index-write path "just for bulk ops" | Faster delivery | Dual semantics and drift bugs | Never |
| Full index rebuild after every mutation | Easy correctness story | Large I/O, UI stalls, poor scale | Only temporary emergency fallback |
| Catch-and-ignore in data/update paths | Fewer visible errors | Silent corruption and hard debugging | Never |
| Rebinding entire DataGrid on every filter keystroke | Simple implementation | Jank and GC churn at scale | MVP only with tiny datasets |

## Integration Gotchas

Common mistakes when connecting reliability/perf mechanisms to existing modules.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Storage + Rules modules | Updating rule files but forgetting index update API | Route all mutations through Storage contract that owns index sync |
| Runspace helpers + UI panels | Updating WPF controls directly from background threads | Return DTOs and marshal UI updates through dispatcher helper |
| Timer callbacks + module state | Using `$script:` state inside `global:` callback | Use explicit global bridge state or injected callback context |
| Validation + save pipeline | Running full validation synchronously on UI action path | Stage lightweight synchronous checks, defer heavy validation off-thread |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Per-row UI update loops | Freeze during bulk operations | Batch updates and refresh UI periodically (coarse-grained) | ~1k+ row updates in one action |
| JSON parse/serialize in navigation handlers | Slow panel switching | Cache summaries/counters; lazy load details | 100s-1000s of policy/rule files |
| Frequent full text filtering without debounce | Typing lag in filter box | Debounce input and avoid full collection rebuilds | 5k+ displayed rows |
| Overuse of synchronous WMI/network calls | Random 10-30s hangs | Move to background + timeout-aware APIs | Air-gapped/unreliable network segments |

## Security Mistakes

Domain-specific security/reliability concerns for this milestone.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging full rule payloads or credentials in new diagnostics | Sensitive data leakage in local logs | Redact sensitive fields and gate debug verbosity |
| Broad `global:` exposure for convenience | Accidental cross-module mutation, harder auditability | Minimize global surface and document approved globals |
| Skipping integrity checks on index repair | Persisting tampered/corrupt metadata | Validate schema + key fields before accepting repaired entries |

## UX Pitfalls

Common user experience mistakes in this milestone context.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Background repair with no user feedback | Users distrust stale/changed counts | Show concise toast/status banner with repair outcome |
| "Loading" overlays that can stall indefinitely | App appears broken | Add operation timeout + auto-hide + retry guidance |
| Performance tweaks that reset selections/filters | Extra operator work, error-prone reruns | Preserve selection/filter state across refresh cycles |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Index reliability:** Create/update/delete paths all hit one canonical mutation API and all pass drift tests.
- [ ] **UI responsiveness:** No panel event path performs blocking I/O or full repository reads on STA thread.
- [ ] **Runspace safety:** Every background callback has explicit scope/data contract; no implicit `$script:` dependency.
- [ ] **Output contracts:** Data functions emit only standardized result objects; no leaked scalar pipeline values.
- [ ] **Workflow stability:** Selection, filters, and button semantics remain unchanged under background refresh/healing.

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Rule/index drift in production | MEDIUM | Freeze writes, run reconciliation, rebuild index from rule source of truth, validate counts/hash lookups, resume writes |
| UI freeze introduced by optimization | LOW-MEDIUM | Capture event-path timings, move offending call off-thread, add timeout/cancellation, ship hotfix |
| Scope/runspace callback silent failures | MEDIUM | Add targeted diagnostic logs, replace implicit scope access with explicit parameters/global bridge, add regression tests for callback paths |

## Pitfall-to-Phase Mapping

How future milestone phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Non-atomic rule/index writes | Phase 2 (Reliability core) | Mutation contract tests + forced-failure recovery tests pass |
| O(n^2) collection and JSON patterns | Phase 1 (Profiling) + Phase 3 (Optimization) | Benchmarks show near-linear scaling in core bulk workflows |
| STA thread blocking | Phase 3 (UI execution model) | UI latency budget checks pass during large-data operations |
| Scope/runspace boundary bugs | Phase 2 (Scope hardening) | Callback/runspace integration tests pass with diagnostics clean |
| Pipeline output pollution | Phase 2 (Output contract enforcement) | Pester tests validate strict result shape for storage/rules APIs |
| Virtualization false confidence | Phase 3 (DataGrid tuning) | Scroll and filter performance tests pass at representative row counts |
| Job model mismatch | Phase 1 (Concurrency decisions) | Concurrency matrix validated for throughput and fault containment |
| Workflow regressions | Phase 4 (Operator hardening) | End-to-end operator workflow tests pass unchanged |

## Sources

- Microsoft Learn - `about_Scopes` (PowerShell 5.1), updated 2026-01-16: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-5.1
- Microsoft Learn - `about_Jobs` (PowerShell 5.1), updated 2025-12-15: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_jobs?view=powershell-5.1
- Microsoft Learn - WPF Threading Model, updated 2025-08-27: https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model
- Microsoft Learn - `BindingOperations.EnableCollectionSynchronization`, updated 2026-02-11: https://learn.microsoft.com/en-us/dotnet/api/system.windows.data.bindingoperations.enablecollectionsynchronization?view=windowsdesktop-9.0
- Microsoft Learn - `DataGrid.EnableRowVirtualization`, updated 2026-02-11: https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagrid.enablerowvirtualization?view=windowsdesktop-9.0
- Project engineering guide and incident history: `/mnt/c/projects/GA-AppLocker/CLAUDE.md` (high-confidence project-specific failure modes)

---
*Pitfalls research for: PS 5.1 WPF rules-index reliability and panel performance milestone*
*Researched: 2026-02-17*
