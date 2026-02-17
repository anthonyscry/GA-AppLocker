# Architecture Research

**Domain:** PowerShell 5.1 WPF AppLocker management (rules-index reliability + UI hot-path performance)
**Researched:** 2026-02-17
**Confidence:** HIGH (repo architecture) / MEDIUM (recommended additions)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WPF Presentation Layer                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │ MainWindow    │  │ Rules Panel   │  │ Dashboard     │  │ Policy/Deploy│ │
│  │ Nav + Dispatch│  │ Grid + Filters│  │ Counters      │  │ Deferred Load│ │
│  └──────┬────────┘  └──────┬────────┘  └──────┬────────┘  └──────┬──────┘ │
│         │                  │                  │                  │         │
├─────────┴──────────────────┴──────────────────┴──────────────────┴─────────┤
│                         App Logic / Module APIs                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ GA-AppLocker.Storage (RuleStorage + BulkOperations + IndexWatcher)  │  │
│  │ + NEW: IndexHealth + IndexWriteCoordinator + RulesProjectionService │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────────────┤
│                              Local Data Layer                               │
│  ┌────────────────────┐  ┌────────────────────────┐  ┌───────────────────┐ │
│  │ Rules/*.json       │  │ rules-index.json       │  │ NEW *.tmp/*.bak   │ │
│  │ Canonical records  │  │ Read-optimized index   │  │ Atomic writes/reco │ │
│  └────────────────────┘  └────────────────────────┘  └───────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `GUI/MainWindow.xaml.ps1` (modified) | Fast panel switch + deferred panel hydration | Keep `Set-ActivePanel` lightweight; enqueue heavy refresh with dispatcher background priority |
| `GUI/Panels/Rules.ps1` (modified) | Rule list rendering and filtering hot path | Request indexed projection, apply lightweight UI transforms, avoid full payload unless needed |
| `Modules/GA-AppLocker.Storage/Functions/RuleStorage.ps1` (modified) | Authoritative in-memory index + CRUD updates | Keep O(1) maps, route all index mutations through a coordinator |
| `.../IndexWatcher.ps1` (modified) | Detect out-of-band file drift | Debounced watcher triggers health-check-first, rebuild-only-when-needed |
| `.../IndexWriteCoordinator.ps1` (new) | Single-writer gate for `rules-index.json` | Named mutex + temp file + replace/rename swap + backup file |
| `.../IndexHealth.ps1` (new) | Validate index consistency and trigger repair path | Schema checks, duplicate ID checks, file existence checks, repair strategy selector |
| `.../RulesProjectionService.ps1` (new) | Provide read models for UI counters/grids | `Get-RulesProjection -Columns ... -Filters ... -Skip/-Take` to avoid loading full rule payloads |

## Recommended Project Structure

```
GA-AppLocker/
├── GUI/
│   ├── MainWindow.xaml.ps1                        # Modify: panel navigation hot path
│   ├── Helpers/
│   │   └── AsyncHelpers.ps1                       # Modify: pooled async patterns for panel refresh
│   └── Panels/
│       ├── Rules.ps1                              # Modify: projection-based grid updates
│       ├── Dashboard.ps1                          # Modify: projection-based counters
│       └── Policy.ps1 / Deploy.ps1                # Modify: lazy/deferred refresh consistency
└── Modules/GA-AppLocker.Storage/Functions/
    ├── RuleStorage.ps1                            # Modify: route writes through coordinator
    ├── BulkOperations.ps1                         # Modify: batch mutation + single index commit
    ├── IndexWatcher.ps1                           # Modify: health-check before rebuild
    ├── IndexWriteCoordinator.ps1                  # New: atomic + serialized writes
    ├── IndexHealth.ps1                            # New: validation/repair service
    └── RulesProjectionService.ps1                 # New: UI read models
```

### Structure Rationale

- **Storage module owns reliability primitives:** index correctness is a data-layer concern, not a panel concern.
- **Panels consume projections, not storage internals:** keeps UI code simple and fast while preserving module boundaries.
- **No changes to locked paths:** policy export, validation pipeline, and rule import logic remain untouched; only index-adjacent integration points change.

## Architectural Patterns

### Pattern 1: Single-Writer Atomic Index Commit

**What:** All index writes go through one coordinator that writes to temp file, validates, then atomically swaps to `rules-index.json` with backup retention.
**When to use:** Any mutation touching index state (`Add-Rule`, `Update-RuleStatusInIndex`, `Save-RulesBulk`, `Remove-RulesBulk`, rebuild).
**Trade-offs:** Slightly more write latency; significantly better crash/power-loss survivability and less corruption risk.

**Example:**
```powershell
function Save-IndexAtomically {
    param([string]$Json, [string]$IndexPath)

    $mutex = New-Object System.Threading.Mutex($false, 'Global\GA_AppLocker_RulesIndex')
    try {
        [void]$mutex.WaitOne()
        $tmp = "$IndexPath.tmp"
        $bak = "$IndexPath.bak"
        [System.IO.File]::WriteAllText($tmp, $Json, [System.Text.Encoding]::UTF8)
        if (Test-Path $IndexPath) { [System.IO.File]::Copy($IndexPath, $bak, $true) }
        [System.IO.File]::Copy($tmp, $IndexPath, $true)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    finally {
        $mutex.ReleaseMutex() | Out-Null
        $mutex.Dispose()
    }
}
```

### Pattern 2: Health-Check-Then-Repair (Not Always Rebuild)

**What:** Before expensive rebuild, run fast integrity checks and choose targeted repair vs full rebuild.
**When to use:** Startup load failures, watcher-triggered drift, post-crash recovery.
**Trade-offs:** Adds logic complexity; avoids frequent full directory scans and startup stalls.

**Example:**
```powershell
$health = Test-RulesIndexHealth
if (-not $health.Success) {
    if ($health.CanRepairInPlace) {
        Repair-RulesIndexInPlace -Plan $health.RepairPlan
    } else {
        Rebuild-RulesIndex
    }
}
```

### Pattern 3: Projection-First UI Data Access

**What:** Panels request only columns/rows needed for current view, not full rule payloads.
**When to use:** Rules grid, dashboard counters, breadcrumb counts, filter updates, panel navigation refreshes.
**Trade-offs:** Requires an explicit projection API; substantial drop in UI thread work and GC pressure.

## Data Flow

### Request Flow

```
[User Action: Approve/Delete/Bulk Change]
    ↓
[Rules Panel Handler] → [Rules Module Op] → [Storage Mutation]
    ↓                        ↓                 ↓
[UI optimistic state]  [IndexWriteCoordinator]→[rules-index.json + .bak]
    ↓                        ↓                 ↓
[Projection refresh] ← [RulesProjectionService]←[in-memory index maps]
```

### State Management

```
[In-memory index maps: RuleById/HashIndex/PublisherIndex]
    ↓ (read models)
[RulesProjectionService] ←→ [Panel refresh actions] → [DataGrid/Counts]
    ↑
[IndexWriteCoordinator commits + version bump]
```

### Key Data Flows

1. **Mutation flow:** Rule operation updates rule file(s) -> single-writer index commit -> in-memory maps refresh -> projection invalidation -> targeted UI refresh.
2. **Navigation flow:** `Set-ActivePanel` only toggles visibility and schedules deferred data fetch -> panel consumes projection snapshot -> optional background hydrate of heavy details.
3. **Drift recovery flow:** `FileSystemWatcher` event -> debounce -> `Test-RulesIndexHealth` -> targeted repair or rebuild -> toast/log + projection cache invalidate.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0-5k rules | Current in-memory index + projection API is enough; prioritize avoiding synchronous full-grid rebinds |
| 5k-50k rules | Enforce paging/virtualization in Rules panel, cache filter results per projection version, coalesce rapid filter updates |
| 50k+ rules | Add persistent secondary projection files (counts + slim row model), schedule incremental rebuild windows instead of full synchronous repair |

### Scaling Priorities

1. **First bottleneck:** Rules panel full `ItemsSource` replacement and expensive per-row transforms on every filter change; fix with projection + incremental UI updates.
2. **Second bottleneck:** Index write contention and occasional watcher-triggered rebuild storms; fix with single-writer coordinator + health-check gate + rebuild backoff.

## Anti-Patterns

### Anti-Pattern 1: "Any module can write the index directly"

**What people do:** Call `Save-JsonIndex` from multiple paths with no write coordination.
**Why it's wrong:** Race windows and partial writes cause stale or corrupted index state.
**Do this instead:** Route all writes through `IndexWriteCoordinator` and expose one public commit API.

### Anti-Pattern 2: "Panel navigation does data work inline"

**What people do:** Run rule/policy counting or full data loads directly in `Set-ActivePanel`.
**Why it's wrong:** UI thread stalls break sub-500ms transition target.
**Do this instead:** keep navigation to visibility/state only; schedule background/deferred fetch with dispatcher and projection snapshots.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Local filesystem (`%LOCALAPPDATA%\GA-AppLocker`) | Atomic file writes + backup + recovery | Maintain compatibility with air-gapped design; no external service dependency |
| WPF Dispatcher | UI marshaling via `BeginInvoke`/helpers | Keep work items small to preserve responsiveness |
| PowerShell runspaces/jobs | Background execution for heavy data prep | Prefer runspace-based work for lower serialization overhead than background jobs |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `GUI/Panels/*` <-> `GA-AppLocker.Storage` | Module function APIs only | Panels never touch index files directly |
| `RuleStorage.ps1` <-> `IndexWriteCoordinator.ps1` | Direct internal function calls | Coordinator is mandatory write path |
| `IndexWatcher.ps1` <-> `IndexHealth.ps1` | Health-check API before rebuild | Prevent unnecessary rebuild storms |
| `Rules.ps1`/`Dashboard.ps1` <-> `RulesProjectionService.ps1` | Projection query APIs | Supports fast counters and grid rendering |

## Dependency Graph (Build-Order Critical)

```
IndexWriteCoordinator (new)
    -> RuleStorage/BulkOperations write-path refactor (modified)
        -> IndexHealth (new)
            -> IndexWatcher debounce + repair integration (modified)
                -> RulesProjectionService (new)
                    -> Rules/Dashboard/MainWindow hot-path UI updates (modified)
                        -> telemetry + perf gates + regression tests
```

## Suggested Build Order (Lowest Regression Risk)

1. **Introduce write coordinator in Storage module (no UI changes).**
   - Dependency: none.
   - Validation: existing rule CRUD/bulk tests pass, index file remains readable across restart.

2. **Refactor all index write callsites to coordinator + add backup recovery path.**
   - Dependency: step 1.
   - Validation: forced interruption tests (mid-write) recover from `.bak` without manual fix.

3. **Add `IndexHealth` and wire startup/load path before rebuild.**
   - Dependency: step 2.
   - Validation: corrupted/partial index fixture triggers health diagnostics and deterministic repair behavior.

4. **Update watcher flow: debounce -> health check -> targeted repair/rebuild.**
   - Dependency: step 3.
   - Validation: bulk import/delete scenarios do not trigger repeated full rebuild loops.

5. **Add projection service and migrate Dashboard/Breadcrumb counters first.**
   - Dependency: step 3 (or 4 if watcher hooks are required).
   - Validation: startup + Dashboard transitions remain under target with large rule sets.

6. **Migrate Rules panel hot path to projection + incremental refresh.**
   - Dependency: step 5.
   - Validation: filter typing, status changes, and panel transitions remain responsive under 10k+ rules.

7. **Tune and harden (instrumentation, fallback toggles, canary flags).**
   - Dependency: all prior steps.
   - Validation: regression suite + perf baselines; disable switch available if field issues occur.

## Sources

- Repository architecture and current integration points: `CLAUDE.md`, `GA-AppLocker/GUI/MainWindow.xaml.ps1`, `GA-AppLocker/GUI/Panels/Rules.ps1`, `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/RuleStorage.ps1`, `GA-AppLocker/Modules/GA-AppLocker.Storage/Functions/IndexWatcher.ps1` (HIGH confidence)
- WPF threading and dispatcher model (official): https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model (HIGH confidence)
- PowerShell scopes/runspace isolation (official): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-5.1 (HIGH confidence)
- PowerShell jobs overhead and serialization trade-offs (official): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_jobs?view=powershell-5.1 (HIGH confidence)
- `FileSystemWatcher` semantics and overflow/error event (official): https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher?view=netframework-4.8.1 (HIGH confidence)
- `ConvertFrom-Json` behavior in Windows PowerShell 5.1 (official): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-5.1 (MEDIUM relevance, HIGH accuracy)

---
*Architecture research for: GA-AppLocker rules-index reliability and UI hot-path performance milestone*
*Researched: 2026-02-17*
