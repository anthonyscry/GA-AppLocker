# Phase 13 Targeted Test Matrix

Date: 2026-02-18
Objective: release-readiness confidence for scoped high-risk paths

## Scope Matrix

| Area | Risk | Test Path | Status |
|---|---|---|---|
| Deployment create/update flow | High | `Tests/Unit/Deployment.Tests.ps1` | Passed |
| Setup status and WinRM/GPO state | High | `Tests/Unit/Setup.Tests.ps1` | Passed |
| Rule conversion behavior | Medium | `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1` | Passed |
| Recent GUI regressions | High | `Tests/Behavioral/GUI/RecentRegressions.Tests.ps1` | Passed |
| End-to-end workflow contract | High | `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1` | Passed |

## Out-of-Scope for Phase 13

- Broad full-suite expansion across all modules
- New feature implementation not tied to release-readiness gates
- Interactive WPF UI automation from non-interactive environments

## Notes

- Baseline test runs in WSL `pwsh` are not release-representative for this project because Windows-only dependencies (`LOCALAPPDATA`, WPF assemblies) are required.
- Release-readiness verification is executed via Windows PowerShell host from WSL.
