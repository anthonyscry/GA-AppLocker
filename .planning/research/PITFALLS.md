# Domain Pitfalls

**Domain:** Event Viewer Rule Workbench integration in existing PS 5.1 WPF AppLocker platform
**Researched:** 2026-02-17
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Unbounded event retrieval freezes the workbench

**What goes wrong:**
Event triage queries pull "everything" (all channels, no time window, no max cap), causing WPF stalls, memory spikes, and huge local cache files.

**Why it happens:**
Teams prototype with direct `Get-WinEvent -LogName ... | Where-Object ...` and keep that path for production; filtering is applied after retrieval.

**How to avoid:**
Enforce bounded queries by contract: require channel + `StartTime` + `MaxEvents` + event level/type filter before execution; implement server-side filters using `-FilterHashtable`/`-FilterXml`; reject unbounded queries in UI validation; add performance tests with representative logs.

**Warning signs:**
Query actions that run longer than 3-5 seconds on normal datasets, UI spinner that stops repainting, peak memory growth during simple searches, and operator reports of "panel hangs".

**Phase to address:**
Phase 1 - Event ingestion foundation (query contract and retrieval guardrails).

---

### Pitfall 2: Wrong event semantics create wrong rules

**What goes wrong:**
Rule generation uses mixed/incorrect event IDs and enforcement meaning (Allowed vs Audited vs Denied), generating allow rules from noisy allowed telemetry or missing true block candidates.

**Why it happens:**
AppLocker emits different event IDs across collections and modes; developers treat the message text as canonical instead of normalized semantics.

**How to avoid:**
Create a versioned event taxonomy table in code (ID -> CollectionType + EnforcementMode + ActionIntent); cover EXE/DLL, MSI/Script, and Packaged app channels; unit-test mappings with fixture events; require explicit "generation source" selection (Audited/Denied only by default).

**Warning signs:**
High percentage of generated rules from informational allow events, many generated rules never used, or policy drift after deployment despite "successful" generation runs.

**Phase to address:**
Phase 1 - Event ingestion foundation (semantic normalization).

---

### Pitfall 3: Losing provenance between event triage and generated rules

**What goes wrong:**
Operators cannot trace a rule/exception back to source events, making audits and incident response slow and low-trust.

**Why it happens:**
Normalization pipelines keep only file path/hash and discard event metadata (event record ID, channel, device, user SID, timestamp).

**How to avoid:**
Persist provenance fields on every candidate and generated artifact; include source event count, first/last seen, host set, and source mode; show provenance in rule preview UI and exports; add tests ensuring round-trip persistence.

**Warning signs:**
Generated rows without "source event" references, support requests asking "why was this rule created?", or manual notebook tracking by operators.

**Phase to address:**
Phase 2 - Triage workbench UX and data model.

---

### Pitfall 4: Trusting incomplete event-derived file metadata

**What goes wrong:**
Generation fails or creates weak path-only rules because event-derived file info is missing publisher/hash/path components.

**Why it happens:**
`Get-AppLockerFileInformation -EventLog` may not contain all needed fields; teams assume complete metadata and do not design fallback/skip behavior.

**How to avoid:**
Implement explicit generation fallback order (`Publisher -> Hash -> Path`) with policy controls; mark low-confidence candidates; require operator confirmation for broad path rules; capture skipped-file warning logs and surface them in UI.

**Warning signs:**
Large skip counts, frequent generation aborts without `-IgnoreMissingFileInformation` strategy, or sudden increase in path rules compared to publisher/hash rules.

**Phase to address:**
Phase 3 - Rule and exception generation engine.

---

### Pitfall 5: Naive bulk generation causes rule explosion

**What goes wrong:**
Bulk actions create near-duplicate rules per host/version/user event, overwhelming policy review and degrading policy performance.

**Why it happens:**
The pipeline converts raw events directly to rules without dedupe keys or frequency thresholds.

**How to avoid:**
Deduplicate candidate generation on stable keys (collection type + signer/hash/path + action + principal); require occurrence thresholds and host diversity gates before auto-select; stage in "candidate" status first, not "approved".

**Warning signs:**
Thousands of new candidates from a short event window, duplicate signatures with only hostname differences, and reviewer throughput collapse.

**Phase to address:**
Phase 3 - Rule and exception generation engine.

---

### Pitfall 6: Exception synthesis creates unintended broad allow paths

**What goes wrong:**
Exception generation uses broad path exceptions (for example `%WINDIR%\*` without safe exclusions), reopening attack paths.

**Why it happens:**
Pressure to reduce false positives leads to convenience exceptions; teams underestimate path-based risk in writable directories and deny/allow precedence interactions.

**How to avoid:**
Introduce exception safety policy: block wildcard exceptions in user-writable paths by default, require risk acknowledgment for wide scopes, and auto-run validation checks against known risky directories; prefer signer/hash exceptions over path exceptions when possible.

**Warning signs:**
Exceptions containing broad wildcards in writable locations, sudden drop in blocked events paired with security concern escalations, or security team rejections during review.

**Phase to address:**
Phase 3 - Rule and exception generation engine, with security sign-off gate.

---

### Pitfall 7: Policy write integration accidentally overwrites trusted policy

**What goes wrong:**
Generated policy import replaces existing GPO policy or enforcement settings unintentionally, causing outages or rollback events.

**Why it happens:**
Integration path calls `Set-AppLockerPolicy` without correct merge and preflight checks; "import/export" is treated as incremental even though it is whole-policy scoped.

**How to avoid:**
Add mandatory deployment preflight: compare target policy snapshot, require explicit mode (`Merge` vs `Replace`), display enforcement delta preview, and block direct apply unless validation + operator confirmation pass; default milestone behavior to "export/dry-run" first.

**Warning signs:**
Unexpected enforcement changes after apply, sudden policy size drops, or operators needing emergency restore from snapshots.

**Phase to address:**
Phase 4 - Policy integration guardrails.

---

### Pitfall 8: Remote retrieval assumptions produce false "clean" results

**What goes wrong:**
Workbench reports few/no events because remote collection silently misses hosts due to access, firewall, or transport constraints.

**Why it happens:**
`Get-WinEvent -ComputerName` supports one computer at a time and has specific remote event log/firewall requirements; teams treat failures as empty data.

**How to avoid:**
Design remote ingest as explicit fan-out with per-host status, timeout, and error taxonomy (auth, connectivity, access denied, channel missing); never coerce retrieval failures into empty result sets; provide retry and exportable failure report.

**Warning signs:**
Large host sets returning near-zero events, high "success" counts with no per-host telemetry, and inconsistent totals between local Event Viewer and workbench output.

**Phase to address:**
Phase 1 - Event ingestion foundation and connectivity diagnostics.

---

### Pitfall 9: Violating stable module boundaries to "move faster"

**What goes wrong:**
New event workflows patch stable policy export/validation paths directly, introducing regressions in core workflows that were previously trusted.

**Why it happens:**
Developers optimize for direct integration and skip adapter layers; mature codebase contracts are treated as optional.

**How to avoid:**
Use an adapter boundary for event-workbench outputs into existing Rules/Policy modules; keep `Export-PolicyToXml` and validation pipeline untouched; add contract tests proving legacy workflows remain unchanged.

**Warning signs:**
Previously passing workflow tests failing after event-workbench changes, unexplained changes in exported XML, or regressions in non-event panels.

**Phase to address:**
Phase 2 - Integration architecture and contract testing.

---

### Pitfall 10: Skipping audit-first rollout for generated rules

**What goes wrong:**
Teams enforce generated rules too early, creating business-impacting blocks and emergency exception churn.

**Why it happens:**
Confidence is inferred from generation volume instead of observed audit telemetry and staged rollout.

**How to avoid:**
Mandate phased rollout: generate -> review -> audit-only deployment -> monitor event deltas -> enforce; define objective promotion gates (false-positive rate, business app pass list, exception delta trend).

**Warning signs:**
Spike in blocked critical apps immediately after deployment, emergency manual bypasses, and rule rollback within first day.

**Phase to address:**
Phase 4 - Policy integration and rollout governance.

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Querying with broad `Get-WinEvent` then filtering in PowerShell | Fast prototype | Persistent performance bottlenecks and UI hangs | Never |
| Storing only generated rules without source-event lineage | Small schema and quick UI | Poor auditability and hard incident investigations | Never |
| Auto-approving bulk generated candidates | Less reviewer work initially | Policy bloat and unsafe rules in production | Never |
| Writing directly into stable policy/deploy modules | Fewer files changed | Regressions in trusted workflows and costly rollback | Only for isolated hotfixes with regression suite pass |

## Integration Gotchas

Common mistakes when connecting event triage and generation into an existing mature tool.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Event ingestion + WPF panel | Running retrieval synchronously in click handlers | Run retrieval in background worker/runspace, marshal compact DTOs to UI thread |
| Event model + Rules module | Generating rules without normalized event taxonomy | Enforce a typed event-normalization layer before candidate creation |
| Candidate store + existing rule index | Bypassing canonical storage/index APIs | Persist through existing repository contract and index sync pipeline |
| Deployment + existing policy builder | Applying generated policy as replacement by default | Default to preview + merge-safe apply with snapshot and diff gates |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Client-side filtering after large event pulls | UI stutter, long query times | Use `FilterHashtable`/`FilterXml` and bounded windows | 30+ days or multi-host logs |
| Rebuilding DataGrid source on each search keystroke | Typing lag and scroll reset | Debounce + incremental filtering on in-memory bounded set | 5k+ displayed events |
| Per-event rule candidate object inflation | High memory and GC pressure | Stream processing + early dedupe + capped previews | 50k+ event records |
| Serial remote host queries with long timeouts | "Works in lab, fails in prod" timings | Parallel fan-out with host-level timeout and result envelopes | 20+ remote hosts |

## Security Mistakes

Domain-specific security issues in event-to-rule feature additions.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Treating event log access failures as empty/no-risk state | False security posture, missed blocks | Represent retrieval failures explicitly and block promotion if host coverage is incomplete |
| Generating broad path exceptions from noisy events | Expanded execution surface for adversaries | Require signer/hash-first strategy and policy checks for writable-path exceptions |
| Logging full event payloads including user/device identifiers without policy | Sensitive telemetry leakage in air-gapped environments | Implement redaction policy and operator-controlled diagnostic verbosity |

## UX Pitfalls

Common user experience mistakes in this milestone context.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Merging triage and deployment actions in one "Generate and Apply" button | Accidental policy changes and low trust | Separate stages: triage, candidate generation, review, deploy |
| Showing generated count without confidence or source quality | Reviewers approve weak candidates | Surface confidence labels (complete metadata, host diversity, frequency) |
| Hiding remote retrieval errors behind generic "0 events" | Operators assume environment is clean | Show per-host status summary with explicit failures and retry links |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Event ingestion:** Every query is bounded (time window + max events + channel/type filter) and rejects unbounded input.
- [ ] **Semantic mapping:** Event IDs/levels are normalized and covered by tests for all targeted AppLocker collections.
- [ ] **Provenance:** Generated rules and exceptions carry source event lineage and reviewable evidence.
- [ ] **Generation safety:** Bulk generation uses dedupe + thresholds + candidate status (not direct approval).
- [ ] **Deployment guardrails:** Apply path enforces snapshot/diff/merge mode and cannot overwrite silently.
- [ ] **Remote coverage:** Host retrieval failures are first-class results and block "safe to enforce" decisions.
- [ ] **Legacy safety:** Existing stable module workflows pass unchanged regression suites.

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Bad rules generated from wrong event semantics | HIGH | Freeze auto-generation, disable promotion, patch taxonomy map, reprocess retained raw events, invalidate impacted candidates |
| Policy overwrite or unsafe merge in target GPO | HIGH | Restore last snapshot/export, reapply with explicit merge mode, diff enforcement settings, run validation and audit-only redeploy |
| Remote ingestion silently missed large host subset | MEDIUM | Re-run retrieval with host-level diagnostics, fix auth/firewall prerequisites, mark previous reports incomplete, regenerate candidates from corrected dataset |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Unbounded event retrieval | Phase 1 (Event ingestion foundation) | Pester/perf tests fail on unbounded queries and pass with bounded contracts |
| Wrong event semantics | Phase 1 (Semantic normalization) | Fixture-based mapping tests for key AppLocker IDs and event types pass |
| Lost provenance | Phase 2 (Triage data model) | Generated candidates include source event IDs/host/time in UI and export tests |
| Incomplete metadata misuse | Phase 3 (Generation engine) | Generation tests verify fallback order, skip logs, and confidence tagging |
| Rule explosion | Phase 3 (Bulk generation controls) | Large dataset test keeps candidate counts within thresholded limits |
| Unsafe exception synthesis | Phase 3 (Exception safety policy) | Validation rejects writable-path wildcards unless explicit override approved |
| Policy overwrite/merge mistakes | Phase 4 (Deployment guardrails) | Apply flow requires snapshot + diff + explicit mode; integration tests cover merge/replace |
| Remote false-clean results | Phase 1 (Remote ingest diagnostics) | Host coverage report must be complete before "ready" status can pass |
| Stable boundary violations | Phase 2 (Integration contracts) | Regression suite for existing workflows remains green after event feature merge |
| Skipped audit-first rollout | Phase 4 (Rollout governance) | Promotion checklist enforces audit-only metrics gate before enforce |

## Sources

- Microsoft Learn - `Get-WinEvent` (PowerShell 5.1), updated 2026-01-18: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1
- Microsoft Learn - Using Event Viewer with AppLocker, updated 2024-09-11: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/using-event-viewer-with-applocker
- Microsoft Learn - Monitor app usage with AppLocker, updated 2024-09-11: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/monitor-application-usage-with-applocker
- Microsoft Learn - `Get-AppLockerFileInformation`, updated 2025-05-14: https://learn.microsoft.com/en-us/powershell/module/applocker/get-applockerfileinformation?view=windowsserver2025-ps
- Microsoft Learn - `New-AppLockerPolicy`, updated 2025-05-14: https://learn.microsoft.com/en-us/powershell/module/applocker/new-applockerpolicy?view=windowsserver2025-ps
- Microsoft Learn - `Set-AppLockerPolicy`, updated 2025-05-14: https://learn.microsoft.com/en-us/powershell/module/applocker/set-applockerpolicy?view=windowsserver2025-ps
- Microsoft Learn - Administer AppLocker, updated 2024-09-11: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/administer-applocker
- Microsoft Learn - Understanding AppLocker default rules, updated 2024-09-11: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-default-rules
- Microsoft Learn - Understanding AppLocker rule exceptions, updated 2024-09-11: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-rule-exceptions
- Microsoft Learn - WPF Threading Model, updated 2025-08-27: https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model
- Project constraints and known failure modes: `/mnt/c/projects/GA-AppLocker/CLAUDE.md`

---
*Pitfalls research for: Event Viewer Rule Workbench milestone in GA-AppLocker*
*Researched: 2026-02-17*
