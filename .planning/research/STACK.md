# Stack Research

**Domain:** PowerShell 5.1 WPF enterprise policy-management app (air-gapped)
**Researched:** 2026-02-17
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Windows PowerShell | 5.1 (pinned) | Runtime and module host | Keep runtime fixed for compatibility with existing code, tests, and deployment footprint in classified/air-gapped Windows estates. |
| .NET Framework BCL | 4.7.2+ | Reliability and performance primitives (`System.IO`, `System.Diagnostics`, `System.Threading`) | All required primitives for index hardening and low-latency UI exist in-box; no external runtime dependency needed. |
| WPF (PresentationFramework/WindowsBase) | .NET Framework 4.7.2+ | UI thread model and virtualization | Existing app already uses WPF; target should be stricter dispatcher discipline and virtualization tuning, not UI stack replacement. |
| GA-AppLocker Storage index layer | Current module (`GA-AppLocker.Storage`) | Single source of truth for rule metadata access | Already has `Get-AllRules`, `Get-RuleCounts`, `Get-RulesFromDatabase`, `IndexWatcher`; milestone should harden this path instead of adding parallel data systems. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `System.IO.File.Replace` | .NET Framework 4.7.2+ | Atomic swap of rebuilt `rules-index.json` with backup | Use for every index write/rebuild commit path to prevent partial/truncated index files on crash/power loss. |
| `System.Threading.ReaderWriterLockSlim` | .NET Framework 4.7.2+ | Guard in-memory index maps (`JsonIndex`, `RuleById`, `HashIndex`) | Use around all read/write access to script-scoped index structures from UI + runspace paths. |
| `System.IO.FileSystemWatcher` | .NET Framework 4.7.2+ | Detect out-of-band rule file changes | Keep existing watcher but move from "blind rebuild" to "mark-dirty + validate + conditional rebuild" state machine. |
| `System.Diagnostics.Stopwatch` | .NET Framework 4.7.2+ | High-resolution timing for panel transition SLOs | Instrument panel init and grid bind hot paths; log p50/p95 and enforce sub-500ms budget in test harness scripts. |
| `System.Windows.Threading.Dispatcher.BeginInvoke` | .NET Framework 4.7.2+ | Non-blocking UI marshaling | Use for all UI updates from background work; avoid synchronous dispatcher calls in hot paths. |
| `System.Windows.Data.BindingOperations.EnableCollectionSynchronization` | .NET Framework 4.7.2+ | Safe multi-thread collection access for bound controls | Use only where background updates touch bound collections; register once on UI thread before cross-thread mutation. |
| `System.Collections.Concurrent.ConcurrentQueue<T>` | .NET Framework 4.7.2+ | Buffer/batch UI update notifications | Use for coalescing frequent background updates before one dispatcher flush (prevents UI event-queue saturation). |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `Measure-Command` (PS 5.1) | Quick timing checks for candidate hot paths | Use for script-level experiments; remember it executes in current scope. |
| Pester (existing project usage) | Regression and performance guardrails | Add targeted performance assertions around panel transitions and index fallback behavior; do not run UI tests in non-interactive contexts. |
| Existing GA logging (`Write-AppLockerLog`) | Operational telemetry | Add structured timing/rebuild-cause fields so reliability/perf regressions are diagnosable post-deploy. |

## Installation

```bash
# Core runtime additions
# None. Use in-box PowerShell 5.1 + .NET Framework 4.7.2+ APIs only.

# Supporting packages
# None. Avoid new NuGet/PowerShell Gallery runtime dependencies for air-gapped environments.

# Dev dependencies
# None required for milestone start; continue using existing Pester/tooling already in repo.
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Harden existing JSON index with atomic write + lock discipline | Introduce SQLite/LiteDB | Only if future scale requires ad-hoc query semantics beyond indexed lookups and the org accepts new binary/runtime supply-chain burden. |
| Index-first reads + selective payload hydration | Always load full rule JSON files | Only acceptable for tiny datasets; does not meet sub-500ms transitions at enterprise rule counts. |
| Runspace/dispatcher model already in app | `Start-Job` for UI-adjacent work | Use `Start-Job` only for isolated background ops with no UI coupling; not for panel hot paths due to overhead and scope complexity. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Adding SQLite/LiteDB in this milestone | Violates "minimal moving parts" for air-gap, adds migration and operational complexity without necessity for current goals | Keep JSON index; add integrity metadata, atomic commit, and deterministic rebuild path |
| Synchronous heavy calls in panel initialization (`Get-AllRules -Take 100000` style in hot path) | Blocks STA thread and directly harms transition latency | Load index summaries first, then async/deferred hydration for details |
| Rebuild-on-every-file-event behavior | Causes avoidable churn and inconsistent UX under burst writes | Debounced dirty-flag + validation checkpoint + conditional rebuild |
| Large `ConvertTo-Json` pipelines for full index writes | Known PS 5.1 performance cost on big payloads; higher timeout risk | Keep StringBuilder serializer path, then atomic `File.Replace` commit |

## Stack Patterns by Variant

**If the workflow only needs counts/lists for navigation (panel transition path):**
- Use `Get-RuleCounts` / lightweight index entries only
- Because sub-500ms transitions require minimal allocation and no per-rule file reads

**If the workflow needs full rule details for selected rows/actions:**
- Use two-stage fetch: index-backed list first, hydrate details on demand (selection, expand, action)
- Because it preserves responsive navigation while still supporting deep operations

**If rule files may be modified externally or during bulk operations:**
- Use watcher to mark index dirty, validate manifest/hash snapshot, then rebuild once
- Because reliability comes from deterministic recovery, not from constant speculative rebuilds

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `System.IO.File.Replace` (.NET Framework 4.7.2+) | PowerShell 5.1 (`mscorlib`) | Requires source/destination on same volume; supports backup file creation for rollback safety. |
| `ReaderWriterLockSlim` (.NET Framework 4.7.2+) | PowerShell 5.1 runspaces | Thread-safe for concurrent readers/exclusive writers; suitable for shared index dictionaries. |
| `Dispatcher.BeginInvoke` + WPF controls | Existing GA-AppLocker WPF shell | Keep all control mutation on UI thread; use async dispatch to avoid blocking. |
| `BindingOperations.EnableCollectionSynchronization` (4.5+) | WPF DataGrid/List controls | Must be called on UI thread before cross-thread collection use; helps avoid collection thread-affinity exceptions. |
| `VirtualizingPanel.IsVirtualizing/VirtualizationMode=Recycling` | Existing `MainWindow.xaml` DataGrid style | Already present; keep and verify every high-volume grid follows this style. |

## Integration Implications (Concrete)

- `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/RuleStorage.ps1`: wrap `Initialize-JsonIndex`, read/query methods, and `Save-JsonIndex`/rebuild mutation paths in explicit RW lock boundaries; add atomic temp-write + `File.Replace` commit strategy.
- `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/IndexWatcher.ps1`: evolve from immediate debounced rebuild to dirty-state coordinator (`dirty`, `rebuildInProgress`, `lastValidIndex`) with validation-before-rebuild and single-flight rebuild.
- `GA-AppLocker/GUI/Panels/Rules.ps1`: replace synchronous full-load hot path in `Refresh-RulesGrid` with index-first async load and deferred full payload fetch for selected/visible slices.
- `GA-AppLocker/GUI/Helpers/AsyncHelpers.ps1`: centralize transition timing (`Stopwatch`) and enforce "no blocking work on STA" guardrail via helper wrappers and warning logs.
- `GA-AppLocker/GUI/MainWindow.xaml.ps1`: instrument panel navigation checkpoints and emit per-panel latency metrics (cold/warm) so sub-500ms target is measurable, not anecdotal.

## Sources

- Microsoft Learn: `System.IO.File.Replace` (netframework monikers include 4.7.2/4.8.1) - atomic replacement semantics, backup behavior, same-volume constraint. (HIGH)
- Microsoft Learn: `System.Threading.ReaderWriterLockSlim` - thread-safe reader/writer lock model. (HIGH)
- Microsoft Learn: `System.Diagnostics.Stopwatch` - high-resolution timing and frequency semantics. (HIGH)
- Microsoft Learn: `System.Windows.Threading.Dispatcher.BeginInvoke` - async UI-thread dispatch behavior and thread-affinity guidance. (HIGH)
- Microsoft Learn: `System.Windows.Data.BindingOperations.EnableCollectionSynchronization` - cross-thread collection synchronization contract and UI-thread registration requirements. (HIGH)
- Microsoft Learn: `System.Windows.Controls.VirtualizingPanel.IsVirtualizing` and `VirtualizationMode` - virtualization and recycling behavior for item controls. (HIGH)
- Microsoft Learn: `System.IO.FileSystemWatcher` - event model and overflow/error considerations. (HIGH)
- Microsoft Learn: `Measure-Command` (`powershell-5.1`) - timing cmdlet behavior and scope note. (HIGH)

---
*Stack research for: GA-AppLocker v1.2.87 performance/reliability milestone*
*Researched: 2026-02-17*
