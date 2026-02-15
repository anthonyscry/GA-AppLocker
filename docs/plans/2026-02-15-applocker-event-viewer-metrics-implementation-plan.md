# AppLocker Event Viewer Metrics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Scanner-integrated Event Viewer metrics section that shows the most common blocked/audited AppLocker files from the latest scan with interactive filters.

**Architecture:** Reuse existing `Start-ArtifactScan` output (`Data.EventLogs`) and keep scan orchestration unchanged. Compute event aggregations in `GUI/Panels/Scanner.ps1` via pure helper functions, then bind results to new Scanner UI controls in `MainWindow.xaml`.

**Tech Stack:** PowerShell 5.1, WPF XAML, GA-AppLocker scan modules, Pester 5 behavioral tests.

---

### Task 1: Add pure event-metric aggregation helper in Scanner panel

**Files:**
- Create: `GA-AppLocker/Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`

**Step 1: Write the failing test**

Add a test for deterministic top-N grouping and blocked/audit split:

```powershell
Describe 'Get-ScanEventMetrics' {
    It 'Groups by machine and file and reports blocked/audit counts' {
        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = (Get-Date).AddMinutes(-10) },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = (Get-Date) },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true; TimeCreated = (Get-Date) }
        )

        $result = Get-ScanEventMetrics -Events $events -Mode 'All' -TopN 10

        $result.Count | Should -Be 1
        $result[0].FilePath | Should -Be 'C:\app\\x.exe'
        $result[0].BlockedCount | Should -Be 2
        $result[0].AuditCount | Should -Be 1
    }
}
```

**Step 2: Run it to make sure it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`
Expected: FAIL (`Get-ScanEventMetrics` not defined).

**Step 3: Write the minimal code to make the test pass**

In `GUI/Panels/Scanner.ps1`, add:

```powershell
function global:Get-ScanEventMetrics {
    param(
        [Parameter(Mandatory)]$Events,
        [ValidateSet('All','Blocked','Audit')]$Mode = 'All',
        [int]$TopN = 20
    )

    $inputEvents = @($Events)
    if ($TopN -le 0) { $TopN = 20 }

    if ($Mode -eq 'Blocked') { $inputEvents = @($inputEvents | Where-Object { $_.IsBlocked }) }
    elseif ($Mode -eq 'Audit') { $inputEvents = @($inputEvents | Where-Object { $_.IsAudit }) }

    $groups = @(
        foreach ($item in @($inputEvents)) {
            if (-not $item.FilePath) { $item.FilePath = '<unknown path>' }
            [PSCustomObject]@{
                FilePath = [string]$item.FilePath
                ComputerName = [string]$item.ComputerName
                EventType = [string]$item.EventType
                Count = $null
                BlockedCount = if ($item.IsBlocked) { 1 } else { 0 }
                AuditCount = if ($item.IsAudit) { 1 } else { 0 }
                LastSeen = $item.TimeCreated
            }
        } |
        Group-Object -Property { $_.ComputerName + '|' + $_.FilePath + '|' + $_.EventType } |
        ForEach-Object {
            $rows = $_.Group
            [PSCustomObject]@{
                FilePath = $rows[0].FilePath
                ComputerName = $rows[0].ComputerName
                EventType = $rows[0].EventType
                Count = $rows.Count
                BlockedCount = ($rows | Where-Object { $_.BlockedCount -gt 0 }).Count
                AuditCount = ($rows | Where-Object { $_.AuditCount -gt 0 }).Count
                LastSeen = @($rows | Sort-Object -Property LastSeen -Descending)[0].LastSeen
            }
        } |
        Sort-Object -Property Count -Descending
    )

    return @($groups | Select-Object -First $TopN)
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`
Expected: PASS for grouping behavior.

**Step 5: Commit**

```bash
git add GA-AppLocker/GUI/Panels/Scanner.ps1 Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1
git commit -m "feat: add scan event grouping helper for metrics"
```

### Task 2: Add event metric state handling in scan completion flow

**Files:**
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`

**Step 1: Write the failing test**

In `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1` add:

```powershell
It 'Clears event metrics when include-event is not enabled' {
    # Set script:CurrentScanEventLogs = @(@{ FilePath = 'C:\x'; ComputerName = 'WKS1' })
    # Invoke scan-completion-like assignment path with IncludeEventLogs false input
    # Assert CurrentScanEventLogs is empty or zeroed
}
```

**Step 2: Run it to make sure it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 3: Write the minimal code to make the test pass**

In `Invoke-StartArtifactScan` completion handler block (around success path):

- initialize `$script:CurrentScanEventLogs = @()` before scan starts,
- on complete set `$script:CurrentScanEventLogs = @($result.Data.EventLogs)` when available.

Add session counters updates:

```powershell
$eventGrid = $win.FindName('TxtEventTotalCount')
if ($eventGrid) { $eventGrid.Text = "$($result.Summary.TotalEvents)" }
```

and call `Update-EventMetricsUI -Window $win`.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 5: Commit**

```bash
git add GA-AppLocker/GUI/Panels/Scanner.ps1 Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1
git commit -m "feat: persist scan event logs for metrics display"
```

### Task 3: Add Scanner event metrics UI in XAML

**Files:**
- Modify: `GA-AppLocker/GUI/MainWindow.xaml`

**Step 1: Write the failing test**

In `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1` add a static structure test:

```powershell
Describe 'Scanner XAML event-metrics controls' {
    It 'Has event metrics counter and filter controls' {
        # New-MockXaml load + FindName checks for:
        # TxtEventTotalCount, TxtEventBlockedCount, TxtEventAuditCount,
        # CboEventMode, CboEventMachine, TxtEventPathFilter, TxtEventTopN, EventMetricsDataGrid
    }
}
```

**Step 2: Run it to make sure it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 3: Write the minimal code to make the test pass**

In Scanner panel layout near artifact results add:

- three text blocks (`TxtEventTotalCount`, `TxtEventBlockedCount`, `TxtEventAuditCount`)
- filter controls (`CboEventMode`, `CboEventMachine`, `TxtEventPathFilter`, `TxtEventTopN`)
- results DataGrid `EventMetricsDataGrid` with columns for rank/path/machine/type/count/blocked/audit/last seen.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 5: Commit**

```bash
git add GA-AppLocker/GUI/MainWindow.xaml
git commit -m "feat: add scanner event metrics UI controls"
```

### Task 4: Bind filter controls to metric refresh behavior

**Files:**
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`
- Modify: `GA-AppLocker/GUI/MainWindow.xaml.ps1` (if event dispatch uses centralized action map)

**Step 1: Write the failing test**

Add test for mode/machine filter behavior using event data and mock controls:

```powershell
It 'Updates visible metrics when event mode and machine filters change' {
    # Seed CurrentScanEventLogs with mixed blocked/audit and multi-machine rows
    # Trigger Update-EventMetricsUI
    # Assert DataGrid ItemsSource matches selected mode and machine
}
```

**Step 2: Run it to make sure it fails**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 3: Write the minimal code to make the test pass**

In `Scanner.ps1`:

- add `Update-EventMetricsUI`, `Set-EventFilterState`, and `Get-SelectedEventMode` helpers,
- add `SelectionChanged` / `TextChanged` handlers for filters,
- call refresh in filter callbacks and at scan completion,
- guard against null grid/controls with early return.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`

**Step 5: Commit**

```bash
git add GA-AppLocker/GUI/Panels/Scanner.ps1 GA-AppLocker/GUI/MainWindow.xaml.ps1
git commit -m "feat: wire scanner event metrics filters and refresh"
```

### Task 5: Add manual verification + smoke scenario

**Files:**
- Modify: `docs/plans/2026-02-15-applocker-event-viewer-metrics-design.md` (optional notes)

**Step 1: Write the acceptance checklist**

No code change; add quick run guide section in the plan if needed.

**Step 2: Run it to make sure it fails (where command-based)**

Run:

- `Invoke-Pester -Path 'Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1' -Output Detailed`
- `Invoke-Pester -Path 'Tests/Behavioral/GUI' -Output Detailed`

Expected: all green before merge.

**Step 3: Write the minimal command sequence for smoke verification**

- `Import-Module .\GA-AppLocker\GA-AppLocker.psd1 -Force`
- Run AppLocker dashboard
- Execute local scan with `Include Event Logs` checked
- Confirm metrics pane renders, blocked/audit counts update, machine filter works

**Step 4: Run manual checks**

Execute the above UI flow once on the development machine.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-15-applocker-event-viewer-metrics-design.md
git commit -m "docs: add implementation verification checklist"
```

## Plan complete and saved to `docs/plans/2026-02-15-applocker-event-viewer-metrics-implementation-plan.md`. Two execution options:

1. **Subagent-Driven (this session)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** — open a new session with `superpowers:executing-plans`, and run with batch checkpoints.

**Which approach?**
