# Bundle A Safety Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add unified preflight diagnostics and policy merge contradiction blocking so risky setup/policy operations fail fast with actionable feedback.

**Architecture:** Introduce one Setup-module orchestrator (`Invoke-PreflightDiagnostics`) that normalizes prerequisite and setup checks into a single result contract. Introduce one Policy-module validator (`Test-RuleMergeConflicts`) and enforce it inside `Add-RuleToPolicy` before policy writes. Keep UI impact minimal by gating existing Setup full initialization flow and reusing existing toast/message patterns.

**Tech Stack:** PowerShell 5.1, WPF code-behind, module manifests (`.psm1`/`.psd1`), Pester behavioral/unit tests.

---

### Task 1: Add unified preflight diagnostics

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Setup/Functions/Invoke-PreflightDiagnostics.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Setup/GA-AppLocker.Setup.psm1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Setup/GA-AppLocker.Setup.psd1`

**Step 1: Write failing unit tests for preflight result contract**

Target test file:
- `Tests/Unit/Setup.Tests.ps1`

**Step 2: Run setup unit tests to capture failing expectations**

Run:
`Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`

**Step 3: Implement `Invoke-PreflightDiagnostics`**

Requirements:
- Return standard object (`Success`, `Data`, `Error`).
- Aggregate `Test-Prerequisites` checks and `Get-SetupStatus` status.
- Provide normalized check statuses (`Pass`, `Warn`, `Fail`) and summary counts.

**Step 4: Export function in Setup module manifest/loader**

**Step 5: Re-run Setup unit tests**

Run:
`Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`

### Task 2: Gate full initialization with preflight

**Files:**
- Modify: `GA-AppLocker/GUI/Panels/Setup.ps1`

**Step 1: Write/adjust behavior expectations in existing tests (if available)**

**Step 2: Add preflight gate to `Invoke-InitializeAll`**

Requirements:
- Call `Invoke-PreflightDiagnostics` before starting initialization.
- Block operation on `Fail` checks and show clear operator message.
- Allow operation when only warnings are present.

**Step 3: Validate setup panel script syntax/behavioral flow**

### Task 3: Add merge contradiction detection and enforce in policy attach flow

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Test-RuleMergeConflicts.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Manage-PolicyRules.ps1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Policy/GA-AppLocker.Policy.psm1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Policy/GA-AppLocker.Policy.psd1`

**Step 1: Write failing behavioral tests for contradiction blocking**

Target test file:
- `Tests/Behavioral/Core/Policy.Behavior.Tests.ps1`

**Step 2: Run policy behavioral tests to verify failures first**

Run:
`Invoke-Pester -Path 'Tests/Behavioral/Core/Policy.Behavior.Tests.ps1' -Output Detailed`

**Step 3: Implement `Test-RuleMergeConflicts`**

Requirements:
- Compare incoming rule IDs vs existing policy rule IDs using rule semantic keys.
- Flag contradictions where same semantic key has both `Allow` and `Deny`.
- Surface duplicates separately; block only contradictions.

**Step 4: Wire check into `Add-RuleToPolicy` before file write**

### Task 4: Update root exports and verify end-to-end availability

**Files:**
- Modify: `GA-AppLocker/GA-AppLocker.psm1`
- Modify: `GA-AppLocker/GA-AppLocker.psd1`

**Step 1: Add both new function names to root export lists**

**Step 2: Re-run targeted tests**

Run:
- `Invoke-Pester -Path 'Tests/Unit/Setup.Tests.ps1' -Output Detailed`
- `Invoke-Pester -Path 'Tests/Behavioral/Core/Policy.Behavior.Tests.ps1' -Output Detailed`

**Step 3: Confirm no regressions in nearest behavioral suite**

Run:
`Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`

### Task 5: Final verification

**Files:**
- Verify changed files only

**Step 1: Run module import smoke check**

Run:
`Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force`

**Step 2: Confirm new commands resolve**

Run:
- `Get-Command Invoke-PreflightDiagnostics`
- `Get-Command Test-RuleMergeConflicts`

**Step 3: Capture evidence and summarize assumptions/limitations**
