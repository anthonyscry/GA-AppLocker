# Feature Research

**Domain:** Enterprise AppLocker admin tooling (event-viewer-driven rule authoring)
**Researched:** 2026-02-17
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| In-window AppLocker event ingestion (local + remote) | Enterprise operators expect one workflow to inspect what was blocked/audited and act immediately | MEDIUM | Pull from AppLocker channels and support host selection; dependency: existing AD Discovery + Credentials + remote connectivity patterns in Scanning/Discovery |
| Event-code-first filtering and saved filter presets | AppLocker workflows are event-ID driven (8002/8003/8004, 8005/8006/8007, 802x/803x) | LOW | Must filter by Event ID, level, time range, host, user SID/name, path/publisher; dependency: existing filter bar/search patterns in GUI panels |
| Rich event detail pane with normalized metadata + raw event XML | Operators need both human-readable fields and forensic truth source before generating rules | MEDIUM | Show normalized fields (file, signer, hash when present, rule collection, policy mode, user, machine) and raw message/XML for validation |
| Single-select "Generate Rule" from event | Native AppLocker tooling supports event-log-to-rule flows via `Get-AppLockerFileInformation` + `New-AppLockerPolicy`; users expect parity | MEDIUM | Reuse existing rule generation engine; default rule type fallback should mirror best practice (`Publisher -> Hash`, optional Path only when explicitly chosen) |
| Bulk selection with dedupe and frequency rollup | Event logs are verbose; enterprise operators need to handle many duplicate events at once | MEDIUM | Group by key fields (path/signer/hash + principal + action) before generation; dependency: existing Rules dedupe/index workflow |
| Exception authoring path from event context | AppLocker operations require allow rules with explicit exceptions in real deployments | MEDIUM | From event row, enable "Create exception" targeting existing allow rules; dependency: existing rule edit/exception model in Rules module |
| Safety guardrails for Audit vs Enforce interpretation | Audit events can look like failures to inexperienced operators | LOW | Persistent badge and filter chips that distinguish Audited vs Denied vs Allowed; tie to policy mode language from AppLocker docs |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Event-to-artifact enrichment step | Converts weak event data into high-confidence rule material without leaving Event Viewer | MEDIUM | "Enrich selected events" triggers targeted local/remote artifact scan for missing signer/hash metadata; dependency: existing Scanner pipeline and connectivity checks |
| Rule impact preview before commit | Reduces accidental over-broad allow rules and rollback churn | HIGH | Show estimated blast radius: unique hosts/users hit, event count coverage, and rule type strength score (Publisher strongest, Hash next, Path highest risk) |
| Guided bulk strategy recommendations | Speeds expert workflow and helps junior operators choose safer rule types | MEDIUM | Recommend per-batch strategy (e.g., "use Publisher for signed set; Hash fallback for unsigned outliers") based on selected events |
| Event-backed exception suggestions | Makes exceptions operational instead of manual hunting | MEDIUM | Detect when event conflicts with broad allow rule and suggest scoped exception template instead of deny rule sprawl |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full SIEM replacement inside GA-AppLocker | Teams want one pane for all event analytics | Explodes scope into retention, correlation, alerting, and data-lake concerns outside milestone | Keep Event Viewer focused on authoring inputs; integrate by importing/exporting filtered event slices |
| Auto-create and auto-approve rules from all audited events | Feels "hands-free" and fast | Produces rule bloat, over-permissive policies, and weak change control in secure environments | Require operator review with batch preview + explicit approval step |
| Cross-forest/unbounded remote log crawling in first release | Sounds powerful for large estates | High auth/network complexity and reliability risk, especially air-gapped or segmented networks | Scope to selected known hosts (from Discovery or manual list) with clear connectivity status |
| Real-time streaming UI with zero batching | Seems modern and responsive | High UI churn and noisy operator experience; hard to reason about policy actions | Use refresh windows + bounded pulls + optional timed refresh |
| Generic "one-click fix all blocks" button | Appeals to helpdesk speed | Hides security tradeoffs and bypasses least-privilege rule design | Offer guided wizard with risk labels and explicit per-rule acceptance |

## Feature Dependencies

```text
[Remote event ingestion]
    -> requires -> [AD Discovery host list] + [Credential profiles] + [Connectivity checks]
    -> enables  -> [Multi-host event triage]

[Event filtering and selection]
    -> requires -> [Normalized event model]
    -> enables  -> [Single/bulk rule generation]

[Single/bulk rule generation from events]
    -> requires -> [Existing Rules generation engine]
    -> requires -> [Deduplication/index update pipeline]
    -> enables  -> [Policy build/deploy workflow]

[Exception authoring from event]
    -> requires -> [Existing rule edit + exception model]
    -> enhances -> [Safe policy refinement without deny sprawl]

[Event enrichment (differentiator)]
    -> requires -> [Scanner local/remote artifact collection]
    -> conflicts -> [Disconnected hosts without scan fallback]
```

### Dependency Notes

- **Event-driven authoring is a front door, not a new backend:** it should call existing Scanning/Rules/Policy capabilities, not duplicate them.
- **Normalized event model is foundational:** filtering, dedupe, bulk actions, and preview all depend on stable extracted fields.
- **Remote ingestion quality depends on existing connectivity controls:** host status and credential selection must be first-class in the Event Viewer flow.
- **Exception workflow depends on rule-edit maturity:** weak exception UX leads teams to create blunt deny/allow rules instead.

## MVP Definition

### Launch With (v1)

Minimum viable milestone for event-centric rule authoring.

- [ ] Local + selected-remote AppLocker event retrieval in Event Viewer panel
- [ ] Event ID + metadata filtering (host, user, path/signer text, time, outcome)
- [ ] Single and bulk rule generation from selected events using existing rule engine
- [ ] Bulk dedupe/frequency rollup before generation
- [ ] Event detail view (normalized fields + raw XML/message)
- [ ] Basic exception creation path from selected event context

### Add After Validation (v1.x)

Features to add once core event workflow proves stable.

- [ ] Event-to-artifact enrichment for missing signer/hash data - add after baseline performance is acceptable
- [ ] Guided bulk strategy recommendations - add after real operator usage patterns are observed

### Future Consideration (v2+)

Features to defer until core workflow is trusted in production-like environments.

- [ ] Rule impact preview with blast-radius scoring - defer until sufficient telemetry/model confidence exists
- [ ] Advanced exception suggestions and conflict analysis - defer until rule graph dependencies are available

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Local + remote event ingestion | HIGH | MEDIUM | P1 |
| Event code/metadata filtering | HIGH | LOW | P1 |
| Single event -> rule action | HIGH | MEDIUM | P1 |
| Bulk selection + dedupe + generate | HIGH | MEDIUM | P1 |
| Event detail pane (normalized + raw) | HIGH | MEDIUM | P1 |
| Exception authoring from event | MEDIUM | MEDIUM | P2 |
| Event-to-artifact enrichment | HIGH | MEDIUM | P2 |
| Rule impact preview | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for milestone success
- P2: Should have after P1 stability
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Native AppLocker MMC/PowerShell | WEF/WEC-Centric Enterprise Ops | Our Approach |
|---------|----------------------------------|----------------------------------|-------------|
| Event-driven authoring | Supported mainly through cmdlet flow (`Get-AppLockerFileInformation` -> `New-AppLockerPolicy`) with manual scripting | Usually focused on collection/monitoring, not direct rule authoring | Bring authoring UX in-window with one-click/bulk generation from selected events |
| Event filtering model | Event Viewer + cmdlet filters; flexible but operator-heavy | Subscription XML and upstream filtering to manage volume | Operator-first filter chips and presets mapped to AppLocker event IDs and metadata |
| Handling verbosity/noise | Manual statistics and review; can be noisy | Baseline/targeted subscriptions to manage volume and latency | Built-in dedupe + frequency rollups before rule generation |

## Sources

- Microsoft Learn - Using Event Viewer with AppLocker (event IDs, channel behavior, verbosity): https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/using-event-viewer-with-applocker (2024-09-11, updated 2025-02-24) [HIGH]
- Microsoft Learn - Monitor app usage with AppLocker (audit-first workflow and event review model): https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/monitor-application-usage-with-applocker (2024-09-11, updated 2025-02-24) [HIGH]
- Microsoft Learn - Get-AppLockerFileInformation (event log ingestion, event type filtering, statistics): https://learn.microsoft.com/en-us/powershell/module/applocker/get-applockerfileinformation?view=windowsserver2025-ps (updated 2025-05-14) [HIGH]
- Microsoft Learn - New-AppLockerPolicy (create policy/rules from event-derived file information): https://learn.microsoft.com/en-us/powershell/module/applocker/new-applockerpolicy?view=windowsserver2025-ps (updated 2025-05-14) [HIGH]
- Microsoft Learn - Get-WinEvent (remote retrieval, filter hashtable/XML, performance-oriented filtering): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1 (updated 2026-01-19) [HIGH]
- Microsoft Learn - Add exceptions for an AppLocker rule: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/configure-exceptions-for-an-applocker-rule (2024-09-11, updated 2025-02-24) [HIGH]
- Microsoft Learn - Understanding AppLocker rule exceptions: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-rule-exceptions (2024-09-11, updated 2025-02-24) [HIGH]
- Microsoft Learn - Use Windows Event Forwarding to help with intrusion detection (volume/scaling and subscription patterns informing anti-features): https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/use-windows-event-forwarding-to-assist-in-intrusion-detection (2025-08-18) [MEDIUM, architecture pattern source]

---
*Feature research for: GA-AppLocker Event Viewer Rule Workbench milestone*
*Researched: 2026-02-17*
