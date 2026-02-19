# GA-AppLocker Planning Workspace

## What This Is

GA-AppLocker is a PowerShell 5.1 WPF application for enterprise AppLocker policy management in air-gapped and high-security environments.
It supports the full operator workflow from discovery and scanning through rule/policy authoring and deployment, with an integrated Event Viewer for event-driven triage and rule generation.

## Core Value

Reliable, operator-friendly policy management that stays responsive on large enterprise datasets.

## Requirements

### Validated

- ✓ Deterministic non-interactive release orchestration with standardized release notes and packaging integrity artifacts — v1.2.86
- ✓ Operators can access a dedicated Event Viewer workflow from the main app navigation — v1.2.88
- ✓ Operators can load bounded AppLocker events from local and remote hosts with per-host status — v1.2.88
- ✓ Operators can filter and search AppLocker events by event code, metadata, and free text — v1.2.88
- ✓ Operators can inspect normalized event details and raw XML for forensic verification — v1.2.88
- ✓ Operators can generate AppLocker rules from single or bulk event selections through existing governance pipeline — v1.2.88

### Active

**Current Milestone: v1.2.90 Production Hardening**

**Goal:** Eliminate silent failures, close test coverage gaps, and fix performance bottlenecks to reach production confidence.

**Target features:**
- Error handling hardening — replace empty catches with logging, standardize return patterns
- Test coverage expansion — add tests for untested modules (Credentials, Deployment, Setup) and GUI panels
- Performance fixes — StringBuilder for XML export, reduce ConvertTo-Json depth, fix O(n²) patterns

### Out of Scope

- Replacing existing Scanner or Rules workflows entirely — Event Viewer augments existing panels
- External SIEM/cloud integrations for event ingestion — remains local/domain and air-gap compatible
- Full SIEM replacement inside GA-AppLocker — scope explosion beyond tool intent
- Auto-create and auto-approve rules from all events — unsafe, bypasses operator review
- Real-time streaming event UI — bounded refresh windows preserve PS 5.1 WPF responsiveness

## Context

Shipped v1.2.88 with Event Viewer Rule Workbench. Codebase is ~195 exported functions across 10 modules.
Tech stack: PowerShell 5.1, WPF/XAML, .NET Framework 4.7.2+, DPAPI credential storage.
70 Event Viewer behavioral tests + 1,282 unit tests passing.

Known tech debt entering v1.2.90 (status after Phase 11):
- ~~105 empty catch blocks in GUI/Panels, ~30 in GUI/Helpers~~ — resolved Phase 10
- ~~14 files with ConvertTo-Json -Depth 10~~ — resolved Phase 11 (all reduced to -Depth 3)
- ~~Export-PolicyToXml.ps1 uses string += in rule loop (O(n²))~~ — resolved Phase 11 (StringBuilder)
- ~~Export-AppLockerHealthReport uses Get-CimInstance/Measure-Object~~ — resolved Phase 11 (.NET APIs)
- No test coverage for Credentials, Deployment, Setup modules
- 7/10 GUI panels have zero behavioral tests
- CollectionType field not emitted by event retrieval backend (functional fallback exists)
- Two script:-scoped functions called from global: context (works but misaligned)

## Constraints

- **Compatibility**: PowerShell 5.1 and ASCII-safe source compatibility — required for current enterprise runtime environment
- **Safety**: No changes to Validation module or rule import core path — these are known-stable. Export-PolicyToXml performance fix is scoped for v1.2.90
- **UX**: Operator-facing workflows must remain non-blocking — air-gapped DC environments amplify timeout and latency impacts

## Key Decisions

| Decision | Rationale | Outcome |
| --- | --- | --- |
| Build Event Viewer as integrated panel, not separate tool | Preserves existing operator workflow and reduces training overhead | ✓ Good — shipped v1.2.88 |
| Support single-item and bulk event-to-rule generation in one window | Operators need fast triage and mass remediation from the same surface | ✓ Good — shipped v1.2.88 |
| Reuse existing remote-access and scanning foundations | Reduces implementation risk and keeps behavior consistent | ✓ Good — shipped v1.2.88 |
| Pre-serialize RawXml in remote Invoke-Command before deserialization | .NET EventLogRecord methods unavailable after PS remoting boundary | ✓ Good — prevents silent data loss |
| Dimension filters default to no-op for backward compatibility | All existing callers work without modification after extension | ✓ Good — zero regressions |
| Comma-operator return for PS 5.1 array-returning functions | PS 5.1 unwraps single-element arrays; comma operator preserves structure | ✓ Good — pattern now established |
| Route all event-derived rules through existing pipeline with Status=Pending | Preserves governance and review controls | ✓ Good — verified by 5 GEN-04 tests |

## Archived Context

<details>
<summary>Pre-v1.2.88 project context</summary>

Shipped version `v1.2.86` focused on release automation and milestone archival setup.
See `.planning/milestones/v1.2.86-ROADMAP.md` and `.planning/MILESTONES.md` for complete milestone history.

</details>

<details>
<summary>v1.2.88 milestone context</summary>

Shipped version `v1.2.88` delivered the Event Viewer Rule Workbench: bounded event ingestion, triage filtering/inspection, and rule generation from event selections.
See `.planning/milestones/v1.2.88-ROADMAP.md` and `.planning/milestones/v1.2.88-REQUIREMENTS.md` for complete details.

</details>

---
*Last updated: 2026-02-19 after Phase 11 (Performance Fixes)*
