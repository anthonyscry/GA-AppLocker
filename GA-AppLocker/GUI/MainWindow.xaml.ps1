<#
.SYNOPSIS
    Code-behind for MainWindow.xaml

.DESCRIPTION
    Handles navigation events and panel switching for the
    GA-AppLocker Dashboard main window.

.NOTES
    This file is loaded by Start-AppLockerDashboard after
    the XAML window is created.
#>

#region ===== DOT-SOURCE PANEL FILES =====
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load helpers first
. "$scriptPath\Helpers\UIHelpers.ps1"
. "$scriptPath\Helpers\AsyncHelpers.ps1"
. "$scriptPath\Helpers\KeyboardShortcuts.ps1"
. "$scriptPath\Helpers\DragDropHelpers.ps1"
. "$scriptPath\Helpers\ThemeManager.ps1"
. "$scriptPath\Helpers\GlobalSearch.ps1"
. "$scriptPath\Helpers\RuleGenerationAsync.ps1"

# Load dialogs
if (Test-Path "$scriptPath\Dialogs") {
    Get-ChildItem -Path "$scriptPath\Dialogs" -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Load wizards
if (Test-Path "$scriptPath\Wizards\SetupWizard.ps1") {
    . "$scriptPath\Wizards\SetupWizard.ps1"
}
if (Test-Path "$scriptPath\Wizards\RuleGenerationWizard.ps1") {
    . "$scriptPath\Wizards\RuleGenerationWizard.ps1"
}

# Load panel handlers
. "$scriptPath\Panels\Dashboard.ps1"
. "$scriptPath\Panels\ADDiscovery.ps1"
. "$scriptPath\Panels\Credentials.ps1"
. "$scriptPath\Panels\Scanner.ps1"
. "$scriptPath\Panels\Rules.ps1"
. "$scriptPath\Panels\Policy.ps1"
. "$scriptPath\Panels\Deploy.ps1"
. "$scriptPath\Panels\Software.ps1"
. "$scriptPath\Panels\Setup.ps1"
#endregion

#region ===== SAFE LOGGING WRAPPER =====
# Wrapper to safely call module functions from code-behind scope
function global:Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== LOADING OVERLAY HELPERS =====
# NOTE: Show-LoadingOverlay, Hide-LoadingOverlay, Update-LoadingText
# are defined in UIHelpers.ps1 (dot-sourced above) with global: scope
# so timer callbacks and closures can access them.
#endregion

#region ===== BUTTON ACTION DISPATCHER =====
# Central dispatcher for button clicks - avoids closure scope issues
# Using global scope so WPF event scriptblocks can access it
function global:Invoke-ButtonAction {
    param([string]$Action)

    $win = $global:GA_MainWindow
    if (-not $win) { return }

    switch ($Action) {
        # Navigation
        'NavDashboard' { Set-ActivePanel -PanelName 'PanelDashboard' }
        'NavDiscovery' { Set-ActivePanel -PanelName 'PanelDiscovery' }
        'NavScanner' { Set-ActivePanel -PanelName 'PanelScanner' }
        'NavRules' { Set-ActivePanel -PanelName 'PanelRules' }
        'NavPolicy' { Set-ActivePanel -PanelName 'PanelPolicy' }
        'NavDeploy' { Set-ActivePanel -PanelName 'PanelDeploy' }
        'NavSoftware' { Set-ActivePanel -PanelName 'PanelSoftware' }
        'NavSettings' { Set-ActivePanel -PanelName 'PanelSettings' }
        'NavSetup' { Set-ActivePanel -PanelName 'PanelSetup' }
        'NavAbout' { Set-ActivePanel -PanelName 'PanelAbout' }
        # Discovery panel
        'RefreshDomain' { Invoke-DomainRefresh -Window $win -Async }
        'TestConnectivity' { Invoke-ConnectivityTest -Window $win -Async }
        # Credentials panel
        'SaveCredential' { Invoke-SaveCredential -Window $win }
        'RefreshCredentials' { Update-CredentialsDataGrid -Window $win }
        'TestCredential' { Invoke-TestSelectedCredential -Window $win }
        'DeleteCredential' { Invoke-DeleteSelectedCredential -Window $win }
        'SetDefaultCredential' { Invoke-SetDefaultCredential -Window $win }
        # Scanner panel
        'StartScan' { Invoke-StartArtifactScan -Window $win }
        'StopScan' { Invoke-StopArtifactScan -Window $win }
        'ImportArtifacts' { Invoke-ImportArtifacts -Window $win }
        'ExportArtifacts' { Invoke-ExportArtifacts -Window $win }
        'RefreshScans' { Update-SavedScansList -Window $win }
        'LoadScan' { Invoke-LoadSelectedScan -Window $win }
        'DeleteScan' { Invoke-DeleteSelectedScan -Window $win }
        'SelectMachines' { Invoke-SelectMachinesForScan -Window $win }
        'FilterArtifacts' { Update-ArtifactFilter -Window $win -Filter $args[0] }
        'DedupeArtifacts' { Invoke-DedupeArtifacts -Window $win }
        'ApplyExclusions' { Invoke-ApplyArtifactExclusions -Window $win }
        # Scheduled Scans
        'CreateScheduledScan' { Invoke-CreateScheduledScan -Window $win }
        'RunScheduledScanNow' { Invoke-RunScheduledScanNow -Window $win }
        'DeleteScheduledScan' { Invoke-DeleteScheduledScan -Window $win }
        # Rules panel
        'LaunchRuleWizard' { Invoke-LaunchRuleWizard -Window $win }
        'GenerateFromArtifacts' { Invoke-LaunchRuleWizard -Window $win }  # Legacy - redirects to wizard
        'CreateManualRule' { Invoke-CreateManualRule -Window $win }
        'ExportRulesXml' { Invoke-ExportRulesToXml -Window $win }
        'ExportRulesCsv' { Invoke-ExportRulesToCsv -Window $win }
        'ImportRulesXml' { Invoke-ImportRulesFromXmlFile -Window $win }
        'RefreshRules' { Update-RulesDataGrid -Window $win -Async }
        'SelectAllRules' { Invoke-SelectAllRules -Window $win }
        'ApproveRule' { Set-SelectedRuleStatus -Window $win -Status 'Approved' }
        'RejectRule' { Set-SelectedRuleStatus -Window $win -Status 'Rejected' }
        'ReviewRule' { Set-SelectedRuleStatus -Window $win -Status 'Review' }
        'DeleteRule' { Invoke-DeleteSelectedRules -Window $win }
        'AddRuleToPolicy' { Invoke-AddSelectedRulesToPolicy -Window $win }
        'ViewRuleDetails' { Show-RuleDetails -Window $win }
        'ViewRuleHistory' { Invoke-ViewRuleHistory -Window $win }
        # Policy panel
        'CreatePolicy' { Invoke-CreatePolicy -Window $win }
        'RefreshPolicies' { Update-PoliciesDataGrid -Window $win -Async }
        'ActivatePolicy' { Set-SelectedPolicyStatus -Window $win -Status 'Active' }
        'ArchivePolicy' { Set-SelectedPolicyStatus -Window $win -Status 'Archived' }
        'DeletePolicy' { Invoke-DeleteSelectedPolicy -Window $win }
        'ExportPolicy' { Invoke-ExportSelectedPolicy -Window $win }
        'DeployPolicy' { Invoke-DeploySelectedPolicy -Window $win }
        'AddRulesToPolicy' { Invoke-AddRulesToPolicy -Window $win }
        'RemoveRulesFromPolicy' { Invoke-RemoveRulesFromPolicy -Window $win }
        'SavePolicyChanges' { Invoke-SavePolicyChanges -Window $win }
        'ComparePolicies' { Invoke-ComparePolicies -Window $win }
        'ExportDiffReport' { Invoke-ExportDiffReport -Window $win }
        # Deployment panel
        'CreateDeploymentJob' { Invoke-CreateDeploymentJob -Window $win }
        'RefreshDeployments' { Update-DeploymentJobsDataGrid -Window $win -Async }
        'DeploySelectedJob' { Invoke-DeploySelectedJob -Window $win }
        'StopDeployment' { Invoke-StopDeployment -Window $win }
        'CancelDeploymentJob' { Invoke-CancelDeploymentJob -Window $win }
        'ViewDeploymentLog' { Show-DeploymentLog -Window $win }
        # Software Inventory panel
        'ScanLocalSoftware' { Invoke-ScanLocalSoftware -Window $win }
        'ScanRemoteSoftware' { Invoke-ScanRemoteSoftware -Window $win }
        'ExportSoftwareCsv' { Invoke-ExportSoftwareCsv -Window $win }
        'ImportSoftwareCsv' { Invoke-ImportSoftwareCsv -Window $win }
        'CompareSoftware' { Invoke-CompareSoftware -Window $win }
        'ClearSoftwareComparison' { Invoke-ClearSoftwareComparison -Window $win }
        # Setup panel (Settings > Setup tab)
        'InitializeWinRM' { Invoke-InitializeWinRM -Window $win }
        'ToggleWinRM' { Invoke-ToggleWinRM -Window $win }
        'RemoveWinRM' { Invoke-RemoveWinRMGPO -Window $win }
        'InitializeAppLockerGPOs' { Invoke-InitializeAppLockerGPOs -Window $win }
        'InitializeADStructure' { Invoke-InitializeADStructure -Window $win }
        'InitializeAll' { Invoke-InitializeAll -Window $win }
        # Rules panel - Common Deny Rules
        'AddCommonDenyRules' { Invoke-AddCommonDenyRules -Window $win }
        'ChangeRuleAction' { Invoke-ChangeSelectedRulesAction -Window $win }
        'ChangeRuleGroup' { Invoke-ChangeSelectedRulesGroup -Window $win }
        # Dashboard Quick Actions
        'ApproveTrustedVendors' { Invoke-ApproveTrustedVendors -Window $win }
        'RemoveDuplicateRules' { Invoke-RemoveDuplicateRules -Window $win }
        # Settings panel
        'ToggleTheme' { Toggle-Theme -Window $win }
        # Default case for unknown actions
        default {
            if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
                Write-AppLockerLog -Message "Unknown button action: $Action" -Level 'WARNING'
            }
        }
    }
}
#endregion

#region ===== SCRIPT-LEVEL VARIABLES =====
# Store window reference for event handlers
$global:GA_MainWindow = $null
$script:DiscoveredOUs = @()
$script:DiscoveredMachines = @()
$script:SelectedScanMachines = @()
$script:CurrentScanArtifacts = @()
$script:CurrentArtifactFilter = 'All'
$script:ScanInProgress = $false
$script:CurrentRulesFilter = 'All'
$script:CurrentRulesTypeFilter = 'All'
$script:CurrentPoliciesFilter = 'All'
$script:SelectedPolicyId = $null
$script:CurrentDeploymentFilter = 'All'
$script:SelectedDeploymentJobId = $null
# Deployment async state
$script:DeploymentInProgress = $false
$script:DeploymentCancelled = $false
$script:DeploySyncHash = $null
$script:DeployRunspace = $null
$script:DeployPowerShell = $null
$script:DeployAsyncResult = $null
$script:DeployTimer = $null
# Track current panel for session state
$script:CurrentActivePanel = 'PanelDashboard'
$script:SidebarCollapsed = $false
#endregion

#region ===== NAVIGATION HANDLERS =====
# Panel visibility management (global for event handler access)
function global:Set-ActivePanel {
    param([string]$PanelName)

    # Try script scope first, fall back to global
    $Window = $global:GA_MainWindow
    if (-not $Window) { $Window = $global:GA_MainWindow }
    if (-not $Window) { return }

    # All panel names
    $panels = @(
        'PanelDashboard',
        'PanelDiscovery',
        'PanelScanner',
        'PanelRules',
        'PanelPolicy',
        'PanelDeploy',
        'PanelSoftware',
        'PanelSettings',
        'PanelSetup',
        'PanelAbout'
    )

    # Nav button names mapped to panels
    $navMap = @{
        'NavDashboard' = 'PanelDashboard'
        'NavDiscovery' = 'PanelDiscovery'
        'NavScanner'   = 'PanelScanner'
        'NavRules'     = 'PanelRules'
        'NavPolicy'    = 'PanelPolicy'
        'NavDeploy'    = 'PanelDeploy'
        'NavSoftware'  = 'PanelSoftware'
        'NavSettings'  = 'PanelSettings'
        'NavSetup'     = 'PanelSetup'
        'NavAbout'     = 'PanelAbout'
    }

    # Hide all panels
    foreach ($panel in $panels) {
        $element = $Window.FindName($panel)
        if ($element) {
            $element.Visibility = 'Collapsed'
        }
    }

    # Show selected panel
    $targetPanel = $Window.FindName($PanelName)
    if ($targetPanel) {
        $targetPanel.Visibility = 'Visible'
    }
    
    # Track current panel for session state
    $script:CurrentActivePanel = $PanelName

    # Update nav button states
    foreach ($navName in $navMap.Keys) {
        $navButton = $Window.FindName($navName)
        if ($navButton) {
            if ($navMap[$navName] -eq $PanelName) {
                $navButton.Tag = 'Active'
            }
            else {
                $navButton.Tag = $null
            }
        }
    }

    # Log navigation
    Write-Log -Message "Navigated to: $PanelName"
    
    # Auto-refresh AD Discovery on first navigation (don't make user click Refresh manually)
    if ($PanelName -eq 'PanelDiscovery' -and $script:DiscoveredMachines.Count -eq 0) {
        Write-Log -Message 'Auto-triggering domain refresh on first Discovery panel visit'
        Invoke-DomainRefresh -Window $Window
    }
    
    # Auto-save session state on panel change
    Save-CurrentSessionState
}
#endregion

#region ===== SESSION STATE MANAGEMENT =====

function script:Save-CurrentSessionState {
    # Build current state from script variables
    $state = @{
        activePanel = $script:CurrentActivePanel
        discovery = @{
            discoveredMachines = @($script:DiscoveredMachines | ForEach-Object { 
                if ($_ -is [string]) { $_ } else { $_.Hostname } 
            })
            selectedForScan = @($script:SelectedScanMachines | ForEach-Object { 
                if ($_ -is [string]) { $_ } else { $_.Hostname } 
            })
        }
        scanner = @{
            artifactCount = $script:CurrentScanArtifacts.Count
        }
        rules = @{
            filter = $script:CurrentRulesFilter
            typeFilter = $script:CurrentRulesTypeFilter
        }
        policy = @{
            selectedPolicyId = $script:SelectedPolicyId
        }
        deployment = @{
            selectedJobId = $script:SelectedDeploymentJobId
        }
    }
    
    # Save asynchronously to not block UI
    if (Get-Command -Name 'Save-SessionState' -ErrorAction SilentlyContinue) {
        try {
            Save-SessionState -State $state | Out-Null
        }
        catch {
            Write-Log -Level Warning -Message "Failed to save session: $($_.Exception.Message)"
        }
    }
}

function script:Restore-PreviousSessionState {
    param([System.Windows.Window]$Window)
    
    if (-not (Get-Command -Name 'Restore-SessionState' -ErrorAction SilentlyContinue)) {
        return $false
    }
    
    try {
        $result = Restore-SessionState
        
        if (-not $result.Success) {
            Write-Log -Message "No previous session to restore: $($result.Error)"
            return $false
        }
        
        $session = $result.Data
        Write-Log -Message "Restoring previous session..."
        
        # Restore discovery state
        if ($session.discovery) {
            if ($session.discovery.discoveredMachines) {
                # Convert back to objects for the UI
                $script:DiscoveredMachines = @($session.discovery.discoveredMachines | ForEach-Object {
                    [PSCustomObject]@{
                        Hostname = $_
                        StatusIcon = '?'
                        MachineType = 'Unknown'
                        OperatingSystem = ''
                        LastLogon = $null
                        WinRMStatus = 'Unknown'
                    }
                })
            }
            if ($session.discovery.selectedForScan) {
                $script:SelectedScanMachines = @($session.discovery.selectedForScan)
            }
        }
        
        # Restore filter states
        if ($session.rules) {
            if ($session.rules.filter) { $script:CurrentRulesFilter = $session.rules.filter }
            if ($session.rules.typeFilter) { $script:CurrentRulesTypeFilter = $session.rules.typeFilter }
        }
        
        # Restore selections
        if ($session.policy -and $session.policy.selectedPolicyId) {
            $script:SelectedPolicyId = $session.policy.selectedPolicyId
        }
        if ($session.deployment -and $session.deployment.selectedJobId) {
            $script:SelectedDeploymentJobId = $session.deployment.selectedJobId
        }
        
        # Update UI
        Update-WorkflowBreadcrumb -Window $Window
        
        # Navigate to last active panel (if not Dashboard)
        if ($session.activePanel -and $session.activePanel -ne 'PanelDashboard') {
            Set-ActivePanel -PanelName $session.activePanel
        }
        
        Write-Log -Message "Session restored successfully."
        return $true
    }
    catch {
        Write-Log -Level Warning -Message "Failed to restore session: $($_.Exception.Message)"
        return $false
    }
}

function global:Update-WorkflowBreadcrumb {
    param([System.Windows.Window]$Window)
    
    if (-not $Window) { $Window = $global:GA_MainWindow }
    if (-not $Window) { return }
    
    # Get brushes
    $successBrush = $Window.FindResource('SuccessBrush')
    $pendingBrush = $Window.FindResource('PendingBrush')
    $inactiveBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#555555')
    
    # Stage 1: Discovery
    $discoveryStage = $Window.FindName('StageDiscovery')
    $discoveryCount = $Window.FindName('StageDiscoveryCount')
    $machineCount = $script:DiscoveredMachines.Count
    if ($discoveryStage) {
        $discoveryStage.Fill = if ($machineCount -gt 0) { $successBrush } else { $inactiveBrush }
    }
    if ($discoveryCount) {
        $discoveryCount.Text = $machineCount.ToString()
    }
    
    # Stage 2: Scanner
    $scannerStage = $Window.FindName('StageScanner')
    $scannerCount = $Window.FindName('StageScannerCount')
    $artifactCount = $script:CurrentScanArtifacts.Count
    if ($scannerStage) {
        if ($script:ScanInProgress) {
            $scannerStage.Fill = $pendingBrush
        }
        elseif ($artifactCount -gt 0) {
            $scannerStage.Fill = $successBrush
        }
        else {
            $scannerStage.Fill = $inactiveBrush
        }
    }
    if ($scannerCount) {
        $scannerCount.Text = $artifactCount.ToString()
    }
    
    # Stage 3: Rules
    $rulesStage = $Window.FindName('StageRules')
    $rulesCount = $Window.FindName('StageRulesCount')
    $ruleCount = 0
    try {
        # Use -Take 1 to minimize data transfer, rely on Total for actual count
        $rulesResult = Get-AllRules -Take 1
        if ($rulesResult.Success) {
            # Use Total (full count) not Data.Count (paginated)
            $ruleCount = $rulesResult.Total
        }
    } catch { }
    if ($rulesStage) {
        $rulesStage.Fill = if ($ruleCount -gt 0) { $successBrush } else { $inactiveBrush }
    }
    if ($rulesCount) {
        $rulesCount.Text = $ruleCount.ToString()
    }
    
    # Stage 4: Policy
    $policyStage = $Window.FindName('StagePolicy')
    $policyCount = $Window.FindName('StagePolicyCount')
    $polCount = 0
    try {
        $policiesResult = Get-AllPolicies
        if ($policiesResult.Success) {
            $polCount = $policiesResult.Data.Count
        }
    } catch { }
    if ($policyStage) {
        $policyStage.Fill = if ($polCount -gt 0) { $successBrush } else { $inactiveBrush }
    }
    if ($policyCount) {
        $policyCount.Text = $polCount.ToString()
    }
}

#endregion

#region ===== NAVIGATION INITIALIZATION =====
# Wire up navigation event handlers
function Initialize-Navigation {
    param([System.Windows.Window]$Window)

    # Store window reference
    $global:GA_MainWindow = $Window

    # Register each nav button directly - no closures needed
    $btn = $Window.FindName('NavDashboard')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDashboard' }) }

    $btn = $Window.FindName('NavDiscovery')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDiscovery' }) }

    $btn = $Window.FindName('NavScanner')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btn = $Window.FindName('NavRules')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavRules' }) }

    $btn = $Window.FindName('NavPolicy')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavPolicy' }) }

    $btn = $Window.FindName('NavDeploy')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDeploy' }) }

    $btn = $Window.FindName('NavSoftware')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSoftware' }) }

    $btn = $Window.FindName('NavSettings')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSettings' }) }

    $btn = $Window.FindName('NavSetup')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSetup' }) }

    $btn = $Window.FindName('NavAbout')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavAbout' }) }

    # Sidebar collapse/expand toggle button
    $btnCollapse = $Window.FindName('BtnCollapseSidebar')
    if ($btnCollapse) {
        $btnCollapse.Add_Click({
                $win = $global:GA_MainWindow
                $sidebar = $win.FindName('SidebarBorder')
                $parentGrid = $sidebar.Parent
            
                if (-not $script:SidebarCollapsed) {
                    # COLLAPSE
                    $script:SidebarCollapsed = $true
                
                    # Shrink sidebar width
                    if ($parentGrid -and $parentGrid.ColumnDefinitions.Count -gt 0) {
                        $parentGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(60)
                    }
                
                    # Hide text elements, keep icons
                    $win.FindName('SidebarTitle').Visibility = 'Collapsed'
                    $win.FindName('SidebarSubtitle').Visibility = 'Collapsed'
                    $win.FindName('NavDashboardText').Visibility = 'Collapsed'
                    $win.FindName('NavDiscoveryText').Visibility = 'Collapsed'
                    $win.FindName('NavScannerText').Visibility = 'Collapsed'
                    $win.FindName('NavRulesText').Visibility = 'Collapsed'
                    $win.FindName('NavPolicyText').Visibility = 'Collapsed'
                    $win.FindName('NavDeployText').Visibility = 'Collapsed'
                    $win.FindName('NavSoftwareText').Visibility = 'Collapsed'
                    $win.FindName('NavSettingsText').Visibility = 'Collapsed'
                    $win.FindName('NavSetupText').Visibility = 'Collapsed'
                    $win.FindName('NavAboutText').Visibility = 'Collapsed'
                    $win.FindName('SidebarFooter').Visibility = 'Collapsed'
                    $breadcrumb = $win.FindName('WorkflowBreadcrumb')
                    if ($breadcrumb) { $breadcrumb.Visibility = 'Collapsed' }
                    $win.FindName('NavSeparator').Margin = [System.Windows.Thickness]::new(5, 20, 5, 20)
                
                    # Change button to expand icon
                    $btn = $win.FindName('BtnCollapseSidebar')
                    $btn.Content = '>>'
                    $btn.ToolTip = 'Expand Sidebar'
                }
                else {
                    # EXPAND
                    $script:SidebarCollapsed = $false
                
                    # Restore sidebar width
                    if ($parentGrid -and $parentGrid.ColumnDefinitions.Count -gt 0) {
                        $parentGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(220)
                    }
                
                    # Show text elements
                    $win.FindName('SidebarTitle').Visibility = 'Visible'
                    $win.FindName('SidebarSubtitle').Visibility = 'Visible'
                    $win.FindName('NavDashboardText').Visibility = 'Visible'
                    $win.FindName('NavDiscoveryText').Visibility = 'Visible'
                    $win.FindName('NavScannerText').Visibility = 'Visible'
                    $win.FindName('NavRulesText').Visibility = 'Visible'
                    $win.FindName('NavPolicyText').Visibility = 'Visible'
                    $win.FindName('NavDeployText').Visibility = 'Visible'
                    $win.FindName('NavSoftwareText').Visibility = 'Visible'
                    $win.FindName('NavSettingsText').Visibility = 'Visible'
                    $win.FindName('NavSetupText').Visibility = 'Visible'
                    $win.FindName('NavAboutText').Visibility = 'Visible'
                    $win.FindName('SidebarFooter').Visibility = 'Visible'
                    $breadcrumb = $win.FindName('WorkflowBreadcrumb')
                    if ($breadcrumb) { $breadcrumb.Visibility = 'Visible' }
                    $win.FindName('NavSeparator').Margin = [System.Windows.Thickness]::new(15, 20, 15, 20)
                
                    # Change button to collapse icon
                    $btn = $win.FindName('BtnCollapseSidebar')
                    $btn.Content = '<<'
                    $btn.ToolTip = 'Collapse Sidebar'
                }
            })
    }
    
    # Theme toggle click event
    $themeToggle = $Window.FindName('ThemeToggleBorder')
    if ($themeToggle) {
        $themeToggle.Add_MouseLeftButtonDown({
            Invoke-ButtonAction -Action 'ToggleTheme'
        })
    }
}
#endregion

#region ===== WINDOW INITIALIZATION =====
function Initialize-MainWindow {
    param(
        [System.Windows.Window]$Window
    )

    # Store window reference for script-level access
    $global:GA_MainWindow = $Window

    # Initialize navigation buttons
    try {
        Initialize-Navigation -Window $Window
        Write-Log -Message 'Navigation initialized'
    }
    catch {
        Write-Log -Level Error -Message "Navigation init failed: $($_.Exception.Message)"
    }
    
    # Initialize Dashboard panel
    try {
        Initialize-DashboardPanel -Window $Window
        Write-Log -Message 'Dashboard panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Dashboard panel init failed: $($_.Exception.Message)"
    }
    
    # Initialize Discovery panel
    try {
        Initialize-DiscoveryPanel -Window $Window
        Write-Log -Message 'Discovery panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Discovery panel init failed: $($_.Exception.Message)"
    }
    
    # Initialize Credentials panel  
    try {
        Initialize-CredentialsPanel -Window $Window
        Write-Log -Message 'Credentials panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Credentials panel init failed: $($_.Exception.Message)"
    }
    
    # Initialize Scanner panel
    try {
        Initialize-ScannerPanel -Window $Window
        Write-Log -Message 'Scanner panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Scanner panel init failed: $($_.Exception.Message)"
    }

    # Initialize Rules panel
    try {
        Initialize-RulesPanel -Window $Window
        Write-Log -Message 'Rules panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Rules panel init failed: $($_.Exception.Message)"
    }

    # Initialize Policy panel
    try {
        Initialize-PolicyPanel -Window $Window
        Write-Log -Message 'Policy panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Policy panel init failed: $($_.Exception.Message)"
    }

    # Initialize Deployment panel
    try {
        Initialize-DeploymentPanel -Window $Window
        Write-Log -Message 'Deployment panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Deployment panel init failed: $($_.Exception.Message)"
    }

    # Initialize Software Inventory panel
    try {
        Initialize-SoftwarePanel -Window $Window
        Write-Log -Message 'Software Inventory panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Software panel init failed: $($_.Exception.Message)"
    }

    # Initialize Setup panel (Settings > Setup tab)
    try {
        Initialize-SetupPanel -Window $Window
        Write-Log -Message 'Setup panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Setup panel init failed: $($_.Exception.Message)"
    }
    
    # Initialize theme from saved preference
    try {
        Initialize-Theme -Window $Window
        Write-Log -Message 'Theme initialized'
    }
    catch {
        Write-Log -Level Warning -Message "Theme init failed: $($_.Exception.Message)"
    }
    
    # Initialize global search
    try {
        Initialize-GlobalSearch -Window $Window
        Write-Log -Message 'Global search initialized'
    }
    catch {
        Write-Log -Level Warning -Message "Global search init failed: $($_.Exception.Message)"
    }

    # Set version in About panel and sidebar from module manifest
    try {
        $modVersion = (Get-Module GA-AppLocker).Version.ToString()
        $aboutVer = $Window.FindName('AboutVersionText')
        if ($aboutVer) { $aboutVer.Text = $modVersion }
        $sidebarSub = $Window.FindName('SidebarSubtitle')
        if ($sidebarSub) { $sidebarSub.Text = "Dashboard v$modVersion" }
    } catch { }

    # Update domain info in status bar and dashboard
    # NOTE: Uses .NET instead of Get-CimInstance to avoid WMI timeouts that block the WPF STA thread
    try {
        $ipProps = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        $domainName = $ipProps.DomainName
        $isDomainJoined = -not [string]::IsNullOrEmpty($domainName)
        
        # Status bar
        $domainText = $Window.FindName('DomainText')
        if ($domainText -and $isDomainJoined) {
            $domainText.Text = "Domain: $domainName"
        }
        
        # Dashboard System Info
        $sysComputer = $Window.FindName('SysInfoComputer')
        if ($sysComputer) { $sysComputer.Text = $env:COMPUTERNAME }
        
        $sysDomain = $Window.FindName('SysInfoDomain')
        if ($sysDomain) {
            if ($isDomainJoined) {
                $sysDomain.Text = $domainName
            }
            else {
                $sysDomain.Text = "Not domain joined"
            }
        }
        
        $sysUser = $Window.FindName('SysInfoUser')
        if ($sysUser) { $sysUser.Text = "$env:USERDOMAIN\$env:USERNAME" }
        
        $sysDataPath = $Window.FindName('SysInfoDataPath')
        if ($sysDataPath) {
            try {
                $dataPath = Get-AppLockerDataPath
                # Insert line break after AppData for better display
                $sysDataPath.Text = $dataPath -replace '(AppData\\)', "`$1`n"
            } catch { }
        }
        Write-Log -Message 'System info updated'
    }
    catch {
        Write-Log -Level Warning -Message "System info update failed: $($_.Exception.Message)"
    }

    # Update data path in settings
    try {
        $settingsPath = $Window.FindName('SettingsDataPath')
        if ($settingsPath) {
            $settingsPath.Text = Get-AppLockerDataPath
        }
    } catch { }

    # Restore previous session state (auto-restore silently)
    try {
        $restored = Restore-PreviousSessionState -Window $Window
        if ($restored) {
            Write-Log -Message 'Previous session restored'
        }
    }
    catch {
        Write-Log -Level Warning -Message "Session restore failed: $($_.Exception.Message)"
    }
    
    # Initialize workflow breadcrumb
    try {
        Update-WorkflowBreadcrumb -Window $Window
        Write-Log -Message 'Workflow breadcrumb initialized'
    }
    catch {
        Write-Log -Level Warning -Message "Breadcrumb init failed: $($_.Exception.Message)"
    }

    # Register keyboard shortcuts
    try {
        if (Get-Command -Name 'Register-KeyboardShortcuts' -ErrorAction SilentlyContinue) {
            Register-KeyboardShortcuts -Window $Window
            Write-Log -Message 'Keyboard shortcuts registered'
        }
    }
    catch {
        Write-Log -Level Warning -Message "Keyboard shortcuts init failed: $($_.Exception.Message)"
    }

    # Register drag-drop handlers
    try {
        if (Get-Command -Name 'Register-DragDropHandlers' -ErrorAction SilentlyContinue) {
            Register-DragDropHandlers -Window $Window
            Write-Log -Message 'Drag-drop handlers registered'
        }
    }
    catch {
        Write-Log -Level Warning -Message "Drag-drop handlers init failed: $($_.Exception.Message)"
    }

    # Wire up Rule Generation Wizard buttons
    try {
        Initialize-WizardButtons -Window $Window
        Write-Log -Message 'Rule generation wizard buttons wired'
    }
    catch {
        Write-Log -Level Warning -Message "Wizard buttons init failed: $($_.Exception.Message)"
    }

    Write-Log -Message 'Main window initialized'
}

function Initialize-WizardButtons {
    <#
    .SYNOPSIS
        Wires up the Rule Generation Wizard overlay buttons.
    #>
    param([System.Windows.Window]$Window)
    
    # Wizard navigation buttons - call global functions directly
    $btnNext = $Window.FindName('WizardBtnNext')
    if ($btnNext) {
        $btnNext.Add_Click({
            try { global:Invoke-WizardNavigation -Direction 'Next' }
            catch { Write-Host "[Wizard] Next button error: $_" -ForegroundColor Red }
        })
    }
    
    $btnBack = $Window.FindName('WizardBtnBack')
    if ($btnBack) {
        $btnBack.Add_Click({
            try { global:Invoke-WizardNavigation -Direction 'Back' }
            catch { Write-Host "[Wizard] Back button error: $_" -ForegroundColor Red }
        })
    }
    
    $btnGenerate = $Window.FindName('WizardBtnGenerate')
    if ($btnGenerate) {
        $btnGenerate.Add_Click({
            try { global:Invoke-WizardNavigation -Direction 'Generate' }
            catch { Write-Host "[Wizard] Generate button error: $_" -ForegroundColor Red }
        })
    }
    
    $btnCancel = $Window.FindName('WizardBtnCancel')
    if ($btnCancel) {
        $btnCancel.Add_Click({
            try { global:Close-RuleGenerationWizard }
            catch { Write-Host "[Wizard] Cancel button error: $_" -ForegroundColor Red }
        })
    }
    
    $btnClose = $Window.FindName('WizardBtnClose')
    if ($btnClose) {
        $btnClose.Add_Click({
            try { global:Close-RuleGenerationWizard }
            catch { Write-Host "[Wizard] Close button error: $_" -ForegroundColor Red }
        })
    }
    
    $btnMinimize = $Window.FindName('WizardBtnMinimize')
    if ($btnMinimize) {
        $btnMinimize.Add_Click({
            try { global:Close-RuleGenerationWizard }
            catch { Write-Host "[Wizard] Minimize button error: $_" -ForegroundColor Red }
        })
    }
}
#endregion
