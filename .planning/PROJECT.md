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

- [ ] Rules index remains consistent and recoverable without manual intervention
- [ ] Rules/Policy/Deploy navigation and filtering remain responsive under large datasets
- [ ] Critical panel transitions stay under 500ms in normal operator workflows
- [ ] No remaining STA-thread blocking in routine navigation and data refresh paths

### Out of Scope

- New release automation capabilities beyond the shipped v1.2.86 baseline - milestone focus is runtime operator UX and index reliability
- New product modules unrelated to rule index and panel performance - defer until performance baseline is restored

## Current Milestone: v1.2.87 Performance

**Goal:** Restore consistently snappy operator workflows by hardening rules index reliability and optimizing UI hot paths.

**Target features:**
- Rules-index validation/rebuild safety path for stale or missing index states
- Fast index-backed rule and policy data access in panel workflows
- Measured UI performance improvements on navigation/filter hot paths
- Guardrails to prevent STA-thread blocking in routine operator actions

## Context

- Latest milestone `v1.2.86` shipped release automation foundations and closed requirements traceability for Phase 06.
- Previous optimization phases (2-5) introduced indexing, UX, diagnostics, and test infrastructure improvements that can be extended.
- A formal milestone audit file for `v1.2.86` is deferred and may be produced retroactively.

## Constraints

- **Compatibility**: PowerShell 5.1 and ASCII-safe source compatibility - required for current enterprise runtime environment
- **Safety**: No changes to locked areas (`Export-PolicyToXml`, Validation module, rule import core path) - these are known-stable and out of scope
- **UX**: Operator-facing workflows must remain non-blocking - air-gapped DC environments amplify timeout and latency impacts

## Key Decisions

| Decision | Rationale | Outcome |
| --- | --- | --- |
| Prioritize snappy operator UX as the milestone objective | Most visible product risk is slow panel interactions during daily operations | - Pending |
| Target `<500ms` panel transitions as primary performance metric | Creates a clear acceptance threshold for optimization work | - Pending |
| Keep release automation scope fixed to v1.2.86 baseline | Avoids scope drift while stabilizing runtime performance | - Pending |

## Archived Context

<details>
<summary>Pre-v1.2.87 project context</summary>

Shipped version `v1.2.86` focused on release automation and milestone archival setup.
See `.planning/milestones/v1.2.86-ROADMAP.md` and `.planning/MILESTONES.md` for complete milestone history.

</details>

---
*Last updated: 2026-02-17 after starting v1.2.87 milestone*
