# Phase 13 Release Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a release-ready Phase 13 by balancing targeted coverage expansion, reliability fixes, and operator-facing verification evidence.

**Architecture:** Execute short TDD loops across test expansion, stability hardening, and release evidence updates. Pair each defect fix with regression coverage and keep operator docs/changelog aligned to verified outcomes.

**Tech Stack:** PowerShell 5.1, Pester, WPF code-behind (`.xaml.ps1` + panel scripts), module functions, markdown docs.

Execution Status: Complete

---

### Task List

1. Establish baseline and targeted test matrix.
2. Add deployment reliability regression assertions.
3. Add setup/status transition regression assertions.
4. Add scanner-to-rules conversion edge assertions.
5. Add Event Viewer action wiring checks.
6. Add workflow-level release smoke assertions.
7. Track and close scoped P0/P1 triage items.
8. Update operator runbook validation docs.
9. Align changelog and release notes.
10. Capture final verification evidence.
11. Record end-of-phase handoff markers.

## Final Verification Command Set

1. `Invoke-Pester -Path 'Tests/Unit/Deployment.Tests.ps1' -Output Detailed`
2. `Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`
3. `Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`
4. `Invoke-Pester -Path 'Tests/Behavioral/GUI/RecentRegressions.Tests.ps1' -Output Detailed`
5. `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`
