# Scanner UI Speed Optimizations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce Scanner event-to-rule interaction cost and improve perceived filter responsiveness with low-risk UI changes.

**Architecture:** Keep the current Scanner layout, add one explicit Event Metrics quick action, and unify all event->rule triggers through a single guarded execution path. Optimize search refresh to prioritize the active results tab so hidden-tab recompute does not slow typing. Preserve existing context-menu behavior and generation settings semantics.

**Tech Stack:** PowerShell 5.1, WPF/XAML, Pester v5 behavioral GUI tests

---

### Task 1: Add failing tests for visible quick action and trigger routing

**Use skills:** @superpowers:test-driven-development, @superpowers:verification-before-completion

**Files:**
- Modify: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
- Modify: `GA-AppLocker/GUI/MainWindow.xaml`

**Step 1: Write the failing tests**

```powershell
Describe 'Event metrics quick action controls' {
    It 'Exposes a visible quick action button for event->rule generation' {
        $mainWindowXaml = Get-Content -Path $script:MainWindowXamlPath -Raw
        $mainWindowXaml | Should -Match 'x:Name="BtnGenerateRuleFromEvent"'
        $mainWindowXaml | Should -Match 'Content="Generate Rule"'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'C:\Projects\GA-AppLocker\Tests\Behavioral\GUI\Scanner.EventMetrics.Tests.ps1' -Output Detailed"`

Expected: FAIL for missing `BtnGenerateRuleFromEvent` control.

**Step 3: Write minimal implementation**

```xml
<Button x:Name="BtnGenerateRuleFromEvent"
        Content="Generate Rule"
        Tag="GenerateRuleFromEvent"
        Style="{StaticResource SecondaryButtonStyle}" />
```

Add this in Event Metrics controls near the mode buttons; do not alter existing context menu.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: New quick-action control test passes.

**Step 5: Commit**

```bash
git add "Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1" "GA-AppLocker/GUI/MainWindow.xaml"
git commit -m "test: cover scanner event quick action control"
```

### Task 2: Add guarded unified trigger function (button/context/double-click/Enter)

**Use skills:** @superpowers:test-driven-development, @superpowers:verification-before-completion

**Files:**
- Modify: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`

**Step 1: Write the failing tests**

```powershell
Describe 'Invoke-GenerateRuleFromEventQuickAction' {
    BeforeEach {
        $script:GA_EventRuleGenerationInProgress = $false
    }

    It 'Invokes selected-event generation once when idle' {
        Mock Invoke-GenerateRuleFromSelectedEvent { }
        Mock Show-Toast { }

        Invoke-GenerateRuleFromEventQuickAction -Window $win

        Should -Invoke Invoke-GenerateRuleFromSelectedEvent -Times 1
    }

    It 'Skips duplicate trigger when generation is already in progress' {
        $script:GA_EventRuleGenerationInProgress = $true
        Mock Invoke-GenerateRuleFromSelectedEvent { }

        Invoke-GenerateRuleFromEventQuickAction -Window $win

        Should -Invoke Invoke-GenerateRuleFromSelectedEvent -Times 0
    }
}
```

**Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'C:\Projects\GA-AppLocker\Tests\Behavioral\GUI\Scanner.EventMetrics.Tests.ps1' -Output Detailed"`

Expected: FAIL because helper function does not exist yet.

**Step 3: Write minimal implementation**

```powershell
function global:Invoke-GenerateRuleFromEventQuickAction {
    param($Window)

    if ($script:GA_EventRuleGenerationInProgress) { return }

    $script:GA_EventRuleGenerationInProgress = $true
    try {
        Invoke-GenerateRuleFromSelectedEvent -Window $Window
    }
    finally {
        $script:GA_EventRuleGenerationInProgress = $false
    }
}
```

Then wire all trigger sources to this helper:
- visible button click
- context menu click
- grid double-click
- Enter key on `EventMetricsDataGrid`

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: trigger-routing tests pass and existing event generation tests stay green.

**Step 5: Commit**

```bash
git add "Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1" "GA-AppLocker/GUI/Panels/Scanner.ps1"
git commit -m "feat: unify and guard scanner event rule triggers"
```

### Task 3: Add active-tab-first refresh behavior for shared Scanner search

**Use skills:** @superpowers:test-driven-development, @superpowers:verification-before-completion

**Files:**
- Modify: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`
- Modify: `GA-AppLocker/GUI/Panels/Scanner.ps1`

**Step 1: Write the failing tests**

```powershell
Describe 'Update-ScannerResultsForSharedSearch' {
    It 'Updates artifacts only when Collected Artifacts tab is active' {
        Mock Update-ArtifactDataGrid { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win -ActiveTabHeader 'Collected Artifacts'

        Should -Invoke Update-ArtifactDataGrid -Times 1
        Should -Invoke Update-EventMetricsUI -Times 0
    }

    It 'Updates event metrics only when Event Metrics tab is active' {
        Mock Update-ArtifactDataGrid { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win -ActiveTabHeader 'Event Metrics'

        Should -Invoke Update-ArtifactDataGrid -Times 0
        Should -Invoke Update-EventMetricsUI -Times 1
    }
}
```

**Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'C:\Projects\GA-AppLocker\Tests\Behavioral\GUI\Scanner.EventMetrics.Tests.ps1' -Output Detailed"`

Expected: FAIL because refresh helper does not exist yet.

**Step 3: Write minimal implementation**

```powershell
function global:Invoke-ScannerSharedSearchRefresh {
    param($Window, [string]$ActiveTabHeader)

    if ($ActiveTabHeader -eq 'Event Metrics') {
        Update-EventMetricsUI -Window $Window
        return
    }

    Update-ArtifactDataGrid -Window $Window
}
```

Call this from the debounce tick based on `ScannerResultsTabControl.SelectedItem.Header`.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: active-tab refresh tests pass and no regression in existing filter tests.

**Step 5: Commit**

```bash
git add "Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1" "GA-AppLocker/GUI/Panels/Scanner.ps1"
git commit -m "perf: prioritize active scanner results tab refresh"
```

### Task 4: Final verification and regression safety

**Use skills:** @superpowers:verification-before-completion

**Files:**
- Test: `Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1`

**Step 1: Run focused Scanner behavioral tests**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'C:\Projects\GA-AppLocker\Tests\Behavioral\GUI\Scanner.EventMetrics.Tests.ps1' -Output Detailed"`

Expected: PASS with zero failures.

**Step 2: Run Rules behavior tests as adjacent regression check**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'C:\Projects\GA-AppLocker\Tests\Behavioral\Core\Rules.Behavior.Tests.ps1' -Output Detailed"`

Expected: PASS with zero failures.

**Step 3: Manual UI smoke checklist**

- Open dashboard and navigate to Scanner.
- Run scan with event logs enabled.
- In Event Metrics: trigger generation via button, right-click, double-click, and Enter.
- Confirm one generation action per input and no duplicate-job behavior.
- Confirm typing in shared search feels responsive and does not stall hidden tab.

**Step 4: Run git status and capture final diff summary**

Run: `git status --short && git diff --stat`

Expected: Only intended files changed.

**Step 5: Commit final polish (if needed)**

```bash
git add "GA-AppLocker/GUI/MainWindow.xaml" "GA-AppLocker/GUI/Panels/Scanner.ps1" "Tests/Behavioral/GUI/Scanner.EventMetrics.Tests.ps1"
git commit -m "feat: speed up scanner event-to-rule workflow"
```
