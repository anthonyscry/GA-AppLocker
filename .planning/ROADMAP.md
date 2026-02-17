# GA-AppLocker Optimization Roadmap

Purpose: comprehensive improvements focused on performance, stability, and operator UX in air-gapped DC environments.

Guiding principles:
- Keep UI responsive (no STA thread blocking)
- Prefer O(1) or indexed reads over file scans
- Async by default for IO-heavy work
- Zero data loss, conservative changes
- PowerShell 5.1 compatibility and ASCII-only sources

Scope:
- WPF UI, modules, data storage, tests, and build/release automation
- No changes to Policy XML export, Validation module, or rule import (locked)

## Phase 1: Startup and Navigation Performance (short term)
Goals:
- Sub-second panel switches on DCs with large data sets
- Zero blocking calls on the STA thread

Focus areas:
- Cache policy list and rule counts across panels
- Debounce or batch breadcrumb refresh
- Remove any remaining synchronous file scans on navigation
- Limit Test Connectivity to selected machines in AD Discovery (no full-domain sweep)
- Scanner: move machine selection into Config, show only when Remote scan checked, and only WinRM-available machines selectable
- Deploy: use policy Target GPO for deployments (remove deploy-time target selection)
- Deploy panel: merge Create + Actions, move status to Setup
- Policy builder: rules management available in Create + Edit, with XML import
- Deployment jobs: status color should reflect Running vs Pending correctly
- Track and log panel load timings

Success criteria:
- Dashboard to Policy navigation < 500ms on 1k+ policies
- Test Connectivity only targets selected machines (no domain-wide run)
- Scanner remote selection shows only WinRM-available machines
- Policy builder can add rules via XML import during Create/Edit
- Deploy panel has Create + Actions merged; status moved to Setup
- Deployment job status colors reflect Running state before completion
- No loading overlay on simple navigation unless a true refresh is triggered

## Phase 2: Data Access and Indexing (short term)
Goals:
- O(1) policy counts and fast list filtering
- Predictable IO behavior under large datasets

Status: Complete (2026-02-04)

Focus areas:
- Add a policy index (similar to rules-index.json)
- Incremental index updates for policy CRUD
- Batch reads for artifacts and scans lists

Success criteria:
- Policy list load < 1s with 1k+ policies
- No more directory-wide JSON parsing for counts

Plans:
- [x] 02-data-access-indexing-01-PLAN.md — Add policy index core helpers
- [x] 02-data-access-indexing-02-PLAN.md — Wire policy CRUD and rule updates to index
- [x] 02-data-access-indexing-03-PLAN.md — Read policy list/count from index

## Phase 3: UX and Workflow Friction (mid term)
Goals:
- Fewer blocking dialogs and smoother workflows
- Clear feedback on long operations

Focus areas:
- Replace modal prompts with non-blocking toasts where safe
- Add progress indicators for long scans and policy operations
- Improve error surfacing and recovery guidance

Success criteria:
- No modal dialogs during routine navigation
- Long operations show progress and remain cancellable

Plans:
- [x] 03-ux-and-workflow-friction-01-PLAN.md — Convert setup wizard and setup panel status dialogs to toasts
- [x] 03-ux-and-workflow-friction-02-PLAN.md — Use toasts for scanner and software panel routine feedback
- [x] 03-ux-and-workflow-friction-03-PLAN.md — Make policy panel feedback non-blocking with async overlays

## Phase 4: Reliability and Diagnostics (mid term)
Goals:
- Faster issue triage in air-gapped environments
- Clear, actionable logs

Focus areas:
- Add structured performance logs per panel
- Expand debug logs in empty catch blocks
- Add a basic health report export (logs, config, counts)

Success criteria:
- Repro steps captured in logs without extra tracing
- Health report export < 5 seconds

## Phase 5: Test and QA Coverage (mid term)
Goals:
- Protect performance regressions
- Keep UI behavior stable

Focus areas:
- Add timing assertions for critical paths
- Extend mock WPF tests for panel loads
- Add policy index tests once implemented

Success criteria:
- Performance tests fail on regressions > 2x baseline
- All GUI tests pass in interactive mode

## Phase 6: Build and Release Automation (long term)
Goals:
- Reproducible releases
- Single-command packaging

Focus areas:
- Standardize release notes generation
- Include zip artifact creation in build pipeline
- Add version bump helper for manifests and docs

Success criteria:
- Release process < 5 minutes end-to-end
- Version consistency validated before release

**Plans:** 4/4 plans complete

Plans:
- [ ] 06-build-and-release-automation-long-term-01-PLAN.md — Build release context and standardized git-based release notes
- [ ] 06-build-and-release-automation-long-term-02-PLAN.md — Create deterministic ZIP packaging and integrity sidecar artifacts
- [ ] 06-build-and-release-automation-long-term-03-PLAN.md — Implement single-command release orchestrator and wire existing entrypoints

## Tracking and Metrics
- Panel load time (ms) for Dashboard, Rules, Policy, Deploy
- Policy list load time and memory footprint
- Rule index load time
- Scan and policy operations success rates
