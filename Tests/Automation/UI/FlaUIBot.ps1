#Requires -Version 5.1
<#
.SYNOPSIS
    UI Automation Bot for GA-AppLocker Dashboard.
.DESCRIPTION
    Uses Windows UIAutomation to test GUI functionality.
    Tests navigation, panel interactions, and basic workflows.
.PARAMETER TestMode
    Quick: Navigation only
    Standard: Navigation + basic interactions
    Full: All panels with data entry
.PARAMETER KeepOpen
    Don't close the dashboard after tests.
.PARAMETER DelayMs
    Delay between actions in milliseconds.
.EXAMPLE
    .\FlaUIBot.ps1 -TestMode Quick
.EXAMPLE
    .\FlaUIBot.ps1 -TestMode Full -KeepOpen
#>
param(
    [ValidateSet('Quick', 'Standard', 'Full')]
    [string]$TestMode = 'Standard',
    [switch]$KeepOpen,
    [int]$DelayMs = 500,
    [int]$StartupTimeoutSec = 240  # Dashboard can take 2-3 minutes to load
)

$ErrorActionPreference = 'Continue'
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Window = $null
$script:Process = $null

#region UIAutomation Helpers
try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
} catch {
    Write-Host "[FATAL] Failed to load UIAutomation assemblies: $_" -ForegroundColor Red
    exit 1
}

function Get-MainWindow {
    param(
        [string]$Title = "GA-AppLocker Dashboard",
        [int]$TimeoutSec = 240
    )
    
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Title)
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastProgress = 0
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
        if ($window) { return $window }
        
        # Show progress every 30 seconds
        $elapsed = [int]$stopwatch.Elapsed.TotalSeconds
        if ($elapsed -ge ($lastProgress + 30)) {
            Write-Host "  Still waiting... ($elapsed s elapsed)" -ForegroundColor Gray
            $lastProgress = $elapsed
        }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Find-Element {
    param(
        $Parent,
        [string]$Name,
        [string]$AutomationId,
        [System.Windows.Automation.TreeScope]$Scope = [System.Windows.Automation.TreeScope]::Descendants
    )
    
    if (-not $Parent) { return $null }
    
    $condition = $null
    if ($Name) {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    } elseif ($AutomationId) {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
    }
    
    if ($condition) {
        return $Parent.FindFirst($Scope, $condition)
    }
    return $null
}

function Find-AllElements {
    param(
        $Parent,
        [string]$ControlType
    )
    
    if (-not $Parent) { return @() }
    
    $typeId = switch ($ControlType) {
        'Button' { [System.Windows.Automation.ControlType]::Button }
        'TextBox' { [System.Windows.Automation.ControlType]::Edit }
        'ComboBox' { [System.Windows.Automation.ControlType]::ComboBox }
        'DataGrid' { [System.Windows.Automation.ControlType]::DataGrid }
        'CheckBox' { [System.Windows.Automation.ControlType]::CheckBox }
        default { $null }
    }
    
    if ($typeId) {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $typeId)
        return $Parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    }
    return @()
}

function Invoke-Button {
    param(
        $Parent,
        [string]$Name,
        [string]$AutomationId
    )
    
    $button = Find-Element -Parent $Parent -Name $Name -AutomationId $AutomationId
    if ($button) {
        try {
            $invokePattern = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $invokePattern.Invoke()
            return $true
        } catch {
            # Pattern not supported, try alternative
            return $false
        }
    }
    return $false
}

function Get-ElementText {
    param($Element)
    
    if (-not $Element) { return $null }
    
    try {
        $valuePattern = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        return $valuePattern.Current.Value
    } catch {
        try {
            return $Element.Current.Name
        } catch {
            return $null
        }
    }
}

function Set-ElementText {
    param(
        $Parent,
        [string]$AutomationId,
        [string]$Name,
        [string]$Text
    )
    
    $element = Find-Element -Parent $Parent -AutomationId $AutomationId -Name $Name
    if ($element) {
        try {
            $valuePattern = $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            $valuePattern.SetValue($Text)
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

function Write-TestResult {
    param(
        [string]$Test,
        [bool]$Passed,
        [string]$Details = ''
    )
    if ($Passed) {
        $script:Passed++
        Write-Host "[PASS] " -ForegroundColor Green -NoNewline
    } else {
        $script:Failed++
        Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
    }
    Write-Host "$Test" -NoNewline
    if ($Details) { Write-Host " - $Details" -ForegroundColor Gray }
    else { Write-Host "" }
}

function Write-Skip {
    param([string]$Test, [string]$Reason)
    $script:Skipped++
    Write-Host "[SKIP] $Test - $Reason" -ForegroundColor Yellow
}
#endregion

#region Test Execution
Write-Host "`n=== GA-AppLocker UI Automation Bot ===" -ForegroundColor Cyan
Write-Host "Mode: $TestMode | Delay: ${DelayMs}ms | KeepOpen: $KeepOpen" -ForegroundColor Yellow
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Find and launch Dashboard
$dashboardPath = Join-Path $PSScriptRoot "..\..\..\Run-Dashboard.ps1"
if (-not (Test-Path $dashboardPath)) {
    # Try alternate path
    $dashboardPath = Join-Path $PSScriptRoot "..\..\..\..\Run-Dashboard.ps1"
}

if (-not (Test-Path $dashboardPath)) {
    Write-Host "[FATAL] Dashboard not found. Searched:" -ForegroundColor Red
    Write-Host "  $dashboardPath" -ForegroundColor Gray
    exit 1
}

Write-Host "`nLaunching GA-AppLocker Dashboard..." -ForegroundColor Yellow
Write-Host "  Path: $dashboardPath" -ForegroundColor Gray

try {
    $script:Process = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardPath`"" -PassThru
    Write-Host "  Process ID: $($script:Process.Id)" -ForegroundColor Gray
} catch {
    Write-Host "[FATAL] Failed to launch dashboard: $_" -ForegroundColor Red
    exit 1
}

# Wait for window (dashboard can take 2-3 minutes to load)
Write-Host "Waiting for window (timeout: ${StartupTimeoutSec}s - dashboard loads slowly)..." -ForegroundColor Gray
$script:Window = Get-MainWindow -TimeoutSec $StartupTimeoutSec

if (-not $script:Window) {
    Write-Host "[FATAL] Dashboard window not found after 30 seconds" -ForegroundColor Red
    if ($script:Process -and -not $script:Process.HasExited) {
        $script:Process | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

Write-Host "[OK] Dashboard window found`n" -ForegroundColor Green
Start-Sleep -Milliseconds 1000
#endregion

#region Navigation Tests
Write-Host "=== NAVIGATION TESTS ===" -ForegroundColor Magenta

$navButtons = @(
    @{ Name = "Dashboard"; AutomationName = "Dashboard" }
    @{ Name = "AD Discovery"; AutomationName = "AD Discovery" }
    @{ Name = "Artifact Scanner"; AutomationName = "Artifact Scanner" }
    @{ Name = "Rule Generator"; AutomationName = "Rule Generator" }
    @{ Name = "Policy Builder"; AutomationName = "Policy Builder" }
    @{ Name = "Deployment"; AutomationName = "Deployment" }
    @{ Name = "Settings"; AutomationName = "Settings" }
    @{ Name = "Setup"; AutomationName = "Setup" }
    @{ Name = "About"; AutomationName = "About" }
)

foreach ($nav in $navButtons) {
    $result = Invoke-Button -Parent $script:Window -Name $nav.AutomationName
    Write-TestResult "Navigate: $($nav.Name)" $result
    Start-Sleep -Milliseconds $DelayMs
}

# Return to Dashboard
Invoke-Button -Parent $script:Window -Name "Dashboard" | Out-Null
Start-Sleep -Milliseconds $DelayMs
#endregion

#region Standard Mode Tests
if ($TestMode -in @('Standard', 'Full')) {
    Write-Host "`n=== PANEL INTERACTION TESTS ===" -ForegroundColor Magenta
    
    #--- Discovery Panel ---
    Write-Host "`n--- Discovery Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "AD Discovery" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    # Look for common buttons
    $refreshBtn = Find-Element -Parent $script:Window -Name "Refresh"
    $connectBtn = Find-Element -Parent $script:Window -Name "Connect"
    
    if ($refreshBtn) {
        $result = Invoke-Button -Parent $script:Window -Name "Refresh"
        Write-TestResult "Discovery: Refresh Button" $result
    } elseif ($connectBtn) {
        Write-TestResult "Discovery: Connect Button Found" $true
    } else {
        Write-Skip "Discovery: Refresh/Connect" "Buttons not found"
    }
    Start-Sleep -Milliseconds $DelayMs
    
    #--- Scanner Panel ---
    Write-Host "`n--- Scanner Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "Artifact Scanner" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    # Look for scan buttons
    $scanLocalBtn = Find-Element -Parent $script:Window -Name "Scan Local"
    $scanBtn = Find-Element -Parent $script:Window -Name "Scan"
    $startScanBtn = Find-Element -Parent $script:Window -Name "Start Scan"
    
    if ($scanLocalBtn -or $scanBtn -or $startScanBtn) {
        Write-TestResult "Scanner: Scan Button Found" $true
    } else {
        Write-Skip "Scanner: Scan Button" "Not found"
    }
    
    # Check for DataGrid
    $dataGrids = Find-AllElements -Parent $script:Window -ControlType 'DataGrid'
    Write-TestResult "Scanner: DataGrid Present" ($dataGrids.Count -gt 0) "Found $($dataGrids.Count) DataGrid(s)"
    Start-Sleep -Milliseconds $DelayMs
    
    #--- Rules Panel ---
    Write-Host "`n--- Rules Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "Rule Generator" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    # Look for rule action buttons
    $approveBtn = Find-Element -Parent $script:Window -Name "Approve"
    $rejectBtn = Find-Element -Parent $script:Window -Name "Reject"
    $generateBtn = Find-Element -Parent $script:Window -Name "Generate"
    
    if ($approveBtn -or $rejectBtn -or $generateBtn) {
        Write-TestResult "Rules: Action Buttons Found" $true
    } else {
        Write-Skip "Rules: Action Buttons" "Not found"
    }
    Start-Sleep -Milliseconds $DelayMs
    
    #--- Policy Panel ---
    Write-Host "`n--- Policy Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "Policy Builder" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    # Look for policy buttons
    $newPolicyBtn = Find-Element -Parent $script:Window -Name "New Policy"
    $newBtn = Find-Element -Parent $script:Window -Name "New"
    $exportBtn = Find-Element -Parent $script:Window -Name "Export"
    
    if ($newPolicyBtn -or $newBtn) {
        Write-TestResult "Policy: New Policy Button Found" $true
    } else {
        Write-Skip "Policy: New Policy Button" "Not found"
    }
    
    if ($exportBtn) {
        Write-TestResult "Policy: Export Button Found" $true
    }
    Start-Sleep -Milliseconds $DelayMs
    
    #--- Deployment Panel ---
    Write-Host "`n--- Deployment Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "Deployment" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    $deployBtn = Find-Element -Parent $script:Window -Name "Deploy"
    $startDeployBtn = Find-Element -Parent $script:Window -Name "Start Deployment"
    
    if ($deployBtn -or $startDeployBtn) {
        Write-TestResult "Deployment: Deploy Button Found" $true
    } else {
        Write-Skip "Deployment: Deploy Button" "Not found"
    }
    Start-Sleep -Milliseconds $DelayMs
    
    #--- Settings Panel ---
    Write-Host "`n--- Settings Panel ---" -ForegroundColor Yellow
    Invoke-Button -Parent $script:Window -Name "Settings" | Out-Null
    Start-Sleep -Milliseconds ($DelayMs * 2)
    
    # Check for textboxes (settings inputs)
    $textBoxes = Find-AllElements -Parent $script:Window -ControlType 'TextBox'
    Write-TestResult "Settings: Input Fields Present" ($textBoxes.Count -gt 0) "Found $($textBoxes.Count) TextBox(es)"
    
    $saveBtn = Find-Element -Parent $script:Window -Name "Save"
    if ($saveBtn) {
        Write-TestResult "Settings: Save Button Found" $true
    }
    Start-Sleep -Milliseconds $DelayMs
}
#endregion

#region Full Mode Tests
if ($TestMode -eq 'Full') {
    Write-Host "`n=== WORKFLOW SIMULATION ===" -ForegroundColor Magenta
    Write-Host "Simulating end-to-end workflow navigation..." -ForegroundColor Yellow
    
    # Simulate workflow: Discovery -> Scanner -> Rules -> Policy -> Deployment -> Dashboard
    $workflowSteps = @(
        "AD Discovery",
        "Artifact Scanner",
        "Rule Generator",
        "Policy Builder",
        "Deployment",
        "Dashboard"
    )
    
    $workflowSuccess = $true
    foreach ($step in $workflowSteps) {
        $result = Invoke-Button -Parent $script:Window -Name $step
        if (-not $result) {
            $workflowSuccess = $false
            Write-Host "  [!] Failed to navigate to: $step" -ForegroundColor Red
        } else {
            Write-Host "  [>] $step" -ForegroundColor Gray
        }
        Start-Sleep -Milliseconds ($DelayMs * 2)
    }
    
    Write-TestResult "Workflow: Full Navigation Cycle" $workflowSuccess
    
    # Test sidebar collapse (if available)
    Write-Host "`nTesting sidebar collapse..." -ForegroundColor Yellow
    $collapseBtn = Find-Element -Parent $script:Window -Name "<<"
    if ($collapseBtn) {
        $result = Invoke-Button -Parent $script:Window -Name "<<"
        Write-TestResult "Sidebar: Collapse Toggle" $result
        Start-Sleep -Milliseconds $DelayMs
        
        # Toggle back
        $expandBtn = Find-Element -Parent $script:Window -Name ">>"
        if ($expandBtn) {
            Invoke-Button -Parent $script:Window -Name ">>" | Out-Null
        }
    } else {
        Write-Skip "Sidebar: Collapse Toggle" "Button not found"
    }
}
#endregion

#region Cleanup & Summary
Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""
Write-Host "Results:" -ForegroundColor White
Write-Host "  Passed:  $script:Passed" -ForegroundColor Green
Write-Host "  Failed:  $script:Failed" -ForegroundColor $(if($script:Failed -gt 0){'Red'}else{'Gray'})
Write-Host "  Skipped: $script:Skipped" -ForegroundColor Yellow
Write-Host ""

$total = $script:Passed + $script:Failed
$passRate = if ($total -gt 0) { [math]::Round(($script:Passed / $total) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if($passRate -ge 80){'Green'}elseif($passRate -ge 50){'Yellow'}else{'Red'})

if (-not $KeepOpen) {
    if ($script:Process -and -not $script:Process.HasExited) {
        Write-Host "`nClosing dashboard..." -ForegroundColor Gray
        $script:Process | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Dashboard closed" -ForegroundColor Green
    }
} else {
    Write-Host "`nDashboard left open (PID: $($script:Process.Id))" -ForegroundColor Yellow
}

Write-Host ""
$exitCode = if ($script:Failed -gt 0) { 1 } else { 0 }
exit $exitCode
#endregion
