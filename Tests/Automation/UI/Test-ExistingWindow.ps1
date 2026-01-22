#Requires -Version 5.1
# Quick test script for an already-open GA-AppLocker Dashboard
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

# Find the dashboard window
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "GA-AppLocker Dashboard")
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)

if (-not $window) {
    Write-Host "[FAIL] GA-AppLocker Dashboard window not found" -ForegroundColor Red
    Write-Host "Make sure the dashboard is open first." -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Found GA-AppLocker Dashboard" -ForegroundColor Green
Write-Host ""

# Test navigation buttons
$navButtons = @("Dashboard", "AD Discovery", "Artifact Scanner", "Rule Generator", "Policy Builder", "Deployment", "Settings", "Setup", "About")
$passed = 0
$failed = 0

Write-Host "=== Navigation Tests ===" -ForegroundColor Cyan
foreach ($btnName in $navButtons) {
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $btnName)
    $btn = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    
    if ($btn) {
        try {
            $invokePattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $invokePattern.Invoke()
            Write-Host "[PASS] $btnName" -ForegroundColor Green
            $passed++
            Start-Sleep -Milliseconds 400
        } catch {
            Write-Host "[FAIL] $btnName - $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "[SKIP] $btnName - Button not found" -ForegroundColor Yellow
    }
}

# Return to Dashboard
Start-Sleep -Milliseconds 500
$dashCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "Dashboard")
$dashBtn = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $dashCond)
if ($dashBtn) {
    $dashBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if($failed -gt 0){'Red'}else{'Gray'})
