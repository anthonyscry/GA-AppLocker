# Bundle C Policy Drift and Telemetry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement backend policy drift and telemetry summary commands to surface drift gaps and trendable policy activity.

**Architecture:** Add two Policy-module functions: one computes drift from categorized event coverage, and one aggregates telemetry from the existing audit trail. Drift evaluation reuses `Invoke-AppLockerEventCategorization` and existing policy/rule retrieval patterns. Telemetry remains JSONL/audit-log based for air-gapped reliability.

**Tech Stack:** PowerShell 5.1, GA-AppLocker.Policy + Core functions (`Get-Policy`, `Get-Rule`, `Get-AuditLog`, `Write-AuditLog`), Pester behavioral tests.

---

### Task 1: Add failing behavioral tests first

**Files:**
- Create: `Tests/Behavioral/Core/PolicyDrift.Telemetry.Behavior.Tests.ps1`

**Step 1: Write failing tests for drift summary and gap extraction**

**Step 2: Write failing tests for telemetry aggregation and policy filtering**

**Step 3: Run test file to verify RED state**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/PolicyDrift.Telemetry.Behavior.Tests.ps1' -Output Detailed`
Expected: fail due missing commands.

### Task 2: Implement drift reporting command

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Get-PolicyDriftReport.ps1`

**Step 1: Implement rule set resolution path (Rules -> PolicyId -> Approved defaults)**

**Step 2: Invoke event categorization and compute drift summary + staleness**

**Step 3: Add optional telemetry write path (`PolicyDriftCalculated`)**

### Task 3: Implement telemetry summary command

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Policy/Functions/Get-PolicyTelemetrySummary.ps1`

**Step 1: Query policy audit entries over configurable time window**

**Step 2: Aggregate action counts and drift-check metadata**

**Step 3: Return standardized summary object with optional raw events**

### Task 4: Export commands in Policy and root modules

**Files:**
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Policy/GA-AppLocker.Policy.psm1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Policy/GA-AppLocker.Policy.psd1`
- Modify: `GA-AppLocker/GA-AppLocker.psm1`
- Modify: `GA-AppLocker/GA-AppLocker.psd1`

**Step 1: Add both command names to module exports**

**Step 2: Add both command names to root exports**

### Task 5: Verify and regressions

**Step 1: Run new behavioral test file**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/PolicyDrift.Telemetry.Behavior.Tests.ps1' -Output Detailed`

**Step 2: Run nearby policy and event suites**

Run:
- `Invoke-Pester -Path 'Tests/Behavioral/Core/Policy.Behavior.Tests.ps1' -Output Detailed`
- `Invoke-Pester -Path 'Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1' -Output Detailed`

**Step 3: Smoke command discovery**

Run:
- `Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force`
- `Get-Command Get-PolicyDriftReport`
- `Get-Command Get-PolicyTelemetrySummary`
