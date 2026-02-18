# Stack Research

**Domain:** Event Viewer rule workbench inside existing PowerShell 5.1 WPF AppLocker tool
**Researched:** 2026-02-17
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `Get-WinEvent` (`Microsoft.PowerShell.Diagnostics`) | PowerShell 5.1 | Primary event retrieval for local and remote AppLocker logs | It is the native API for modern Windows Event Log channels, supports `-FilterHashtable`, `-FilterXPath`, and `-FilterXml`, and is explicitly documented for remote use with `-ComputerName`. |
| `System.Diagnostics.Eventing.Reader` (`EventLogQuery`, `EventLogReader`, `EventLogSession`, `EventBookmark`) | .NET Framework 4.7.2+ (already in-box) | Advanced query control, remote session targeting, and resumable reads | Use this only where `Get-WinEvent` becomes limiting (bookmark resume, long-running paging, strict query control). It keeps everything in-box and PS 5.1 compatible. |
| AppLocker cmdlets (`Get-AppLockerFileInformation`, `New-AppLockerPolicy`) | Windows AppLocker module (server/client SKUs where available) | Canonical file-info extraction from AppLocker events and policy/rule scaffolding | Microsoft explicitly supports event-log-driven policy creation through these cmdlets; use for batch conversion paths and consistency with native AppLocker semantics. |
| WPF collection view stack (`CollectionViewSource` + `ICollectionView`) | PresentationFramework/WindowsBase in .NET Framework 4.7.2+ | Fast in-memory filtering/search UX over already-fetched events | This is the right in-place UX stack for existing WPF: shared view, predicate filtering, deferred refresh batching, and no new UI framework cost. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Get-WinEvent -FilterHashtable` | PS 5.1 | Server-side prefilter by `LogName`, `ID`, `StartTime`, `EndTime`, `Level`, `ProviderName` | Default filter mode for Event Viewer panel and remote queries; avoids pulling huge unfiltered logs into memory. |
| `Get-WinEvent -FilterXml` | PS 5.1 + Win32 query schema | Complex include/exclude logic across channels and predicates | Use only when UI filter combinations outgrow hashtable capabilities; generate XML from known templates, not free-form user text. |
| `EventRecord.ToXml()` | .NET Framework 4.7.2+ | Stable access to structured event payload fields | Use to map event metadata (`EventData`) to rule inputs; avoid brittle message-string regex extraction as primary parser. |
| `ICollectionView.Filter` + `ICollectionView.DeferRefresh()` | WPF | Responsive search and multi-filter UI updates | Use for text search + event-code filters so every checkbox/keystroke does not trigger full rebind churn. |
| `DataGrid.EnableRowVirtualization` + `VirtualizingPanel.VirtualizationMode=Recycling` | WPF | Keep event grid responsive with large result sets | Keep virtualization enabled for event lists and selection-heavy bulk workflows. |
| Existing GA runspace helpers (`GUI/Helpers/AsyncHelpers.ps1`) | Current repo | Non-blocking retrieval/filter application | Use existing async pattern for fetch + normalize + bind stages; do not execute event retrieval on STA thread. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Pester (existing test stack) | Validate event mapping and rule-generation correctness | Add fixtures for AppLocker event IDs and mapping to Allowed/Audited/Denied semantics. |
| `.evtx` sample files + `Get-WinEvent -Path` | Deterministic test data in air-gapped/offline environments | Use archived logs for regression tests without requiring live domain connectivity. |
| Existing `Write-AppLockerLog` | Operational diagnostics | Log query shape (`LogName`, IDs, time range, source host, duration, count) for supportability. |

## Installation

```bash
# Runtime packages
# None. Use in-box Windows PowerShell 5.1 + .NET Framework eventing APIs.

# PowerShell Gallery/NuGet additions
# None. Do not add internet-sourced runtime dependencies for this milestone.

# Existing module dependencies
# Ensure AppLocker module availability where event-to-policy cmdlets are used.
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Get-WinEvent` first, `Eventing.Reader` only for advanced needs | Build everything directly on `EventLogReader` from day one | Use full `EventLogReader` pipeline only if bookmark/resume and incremental tailing become hard requirements in phase 1, not just nice-to-have. |
| Remote collection through existing WinRM flow (`Invoke-Command` + `Get-WinEvent`) for managed hosts | Direct `Get-WinEvent -ComputerName` RPC path | Use direct `-ComputerName` for environments where WinRM is intentionally disabled but Event Log remote access ports are opened and governed. |
| Structured field extraction from `EventRecord.ToXml()` | Parse `Message` text only | Use message parsing only as fallback when specific payload fields are missing; messages are localized and more brittle. |
| WPF `ICollectionView` filtering | External search/index engine (Lucene/Elastic/SQLite FTS) | Use external index/search only if dataset size exceeds in-memory UI filtering limits and org accepts added deployment/runtime burden. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `Get-EventLog` for AppLocker channels | Legacy cmdlet; does not cover modern Windows Event Log channels needed here | `Get-WinEvent` |
| Fetch-all then `Where-Object` filtering on large logs | Pulls too much data and hurts responsiveness, especially remote | `-FilterHashtable` first, `-FilterXml` for complex cases |
| Event ID assumptions copied from old/internal comments without validation | AppLocker event ID semantics have specific meanings and evolved IDs (8000+ range) | Use Microsoft AppLocker event tables as source of truth |
| New third-party UI/data stacks in this milestone | Violates air-gap simplicity and increases maintenance surface | Stay with existing WPF + runspace + GA modules |
| Primary dependency on `Get-AppLockerFileInformation -EventLog` for remote hosts | Cmdlet does not expose `-ComputerName`; remote workflow becomes awkward | Collect remotely with `Get-WinEvent` and map to internal event DTO; use `Get-AppLockerFileInformation` in local/imported-log batch flows |

## Stack Patterns by Variant

**If local operator triage (single host):**
- Query AppLocker channels with `Get-WinEvent -FilterHashtable`.
- Bind to `ICollectionView` and apply `Filter` + `DeferRefresh` for live UX.

**If remote fleet sampling (selected machines):**
- Reuse existing credential + remote execution pipeline (`Discovery` + `Credentials` + async runspaces).
- Execute per-host `Get-WinEvent` server-side, return normalized lightweight objects, and aggregate centrally.

**If operator generates rules/exceptions from selected events:**
- Normalize event fields to existing rule input contracts (`Rules` module object shape).
- Use AppLocker cmdlets for policy-oriented batch pipelines when available; keep existing GA rule creation path as primary integration target.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `Get-WinEvent` (PS 5.1 docs, updated 2026-01-18) | Windows PowerShell 5.1 | `-ComputerName` supports one target at a time; docs call out firewall requirements and non-dependence on PowerShell remoting. |
| `Get-WinEvent -FilterHashtable` | PS 5.1 | Valid keys documented (`LogName`, `ProviderName`, `ID`, `Level`, `StartTime`, `EndTime`, etc.). `<named-data>` filtering is a PS 6+ enhancement and should not be assumed in PS 5.1. |
| `System.Diagnostics.Eventing.Reader` classes | .NET Framework 4.7.2+ / PS 5.1 | `EventLogSession` supports remote constructor with credentials; `EventBookmark` supports resume scenarios. |
| WPF `ICollectionView` / `CollectionViewSource` | Existing WPF shell | Supports shared view filtering and deferred refresh; suitable for event-grid UX without stack changes. |
| AppLocker cmdlets (`Get-AppLockerFileInformation`, `New-AppLockerPolicy`) | Systems with AppLocker module | Official examples show event-log-driven policy generation; validate module presence at runtime and degrade gracefully if absent. |

## Integration Points (Existing GA-AppLocker Codebase)

- `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Get-AppLockerEventLogs.ps1`: keep retrieval primitive but correct event-ID mapping against official AppLocker event documentation and switch primary parsing from `Message` regex to structured XML field extraction.
- `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Start-ArtifactScan.ps1`: expose a shared event-query parameter model so Event Viewer workflow and Scanner workflow reuse the same retrieval engine.
- `GA-AppLocker/Modules/GA-AppLocker.Rules/*`: add an event-to-rule adapter layer that converts normalized event DTOs into existing rule-generation inputs instead of creating a parallel rule engine.
- `GA-AppLocker/GUI/Panels/*` (new Event Viewer panel): implement filtering via `ICollectionView` and preserve established async + dispatcher helpers to avoid STA blocking.
- `GA-AppLocker/Modules/GA-AppLocker.Credentials` + `GA-AppLocker.Discovery`: reuse existing tiered credentials and host-selection plumbing for remote event collection, rather than adding separate auth/targeting logic.

## Sources

- `Get-WinEvent` cmdlet reference (PowerShell 5.1, updated 2026-01-18) - remote usage model, filter parameter capabilities, hashtable keys, performance guidance. (HIGH)  
  https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1
- Creating `Get-WinEvent` queries with `FilterHashtable` (PowerShell docs, updated 2025-03-24) - key/value behavior and PS version notes (`<named-data>` in PS 6+). (HIGH)  
  https://learn.microsoft.com/en-us/powershell/scripting/samples/creating-get-winevent-queries-with-filterhashtable?view=powershell-5.1
- AppLocker Event Viewer usage and event ID table (updated 2025-02-24) - authoritative event semantics for IDs 8000+ and channel expectations. (HIGH)  
  https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/using-event-viewer-with-applocker
- Monitor app usage with AppLocker (updated 2025-02-24) - confirms AppLocker logs/channels and cmdlet-based review workflow. (HIGH)  
  https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/monitor-application-usage-with-applocker
- `Get-AppLockerFileInformation` cmdlet reference (updated 2025-05-14) - `-EventLog` behavior, `-EventType`, statistics mode, default log path behavior. (HIGH)  
  https://learn.microsoft.com/en-us/powershell/module/applocker/get-applockerfileinformation?view=windowsserver2025-ps
- `New-AppLockerPolicy` cmdlet reference (updated 2025-05-14) - event-log-to-policy pipeline and fallback behavior for missing file info. (HIGH)  
  https://learn.microsoft.com/en-us/powershell/module/applocker/new-applockerpolicy?view=windowsserver2025-ps
- `.NET Eventing.Reader` API docs (`EventLogQuery`, `EventLogReader`, `EventLogSession`, `EventBookmark`, `EventRecord.ToXml`) - query/session/bookmark and structured event extraction primitives. (HIGH)  
  https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.eventlogquery?view=netframework-4.8.1  
  https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.eventlogreader?view=netframework-4.8.1  
  https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.eventlogsession?view=netframework-4.8.1  
  https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.eventbookmark?view=netframework-4.8.1  
  https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.eventrecord.toxml?view=netframework-4.8.1
- WPF view/filter/virtualization docs (`CollectionViewSource`, `ICollectionView.Filter`, `ICollectionView.DeferRefresh`, `DataGrid.EnableRowVirtualization`, `VirtualizingPanel.VirtualizationMode`) - responsive grid filtering guidance. (HIGH)  
  https://learn.microsoft.com/en-us/dotnet/api/system.windows.data.collectionviewsource.getdefaultview?view=windowsdesktop-9.0  
  https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.icollectionview.filter?view=windowsdesktop-9.0  
  https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.icollectionview.deferrefresh?view=windowsdesktop-9.0  
  https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagrid.enablerowvirtualization?view=windowsdesktop-9.0  
  https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.virtualizingpanel.virtualizationmode?view=windowsdesktop-9.0

---
*Stack research for: Event Viewer Rule Workbench milestone*
*Researched: 2026-02-17*
