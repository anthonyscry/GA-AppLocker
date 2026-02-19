# Phase 13 Targeted Test Matrix

Date: 2026-02-18
Phase: 13
Status: Complete

## Scope Matrix

| Area | Risk | Why now | Primary test files |
|---|---|---|---|
| Deployment prereq/error handling | High | Deploy path is release-critical and has recent churn in job execution + status shaping | `Tests/Unit/Deployment.Tests.ps1`, `Tests/Behavioral/GUI/RecentRegressions.Tests.ps1` |
| Setup status transitions and module-partial failure | High | Setup panel depends on resilient GPO status probes in mixed RSAT availability environments | `Tests/Unit/Setup.Tests.ps1` |
| Scanner -> Rules unsigned/signed coercion edges | High | Past regressions around string boolean values caused incorrect hash/publisher routing | `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1` |
| Event Viewer action wiring | Medium | New Event Viewer shell introduces handler/tag routing that can fail silently if mismatched | `Tests/Behavioral/GUI/EventViewer.Navigation.Tests.ps1`, `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1` |
| Workflow smoke contract | Medium | Need deterministic go/no-go signal for discovery->deploy mock path | `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`, `Tests/Behavioral/Workflows/Workflow.Mock.Tests.ps1` |
| Release docs and sign-off artifacts | High | Phase exit gate requires reproducible evidence + operator-facing updates | `Tests/Behavioral/GUI/RecentRegressions.Tests.ps1`, `Tests/Run-MustPass.ps1` |

## Out of Scope (Phase 13)

- Large refactors unrelated to release-readiness defects
- Broad full-suite test expansion not tied to risk/recency
- UI redesign work unrelated to reliability or operator flow clarity
