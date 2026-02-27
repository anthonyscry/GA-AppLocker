# Scheduled Scan Event Logs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable scheduled scans to persist and execute with `IncludeEventLogs` so recurring jobs can collect AppLocker event logs.

**Architecture:** Extend scheduled-scan configuration and execution paths in `ScheduledScans.ps1` with a new boolean setting, then wire the existing Scanner checkbox into scheduled-scan creation. Keep compatibility by treating missing `IncludeEventLogs` as false for legacy schedule JSON files.

**Tech Stack:** PowerShell 5.1, GA-AppLocker.Scanning + GUI Scanner panel, Pester behavioral tests.

---

### Task 1: Add failing behavioral tests for scheduled scan include-event behavior

**Files:**
- Create: `Tests/Behavioral/Core/ScheduledScans.EventLogs.Behavior.Tests.ps1`

**Step 1: Write failing test for persistence on create**

- Dot-source `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/ScheduledScans.ps1`.
- Use a temp data path mock (`Get-AppLockerDataPath`) and create schedule with `-IncludeEventLogs`.
- Assert persisted JSON includes `IncludeEventLogs = true`.

**Step 2: Write failing test for execution forwarding**

- Seed a schedule JSON with `IncludeEventLogs = true`.
- Mock `Start-ArtifactScan` and call `Invoke-ScheduledScan`.
- Assert mock receives `IncludeEventLogs = $true`.

**Step 3: Write failing test for legacy schedule fallback**

- Seed schedule JSON without `IncludeEventLogs`.
- Mock `Start-ArtifactScan` and call `Invoke-ScheduledScan`.
- Assert call does not include `IncludeEventLogs`.

**Step 4: Run test file to verify RED state**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/ScheduledScans.EventLogs.Behavior.Tests.ps1' -Output Detailed`

Expected: one or more failures due missing implementation wiring.

### Task 2: Implement scheduled-scan model and runtime pass-through

**Files:**
- Modify: `GA-AppLocker/Modules/GA-AppLocker.Scanning/Functions/ScheduledScans.ps1`

**Step 1: Extend New-ScheduledScan parameters**

- Add `[switch]$IncludeEventLogs` parameter in `New-ScheduledScan`.

**Step 2: Persist IncludeEventLogs in schedule object**

- Add `IncludeEventLogs = $IncludeEventLogs.IsPresent` to the schedule payload written to JSON.

**Step 3: Forward IncludeEventLogs in Invoke-ScheduledScan**

- When loaded schedule indicates true, set `$scanParams.IncludeEventLogs = $true` before `Start-ArtifactScan`.

**Step 4: Keep legacy-safe behavior**

- Ensure missing property from old JSON evaluates safely to false.

### Task 3: Wire Scanner schedule-creation path to pass IncludeEventLogs

**Files:**
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`

**Step 1: Read existing checkbox state for schedule create call**

- Reuse existing `ChkIncludeEventLogs` lookup in `Invoke-CreateScheduledScan`.

**Step 2: Add IncludeEventLogs to New-ScheduledScan params**

- If checked, set `$params.IncludeEventLogs = $true`.

**Step 3: Preserve current behavior for unchecked state**

- Do not pass parameter when unchecked.

### Task 4: Add/extend UI behavioral test for Scanner scheduled-scan create wiring

**Files:**
- Modify: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
  - OR create focused file if cleaner: `Tests/Behavioral/GUI/Scanner.ScheduledScans.Tests.ps1`

**Step 1: Add failing test for IncludeEventLogs checkbox forwarding**

- Build mock window with `ChkIncludeEventLogs` checked and required schedule controls.
- Mock `New-ScheduledScan` and call `Invoke-CreateScheduledScan`.
- Assert parameter forwarding includes `IncludeEventLogs = $true`.

**Step 2: Add complementary unchecked-state assertion**

- Same setup with checkbox unchecked.
- Assert `IncludeEventLogs` is not forwarded.

**Step 3: Run relevant GUI behavioral tests**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

Expected: new and existing scanner tests pass.

### Task 5: Verification and regression

**Step 1: Run new core behavioral test**

Run: `Invoke-Pester -Path 'Tests/Behavioral/Core/ScheduledScans.EventLogs.Behavior.Tests.ps1' -Output Detailed`

**Step 2: Run scanner GUI behavioral tests**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 3: Run event pipeline regressions**

Run:
- `Invoke-Pester -Path 'Tests/Behavioral/Core/EventCategorization.Candidates.Behavior.Tests.ps1' -Output Detailed`
- `Invoke-Pester -Path 'Tests/Behavioral/Core/PolicyDrift.Telemetry.Behavior.Tests.ps1' -Output Detailed`

**Step 4: Optional import smoke (environment permitting)**

Run:
- `Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force`
- `Get-Command New-ScheduledScan`
- `Get-Command Invoke-ScheduledScan`
