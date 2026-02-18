# Architecture Research

**Domain:** Event Viewer Rule Workbench integration for GA-AppLocker (local + remote AppLocker events)
**Researched:** 2026-02-17
**Confidence:** HIGH (existing repo boundaries + Microsoft platform behavior), MEDIUM (new exception-generation workflow design)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              WPF Presentation Layer                             │
├──────────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐ │
│  │ MainWindow Nav       │   │ NEW Event Viewer     │   │ Existing Rules Panel │ │
│  │ (modified)           │──▶│ Panel + Filters      │──▶│ + Policy Panel       │ │
│  │ Add NavEventViewer   │   │ (new panel)          │   │ (existing)           │ │
│  └──────────┬───────────┘   └──────────┬───────────┘   └──────────┬───────────┘ │
│             │                          │                           │             │
├─────────────┴──────────────────────────┴───────────────────────────┴─────────────┤
│                           Integration / Domain Modules                            │
├──────────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────────────────────┐ │
│  │ NEW GA-AppLocker.EventViewer module                                         │ │
│  │ - Event query service (local/remote)                                        │ │
│  │ - Event filter/search service (ID/time/path/machine/action)                 │ │
│  │ - Event->candidate mapper (rule + exception candidates)                     │ │
│  └───────────────┬───────────────────────────────┬──────────────────────────────┘ │
│                  │                               │                                │
│         (reuse)  ▼                      (reuse)  ▼                       (reuse)  ▼
│   GA-AppLocker.Credentials         GA-AppLocker.Discovery          GA-AppLocker.Rules
│   tiered credential retrieval       connectivity/host metadata      rule creation pipeline
│                                                                              + GA-AppLocker.Policy
├──────────────────────────────────────────────────────────────────────────────────┤
│                               Local Data / Cache Layer                           │
├──────────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────┐  ┌────────────────────────────┐  ┌────────────────┐ │
│  │ Scans/*.json (existing)│  │ NEW EventQueries/*.json    │  │ Rules/*.json   │ │
│  │ optional enrichment     │  │ query snapshots + metadata │  │ Policies/*.json│ │
│  └────────────────────────┘  └────────────────────────────┘  └────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `GUI/MainWindow.xaml` + `GUI/MainWindow.xaml.ps1` (**modified**) | Add Event Viewer menu option and panel routing without changing existing panel semantics | Add `NavEventViewer`, `PanelEventViewer`, navigation map entry, and panel initializer in current dispatcher pattern |
| `GUI/Panels/EventViewer.ps1` (**new**) | Own Event Viewer UI behavior: query submit, search/filter state, grid actions, single/bulk generation actions | Mirror existing panel style (`Initialize-*Panel`, `Invoke-*` action handlers, no direct module internals) |
| `Modules/GA-AppLocker.EventViewer/GA-AppLocker.EventViewer.psm1` (**new**) | Bounded domain module for event retrieval, shaping, caching, and candidate generation | Return standardized `{ Success, Data, Error }` objects; export only public functions used by GUI |
| `Modules/GA-AppLocker.Scanning/Functions/Get-AppLockerEventLogs.ps1` (**modified, minimal**) | Become shared low-level retrieval function (already exists) | Keep current event collection logic; add optional query object input instead of scanner-only assumptions |
| `Modules/GA-AppLocker.Credentials` (**reuse only**) | Provide tier-aware credentials for remote event retrieval | Use existing `Get-CredentialForTier` fallback chain used in scan workflow |
| `Modules/GA-AppLocker.Discovery` (**reuse only**) | Supply machine lists/connectivity gates for remote path | Reuse selected machine set + connectivity status as preflight before query fan-out |
| `Modules/GA-AppLocker.Rules` (**modified**) | Accept event-derived candidates in existing generation path | Add `ConvertFrom-EventCandidate` -> artifact-like input for `Invoke-BatchRuleGeneration` to avoid duplicate rule logic |
| `Modules/GA-AppLocker.Policy` (**modified, optional phase**) | Apply exception candidates to selected policy context | Introduce explicit API for exception attachment; do not alter export/validation pathways |

## Recommended Project Structure

```
GA-AppLocker/
├── GUI/
│   ├── MainWindow.xaml                                      # Modify: add Event Viewer nav + panel host
│   ├── MainWindow.xaml.ps1                                  # Modify: nav map + action dispatcher + panel init
│   └── Panels/
│       ├── Scanner.ps1                                      # Modify: remove EventViewer-only growth; keep scan metrics lean
│       └── EventViewer.ps1                                  # New: dedicated Event Viewer workflow panel
└── Modules/
    ├── GA-AppLocker.EventViewer/                            # New module
    │   ├── GA-AppLocker.EventViewer.psd1
    │   ├── GA-AppLocker.EventViewer.psm1
    │   └── Functions/
    │       ├── Get-EventWorkbenchData.ps1                   # orchestrates local/remote retrieval
    │       ├── Search-EventWorkbenchData.ps1                # in-memory filter/search
    │       ├── Save-EventQuerySnapshot.ps1                  # optional cache persistence
    │       └── ConvertTo-EventRuleCandidates.ps1            # single/bulk rule + exception candidates
    ├── GA-AppLocker.Scanning/Functions/Get-AppLockerEventLogs.ps1  # Modify: parameterize for workbench reuse
    ├── GA-AppLocker.Rules/Functions/ConvertFrom-Artifact.ps1       # Modify: accept event-derived normalized shape
    └── GA-AppLocker.Policy/Functions/Manage-PolicyRules.ps1        # Modify: add exception attachment API (phase-gated)
```

### Structure Rationale

- **New module instead of stuffing Scanner panel:** scanner is acquisition-oriented; Event Viewer is investigation/action-oriented and needs separate state + actions.
- **Reuse existing retrieval primitive (`Get-AppLockerEventLogs`) first:** lowest-risk path because event collection already works in scan workflows.
- **Reuse existing Rules pipeline by mapping event output to candidate artifacts:** avoids building a second rule generator and keeps dedupe/status behavior consistent.

## Architectural Patterns

### Pattern 1: Query Object + Fan-Out Retrieval

**What:** Build one immutable query object (`timeRange`, `eventIds`, `machines`, `maxEvents`, `searchText`) and pass it to local/remote retrieval paths.
**When to use:** Every Event Viewer fetch request.
**Trade-offs:** Slight upfront mapping complexity; major gain in consistent local/remote behavior and testability.

**Example:**
```powershell
$query = [PSCustomObject]@{
    StartTime  = (Get-Date).AddDays(-7)
    EndTime    = Get-Date
    EventIds   = @(8002, 8003, 8004, 8006, 8007, 8021, 8022, 8024, 8025)
    Machines   = @('LOCALHOST', 'SRV01')
    MaxEvents  = 2000
    SearchText = 'C:\\ProgramData\\'
}

$result = Get-EventWorkbenchData -Query $query
```

### Pattern 2: Candidate Pipeline (Event -> Rule/Exception)

**What:** Convert selected events to normalized candidates, then pass candidates into existing rules/policy actions.
**When to use:** Single-row action and bulk-generation action.
**Trade-offs:** Needs schema discipline; prevents duplication of rule-creation logic.

**Example:**
```powershell
$candidates = ConvertTo-EventRuleCandidates -Events $selectedEvents -Mode Smart
Invoke-BatchRuleGeneration -Artifacts $candidates.RuleArtifacts -Mode Smart -Status Pending

if ($candidates.ExceptionTargets.Count -gt 0) {
    Add-PolicyExceptionsFromCandidates -PolicyId $policyId -Candidates $candidates.ExceptionTargets
}
```

### Pattern 3: UI-Thread Thin, Background Heavy

**What:** UI handlers only collect inputs, trigger background retrieval, and marshal final view-model updates back to dispatcher.
**When to use:** Event retrieval, remote fan-out, and bulk generation.
**Trade-offs:** More plumbing; keeps STA thread responsive and aligned with current app architecture.

## Data Flow

### Request Flow

```
[User opens Event Viewer panel]
    ↓
[PanelEventViewer query form] → [Get-EventWorkbenchData]
    ↓                             ↓
[local machine path]         [remote machine fan-out]
    ↓                             ↓
[Get-WinEvent FilterHashtable] [credential + connectivity gate]
    ↓                             ↓
           [normalized event records + source metadata]
                          ↓
                 [Search-EventWorkbenchData]
                          ↓
                 [EventViewer DataGrid model]
                          ↓
       [single/bulk action: generate rule/exception candidates]
                          ↓
        [Rules module / Policy module APIs, existing persistence]
```

### State Management

```
[Panel state: query + filter + selection]
    ↓
[EventViewer in-memory result set]
    ↓ (derived)
[filtered result set + candidate selection]
    ↓
[optional snapshot cache in %LOCALAPPDATA%\GA-AppLocker\EventQueries]
```

### Key Data Flows

1. **Local query path:** `PanelEventViewer` -> `Get-EventWorkbenchData -Scope Local` -> `Get-WinEvent -FilterHashtable` -> normalized rows -> UI grid.
2. **Remote query path:** `PanelEventViewer` -> machine list from Discovery -> credentials from Credentials -> remote `Get-AppLockerEventLogs` retrieval -> merged rows with `ComputerName` provenance.
3. **Single generation path:** selected grid row -> `ConvertTo-EventRuleCandidates` -> existing Rules creation flow.
4. **Bulk generation path:** selected rows / filtered set -> batch candidate conversion -> chunked rule generation + optional exception attachment.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-10 machines, <=10k events/query | In-memory filtering in panel is sufficient; keep default `MaxEvents` conservative |
| 10-200 machines, <=250k events/query | Add paged retrieval (`-MaxEventsPerHost`), chunked fan-out, and snapshot-based incremental loading |
| 200+ machines or repeated heavy hunts | Move to pre-aggregated summaries (`group by path/eventId`) before shipping to UI; keep full detail on demand |

### Scaling Priorities

1. **First bottleneck:** over-fetching raw remote events and then filtering client-side; fix by server-side `FilterHashtable` narrowing first.
2. **Second bottleneck:** UI grid rebinding with very large result sets; fix with result pagination and action-scope selection (current page vs all filtered).

## Anti-Patterns

### Anti-Pattern 1: Keep extending `Scanner.ps1` for Event Viewer workflows

**What people do:** Add Event Viewer actions into scanner panel/state because event metrics already exist there.
**Why it's wrong:** Scanner file is already large and tied to scan lifecycle state; coupling increases regression risk.
**Do this instead:** Keep scanner event metrics as lightweight scan output; put new investigation workflows in `PanelEventViewer`.

### Anti-Pattern 2: Build a second rule engine for events

**What people do:** Implement separate event-specific rule generation logic.
**Why it's wrong:** Diverges from existing dedupe/status/group behavior and doubles maintenance.
**Do this instead:** Normalize event-derived inputs into the existing Rules pipeline (`Invoke-BatchRuleGeneration`).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Windows Event Log API (`Get-WinEvent`) | `FilterHashtable`-first retrieval for local and remote machines | Official docs explicitly recommend filter methods over `Where-Object` for efficiency |
| PowerShell remoting / WinRM (`Invoke-Command`) | Remote retrieval where current credential and transport controls are required | Align with existing setup/credential model for air-gapped enterprise paths |
| AD/host discovery context | Use existing Discovery machine inventory + connectivity checks | Avoid inventing separate host inventory source |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `GUI/Panels/EventViewer.ps1` <-> `GA-AppLocker.EventViewer` | Public module functions only | UI owns presentation state; module owns retrieval/filter/candidate shaping |
| `GA-AppLocker.EventViewer` <-> `GA-AppLocker.Scanning` | Shared low-level function (`Get-AppLockerEventLogs`) | Keep one authoritative event retrieval implementation |
| `GA-AppLocker.EventViewer` <-> `GA-AppLocker.Credentials` / `GA-AppLocker.Discovery` | Existing function APIs | Reuse current tier + connectivity semantics for remote operations |
| `GA-AppLocker.EventViewer` <-> `GA-AppLocker.Rules` | Candidate artifact hand-off | No direct file writes from EventViewer module |
| `GA-AppLocker.EventViewer` <-> `GA-AppLocker.Policy` | Exception-candidate hand-off (phase-gated) | Medium-confidence area; may need dedicated exception schema decision |

## Dependency Graph (Build-Order Critical)

```
MainWindow nav/panel shell (modified)
    -> GA-AppLocker.EventViewer module skeleton (new)
        -> shared event retrieval reuse from Scanning (modified minimal)
            -> EventViewer panel query/filter UI (new)
                -> single-row rule generation via existing Rules pipeline (modified small)
                    -> bulk generation and batching controls (modified)
                        -> exception-generation integration with Policy module (modified, highest risk)
```

## Suggested Build Order (Lowest Regression Risk)

1. **Add panel shell and navigation only (no business logic).**
   - New vs modified: `MainWindow.xaml`/`.ps1` modified, empty `Panels/EventViewer.ps1` added.
   - Risk containment: proves routing, keyboard/nav, and panel initialization without touching scan/rule code.

2. **Create `GA-AppLocker.EventViewer` module with local query path only.**
   - New vs modified: new module files only.
   - Risk containment: validates result shape and UI responsiveness before remote complexity.

3. **Integrate remote query fan-out using existing Discovery + Credentials patterns.**
   - New vs modified: EventViewer module modified; no Rules/Policy change yet.
   - Risk containment: isolates remote auth/connectivity failures from rule-generation workflows.

4. **Ship filtering/search and snapshot caching on EventViewer results.**
   - New vs modified: EventViewer panel + module modifications.
   - Risk containment: stabilize operator UX and query repeatability before mutation actions.

5. **Add single-row rule generation through existing Rules pipeline.**
   - New vs modified: small Rules integration points + EventViewer action handlers.
   - Risk containment: minimal blast radius, easy rollback if candidate mapping is wrong.

6. **Add bulk rule generation (selection scopes + chunking + progress).**
   - New vs modified: EventViewer panel/module and thin Rules integration.
   - Risk containment: introduce batching after single-path correctness is proven.

7. **Add exception generation/attachment in Policy integration (final phase).**
   - New vs modified: Policy integration points + EventViewer candidate mapping.
   - Risk containment: this is highest uncertainty; keep last so earlier value ships without policy-model churn.

## Sources

- Repo integration points and existing event/reuse opportunities (HIGH confidence):
  - `GA-AppLocker/GUI/MainWindow.xaml.ps1`
  - `GA-AppLocker/GUI/Helpers/KeyboardShortcuts.ps1`
  - `GA-AppLocker/GUI/Panels/Scanner.ps1`
  - `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Get-AppLockerEventLogs.ps1`
  - `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Start-ArtifactScan.ps1`
  - `GA-AppLocker/Modules/GA-AppLocker.Scanning/GA-AppLocker.Scanning.psm1`
- Official `Get-WinEvent` docs (PowerShell 5.1, updated 2026-01-19) (HIGH confidence):
  - https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1
- Official AppLocker Event Viewer reference (updated 2025-02-24) (HIGH confidence):
  - https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/using-event-viewer-with-applocker
- Official WPF threading/dispatcher guidance (updated 2025-08-27) (HIGH confidence):
  - https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model
- Official PowerShell remoting requirements (updated 2025-11-07) (HIGH confidence):
  - https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_remote_requirements?view=powershell-5.1

---
*Architecture research for: Event Viewer Rule Workbench milestone*
*Researched: 2026-02-17*
