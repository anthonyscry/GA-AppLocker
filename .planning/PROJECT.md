# GA-AppLocker Planning Workspace

## What This Is

GA-AppLocker is a PowerShell 5.1 WPF application for enterprise AppLocker policy management in air-gapped and high-security environments.
It supports the full operator workflow from discovery and scanning through rule/policy authoring and deployment.

## Core Value

Reliable, operator-friendly policy management that stays responsive on large enterprise datasets.

## Requirements

### Validated

- ✓ Deterministic non-interactive release orchestration with standardized release notes and packaging integrity artifacts - v1.2.86

### Active

- [ ] Operators can access a dedicated Event Viewer workflow from the main app navigation
- [ ] Operators can scan local and remote assets directly from the Event Viewer workflow
- [ ] Operators can filter and search AppLocker events by event code and key event metadata
- [ ] Operators can generate AppLocker rules and exceptions from single or bulk event selections

### Out of Scope

- Replacing existing Scanner or Rules workflows entirely - Event Viewer workflow augments existing panels
- External SIEM/cloud integrations for event ingestion - milestone remains local/domain and air-gap compatible

## Current Milestone: v1.2.88 Event Viewer Rule Workbench

**Goal:** Let operators investigate AppLocker events and create actionable rules/exceptions directly from a dedicated event-driven workflow.

**Target features:**
- New Event Viewer menu option and panel in the WPF workflow
- AppLocker event log browser for local and remote targets
- Filter bar with event-code filtering plus text search over core fields
- Single and bulk rule/exception generation directly from selected events
- Integrated asset scan actions from Event Viewer context

## Context

- Latest shipped milestone `v1.2.86` delivered deterministic release automation and integrity artifacts.
- Existing planning artifacts include a drafted `v1.2.87` performance scope, but the immediate milestone focus is now event-driven operations workflow expansion.
- GA-AppLocker already has discovery, scanning, and rules modules that can be reused for event-to-rule orchestration.

## Constraints

- **Compatibility**: PowerShell 5.1 and ASCII-safe source compatibility - required for current enterprise runtime environment
- **Safety**: No changes to locked areas (`Export-PolicyToXml`, Validation module, rule import core path) - these are known-stable and out of scope
- **UX**: Operator-facing workflows must remain non-blocking - air-gapped DC environments amplify timeout and latency impacts

## Key Decisions

| Decision | Rationale | Outcome |
| --- | --- | --- |
| Build Event Viewer capability as an integrated panel, not a separate tool | Preserves existing operator workflow and reduces training overhead | - Pending |
| Support both single-item and bulk event-to-rule generation in one window | Operators need fast triage and mass remediation from the same surface | - Pending |
| Reuse existing remote-access and scanning foundations for Event Viewer actions | Reduces implementation risk and keeps behavior consistent with current modules | - Pending |

## Archived Context

<details>
<summary>Pre-v1.2.88 project context</summary>

Shipped version `v1.2.86` focused on release automation and milestone archival setup.
See `.planning/milestones/v1.2.86-ROADMAP.md` and `.planning/MILESTONES.md` for complete milestone history.

</details>

---
*Last updated: 2026-02-17 after starting v1.2.88 milestone*
