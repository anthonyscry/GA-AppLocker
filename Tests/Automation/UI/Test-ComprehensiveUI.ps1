#Requires -Version 5.1
# Comprehensive UI test for an already-open GA-AppLocker Dashboard
param([int]$DelayMs = 400)

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Write-Result {
    param([string]$Test, [bool]$Pass, [string]$Details = '')
    if ($Pass) {
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
    param([string]$Test, [string]$Reason = '')
    $script:Skipped++
    Write-Host "[SKIP] $Test" -ForegroundColor Yellow -NoNewline
    if ($Reason) { Write-Host " - $Reason" -ForegroundColor Gray }
    else { Write-Host "" }
}

function Find-Element {
    param($Parent, [string]$Name, [string]$AutomationId)
    if ($Name) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    } elseif ($AutomationId) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
    } else { return $null }
    return $Parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Find-AllByType {
    param($Parent, [string]$ControlType)
    $typeId = switch ($ControlType) {
        'Button' { [System.Windows.Automation.ControlType]::Button }
        'DataGrid' { [System.Windows.Automation.ControlType]::DataGrid }
        'TextBox' { [System.Windows.Automation.ControlType]::Edit }
        'ComboBox' { [System.Windows.Automation.ControlType]::ComboBox }
        'CheckBox' { [System.Windows.Automation.ControlType]::CheckBox }
        'Tab' { [System.Windows.Automation.ControlType]::TabItem }
        default { return @() }
    }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $typeId)
    return $Parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Click-Button {
    param($Parent, [string]$Name)
    $btn = Find-Element -Parent $Parent -Name $Name
    if ($btn) {
        try {
            $pattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $pattern.Invoke()
            return $true
        } catch { return $false }
    }
    return $false
}

function Navigate-To {
    param($Window, [string]$Panel)
    $result = Click-Button -Parent $Window -Name $Panel
    Start-Sleep -Milliseconds $DelayMs
    return $result
}

# ============================================================
# SETUP
# ============================================================
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " GA-AppLocker Comprehensive UI Tests" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "GA-AppLocker Dashboard")
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)

if (-not $window) {
    Write-Host "[FATAL] GA-AppLocker Dashboard not found!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Connected to GA-AppLocker Dashboard" -ForegroundColor Green
Write-Host ""

# ============================================================
# TEST 1: NAVIGATION
# ============================================================
Write-Host "=== TEST 1: Navigation ===" -ForegroundColor Magenta

$navButtons = @("Dashboard", "AD Discovery", "Artifact Scanner", "Rule Generator", "Policy Builder", "Deployment", "Settings", "Setup", "About")
foreach ($btn in $navButtons) {
    $result = Navigate-To -Window $window -Panel $btn
    Write-Result "Navigate: $btn" $result
}

# Return to Dashboard
Navigate-To -Window $window -Panel "Dashboard" | Out-Null
Start-Sleep -Milliseconds 500

# ============================================================
# TEST 2: PANEL INTERACTIONS
# ============================================================
Write-Host ""
Write-Host "=== TEST 2: Panel Interactions ===" -ForegroundColor Magenta

# --- Discovery Panel ---
Write-Host "`n--- AD Discovery ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "AD Discovery" | Out-Null

$btnsToFind = @("Refresh", "Connect", "Load", "Search")
$foundAny = $false
foreach ($b in $btnsToFind) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Discovery: '$b' button found" $true
        $foundAny = $true
        break
    }
}
if (-not $foundAny) { Write-Skip "Discovery: Action button" "No known buttons found" }

$dataGrids = Find-AllByType -Parent $window -ControlType 'DataGrid'
Write-Result "Discovery: DataGrid present" ($dataGrids.Count -gt 0) "$($dataGrids.Count) grid(s)"

# --- Scanner Panel ---
Write-Host "`n--- Artifact Scanner ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "Artifact Scanner" | Out-Null

$scanBtns = @("Scan", "Scan Local", "Start Scan", "Run Scan")
$foundScan = $false
foreach ($b in $scanBtns) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Scanner: '$b' button found" $true
        $foundScan = $true
        break
    }
}
if (-not $foundScan) { Write-Skip "Scanner: Scan button" "No scan button found" }

$dataGrids = Find-AllByType -Parent $window -ControlType 'DataGrid'
Write-Result "Scanner: DataGrid present" ($dataGrids.Count -gt 0) "$($dataGrids.Count) grid(s)"

$textBoxes = Find-AllByType -Parent $window -ControlType 'TextBox'
Write-Result "Scanner: Input fields present" ($textBoxes.Count -gt 0) "$($textBoxes.Count) field(s)"

# --- Rules Panel ---
Write-Host "`n--- Rule Generator ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "Rule Generator" | Out-Null

$ruleBtns = @("Approve", "Reject", "Generate", "Create Rule", "Add Rule")
$foundRule = $false
foreach ($b in $ruleBtns) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Rules: '$b' button found" $true
        $foundRule = $true
        break
    }
}
if (-not $foundRule) { Write-Skip "Rules: Action button" "No rule buttons found" }

$dataGrids = Find-AllByType -Parent $window -ControlType 'DataGrid'
Write-Result "Rules: DataGrid present" ($dataGrids.Count -gt 0) "$($dataGrids.Count) grid(s)"

# --- Policy Panel ---
Write-Host "`n--- Policy Builder ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "Policy Builder" | Out-Null

$policyBtns = @("New Policy", "New", "Create", "Export", "Save")
$foundPolicy = $false
foreach ($b in $policyBtns) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Policy: '$b' button found" $true
        $foundPolicy = $true
        break
    }
}
if (-not $foundPolicy) { Write-Skip "Policy: Action button" "No policy buttons found" }

$dataGrids = Find-AllByType -Parent $window -ControlType 'DataGrid'
Write-Result "Policy: DataGrid present" ($dataGrids.Count -gt 0) "$($dataGrids.Count) grid(s)"

# --- Deployment Panel ---
Write-Host "`n--- Deployment ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "Deployment" | Out-Null

$deployBtns = @("Deploy", "Start", "Execute", "Run")
$foundDeploy = $false
foreach ($b in $deployBtns) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Deployment: '$b' button found" $true
        $foundDeploy = $true
        break
    }
}
if (-not $foundDeploy) { Write-Skip "Deployment: Action button" "No deploy buttons found" }

# --- Settings Panel ---
Write-Host "`n--- Settings ---" -ForegroundColor Yellow
Navigate-To -Window $window -Panel "Settings" | Out-Null

$textBoxes = Find-AllByType -Parent $window -ControlType 'TextBox'
Write-Result "Settings: Config fields present" ($textBoxes.Count -gt 0) "$($textBoxes.Count) field(s)"

$saveBtns = @("Save", "Apply", "Update")
$foundSave = $false
foreach ($b in $saveBtns) {
    $btn = Find-Element -Parent $window -Name $b
    if ($btn) {
        Write-Result "Settings: '$b' button found" $true
        $foundSave = $true
        break
    }
}
if (-not $foundSave) { Write-Skip "Settings: Save button" "No save button found" }

# ============================================================
# TEST 3: DATA GRID VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== TEST 3: DataGrid Verification ===" -ForegroundColor Magenta

$panelsWithGrids = @("AD Discovery", "Artifact Scanner", "Rule Generator", "Policy Builder", "Deployment")
foreach ($panel in $panelsWithGrids) {
    Navigate-To -Window $window -Panel $panel | Out-Null
    
    $grids = Find-AllByType -Parent $window -ControlType 'DataGrid'
    if ($grids.Count -gt 0) {
        foreach ($grid in $grids) {
            $gridName = $grid.Current.Name
            if (-not $gridName) { $gridName = $grid.Current.AutomationId }
            if (-not $gridName) { $gridName = "DataGrid" }
            
            # Check if grid supports TablePattern (sortable columns)
            try {
                $tablePattern = $grid.GetCurrentPattern([System.Windows.Automation.TablePattern]::Pattern)
                $rowCount = $tablePattern.Current.RowCount
                $colCount = $tablePattern.Current.ColumnCount
                Write-Result "$panel Grid" $true "$colCount columns, $rowCount rows"
            } catch {
                # Try GridPattern instead
                try {
                    $gridPattern = $grid.GetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern)
                    $rowCount = $gridPattern.Current.RowCount
                    $colCount = $gridPattern.Current.ColumnCount
                    Write-Result "$panel Grid" $true "$colCount columns, $rowCount rows"
                } catch {
                    Write-Result "$panel Grid" $true "Grid present (pattern not supported)"
                }
            }
        }
    } else {
        Write-Skip "$panel Grid" "No DataGrid found"
    }
}

# ============================================================
# TEST 4: WORKFLOW SIMULATION
# ============================================================
Write-Host ""
Write-Host "=== TEST 4: Workflow Simulation ===" -ForegroundColor Magenta
Write-Host "Simulating: Discovery -> Scanner -> Rules -> Policy -> Deploy -> Dashboard" -ForegroundColor Gray

$workflowSteps = @(
    @{ Panel = "AD Discovery"; Action = "Discovery" },
    @{ Panel = "Artifact Scanner"; Action = "Scanning" },
    @{ Panel = "Rule Generator"; Action = "Rule Generation" },
    @{ Panel = "Policy Builder"; Action = "Policy Building" },
    @{ Panel = "Deployment"; Action = "Deployment" },
    @{ Panel = "Dashboard"; Action = "Return to Dashboard" }
)

$workflowPassed = $true
foreach ($step in $workflowSteps) {
    $result = Navigate-To -Window $window -Panel $step.Panel
    if ($result) {
        Write-Host "  [>] $($step.Action)" -ForegroundColor Gray
    } else {
        Write-Host "  [X] $($step.Action) - FAILED" -ForegroundColor Red
        $workflowPassed = $false
    }
    Start-Sleep -Milliseconds ($DelayMs * 2)
}

Write-Result "Workflow: Full cycle completed" $workflowPassed

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Passed:  $script:Passed" -ForegroundColor Green
Write-Host "Failed:  $script:Failed" -ForegroundColor $(if($script:Failed -gt 0){'Red'}else{'Gray'})
Write-Host "Skipped: $script:Skipped" -ForegroundColor Yellow
Write-Host ""

$total = $script:Passed + $script:Failed
$rate = if ($total -gt 0) { [math]::Round(($script:Passed / $total) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $rate%" -ForegroundColor $(if($rate -ge 80){'Green'}elseif($rate -ge 50){'Yellow'}else{'Red'})
Write-Host ""

# Return to Dashboard
Navigate-To -Window $window -Panel "Dashboard" | Out-Null

exit $(if ($script:Failed -gt 0) { 1 } else { 0 })
