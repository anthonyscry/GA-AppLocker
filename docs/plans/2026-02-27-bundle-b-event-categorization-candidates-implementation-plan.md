# Bundle B Event Categorization and Candidate Scoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add backend commands that categorize AppLocker events and generate scored rule candidates from recurring telemetry patterns.

**Architecture:** Implement two new Scanning-module functions so current event ingestion and rule workflows gain decision-support without adding UI coupling. Both functions consume in-memory event/rule objects and return standardized result objects with deterministic summaries. Exports are wired through module and root manifests so commands are available from `GA-AppLocker` import.

**Tech Stack:** PowerShell 5.1, GA-AppLocker module manifests (`.psd1`/`.psm1`), Pester behavioral tests.

---

### Task 1: Add failing behavioral tests for Bundle B

**Files:**
- Create: `Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1`
- Test helper input shape: event objects compatible with `Get-AppLockerEventLogs` output

**Step 1: Write failing test for covered event categorization**

```powershell
It 'Categorizes covered blocked event as KnownGood' {
    $events = @([PSCustomObject]@{ EventId=8002; FilePath='C:\Windows\System32\cmd.exe'; IsBlocked=$true; IsAudit=$false; SHA256Hash='A'*64 })
    $rules = @([PSCustomObject]@{ RuleType='Hash'; Hash=('A'*64); Action='Allow'; CollectionType='Exe'; UserOrGroupSid='S-1-1-0'; Status='Approved' })
    $result = Invoke-AppLockerEventCategorization -Events $events -Rules $rules
    $result.Success | Should -BeTrue
    $result.Data.Events[0].Category | Should -Be 'KnownGood'
}
```

**Step 2: Write failing tests for uncovered blocked/audit categorization and candidate scoring**

**Step 3: Run the new test file to verify RED state**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1' -Output Detailed`
Expected: fails with command/function not found.

### Task 2: Implement event categorization function

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Invoke-AppLockerEventCategorization.ps1`

**Step 1: Implement coverage matching helpers (hash/path/publisher)**

**Step 2: Implement categorization mapping and summary object**

**Step 3: Re-run tests to move partially GREEN**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1' -Output Detailed`
Expected: categorization tests pass, candidate tests still fail.

### Task 3: Implement candidate generation and scoring function

**Files:**
- Create: `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/Get-AppLockerRuleCandidates.ps1`

**Step 1: Implement correlation grouping by hash/path with recurrence + machine spread**

**Step 2: Implement deterministic confidence scoring and recommended rule type**

**Step 3: Apply threshold filters and sorted output**

**Step 4: Re-run tests to reach GREEN**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1' -Output Detailed`
Expected: all tests pass.

### Task 4: Export new commands in module and root

**Files:**
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Scanning/GA-AppLocker.Scanning.psm1`
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Scanning/GA-AppLocker.Scanning.psd1`
- Modify: `GA-AppLocker/GA-AppLocker.psm1`
- Modify: `GA-AppLocker/GA-AppLocker.psd1`

**Step 1: Add both command names to Scanning exports**

**Step 2: Add both command names to root exports**

**Step 3: Run import/command resolution smoke checks**

Run:
- `Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force`
- `Get-Command Invoke-AppLockerEventCategorization`
- `Get-Command Get-AppLockerRuleCandidates`

Expected: both commands resolve from root module.

### Task 5: Verify regressions in nearest related suites

**Files:**
- Verify existing tests only

**Step 1: Run event ingestion behavioral suite**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/EventIngestion.BoundedQuery.Tests.ps1' -Output Detailed`

**Step 2: Run rules behavioral suite**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/Rules.Behavior.Tests.ps1' -Output Detailed`

**Step 3: Parse-check modified scanning files**

Run parser checks on newly added function files and modified module manifests.
