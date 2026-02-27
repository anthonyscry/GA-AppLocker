# Phase 13 Release Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a release-ready Phase 13 by balancing targeted coverage expansion, reliability fixes, and operator-facing verification evidence.

**Architecture:** Execute in short TDD loops across three lanes: test expansion, stability hardening, and release evidence updates. Every defect fix must pair with a regression test, and every user-visible change must land in docs/changelog. Finish with a deterministic verification gate aligned to the phase exit criteria.

**Tech Stack:** PowerShell 5.1, Pester, WPF code-behind (`.xaml.ps1` and panel scripts), module function scripts, markdown docs.

---

### Task 1: Establish Phase 13 Baseline and Targeted Test Scope

**Files:**
- Modify: `docs/plans/2026-02-18-phase-13-release-readiness-design.md`
- Create: `docs/plans/2026-02-18-phase-13-targeted-test-matrix.md`

**Step 1: Write the failing test**

```powershell
It 'has a Phase 13 targeted matrix file' {
    Test-Path "$PSScriptRoot/../../docs/plans/2026-02-18-phase-13-targeted-test-matrix.md" | Should -BeTrue
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: FAIL because matrix file does not exist yet.

**Step 3: Write minimal implementation**

Create `docs/plans/2026-02-18-phase-13-targeted-test-matrix.md` with scoped areas, risk level, and target test files.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: PASS for the new existence assertion.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-18-phase-13-release-readiness-design.md docs/plans/2026-02-18-phase-13-targeted-test-matrix.md
git commit -m "docs(phase-13): define targeted test matrix and baseline"
```

### Task 2: Add Deployment Reliability Regression Tests

**Files:**
- Modify: `Tests/Unit/Deployment.Tests.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Deployment/Functions/Start-Deployment.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Deployment/Functions/Update-DeploymentJob.ps1`

**Step 1: Write the failing test**

```powershell
It 'returns standardized failure object when deployment prerequisites fail' {
    $result = Start-Deployment -PolicyPath 'Z:\missing.xml' -TargetGPO 'AppLocker-Workstations'
    $result.Success | Should -BeFalse
    $result.Error | Should -Not -BeNullOrEmpty
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Unit/Deployment.Tests.ps1' -Output Detailed`
Expected: FAIL in new deployment prerequisite test.

**Step 3: Write minimal implementation**

Add/adjust guarded prerequisite checks and consistent return object handling in deployment functions.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Unit/Deployment.Tests.ps1' -Output Detailed`
Expected: PASS for new and existing Deployment tests.

**Step 5: Commit**

```bash
git add Tests/Unit/Deployment.Tests.ps1 GA-AppLocker/Modules/GA-AppLocker.Deployment/Functions/Start-Deployment.ps1 GA-AppLocker/Modules/GA-AppLocker.Deployment/Functions/Update-DeploymentJob.ps1
git commit -m "test(deployment): add prereq failure regression coverage"
```

### Task 3: Add Setup/Status Transition Regression Tests

**Files:**
- Modify: `Tests/Unit/Setup.Tests.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Get-SetupStatus.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Initialize-WinRMGPO.ps1`

**Step 1: Write the failing test**

```powershell
It 'reports consistent GPO toggle states when status source partially fails' {
    $status = Get-SetupStatus
    $status | Should -Not -BeNullOrEmpty
    $status.Success | Should -BeTrue
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`
Expected: FAIL around inconsistent/exceptional status path handling.

**Step 3: Write minimal implementation**

Harden setup status path with per-check isolation and standardized status shaping.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`
Expected: PASS for setup status transition assertions.

**Step 5: Commit**

```bash
git add Tests/Unit/Setup.Tests.ps1 GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Get-SetupStatus.ps1 GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Initialize-WinRMGPO.ps1
git commit -m "test(setup): harden setup status transition behavior"
```

### Task 4: Add Scanner-to-Rules Conversion Edge Tests

**Files:**
- Modify: `Tests/Behavioral/Core/Rules.Behavior.Tests.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/ConvertFrom-Artifact.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Get-LocalArtifacts.ps1`

**Step 1: Write the failing test**

```powershell
It 'creates hash rules for unsigned artifacts with explicit false values' {
    $artifact = [pscustomobject]@{ Path='C:\temp\a.exe'; IsSigned=$false; SHA256Hash='11' * 32; ArtifactType='EXE' }
    $rule = ConvertFrom-Artifact -Artifact $artifact
    $rule.RuleType | Should -Be 'Hash'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: FAIL in unsigned conversion edge case.

**Step 3: Write minimal implementation**

Normalize signed-state coercion and enforce deterministic rule type mapping.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`
Expected: PASS for new conversion assertions.

**Step 5: Commit**

```bash
git add Tests/Behavioral/Core/Rules.Behavior.Tests.ps1 GA-AppLocker/Modules/GA-AppLocker.Rules/Functions/ConvertFrom-Artifact.ps1 GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Get-LocalArtifacts.ps1
git commit -m "fix(rules): stabilize artifact conversion edge behavior"
```

### Task 5: Add Event Viewer/Scanner GUI Wiring Checks

**Files:**
- Modify: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
- Modify: `Tests/Behavioral/GUI/EventViewer.Navigation.Tests.ps1`
- Modify: `GA-AppLocker/GUI/Panels/EventViewer.ps1`

**Step 1: Write the failing test**

```powershell
It 'wires Event Viewer action buttons to callable handlers' {
    $handlers = Get-Command -Name Invoke-EventViewer* -ErrorAction SilentlyContinue
    @($handlers).Count | Should -BeGreaterThan 0
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/EventViewer.Navigation.Tests.ps1' -Output Detailed`
Expected: FAIL on missing or mismatched handler wiring.

**Step 3: Write minimal implementation**

Align button event wiring and handler names to tested entry points.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/EventViewer.Navigation.Tests.ps1' -Output Detailed`
Expected: PASS with handler discovery and invocation path assertions.

**Step 5: Commit**

```bash
git add Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1 Tests/Behavioral/GUI/EventViewer.Navigation.Tests.ps1 GA-AppLocker/GUI/Panels/EventViewer.ps1
git commit -m "test(gui): add event viewer wiring regression checks"
```

### Task 6: Add Workflow-Level Release Smoke Assertions

**Files:**
- Modify: `Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1`
- Modify: `Tests/Behavioral/Workflows/Workflow.Mock.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It 'completes discovery to deploy mock workflow without blocking failures' {
    $result = Invoke-AppLockerWorkflowMock
    $result.Success | Should -BeTrue
    $result.Blockers | Should -BeNullOrEmpty
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: FAIL where workflow contract is currently incomplete.

**Step 3: Write minimal implementation**

Adjust mock workflow result contract and failure propagation to satisfy deterministic e2e assertions.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: PASS for new release smoke assertions.

**Step 5: Commit**

```bash
git add Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1 Tests/Behavioral/Workflows/Workflow.Mock.Tests.ps1
git commit -m "test(workflow): add release smoke e2e assertions"
```

### Task 7: P0/P1 Stability Triage and Fix Loop

**Files:**
- Modify: `docs/plans/2026-02-18-phase-13-p0-p1-triage.md`
- Modify: `GA-AppLocker/GUI/Panels/Deploy.ps1`
- Modify: `GA-AppLocker/GUI/Panels/Setup.ps1`
- Modify: `GA-AppLocker/GUI/MainWindow.xaml.ps1`
- Test: `Tests/Behavioral/GUI/RecentRegressions.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It 'contains no open scoped P0/P1 blockers' {
    $triage = Get-Content "$PSScriptRoot/../../docs/plans/2026-02-18-phase-13-p0-p1-triage.md" -Raw
    $triage | Should -Not -Match 'Status:\s*Open\s*Severity:\s*P0|Status:\s*Open\s*Severity:\s*P1'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: FAIL until triage document and fixes are complete.

**Step 3: Write minimal implementation**

Create and maintain triage doc, apply minimal fixes for scoped blockers, and update statuses.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: PASS with zero open scoped P0/P1 entries.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-18-phase-13-p0-p1-triage.md GA-AppLocker/GUI/Panels/Deploy.ps1 GA-AppLocker/GUI/Panels/Setup.ps1 GA-AppLocker/GUI/MainWindow.xaml.ps1 Tests/Behavioral/GUI/RecentRegressions.Tests.ps1
git commit -m "fix(phase-13): resolve scoped P0/P1 blockers"
```

### Task 8: Operator Runbook Validation Updates

**Files:**
- Modify: `docs/QuickStart.md`
- Modify: `docs/README.md`
- Modify: `docs/STIG-Compliance.md`
- Create: `docs/plans/2026-02-18-phase-13-operator-runbook-checks.md`

**Step 1: Write the failing test**

```powershell
It 'has completed operator runbook checks for phase 13' {
    $runbook = Get-Content "$PSScriptRoot/../../docs/plans/2026-02-18-phase-13-operator-runbook-checks.md" -Raw
    $runbook | Should -Match 'Status:\s*Complete'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/Workflow.Mock.Tests.ps1' -Output Detailed`
Expected: FAIL because runbook check document is missing/incomplete.

**Step 3: Write minimal implementation**

Document and execute runbook checks, then update QuickStart/README/STIG notes for any clarified steps.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/Workflow.Mock.Tests.ps1' -Output Detailed`
Expected: PASS with runbook completion evidence.

**Step 5: Commit**

```bash
git add docs/QuickStart.md docs/README.md docs/STIG-Compliance.md docs/plans/2026-02-18-phase-13-operator-runbook-checks.md
git commit -m "docs(phase-13): complete operator runbook validation updates"
```

### Task 9: Changelog and Release Notes Alignment

**Files:**
- Modify: `CHANGELOG.md`
- Create: `docs/plans/2026-02-18-phase-13-release-notes-draft.md`

**Step 1: Write the failing test**

```powershell
It 'contains a Phase 13 changelog section' {
    $changelog = Get-Content "$PSScriptRoot/../../CHANGELOG.md" -Raw
    $changelog | Should -Match '## \[1\.2\.'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: FAIL if no Phase 13 release notes section exists.

**Step 3: Write minimal implementation**

Add Phase 13 release notes bullets and draft release notes document aligned to verified outcomes.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/RecentRegressions.Tests.ps1' -Output Detailed`
Expected: PASS for release note presence check.

**Step 5: Commit**

```bash
git add CHANGELOG.md docs/plans/2026-02-18-phase-13-release-notes-draft.md
git commit -m "docs(release): add phase 13 changelog and release notes draft"
```

### Task 10: Final Verification Gate

**Files:**
- Create: `docs/plans/2026-02-18-phase-13-verification-evidence.md`
- Modify: `Tests/Run-MustPass.ps1`

**Step 1: Write the failing test**

```powershell
It 'records final phase 13 verification outcomes' {
    Test-Path "$PSScriptRoot/../../docs/plans/2026-02-18-phase-13-verification-evidence.md" | Should -BeTrue
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Run-MustPass.ps1' -Output Detailed`
Expected: FAIL until evidence file exists and is populated.

**Step 3: Write minimal implementation**

Execute final targeted verification commands and log exact outcomes in evidence document.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Run-MustPass.ps1' -Output Detailed`
Expected: PASS with all scoped checks green.

**Step 5: Commit**

```bash
git add Tests/Run-MustPass.ps1 docs/plans/2026-02-18-phase-13-verification-evidence.md
git commit -m "chore(phase-13): capture final verification evidence"
```

### Task 11: End-of-Phase Sanity and Handoff

**Files:**
- Modify: `docs/plans/2026-02-18-phase-13-release-readiness-design.md`
- Modify: `docs/plans/2026-02-18-phase-13-release-readiness-implementation-plan.md`

**Step 1: Write the failing test**

```powershell
It 'marks phase 13 implementation plan as complete' {
    $plan = Get-Content "$PSScriptRoot/../../docs/plans/2026-02-18-phase-13-release-readiness-implementation-plan.md" -Raw
    $plan | Should -Match 'Execution Status:\s*Complete'
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: FAIL until completion marker and handoff notes are present.

**Step 3: Write minimal implementation**

Add completion marker, unresolved follow-ups (if any), and handoff summary.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`
Expected: PASS for completion marker assertion.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-18-phase-13-release-readiness-design.md docs/plans/2026-02-18-phase-13-release-readiness-implementation-plan.md
git commit -m "docs(phase-13): mark implementation complete and handoff"
```

## Final Verification Command Set

Run these commands at the final gate and record results in `docs/plans/2026-02-18-phase-13-verification-evidence.md`:

1. `Invoke-Pester -Path 'Tests/Unit/Deployment.Tests.ps1' -Output Detailed`
2. `Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`
3. `Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`
4. `Invoke-Pester -Path 'Tests/Behavioral/GUI/RecentRegressions.Tests.ps1' -Output Detailed`
5. `Invoke-Pester -Path 'Tests/Behavioral/Workflows/CoreFlows.E2E.Tests.ps1' -Output Detailed`

Expected final state: all targeted suites pass, no scoped open P0/P1 blockers, docs/changelog updated, operator runbook checks complete.
