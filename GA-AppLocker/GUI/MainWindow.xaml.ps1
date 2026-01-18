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

#region ===== SAFE LOGGING WRAPPER =====
# Wrapper to safely call module functions from code-behind scope
function script:Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== BUTTON ACTION DISPATCHER =====
# Central dispatcher for button clicks - avoids closure scope issues
# Using global scope so WPF event scriptblocks can access it
function global:Invoke-ButtonAction {
    param([string]$Action)

    $win = $script:MainWindow
    if (-not $win) { return }

    switch ($Action) {
        # Navigation
        'NavDashboard' { Set-ActivePanel -PanelName 'PanelDashboard' }
        'NavDiscovery' { Set-ActivePanel -PanelName 'PanelDiscovery' }
        'NavScanner' { Set-ActivePanel -PanelName 'PanelScanner' }
        'NavRules' { Set-ActivePanel -PanelName 'PanelRules' }
        'NavPolicy' { Set-ActivePanel -PanelName 'PanelPolicy' }
        'NavDeploy' { Set-ActivePanel -PanelName 'PanelDeploy' }
        'NavSettings' { Set-ActivePanel -PanelName 'PanelSettings' }
        'NavSetup' { Set-ActivePanel -PanelName 'PanelSetup' }
        'NavAbout' { Set-ActivePanel -PanelName 'PanelAbout' }
        # Discovery panel
        'RefreshDomain' { Invoke-DomainRefresh -Window $win }
        'TestConnectivity' { Invoke-ConnectivityTest -Window $win }
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
        # Rules panel
        'GenerateFromArtifacts' { Invoke-GenerateRulesFromArtifacts -Window $win }
        'CreateManualRule' { Invoke-CreateManualRule -Window $win }
        'ExportRulesXml' { Invoke-ExportRulesToXml -Window $win }
        'ExportRulesCsv' { Invoke-ExportRulesToCsv -Window $win }
        'RefreshRules' { Update-RulesDataGrid -Window $win }
        'SelectAllRules' { Invoke-SelectAllRules -Window $win }
        'ApproveRule' { Set-SelectedRuleStatus -Window $win -Status 'Approved' }
        'RejectRule' { Set-SelectedRuleStatus -Window $win -Status 'Rejected' }
        'ReviewRule' { Set-SelectedRuleStatus -Window $win -Status 'Review' }
        'DeleteRule' { Invoke-DeleteSelectedRules -Window $win }
        'AddRuleToPolicy' { Invoke-AddSelectedRulesToPolicy -Window $win }
        'ViewRuleDetails' { Show-RuleDetails -Window $win }
        # Policy panel
        'CreatePolicy' { Invoke-CreatePolicy -Window $win }
        'RefreshPolicies' { Update-PoliciesDataGrid -Window $win }
        'ActivatePolicy' { Set-SelectedPolicyStatus -Window $win -Status 'Active' }
        'ArchivePolicy' { Set-SelectedPolicyStatus -Window $win -Status 'Archived' }
        'DeletePolicy' { Invoke-DeleteSelectedPolicy -Window $win }
        'ExportPolicy' { Invoke-ExportSelectedPolicy -Window $win }
        'DeployPolicy' { Invoke-DeploySelectedPolicy -Window $win }
        'AddRulesToPolicy' { Invoke-AddRulesToPolicy -Window $win }
        'RemoveRulesFromPolicy' { Invoke-RemoveRulesFromPolicy -Window $win }
        'SelectTargetOUs' { Invoke-SelectTargetOUs -Window $win }
        'SavePolicyTargets' { Invoke-SavePolicyTargets -Window $win }
        # Deployment panel
        'CreateDeploymentJob' { Invoke-CreateDeploymentJob -Window $win }
        'RefreshDeployments' { Update-DeploymentJobsDataGrid -Window $win }
        'DeploySelectedJob' { Invoke-DeploySelectedJob -Window $win }
        'StopDeployment' { Invoke-StopDeployment -Window $win }
        'CancelDeploymentJob' { Invoke-CancelDeploymentJob -Window $win }
        'ViewDeploymentLog' { Show-DeploymentLog -Window $win }
        # Setup panel (Settings > Setup tab)
        'InitializeWinRM' { Invoke-InitializeWinRM -Window $win }
        'ToggleWinRM' { Invoke-ToggleWinRM -Window $win }
        'InitializeAppLockerGPOs' { Invoke-InitializeAppLockerGPOs -Window $win }
        'InitializeADStructure' { Invoke-InitializeADStructure -Window $win }
        'InitializeAll' { Invoke-InitializeAll -Window $win }
    }
}
#endregion

#region ===== SCRIPT-LEVEL VARIABLES =====
# Store window reference for event handlers
$script:MainWindow = $null
$script:DiscoveredOUs = @()
$script:DiscoveredMachines = @()
$script:SelectedScanMachines = @()
$script:CurrentScanArtifacts = @()
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
#endregion

#region ===== NAVIGATION HANDLERS =====
# Panel visibility management
function Set-ActivePanel {
    param([string]$PanelName)

    # Try script scope first, fall back to global
    $Window = $script:MainWindow
    if (-not $Window) { $Window = $script:MainWindow }
    if (-not $Window) { return }

    # All panel names
    $panels = @(
        'PanelDashboard',
        'PanelDiscovery',
        'PanelScanner',
        'PanelRules',
        'PanelPolicy',
        'PanelDeploy',
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
    
    # Auto-save session state on panel change
    Save-CurrentSessionState
}

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

function script:Update-WorkflowBreadcrumb {
    param([System.Windows.Window]$Window)
    
    if (-not $Window) { $Window = $script:MainWindow }
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
    if (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue) {
        $rulesResult = Get-AllRules
        if ($rulesResult.Success) {
            $ruleCount = $rulesResult.Data.Count
        }
    }
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
    if (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue) {
        $policiesResult = Get-AllPolicies
        if ($policiesResult.Success) {
            $polCount = $policiesResult.Data.Count
        }
    }
    if ($policyStage) {
        $policyStage.Fill = if ($polCount -gt 0) { $successBrush } else { $inactiveBrush }
    }
    if ($policyCount) {
        $policyCount.Text = $polCount.ToString()
    }
}

# Track current panel for session state
$script:CurrentActivePanel = 'PanelDashboard'

#endregion

#region ===== DASHBOARD PANEL =====

function Initialize-DashboardPanel {
    param([System.Windows.Window]$Window)

    # Wire up quick action buttons
    $btnGoToScanner = $Window.FindName('BtnDashGoToScanner')
    if ($btnGoToScanner) { $btnGoToScanner.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btnGoToRules = $Window.FindName('BtnDashGoToRules')
    if ($btnGoToRules) { $btnGoToRules.Add_Click({ Invoke-ButtonAction -Action 'NavRules' }) }

    $btnQuickScan = $Window.FindName('BtnDashQuickScan')
    if ($btnQuickScan) { $btnQuickScan.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btnQuickImport = $Window.FindName('BtnDashQuickImport')
    if ($btnQuickImport) { $btnQuickImport.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btnQuickDeploy = $Window.FindName('BtnDashQuickDeploy')
    if ($btnQuickDeploy) { $btnQuickDeploy.Add_Click({ Invoke-ButtonAction -Action 'NavDeploy' }) }

    # Load dashboard data
    Update-DashboardStats -Window $Window
}

function Update-DashboardStats {
    param([System.Windows.Window]$Window)

    # Update stats from actual data
    try {
        # Machines count
        $statMachines = $Window.FindName('StatMachines')
        if ($statMachines) { 
            $statMachines.Text = $script:DiscoveredMachines.Count.ToString()
        }

        # Artifacts count
        $statArtifacts = $Window.FindName('StatArtifacts')
        if ($statArtifacts -and $script:CurrentScanArtifacts) { 
            $statArtifacts.Text = $script:CurrentScanArtifacts.Count.ToString()
        }

        # Rules count
        $statRules = $Window.FindName('StatRules')
        $statPending = $Window.FindName('StatPending')
        $rulesResult = Get-AllRules
        if ($rulesResult.Success) {
            $allRules = $rulesResult.Data
            if ($statRules) { $statRules.Text = $allRules.Count.ToString() }
            if ($statPending) {
                $pendingCount = ($allRules | Where-Object { $_.Status -eq 'Pending' }).Count
                $statPending.Text = $pendingCount.ToString()
            }

            # Populate pending rules list
            $pendingList = $Window.FindName('DashPendingRules')
            if ($pendingList) {
                $pendingRules = @($allRules | Where-Object { $_.Status -eq 'Pending' } | Select-Object -First 10 | ForEach-Object {
                        [PSCustomObject]@{
                            Type = $_.RuleType
                            Name = $_.Name
                        }
                    })
                $pendingList.ItemsSource = $pendingRules
            }
        }

        # Policies count
        $statPolicies = $Window.FindName('StatPolicies')
        $policiesResult = Get-AllPolicies
        if ($policiesResult.Success -and $statPolicies) {
            $statPolicies.Text = $policiesResult.Data.Count.ToString()
        }

        # Recent scans
        $scansList = $Window.FindName('DashRecentScans')
        if ($scansList) {
            $scansResult = Get-ScanResults
            if ($scansResult.Success -and $scansResult.Data) {
                # Ensure Data is always an array
                $scanData = @($scansResult.Data)
                $recentScans = @($scanData | Select-Object -First 5 | ForEach-Object {
                        [PSCustomObject]@{
                            Name  = $_.ScanName
                            Date  = $_.Date.ToString('MM/dd HH:mm')
                            Count = "$($_.Artifacts) items"
                        }
                    })
                $scansList.ItemsSource = $recentScans
            }
        }
    }
    catch {
        Write-Log -Level Warning -Message "Failed to update dashboard stats: $($_.Exception.Message)"
    }
}

#endregion

# Sidebar collapsed state
$script:SidebarCollapsed = $false

# Wire up navigation event handlers
function Initialize-Navigation {
    param([System.Windows.Window]$Window)

    # Store window reference
    $script:MainWindow = $Window
    $script:MainWindow = $Window

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

    $btn = $Window.FindName('NavSettings')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSettings' }) }

    $btn = $Window.FindName('NavSetup')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSetup' }) }

    $btn = $Window.FindName('NavAbout')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavAbout' }) }

    # Sidebar collapse/expand toggle button
    $script:SidebarCollapsed = $false
    $btnCollapse = $Window.FindName('BtnCollapseSidebar')
    if ($btnCollapse) {
        $btnCollapse.Add_Click({
                $win = $script:MainWindow
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
                    $win.FindName('NavSettingsText').Visibility = 'Collapsed'
                    $win.FindName('NavSetupText').Visibility = 'Collapsed'
                    $win.FindName('NavAboutText').Visibility = 'Collapsed'
                    $win.FindName('SidebarFooter').Visibility = 'Collapsed'
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
                    $win.FindName('NavSettingsText').Visibility = 'Visible'
                    $win.FindName('NavSetupText').Visibility = 'Visible'
                    $win.FindName('NavAboutText').Visibility = 'Visible'
                    $win.FindName('SidebarFooter').Visibility = 'Visible'
                    $win.FindName('NavSeparator').Margin = [System.Windows.Thickness]::new(15, 20, 15, 20)
                
                    # Change button to collapse icon
                    $btn = $win.FindName('BtnCollapseSidebar')
                    $btn.Content = '<<'
                    $btn.ToolTip = 'Collapse Sidebar'
                }
            })
    }
}
#endregion

#region ===== DISCOVERY PANEL HANDLERS =====

function Initialize-DiscoveryPanel {
    param([System.Windows.Window]$Window)

    # Wire up Refresh Domain button
    $btnRefresh = $Window.FindName('BtnRefreshDomain')
    if ($btnRefresh) {
        $btnRefresh.Add_Click({ Invoke-ButtonAction -Action 'RefreshDomain' })
    }

    # Wire up Test Connectivity button
    $btnTest = $Window.FindName('BtnTestConnectivity')
    if ($btnTest) {
        $btnTest.Add_Click({ Invoke-ButtonAction -Action 'TestConnectivity' })
    }
}

function Invoke-DomainRefresh {
    param([System.Windows.Window]$Window)

    $domainLabel = $Window.FindName('DiscoveryDomainLabel')
    $machineCount = $Window.FindName('DiscoveryMachineCount')
    $treeView = $Window.FindName('OUTreeView')

    # Update status
    if ($domainLabel) { $domainLabel.Text = 'Domain: Connecting...' }

    try {
        # Get domain info
        $domainResult = Get-DomainInfo
        if ($domainResult.Success) {
            if ($domainLabel) {
                $domainLabel.Text = "Domain: $($domainResult.Data.DnsRoot)"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
            }

            # Get OU tree
            $ouResult = Get-OUTree
            if ($ouResult.Success -and $treeView) {
                $script:DiscoveredOUs = $ouResult.Data
                Update-OUTreeView -TreeView $treeView -OUs $ouResult.Data
            }

            # Get all computers
            $rootDN = $domainResult.Data.DistinguishedName
            $computerResult = Get-ComputersByOU -OUDistinguishedNames @($rootDN)
            if ($computerResult.Success) {
                $script:DiscoveredMachines = $computerResult.Data
                Update-MachineDataGrid -Window $Window -Machines $computerResult.Data
                Update-WorkflowBreadcrumb -Window $Window

                if ($machineCount) {
                    $machineCount.Text = "$($computerResult.Data.Count) machines discovered"
                }
            }
        }
        else {
            if ($domainLabel) {
                $domainLabel.Text = "Domain: Error - $($domainResult.Error)"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            }
        }
    }
    catch {
        if ($domainLabel) {
            $domainLabel.Text = "Domain: Error - $($_.Exception.Message)"
            $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
    }
}

function Update-OUTreeView {
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [array]$OUs
    )

    $TreeView.Items.Clear()

    # Build hierarchical tree
    $root = $OUs | Where-Object { $_.Depth -eq 0 } | Select-Object -First 1
    if ($root) {
        $rootItem = New-TreeViewItem -OU $root -AllOUs $OUs
        $TreeView.Items.Add($rootItem)
        $rootItem.IsExpanded = $true
    }
}

function New-TreeViewItem {
    param($OU, $AllOUs)

    $icon = switch ($OU.MachineType) {
        'DomainController' { '&#x1F3E2;' }
        'Server' { '&#x1F5A7;' }
        'Workstation' { '&#x1F5A5;' }
        default { '&#x1F4C1;' }
    }

    $header = "$icon $($OU.Name)"
    if ($OU.ComputerCount -gt 0) {
        $header += " ($($OU.ComputerCount))"
    }

    $item = [System.Windows.Controls.TreeViewItem]::new()
    $item.Header = $header
    $item.Tag = $OU.DistinguishedName
    $item.Foreground = [System.Windows.Media.Brushes]::White

    # Add child OUs
    $children = $AllOUs | Where-Object {
        $_.DistinguishedName -ne $OU.DistinguishedName -and
        $_.DistinguishedName -like "*,$($OU.DistinguishedName)" -and
        $_.Depth -eq ($OU.Depth + 1)
    }

    foreach ($child in $children) {
        $childItem = New-TreeViewItem -OU $child -AllOUs $AllOUs
        $item.Items.Add($childItem)
    }

    return $item
}

function Update-MachineDataGrid {
    param(
        [System.Windows.Window]$Window,
        [array]$Machines
    )

    $dataGrid = $Window.FindName('MachineDataGrid')
    if ($dataGrid) {
        # Add status icon property
        $machinesWithIcon = $Machines | ForEach-Object {
            $statusIcon = switch ($_.IsOnline) {
                $true { '&#x1F7E2;' }
                $false { '&#x1F534;' }
                default { '&#x26AA;' }
            }
            $_ | Add-Member -NotePropertyName 'StatusIcon' -NotePropertyValue $statusIcon -PassThru -Force
        }

        $dataGrid.ItemsSource = $machinesWithIcon
    }
}

function Invoke-ConnectivityTest {
    param([System.Windows.Window]$Window)

    if ($script:DiscoveredMachines.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            'No machines discovered. Click "Refresh Domain" first.',
            'No Machines',
            'OK',
            'Information'
        )
        return
    }

    $machineCount = $Window.FindName('DiscoveryMachineCount')
    if ($machineCount) { $machineCount.Text = 'Testing connectivity...' }

    $testResult = Test-MachineConnectivity -Machines $script:DiscoveredMachines
    if ($testResult.Success) {
        $script:DiscoveredMachines = $testResult.Data
        Update-MachineDataGrid -Window $Window -Machines $testResult.Data
        Update-WorkflowBreadcrumb -Window $Window

        $summary = $testResult.Summary
        if ($machineCount) {
            $machineCount.Text = "$($summary.OnlineCount)/$($summary.TotalMachines) online, $($summary.WinRMAvailable) WinRM"
        }
    }
}
#endregion

#region ===== CREDENTIALS PANEL HANDLERS =====

function Initialize-CredentialsPanel {
    param([System.Windows.Window]$Window)

    # Wire up Save Credential button
    $btnSave = $Window.FindName('BtnSaveCredential')
    if ($btnSave) {
        $btnSave.Add_Click({ Invoke-ButtonAction -Action 'SaveCredential' })
    }

    # Wire up Refresh Credentials button
    $btnRefresh = $Window.FindName('BtnRefreshCredentials')
    if ($btnRefresh) {
        $btnRefresh.Add_Click({ Invoke-ButtonAction -Action 'RefreshCredentials' })
    }

    # Wire up Test Credential button
    $btnTest = $Window.FindName('BtnTestCredential')
    if ($btnTest) {
        $btnTest.Add_Click({ Invoke-ButtonAction -Action 'TestCredential' })
    }

    # Wire up Delete Credential button
    $btnDelete = $Window.FindName('BtnDeleteCredential')
    if ($btnDelete) {
        $btnDelete.Add_Click({ Invoke-ButtonAction -Action 'DeleteCredential' })
    }

    # Wire up Set Default button
    $btnSetDefault = $Window.FindName('BtnSetDefaultCredential')
    if ($btnSetDefault) {
        $btnSetDefault.Add_Click({ Invoke-ButtonAction -Action 'SetDefaultCredential' })
    }

    # Load existing credentials
    try {
        Update-CredentialsDataGrid -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load credentials: $($_.Exception.Message)"
    }
}

function Invoke-SaveCredential {
    param([System.Windows.Window]$Window)

    $profileName = $Window.FindName('CredProfileName')
    $tierCombo = $Window.FindName('CredTierCombo')
    $username = $Window.FindName('CredUsername')
    $password = $Window.FindName('CredPassword')
    $description = $Window.FindName('CredDescription')
    $setAsDefault = $Window.FindName('CredSetAsDefault')

    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($profileName.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a profile name.', 'Validation Error', 'OK', 'Warning')
        return
    }

    if ([string]::IsNullOrWhiteSpace($username.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a username.', 'Validation Error', 'OK', 'Warning')
        return
    }

    if ($password.SecurePassword.Length -eq 0) {
        [System.Windows.MessageBox]::Show('Please enter a password.', 'Validation Error', 'OK', 'Warning')
        return
    }

    # Build PSCredential
    $securePassword = $password.SecurePassword
    $credential = [PSCredential]::new($username.Text, $securePassword)

    # Get tier from combo box
    $tier = $tierCombo.SelectedIndex

    # Create credential profile
    $params = @{
        Name        = $profileName.Text
        Credential  = $credential
        Tier        = $tier
        Description = $description.Text
    }

    if ($setAsDefault.IsChecked) {
        $params.SetAsDefault = $true
    }

    $result = New-CredentialProfile @params

    if ($result.Success) {
        [System.Windows.MessageBox]::Show(
            "Credential profile '$($profileName.Text)' saved successfully.",
            'Success',
            'OK',
            'Information'
        )

        # Clear form
        $profileName.Text = ''
        $username.Text = ''
        $password.Clear()
        $description.Text = ''
        $setAsDefault.IsChecked = $false

        # Refresh grid
        Update-CredentialsDataGrid -Window $Window
    }
    else {
        [System.Windows.MessageBox]::Show(
            "Failed to save credential: $($result.Error)",
            'Error',
            'OK',
            'Error'
        )
    }
}

function Update-CredentialsDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    if (-not $dataGrid) { return }

    $result = Get-AllCredentialProfiles

    if ($result.Success -and $result.Data) {
        # Add display properties
        $displayData = $result.Data | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'IsDefaultDisplay' -NotePropertyValue $(if ($_.IsDefault) { 'Yes' } else { '' }) -PassThru -Force |
            Add-Member -NotePropertyName 'LastTestDisplay' -NotePropertyValue $(
                if ($_.LastTestResult) {
                    $status = if ($_.LastTestResult.Success) { 'Passed' } else { 'Failed' }
                    "$status - $($_.LastTestResult.TestTime)"
                }
                else { 'Not tested' }
            ) -PassThru -Force
        }
        $dataGrid.ItemsSource = $displayData
    }
    else {
        $dataGrid.ItemsSource = $null
    }
}

function Invoke-TestSelectedCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    $testTarget = $Window.FindName('CredTestTarget')
    $resultBorder = $Window.FindName('CredTestResultBorder')
    $resultText = $Window.FindName('CredTestResultText')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to test.', 'No Selection', 'OK', 'Information')
        return
    }

    if ([string]::IsNullOrWhiteSpace($testTarget.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a target hostname to test against.', 'No Target', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem
    $resultBorder.Visibility = 'Visible'
    $resultText.Text = "Testing credential '$($selectedProfile.Name)' against $($testTarget.Text)..."
    $resultText.Foreground = [System.Windows.Media.Brushes]::White

    # Run test
    $testResult = Test-CredentialProfile -Name $selectedProfile.Name -ComputerName $testTarget.Text

    if ($testResult.Success) {
        $resultText.Text = "SUCCESS: Credential '$($selectedProfile.Name)' authenticated to $($testTarget.Text)`n" +
        "Ping: Passed | WinRM: Passed"
        $resultText.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    else {
        $resultText.Text = "FAILED: $($testResult.Error)`n"
        if ($testResult.Data) {
            $resultText.Text += "Ping: $(if ($testResult.Data.PingSuccess) { 'Passed' } else { 'Failed' }) | " +
            "WinRM: $(if ($testResult.Data.WinRMSuccess) { 'Passed' } else { 'Failed' })`n" +
            "Error: $($testResult.Data.ErrorMessage)"
        }
        $resultText.Foreground = [System.Windows.Media.Brushes]::OrangeRed
    }

    # Refresh grid to show updated test result
    Update-CredentialsDataGrid -Window $Window
}

function Invoke-DeleteSelectedCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete credential profile '$($selectedProfile.Name)'?",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $result = Remove-CredentialProfile -Name $selectedProfile.Name

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "Credential profile '$($selectedProfile.Name)' deleted.",
                'Deleted',
                'OK',
                'Information'
            )
            Update-CredentialsDataGrid -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show(
                "Failed to delete: $($result.Error)",
                'Error',
                'OK',
                'Error'
            )
        }
    }
}

function Invoke-SetDefaultCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to set as default.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    # Get existing profile
    $profileResult = Get-CredentialProfile -Name $selectedProfile.Name
    if (-not $profileResult.Success) {
        [System.Windows.MessageBox]::Show("Profile not found: $($profileResult.Error)", 'Error', 'OK', 'Error')
        return
    }

    $profile = $profileResult.Data

    # Clear other defaults for same tier
    $allProfiles = Get-AllCredentialProfiles
    if ($allProfiles.Success) {
        foreach ($p in $allProfiles.Data) {
            if ($p.Tier -eq $profile.Tier -and $p.Name -ne $profile.Name -and $p.IsDefault) {
                $p.IsDefault = $false
                $credPath = Get-CredentialStoragePath
                $profilePath = Join-Path $credPath "$($p.Id).json"
                $p | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8
            }
        }
    }

    # Set this profile as default
    $profile.IsDefault = $true
    $credPath = Get-CredentialStoragePath
    $profilePath = Join-Path $credPath "$($profile.Id).json"
    $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8

    [System.Windows.MessageBox]::Show(
        "Credential profile '$($selectedProfile.Name)' set as default for Tier $($profile.Tier).",
        'Default Set',
        'OK',
        'Information'
    )

    Update-CredentialsDataGrid -Window $Window
}

#endregion

#region ===== SCANNER PANEL HANDLERS =====

function Initialize-ScannerPanel {
    param([System.Windows.Window]$Window)

    # Initialize scan paths from config
    $txtPaths = $Window.FindName('TxtScanPaths')
    if ($txtPaths) {
        try {
            $config = Get-AppLockerConfig
            if ($config.DefaultScanPaths) {
                $txtPaths.Text = $config.DefaultScanPaths -join "`n"
            }
        }
        catch {
            # Keep XAML default if config unavailable
        }
    }

    # Wire up main action buttons
    $btnStart = $Window.FindName('BtnStartScan')
    if ($btnStart) { $btnStart.Add_Click({ Invoke-ButtonAction -Action 'StartScan' }) }

    $btnStop = $Window.FindName('BtnStopScan')
    if ($btnStop) { $btnStop.Add_Click({ Invoke-ButtonAction -Action 'StopScan' }) }

    $btnImport = $Window.FindName('BtnImportArtifacts')
    if ($btnImport) { $btnImport.Add_Click({ Invoke-ButtonAction -Action 'ImportArtifacts' }) }

    $btnExport = $Window.FindName('BtnExportArtifacts')
    if ($btnExport) { $btnExport.Add_Click({ Invoke-ButtonAction -Action 'ExportArtifacts' }) }

    # Wire up configuration buttons
    $btnSelectMachines = $Window.FindName('BtnSelectMachines')
    if ($btnSelectMachines) { $btnSelectMachines.Add_Click({ Invoke-ButtonAction -Action 'SelectMachines' }) }

    $btnBrowsePath = $Window.FindName('BtnBrowsePath')
    if ($btnBrowsePath) { $btnBrowsePath.Add_Click({ Invoke-BrowseScanPath -Window $script:MainWindow }) }

    $btnResetPaths = $Window.FindName('BtnResetPaths')
    if ($btnResetPaths) {
        $btnResetPaths.Add_Click({ 
                $txtPaths = $script:MainWindow.FindName('TxtScanPaths')
                if ($txtPaths) { 
                    $config = Get-AppLockerConfig
                    $defaultPaths = if ($config.DefaultScanPaths) { $config.DefaultScanPaths -join "`n" } else { "C:\Program Files`nC:\Program Files (x86)" }
                    $txtPaths.Text = $defaultPaths
                }
            }) 
    }

    # Wire up saved scans buttons
    $btnRefreshScans = $Window.FindName('BtnRefreshScans')
    if ($btnRefreshScans) { $btnRefreshScans.Add_Click({ Invoke-ButtonAction -Action 'RefreshScans' }) }

    $btnLoadScan = $Window.FindName('BtnLoadScan')
    if ($btnLoadScan) { $btnLoadScan.Add_Click({ Invoke-ButtonAction -Action 'LoadScan' }) }

    $btnDeleteScan = $Window.FindName('BtnDeleteScan')
    if ($btnDeleteScan) { $btnDeleteScan.Add_Click({ Invoke-ButtonAction -Action 'DeleteScan' }) }

    # Wire up filter buttons
    $filterButtons = @{
        'BtnFilterAllArtifacts' = 'All'
        'BtnFilterExe'          = 'EXE'
        'BtnFilterDll'          = 'DLL'
        'BtnFilterMsi'          = 'MSI'
        'BtnFilterScript'       = 'Script'
        'BtnFilterSigned'       = 'Signed'
        'BtnFilterUnsigned'     = 'Unsigned'
    }

    foreach ($btnName in $filterButtons.Keys) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $filterType = $filterButtons[$btnName]
            $btn.Add_Click({ 
                    param($sender, $e)
                    $filter = $sender.Content -replace '[^a-zA-Z]', ''
                    Update-ArtifactFilter -Window $script:MainWindow -Filter $filter
                }.GetNewClosure())
        }
    }

    # Wire up text filter
    $filterBox = $Window.FindName('ArtifactFilterBox')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
                Update-ArtifactDataGrid -Window $script:MainWindow
            })
    }

    # Load saved scans list
    try {
        Update-SavedScansList -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load saved scans: $($_.Exception.Message)"
    }
}

function Invoke-StartArtifactScan {
    param([System.Windows.Window]$Window)

    if ($script:ScanInProgress) {
        [System.Windows.MessageBox]::Show('A scan is already in progress.', 'Scan Active', 'OK', 'Warning')
        return
    }

    # Get scan configuration
    $scanLocal = $Window.FindName('ChkScanLocal').IsChecked
    $scanRemote = $Window.FindName('ChkScanRemote').IsChecked
    $includeEvents = $Window.FindName('ChkIncludeEventLogs').IsChecked
    $saveResults = $Window.FindName('ChkSaveResults').IsChecked
    $scanName = $Window.FindName('TxtScanName').Text
    $pathsText = $Window.FindName('TxtScanPaths').Text

    # Validate
    if (-not $scanLocal -and -not $scanRemote) {
        [System.Windows.MessageBox]::Show('Please select at least one scan type (Local or Remote).', 'Configuration Error', 'OK', 'Warning')
        return
    }

    if ($scanRemote -and $script:SelectedScanMachines.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Remote scan selected but no machines are selected. Go to AD Discovery first or select Local scan.', 'No Machines', 'OK', 'Warning')
        return
    }

    if ([string]::IsNullOrWhiteSpace($scanName)) {
        $scanName = "Scan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Window.FindName('TxtScanName').Text = $scanName
    }

    # Parse paths
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($pathsText)) {
        $paths = $pathsText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # Update UI state
    $script:ScanInProgress = $true
    $script:ScanCancelled = $false
    Update-ScanUIState -Window $Window -Scanning $true
    Update-ScanProgress -Window $Window -Text "Starting scan: $scanName" -Percent 5

    # Build scan parameters
    $scanParams = @{
        SaveResults = $saveResults
        ScanName    = $scanName
    }

    if ($scanLocal) { $scanParams.ScanLocal = $true }
    if ($includeEvents) { $scanParams.IncludeEventLogs = $true }
    if ($paths.Count -gt 0) { $scanParams.Paths = $paths }
    if ($scanRemote -and $script:SelectedScanMachines.Count -gt 0) {
        $scanParams.Machines = $script:SelectedScanMachines
    }

    # Create a synchronized hashtable for cross-thread communication
    $script:ScanSyncHash = [hashtable]::Synchronized(@{
            Window     = $Window
            Params     = $scanParams
            Result     = $null
            Error      = $null
            IsComplete = $false
            Progress   = 10
            StatusText = "Initializing scan..."
        })

    # Create and start the background runspace
    $script:ScanRunspace = [runspacefactory]::CreateRunspace()
    $script:ScanRunspace.ApartmentState = 'STA'
    $script:ScanRunspace.ThreadOptions = 'ReuseThread'
    $script:ScanRunspace.Open()
    $script:ScanRunspace.SessionStateProxy.SetVariable('SyncHash', $script:ScanSyncHash)

    # Import module path for the runspace
    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:ScanRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:ScanPowerShell = [powershell]::Create()
    $script:ScanPowerShell.Runspace = $script:ScanRunspace
    
    [void]$script:ScanPowerShell.AddScript({
            param($SyncHash, $ModulePath)
        
            try {
                # Import the module in this runspace
                $SyncHash.StatusText = "Loading modules..."
                $SyncHash.Progress = 15
            
                $manifestPath = Join-Path $ModulePath "GA-AppLocker.psd1"
                if (Test-Path $manifestPath) {
                    Import-Module $manifestPath -Force -ErrorAction Stop
                }
                else {
                    throw "Module not found at: $manifestPath"
                }
            
                $SyncHash.StatusText = "Scanning files..."
                $SyncHash.Progress = 25
            
                # Execute the scan - splat the params hashtable
                $scanParams = $SyncHash.Params
                $result = Start-ArtifactScan @scanParams
            
                $SyncHash.Progress = 90
                $SyncHash.StatusText = "Processing results..."
                $SyncHash.Result = $result
            }
            catch {
                $SyncHash.Error = $_.Exception.Message
            }
            finally {
                $SyncHash.IsComplete = $true
                $SyncHash.Progress = 100
            }
        })
    
    [void]$script:ScanPowerShell.AddArgument($script:ScanSyncHash)
    [void]$script:ScanPowerShell.AddArgument($modulePath)

    # Start async execution
    $script:ScanAsyncResult = $script:ScanPowerShell.BeginInvoke()

    # Create a DispatcherTimer to poll for completion and update UI
    $script:ScanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ScanTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    
    $script:ScanTimer.Add_Tick({
            $syncHash = $script:ScanSyncHash
            $win = $syncHash.Window
        
            # Update progress
            Update-ScanProgress -Window $win -Text $syncHash.StatusText -Percent $syncHash.Progress
        
            # Check if cancelled
            if ($script:ScanCancelled) {
                $script:ScanTimer.Stop()
            
                # Clean up runspace
                if ($script:ScanPowerShell) {
                    $script:ScanPowerShell.Stop()
                    $script:ScanPowerShell.Dispose()
                }
                if ($script:ScanRunspace) {
                    $script:ScanRunspace.Close()
                    $script:ScanRunspace.Dispose()
                }
            
                $script:ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
                Update-ScanProgress -Window $win -Text "Scan cancelled" -Percent 0
                $win.FindName('ScanStatusLabel').Text = "Cancelled"
                $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::Orange
                return
            }
        
            # Check if complete
            if ($syncHash.IsComplete) {
                $script:ScanTimer.Stop()
            
                # End the async operation
                try {
                    $script:ScanPowerShell.EndInvoke($script:ScanAsyncResult)
                }
                catch { }
            
                # Clean up runspace
                if ($script:ScanPowerShell) { $script:ScanPowerShell.Dispose() }
                if ($script:ScanRunspace) { 
                    $script:ScanRunspace.Close()
                    $script:ScanRunspace.Dispose() 
                }
            
                $script:ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
            
                if ($syncHash.Error) {
                    Update-ScanProgress -Window $win -Text "Error: $($syncHash.Error)" -Percent 0
                    $win.FindName('ScanStatusLabel').Text = "Error"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    [System.Windows.MessageBox]::Show("Scan error: $($syncHash.Error)", 'Error', 'OK', 'Error')
                }
                elseif ($syncHash.Result -and $syncHash.Result.Success) {
                    $result = $syncHash.Result
                    $script:CurrentScanArtifacts = $result.Data.Artifacts
                    Update-ArtifactDataGrid -Window $win
                    Update-ScanProgress -Window $win -Text "Scan complete: $($result.Summary.TotalArtifacts) artifacts" -Percent 100

                    # Update counters
                    $win.FindName('ScanArtifactCount').Text = "$($result.Summary.TotalArtifacts) artifacts"
                    $win.FindName('ScanSignedCount').Text = "$($result.Summary.SignedArtifacts)"
                    $win.FindName('ScanUnsignedCount').Text = "$($result.Summary.UnsignedArtifacts)"
                    $win.FindName('ScanStatusLabel').Text = "Complete"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

                    # Refresh saved scans list
                    Update-SavedScansList -Window $win
                    
                    # Update workflow breadcrumb
                    Update-WorkflowBreadcrumb -Window $win

                    Show-Toast -Message "Scan complete: $($result.Summary.TotalArtifacts) artifacts found ($($result.Summary.SignedArtifacts) signed)." -Type 'Success'
                }
                else {
                    $errorMsg = if ($syncHash.Result) { $syncHash.Result.Error } else { "Unknown error" }
                    Update-ScanProgress -Window $win -Text "Scan failed: $errorMsg" -Percent 0
                    $win.FindName('ScanStatusLabel').Text = "Failed"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    [System.Windows.MessageBox]::Show("Scan failed: $errorMsg", 'Scan Error', 'OK', 'Error')
                }
            }
        })
    
    # Start the timer
    $script:ScanTimer.Start()
}

function Invoke-StopArtifactScan {
    param([System.Windows.Window]$Window)

    # Signal cancellation - the timer tick handler will clean up
    $script:ScanCancelled = $true
}

function Update-ScanUIState {
    param(
        [System.Windows.Window]$Window,
        [bool]$Scanning
    )

    $btnStart = $Window.FindName('BtnStartScan')
    $btnStop = $Window.FindName('BtnStopScan')

    if ($btnStart) { $btnStart.IsEnabled = -not $Scanning }
    if ($btnStop) { $btnStop.IsEnabled = $Scanning }
}

function Update-ScanProgress {
    param(
        [System.Windows.Window]$Window,
        [string]$Text,
        [int]$Percent
    )

    $progressText = $Window.FindName('ScanProgressText')
    $progressBar = $Window.FindName('ScanProgressBar')
    $progressPercent = $Window.FindName('ScanProgressPercent')

    if ($progressText) { $progressText.Text = $Text }
    if ($progressBar) { $progressBar.Value = $Percent }
    if ($progressPercent) { $progressPercent.Text = if ($Percent -gt 0) { "$Percent%" } else { '' } }

    # Note: DoEvents() removed - anti-pattern that causes re-entrancy issues
    # TODO: Implement proper async pattern with runspaces for long operations
}

function script:Update-ArtifactDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('ArtifactDataGrid')
    if (-not $dataGrid) { return }

    $artifacts = $script:CurrentScanArtifacts
    if (-not $artifacts) {
        $dataGrid.ItemsSource = $null
        return
    }

    # Apply text filter
    $filterBox = $Window.FindName('ArtifactFilterBox')
    $filterText = if ($filterBox) { $filterBox.Text } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($filterText)) {
        $artifacts = $artifacts | Where-Object {
            $_.FileName -like "*$filterText*" -or
            $_.Publisher -like "*$filterText*" -or
            $_.Path -like "*$filterText*"
        }
    }

    # Add display properties
    $displayData = $artifacts | ForEach-Object {
        $signedIcon = if ($_.IsSigned) { [char]0x2714 } else { [char]0x2718 }
        $_ | Add-Member -NotePropertyName 'SignedIcon' -NotePropertyValue $signedIcon -PassThru -Force
    }

    $dataGrid.ItemsSource = $displayData
}

function global:Update-ArtifactFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    # Reset button styles
    $allButtons = @('BtnFilterAllArtifacts', 'BtnFilterExe', 'BtnFilterDll', 'BtnFilterMsi', 'BtnFilterScript', 'BtnFilterSigned', 'BtnFilterUnsigned')
    foreach ($btnName in $allButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
        }
    }

    # Highlight active filter
    $activeBtn = switch ($Filter) {
        'All' { 'BtnFilterAllArtifacts' }
        'EXE' { 'BtnFilterExe' }
        'DLL' { 'BtnFilterDll' }
        'MSI' { 'BtnFilterMsi' }
        'Script' { 'BtnFilterScript' }
        'Signed' { 'BtnFilterSigned' }
        'Unsigned' { 'BtnFilterUnsigned' }
    }

    $btn = $Window.FindName($activeBtn)
    if ($btn) {
        $btn.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(62, 62, 66))
    }

    # Filter artifacts
    $baseArtifacts = $script:CurrentScanArtifacts
    if (-not $baseArtifacts) { return }

    $filtered = switch ($Filter) {
        'All' { $baseArtifacts }
        'EXE' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'EXE' } }
        'DLL' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'DLL' } }
        'MSI' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'MSI' } }
        'Script' { $baseArtifacts | Where-Object { $_.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS') } }
        'Signed' { $baseArtifacts | Where-Object { $_.IsSigned } }
        'Unsigned' { $baseArtifacts | Where-Object { -not $_.IsSigned } }
        default { $baseArtifacts }
    }

    # Temporarily replace current artifacts for display
    $original = $script:CurrentScanArtifacts
    $script:CurrentScanArtifacts = $filtered
    Update-ArtifactDataGrid -Window $Window
    $script:CurrentScanArtifacts = $original
}

function Update-SavedScansList {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox) { return }

    if (-not (Get-Command -Name 'Get-ScanResults' -ErrorAction SilentlyContinue)) {
        return
    }

    $result = Get-ScanResults
    if ($result.Success -and $result.Data) {
        $listBox.ItemsSource = $result.Data
    }
    else {
        $listBox.ItemsSource = $null
    }
}

function Invoke-LoadSelectedScan {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a saved scan to load.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedScan = $listBox.SelectedItem
    $result = Get-ScanResults -ScanId $selectedScan.ScanId

    if ($result.Success) {
        $script:CurrentScanArtifacts = $result.Data.Artifacts
        Update-ArtifactDataGrid -Window $Window

        # Update counters
        $signed = ($result.Data.Artifacts | Where-Object { $_.IsSigned }).Count
        $unsigned = $result.Data.Artifacts.Count - $signed
        $Window.FindName('ScanArtifactCount').Text = "$($result.Data.Artifacts.Count) artifacts"
        $Window.FindName('ScanSignedCount').Text = "$signed"
        $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
        $Window.FindName('ScanStatusLabel').Text = "Loaded"
        $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightBlue

        Update-ScanProgress -Window $Window -Text "Loaded: $($selectedScan.ScanName)" -Percent 100
    }
    else {
        [System.Windows.MessageBox]::Show("Failed to load scan: $($result.Error)", 'Error', 'OK', 'Error')
    }
}

function Invoke-DeleteSelectedScan {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a saved scan to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedScan = $listBox.SelectedItem

    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete scan '$($selectedScan.ScanName)'?",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $scanPath = Join-Path (Get-AppLockerDataPath) 'Scans'
        $scanFile = Join-Path $scanPath "$($selectedScan.ScanId).json"
        
        if (Test-Path $scanFile) {
            Remove-Item -Path $scanFile -Force
            [System.Windows.MessageBox]::Show("Scan '$($selectedScan.ScanName)' deleted.", 'Deleted', 'OK', 'Information')
            Update-SavedScansList -Window $Window
        }
    }
}

function Invoke-ImportArtifacts {
    param([System.Windows.Window]$Window)

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Import Artifacts'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json|All Files (*.*)|*.*'
    $dialog.FilterIndex = 1

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            
            $artifacts = switch ($extension) {
                '.csv' { Import-Csv -Path $dialog.FileName }
                '.json' { Get-Content -Path $dialog.FileName -Raw | ConvertFrom-Json }
                default { throw "Unsupported file format: $extension" }
            }

            $script:CurrentScanArtifacts = $artifacts
            Update-ArtifactDataGrid -Window $Window

            # Update counters
            $signed = ($artifacts | Where-Object { $_.IsSigned }).Count
            $unsigned = $artifacts.Count - $signed
            $Window.FindName('ScanArtifactCount').Text = "$($artifacts.Count) artifacts"
            $Window.FindName('ScanSignedCount').Text = "$signed"
            $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
            $Window.FindName('ScanStatusLabel').Text = "Imported"
            $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

            [System.Windows.MessageBox]::Show(
                "Imported $($artifacts.Count) artifacts from file.",
                'Import Complete',
                'OK',
                'Information'
            )
        }
        catch {
            [System.Windows.MessageBox]::Show("Import failed: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-ExportArtifacts {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No artifacts to export. Run a scan first.', 'No Data', 'OK', 'Information')
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Artifacts'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json'
    $dialog.FilterIndex = 1
    $dialog.FileName = "Artifacts_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            
            switch ($extension) {
                '.csv' { $script:CurrentScanArtifacts | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8 }
                '.json' { $script:CurrentScanArtifacts | ConvertTo-Json -Depth 5 | Set-Content -Path $dialog.FileName -Encoding UTF8 }
            }

            [System.Windows.MessageBox]::Show(
                "Exported $($script:CurrentScanArtifacts.Count) artifacts to:`n$($dialog.FileName)",
                'Export Complete',
                'OK',
                'Information'
            )
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-BrowseScanPath {
    param([System.Windows.Window]$Window)

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Select a folder to scan'
    $dialog.ShowNewFolderButton = $false

    if ($dialog.ShowDialog() -eq 'OK') {
        $txtPaths = $Window.FindName('TxtScanPaths')
        if ($txtPaths) {
            if ([string]::IsNullOrWhiteSpace($txtPaths.Text)) {
                $txtPaths.Text = $dialog.SelectedPath
            }
            else {
                $txtPaths.Text += "`n$($dialog.SelectedPath)"
            }
        }
    }
}

function Invoke-SelectMachinesForScan {
    param([System.Windows.Window]$Window)

    # Use machines from Discovery panel
    if ($script:DiscoveredMachines.Count -eq 0) {
        $confirm = [System.Windows.MessageBox]::Show(
            "No machines discovered. Would you like to navigate to AD Discovery to scan for machines?",
            'No Machines',
            'YesNo',
            'Question'
        )

        if ($confirm -eq 'Yes') {
            Set-ActivePanel -PanelName 'PanelDiscovery'
        }
        return
    }

    # For now, use all discovered machines
    # TODO: Add a proper selection dialog
    $script:SelectedScanMachines = $script:DiscoveredMachines

    # Update the machine list display
    $machineList = $Window.FindName('ScanMachineList')
    $machineCount = $Window.FindName('ScanMachineCount')

    if ($machineList) {
        $machineList.ItemsSource = $script:SelectedScanMachines | Select-Object -ExpandProperty Hostname
    }

    if ($machineCount) {
        $machineCount.Text = "$($script:SelectedScanMachines.Count)"
    }

    # Enable remote scan checkbox
    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) { $chkRemote.IsChecked = $true }

    [System.Windows.MessageBox]::Show(
        "Selected $($script:SelectedScanMachines.Count) machines for scanning.",
        'Machines Selected',
        'OK',
        'Information'
    )
}

#endregion

#region ===== RULES PANEL HANDLERS =====

function Initialize-RulesPanel {
    param([System.Windows.Window]$Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllRules', 'BtnFilterPublisher', 'BtnFilterHash', 'BtnFilterPath',
        'BtnFilterPending', 'BtnFilterApproved', 'BtnFilterRejected'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterRules(.+)') {
                        $filter = $Matches[1]
                        Update-RulesFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnGenerateFromArtifacts', 'BtnCreateManualRule', 'BtnExportRulesXml', 'BtnExportRulesCsv',
        'BtnRefreshRules', 'BtnApproveRule', 'BtnRejectRule', 'BtnReviewRule',
        'BtnDeleteRule', 'BtnViewRuleDetails', 'BtnAddRuleToPolicy'
    )

    foreach ($btnName in $actionButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                    param($sender, $e)
                    Invoke-ButtonAction -Action $sender.Tag
                }.GetNewClosure())
        }
    }

    # Wire up text filter
    $filterBox = $Window.FindName('TxtRuleFilter')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
                Update-RulesDataGrid -Window $script:MainWindow
            })
    }

    # Wire up Select All checkbox
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    if ($selectAllChk) {
        $selectAllChk.Add_Checked({
                Invoke-SelectAllRules -Window $script:MainWindow -SelectAll $true
            })
        $selectAllChk.Add_Unchecked({
                Invoke-SelectAllRules -Window $script:MainWindow -SelectAll $false
            })
    }

    # Wire up DataGrid selection changed for count update
    $rulesGrid = $Window.FindName('RulesDataGrid')
    if ($rulesGrid) {
        $rulesGrid.Add_SelectionChanged({
                Update-RulesSelectionCount -Window $script:MainWindow
            })
    }

    # Initial load
    Update-RulesDataGrid -Window $Window
}

function script:Update-RulesDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }

    # Check if module function is available
    if (-not (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

    try {
        $result = Get-AllRules
        if (-not $result.Success) {
            $dataGrid.ItemsSource = $null
            return
        }

        $rules = $result.Data

        # Apply type filter
        if ($script:CurrentRulesTypeFilter -and $script:CurrentRulesTypeFilter -ne 'All') {
            $rules = $rules | Where-Object { $_.RuleType -eq $script:CurrentRulesTypeFilter }
        }

        # Apply status filter
        if ($script:CurrentRulesFilter -and $script:CurrentRulesFilter -notin @('All', 'Publisher', 'Hash', 'Path')) {
            $rules = $rules | Where-Object { $_.Status -eq $script:CurrentRulesFilter }
        }

        # Apply text filter
        $filterBox = $Window.FindName('TxtRuleFilter')
        if ($filterBox -and -not [string]::IsNullOrWhiteSpace($filterBox.Text)) {
            $filterText = $filterBox.Text.ToLower()
            $rules = $rules | Where-Object {
                $_.Name.ToLower().Contains($filterText) -or
                $_.CollectionType.ToLower().Contains($filterText) -or
                ($_.Description -and $_.Description.ToLower().Contains($filterText)) -or
                ($_.GroupName -and $_.GroupName.ToLower().Contains($filterText)) -or
                ($_.GroupVendor -and $_.GroupVendor.ToLower().Contains($filterText))
            }
        }

        # Add display properties and map rule properties for UI
        $displayData = $rules | ForEach-Object {
            $rule = $_
            $props = @{}
            $_.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            # Map properties for XAML bindings and UI compatibility
            $props['RuleId'] = $_.Id
            $props['Collection'] = $_.CollectionType
            $props['CreatedAt'] = $_.CreatedDate
            $props['ModifiedAt'] = $_.ModifiedDate
            $props['CreatedDisplay'] = if ($_.CreatedDate) { ([datetime]$_.CreatedDate).ToString('MM/dd HH:mm') } else { '' }
            [PSCustomObject]$props
        }

        $dataGrid.ItemsSource = @($displayData)

        # Update counters
        $allRules = (Get-AllRules).Data
        Update-RuleCounters -Window $Window -Rules $allRules
    }
    catch {
        Write-Log -Level Error -Message "Failed to update rules grid: $($_.Exception.Message)"
        $dataGrid.ItemsSource = $null
    }
}

function Update-RuleCounters {
    param(
        [System.Windows.Window]$Window,
        [array]$Rules
    )

    $total = if ($Rules) { $Rules.Count } else { 0 }
    $pending = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $approved = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Approved' }).Count } else { 0 }
    $rejected = if ($Rules) { ($Rules | Where-Object { $_.Status -eq 'Rejected' }).Count } else { 0 }

    $Window.FindName('TxtRuleTotalCount').Text = "$total"
    $Window.FindName('TxtRulePendingCount').Text = "$pending"
    $Window.FindName('TxtRuleApprovedCount').Text = "$approved"
    $Window.FindName('TxtRuleRejectedCount').Text = "$rejected"
}

function Update-RulesSelectionCount {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $countText = $Window.FindName('TxtSelectedRuleCount')
    $selectAllChk = $Window.FindName('ChkSelectAllRules')
    
    if (-not $dataGrid -or -not $countText) { return }
    
    $selectedCount = $dataGrid.SelectedItems.Count
    $totalCount = if ($dataGrid.ItemsSource) { @($dataGrid.ItemsSource).Count } else { 0 }
    
    $countText.Text = "$selectedCount"
    
    # Update Select All checkbox state (without triggering events)
    if ($selectAllChk) {
        $selectAllChk.IsChecked = ($selectedCount -gt 0 -and $selectedCount -eq $totalCount)
    }
}

function Invoke-SelectAllRules {
    param(
        [System.Windows.Window]$Window,
        [bool]$SelectAll = $true
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    if (-not $dataGrid) { return }
    
    if ($SelectAll) {
        $dataGrid.SelectAll()
    }
    else {
        $dataGrid.UnselectAll()
    }
    
    Update-RulesSelectionCount -Window $Window
}

function Invoke-AddSelectedRulesToPolicy {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = @($dataGrid.SelectedItems)

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to add to a policy.' -Type 'Warning'
        return
    }

    # Get available policies
    if (-not (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Policy functions not available.' -Type 'Error'
        return
    }

    $policiesResult = Get-AllPolicies
    if (-not $policiesResult.Success -or $policiesResult.Data.Count -eq 0) {
        Show-Toast -Message 'No policies available. Create a policy first.' -Type 'Warning'
        return
    }

    # Create selection dialog
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "Add $($selectedItems.Count) Rule(s) to Policy"
    $dialog.Width = 400
    $dialog.Height = 300
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Owner = $Window
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1E1E1E')
    $dialog.ResizeMode = 'NoResize'

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Margin = [System.Windows.Thickness]::new(20)

    # Label
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = "Select a policy to add the selected rules:"
    $label.Foreground = [System.Windows.Media.Brushes]::White
    $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 15)
    $stack.Children.Add($label)

    # Policy ListBox
    $listBox = [System.Windows.Controls.ListBox]::new()
    $listBox.Height = 150
    $listBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2D2D30')
    $listBox.Foreground = [System.Windows.Media.Brushes]::White
    $listBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $listBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')

    foreach ($policy in $policiesResult.Data) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content = "$($policy.Name) (Phase $($policy.Phase)) - $($policy.Status)"
        $item.Tag = $policy.Id
        $item.Foreground = [System.Windows.Media.Brushes]::White
        $listBox.Items.Add($item)
    }
    $stack.Children.Add($listBox)

    # Buttons
    $btnPanel = [System.Windows.Controls.StackPanel]::new()
    $btnPanel.Orientation = 'Horizontal'
    $btnPanel.HorizontalAlignment = 'Right'
    $btnPanel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)

    $btnAdd = [System.Windows.Controls.Button]::new()
    $btnAdd.Content = "Add Rules"
    $btnAdd.Width = 100
    $btnAdd.Height = 32
    $btnAdd.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
    $btnAdd.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4')
    $btnAdd.Foreground = [System.Windows.Media.Brushes]::White
    $btnAdd.BorderThickness = [System.Windows.Thickness]::new(0)

    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Height = 32
    $btnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
    $btnCancel.Foreground = [System.Windows.Media.Brushes]::White
    $btnCancel.BorderThickness = [System.Windows.Thickness]::new(0)

    $btnPanel.Children.Add($btnAdd)
    $btnPanel.Children.Add($btnCancel)
    $stack.Children.Add($btnPanel)

    $dialog.Content = $stack

    # Store references for closures
    $listBoxRef = $listBox
    $selectedRules = $selectedItems
    $dialogRef = $dialog
    $windowRef = $Window

    $btnAdd.Add_Click({
        if ($listBoxRef.SelectedItem) {
            $policyId = $listBoxRef.SelectedItem.Tag
            $addedCount = 0
            $errors = @()
            
            foreach ($rule in $selectedRules) {
                try {
                    $result = Add-RuleToPolicy -PolicyId $policyId -RuleId $rule.Id
                    if ($result.Success) { $addedCount++ }
                    else { $errors += $result.Error }
                }
                catch {
                    $errors += "Rule $($rule.Id): $($_.Exception.Message)"
                }
            }
            
            $dialogRef.DialogResult = $true
            $dialogRef.Close()
            
            if ($addedCount -gt 0) {
                Show-Toast -Message "Added $addedCount rule(s) to policy." -Type 'Success'
            }
            if ($errors.Count -gt 0) {
                Show-Toast -Message "Some rules could not be added: $($errors.Count) error(s)" -Type 'Warning'
                Write-Log -Level Warning -Message "Errors adding rules: $($errors -join '; ')"
            }
        }
        else {
            Show-Toast -Message 'Please select a policy.' -Type 'Warning'
        }
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $dialogRef.DialogResult = $false
        $dialogRef.Close()
    }.GetNewClosure())

    $dialog.ShowDialog()
}

function global:Update-RulesFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    # Type filters
    if ($Filter -in @('All', 'Publisher', 'Hash', 'Path')) {
        $script:CurrentRulesTypeFilter = $Filter
        if ($Filter -eq 'All') { $script:CurrentRulesFilter = 'All' }
    }
    # Status filters
    elseif ($Filter -in @('Pending', 'Approved', 'Rejected', 'Review')) {
        $script:CurrentRulesFilter = $Filter
    }

    Update-RulesDataGrid -Window $Window
}

function Invoke-GenerateRulesFromArtifacts {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message 'No artifacts loaded. Please run a scan or load saved scan results first.' -Type 'Warning'
        return
    }

    if (-not (Get-Command -Name 'ConvertFrom-Artifact' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Rules module not loaded.' -Type 'Error'
        return
    }

    # Get options
    $collection = $Window.FindName('TxtRuleCollectionName').Text
    if ([string]::IsNullOrWhiteSpace($collection)) { $collection = 'Default' }

    $modeCombo = $Window.FindName('CboRuleGenMode')
    $modeIndex = $modeCombo.SelectedIndex

    $mode = switch ($modeIndex) {
        0 { 'Smart' }
        1 { 'Publisher' }
        2 { 'Hash' }
        3 { 'Path' }
        default { 'Smart' }
    }

    $action = if ($Window.FindName('RbRuleAllow').IsChecked) { 'Allow' } else { 'Deny' }

    # Get target group SID
    $targetGroupCombo = $Window.FindName('CboRuleTargetGroup')
    $targetGroupSid = if ($targetGroupCombo -and $targetGroupCombo.SelectedItem) {
        $targetGroupCombo.SelectedItem.Tag
    }
    else {
        'S-1-1-0'  # Everyone
    }

    # Generate rules
    $generated = 0
    $failed = 0

    foreach ($artifact in $script:CurrentScanArtifacts) {
        try {
            $ruleType = switch ($mode) {
                'Smart' { if ($artifact.IsSigned) { 'Publisher' } else { 'Hash' } }
                'Publisher' { if ($artifact.IsSigned) { 'Publisher' } else { $null } }
                'Hash' { 'Hash' }
                'Path' { 'Path' }
            }

            if (-not $ruleType) { continue }

            $result = ConvertFrom-Artifact -Artifact $artifact -PreferredRuleType $ruleType -Action $action -UserOrGroupSid $targetGroupSid -Save
            if ($result.Success) { $generated++ } else { $failed++ }
        }
        catch {
            $failed++
        }
    }

    Update-RulesDataGrid -Window $Window
    Update-WorkflowBreadcrumb -Window $Window

    if ($generated -gt 0) {
        Show-Toast -Message "Generated $generated rule(s) from $($script:CurrentScanArtifacts.Count) artifacts." -Type 'Success'
    }
    if ($failed -gt 0) {
        Show-Toast -Message "$failed artifact(s) failed to generate rules." -Type 'Warning'
    }
}

function Invoke-CreateManualRule {
    param([System.Windows.Window]$Window)

    $typeCombo = $Window.FindName('CboManualRuleType')
    $value = $Window.FindName('TxtManualRuleValue').Text
    $desc = $Window.FindName('TxtManualRuleDesc').Text
    $action = if ($Window.FindName('RbRuleAllow').IsChecked) { 'Allow' } else { 'Deny' }

    # Get target group SID
    $targetGroupCombo = $Window.FindName('CboManualRuleTargetGroup')
    $targetGroupSid = if ($targetGroupCombo -and $targetGroupCombo.SelectedItem) {
        $targetGroupCombo.SelectedItem.Tag
    }
    else {
        'S-1-1-0'  # Everyone
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        Show-Toast -Message 'Please enter a path, hash, or publisher value.' -Type 'Warning'
        return
    }

    $ruleType = switch ($typeCombo.SelectedIndex) {
        0 { 'Path' }
        1 { 'Hash' }
        2 { 'Publisher' }
        default { 'Path' }
    }

    try {
        $result = switch ($ruleType) {
            'Path' {
                if (-not (Get-Command -Name 'New-PathRule' -ErrorAction SilentlyContinue)) { throw 'New-PathRule not available' }
                New-PathRule -Path $value -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
            'Hash' {
                if (-not (Get-Command -Name 'New-HashRule' -ErrorAction SilentlyContinue)) { throw 'New-HashRule not available' }
                New-HashRule -Hash $value -SourceFileName 'Manual' -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
            'Publisher' {
                if (-not (Get-Command -Name 'New-PublisherRule' -ErrorAction SilentlyContinue)) { throw 'New-PublisherRule not available' }
                $parts = $value -split ','
                $pubName = $parts[0].Trim()
                $prodName = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '*' }
                New-PublisherRule -PublisherName $pubName -ProductName $prodName -Action $action -Description $desc -CollectionType 'Exe' -UserOrGroupSid $targetGroupSid -Save
            }
        }

        if ($result.Success) {
            $Window.FindName('TxtManualRuleValue').Text = ''
            $Window.FindName('TxtManualRuleDesc').Text = ''
            Update-RulesDataGrid -Window $Window
            Show-Toast -Message "$ruleType rule created successfully." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to create rule: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error creating rule: $($_.Exception.Message)" -Type 'Error'
    }
}

function Set-SelectedRuleStatus {
    param(
        [System.Windows.Window]$Window,
        [string]$Status
    )

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = $dataGrid.SelectedItems

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules.' -Type 'Warning'
        return
    }

    if (-not (Get-Command -Name 'Set-RuleStatus' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Set-RuleStatus function not available.' -Type 'Error'
        return
    }

    $updated = 0
    $errors = @()
    foreach ($item in $selectedItems) {
        try {
            $result = Set-RuleStatus -Id $item.Id -Status $Status
            if ($result.Success) { $updated++ }
        }
        catch { 
            $errors += "Rule $($item.Id): $($_.Exception.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        Write-AppLockerLog -Level Warning -Message "Errors updating rules: $($errors -join '; ')" -NoConsole
    }

    Update-RulesDataGrid -Window $Window
    Update-RulesSelectionCount -Window $Window
    
    if ($updated -gt 0) {
        Show-Toast -Message "Updated $updated rule(s) to '$Status'." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Show-Toast -Message "$($errors.Count) rule(s) failed to update." -Type 'Warning'
    }
}

function Invoke-DeleteSelectedRules {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItems = $dataGrid.SelectedItems

    if ($selectedItems.Count -eq 0) {
        Show-Toast -Message 'Please select one or more rules to delete.' -Type 'Warning'
        return
    }

    # Use MessageBox for confirmation (requires blocking user interaction)
    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete $($selectedItems.Count) rule(s)?`n`nThis action cannot be undone.",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    if (-not (Get-Command -Name 'Remove-Rule' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Remove-Rule function not available.' -Type 'Error'
        return
    }

    $deleted = 0
    $errors = @()
    foreach ($item in $selectedItems) {
        try {
            $result = Remove-Rule -Id $item.Id
            if ($result.Success) { $deleted++ }
        }
        catch { 
            $errors += "Rule $($item.Id): $($_.Exception.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        Write-AppLockerLog -Level Warning -Message "Errors deleting rules: $($errors -join '; ')" -NoConsole
    }

    Update-RulesDataGrid -Window $Window
    Update-RulesSelectionCount -Window $Window
    
    if ($deleted -gt 0) {
        Show-Toast -Message "Deleted $deleted rule(s)." -Type 'Success'
    }
    if ($errors.Count -gt 0) {
        Show-Toast -Message "$($errors.Count) rule(s) failed to delete." -Type 'Warning'
    }
}

function Invoke-ExportRulesToXml {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Export-RulesToXml' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Export-RulesToXml function not available.' -Type 'Error'
        return
    }

    $approvedOnly = $Window.FindName('ChkExportApprovedOnly').IsChecked

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export AppLocker Rules'
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.FileName = "AppLockerRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            # IncludeAllStatuses is the inverse of "approved only"
            # If checkbox is checked (approved only), don't include all statuses
            # If checkbox is unchecked, include all statuses
            if ($approvedOnly) {
                $result = Export-RulesToXml -OutputPath $dialog.FileName
            }
            else {
                $result = Export-RulesToXml -OutputPath $dialog.FileName -IncludeAllStatuses
            }
            
            if ($result.Success) {
                Show-Toast -Message "Exported $($result.Data.RuleCount) rule(s) to XML." -Type 'Success'
            }
            else {
                Show-Toast -Message "Export failed: $($result.Error)" -Type 'Error'
            }
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function Invoke-ExportRulesToCsv {
    param([System.Windows.Window]$Window)

    if (-not (Get-Command -Name 'Get-AllRules' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Get-AllRules function not available.' -Type 'Error'
        return
    }

    $approvedOnly = $Window.FindName('ChkExportApprovedOnly').IsChecked

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Rules to CSV'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv'
    $dialog.FileName = "AppLockerRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $result = Get-AllRules
            
            if ($result.Success) {
                $rules = $result.Data
                if ($approvedOnly) {
                    $rules = $rules | Where-Object { $_.Status -eq 'Approved' }
                }
                
                $rules | Select-Object Id, Name, RuleType, CollectionType, Action, Status, CreatedDate | 
                Export-Csv -Path $dialog.FileName -NoTypeInformation
                
                Show-Toast -Message "Exported $($rules.Count) rule(s) to CSV." -Type 'Success'
            }
            else {
                Show-Toast -Message "Export failed: $($result.Error)" -Type 'Error'
            }
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function Show-RuleDetails {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('RulesDataGrid')
    $selectedItem = $dataGrid.SelectedItem

    if (-not $selectedItem) {
        Show-Toast -Message 'Please select a rule to view details.' -Type 'Warning'
        return
    }

    $details = @"
Rule Details
============

ID: $($selectedItem.RuleId)
Name: $($selectedItem.Name)
Type: $($selectedItem.RuleType)
Action: $($selectedItem.Action)
Status: $($selectedItem.Status)
Collection: $($selectedItem.Collection)
Rule Collection: $($selectedItem.RuleCollection)

Description:
$($selectedItem.Description)

Created: $($selectedItem.CreatedAt)
Modified: $($selectedItem.ModifiedAt)

Condition Data:
$($selectedItem | Select-Object -Property Publisher*, Hash*, Path* | Format-List | Out-String)
"@

    [System.Windows.MessageBox]::Show($details.Trim(), 'Rule Details', 'OK', 'Information')
}

#endregion

#region ===== POLICY PANEL HANDLERS =====

function Initialize-PolicyPanel {
    param([System.Windows.Window]$Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllPolicies', 'BtnFilterDraft', 'BtnFilterActive', 
        'BtnFilterDeployed', 'BtnFilterArchived'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterPolicies(.+)') {
                        $filter = $Matches[1]
                        Update-PoliciesFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreatePolicy', 'BtnRefreshPolicies', 'BtnActivatePolicy', 
        'BtnArchivePolicy', 'BtnExportPolicy', 'BtnDeletePolicy', 'BtnDeployPolicy',
        'BtnAddRulesToPolicy', 'BtnRemoveRulesFromPolicy', 'BtnSelectTargetOUs', 'BtnSaveTargets'
    )

    foreach ($btnName in $actionButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                    param($sender, $e)
                    Invoke-ButtonAction -Action $sender.Tag
                }.GetNewClosure())
        }
    }

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                Update-SelectedPolicyInfo -Window $script:MainWindow
            })
    }

    # Initial load
    Update-PoliciesDataGrid -Window $Window
}

function script:Update-PoliciesDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    if (-not $dataGrid) { return }

    if (-not (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

    try {
        $result = Get-AllPolicies
        if (-not $result.Success) {
            $dataGrid.ItemsSource = $null
            return
        }

        $policies = $result.Data

        # Apply status filter
        if ($script:CurrentPoliciesFilter -and $script:CurrentPoliciesFilter -ne 'All') {
            $policies = $policies | Where-Object { $_.Status -eq $script:CurrentPoliciesFilter }
        }

        # Apply text filter
        $filterBox = $Window.FindName('TxtPolicyFilter')
        if ($filterBox -and -not [string]::IsNullOrWhiteSpace($filterBox.Text)) {
            $filterText = $filterBox.Text.ToLower()
            $policies = $policies | Where-Object {
                $_.Name.ToLower().Contains($filterText) -or
                ($_.Description -and $_.Description.ToLower().Contains($filterText))
            }
        }

        # Add display properties
        $displayData = $policies | ForEach-Object {
            $policy = $_
            $props = @{}
            $_.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            $props['RuleCount'] = if ($_.RuleIds) { $_.RuleIds.Count } else { 0 }
            [PSCustomObject]$props
        }

        $dataGrid.ItemsSource = @($displayData)

        # Update counters
        $allPolicies = (Get-AllPolicies).Data
        Update-PolicyCounters -Window $Window -Policies $allPolicies
    }
    catch {
        Write-Log -Level Error -Message "Failed to update policies grid: $($_.Exception.Message)"
        $dataGrid.ItemsSource = $null
    }
}

function Update-PolicyCounters {
    param(
        [System.Windows.Window]$Window,
        [array]$Policies
    )

    $total = if ($Policies) { $Policies.Count } else { 0 }
    $draft = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Draft' }).Count } else { 0 }
    $active = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Active' }).Count } else { 0 }
    $deployed = if ($Policies) { ($Policies | Where-Object { $_.Status -eq 'Deployed' }).Count } else { 0 }

    $Window.FindName('TxtPolicyTotalCount').Text = "$total"
    $Window.FindName('TxtPolicyDraftCount').Text = "$draft"
    $Window.FindName('TxtPolicyActiveCount').Text = "$active"
    $Window.FindName('TxtPolicyDeployedCount').Text = "$deployed"
}

function global:Update-PoliciesFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    $script:CurrentPoliciesFilter = $Filter
    Update-PoliciesDataGrid -Window $Window
}

function Update-SelectedPolicyInfo {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('PoliciesDataGrid')
    $selectedItem = $dataGrid.SelectedItem

    if ($selectedItem) {
        $script:SelectedPolicyId = $selectedItem.PolicyId
        $Window.FindName('TxtSelectedPolicyName').Text = $selectedItem.Name
        $Window.FindName('TxtSelectedPolicyName').FontStyle = 'Normal'
        $Window.FindName('TxtSelectedPolicyName').Foreground = [System.Windows.Media.Brushes]::White
        $ruleCount = if ($selectedItem.RuleIds) { $selectedItem.RuleIds.Count } else { 0 }
        $Window.FindName('TxtPolicyRuleCount').Text = "$ruleCount rules"

        # Update target fields
        $Window.FindName('TxtTargetGPO').Text = if ($selectedItem.TargetGPO) { $selectedItem.TargetGPO } else { '' }
        $Window.FindName('PolicyTargetOUsList').ItemsSource = if ($selectedItem.TargetOUs) { $selectedItem.TargetOUs } else { @() }
    }
    else {
        $script:SelectedPolicyId = $null
        $Window.FindName('TxtSelectedPolicyName').Text = '(Select a policy)'
        $Window.FindName('TxtSelectedPolicyName').FontStyle = 'Italic'
        $Window.FindName('TxtSelectedPolicyName').Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(158, 158, 158))
        $Window.FindName('TxtPolicyRuleCount').Text = '0 rules'
        $Window.FindName('TxtTargetGPO').Text = ''
        $Window.FindName('PolicyTargetOUsList').ItemsSource = $null
    }
}

function Invoke-CreatePolicy {
    param([System.Windows.Window]$Window)

    $name = $Window.FindName('TxtPolicyName').Text
    $description = $Window.FindName('TxtPolicyDescription').Text

    if ([string]::IsNullOrWhiteSpace($name)) {
        Show-Toast -Message 'Please enter a policy name.' -Type 'Warning'
        return
    }

    $enforcementCombo = $Window.FindName('CboPolicyEnforcement')
    $enforcement = switch ($enforcementCombo.SelectedIndex) {
        0 { 'AuditOnly' }
        1 { 'Enabled' }
        2 { 'NotConfigured' }
        default { 'AuditOnly' }
    }

    # Get deployment phase from ComboBox
    $phaseCombo = $Window.FindName('CboPolicyPhase')
    $selectedPhaseItem = $phaseCombo.SelectedItem
    $phase = if ($selectedPhaseItem -and $selectedPhaseItem.Tag) {
        [int]$selectedPhaseItem.Tag
    } else {
        1  # Default to Phase 1
    }

    try {
        $result = New-Policy -Name $name -Description $description -EnforcementMode $enforcement -Phase $phase
        
        if ($result.Success) {
            $Window.FindName('TxtPolicyName').Text = ''
            $Window.FindName('TxtPolicyDescription').Text = ''
            $Window.FindName('CboPolicyPhase').SelectedIndex = 0  # Reset to Phase 1
            Update-PoliciesDataGrid -Window $Window
            Update-WorkflowBreadcrumb -Window $Window
            Show-Toast -Message "Policy '$name' created successfully (Phase $phase)." -Type 'Success'
        }
        else {
            Show-Toast -Message "Failed to create policy: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Set-SelectedPolicyStatus {
    param(
        [System.Windows.Window]$Window,
        [string]$Status
    )

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy.', 'No Selection', 'OK', 'Information')
        return
    }

    try {
        $result = Set-PolicyStatus -PolicyId $script:SelectedPolicyId -Status $Status
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            [System.Windows.MessageBox]::Show("Policy status updated to '$Status'.", 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-DeleteSelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Are you sure you want to delete this policy?',
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    try {
        $result = Remove-Policy -PolicyId $script:SelectedPolicyId -Force
        
        if ($result.Success) {
            $script:SelectedPolicyId = $null
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show('Policy deleted.', 'Deleted', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-ExportSelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to export.', 'No Selection', 'OK', 'Information')
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Policy to XML'
    $dialog.Filter = 'XML Files (*.xml)|*.xml'
    $dialog.FileName = "AppLockerPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $result = Export-PolicyToXml -PolicyId $script:SelectedPolicyId -OutputPath $dialog.FileName
            
            if ($result.Success) {
                [System.Windows.MessageBox]::Show(
                    "Exported policy to:`n$($dialog.FileName)`n`nRules: $($result.Data.RuleCount)",
                    'Export Complete',
                    'OK',
                    'Information'
                )
            }
            else {
                [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-DeploySelectedPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy to deploy.', 'No Selection', 'OK', 'Information')
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) {
        [System.Windows.MessageBox]::Show("Could not load policy: $($policyResult.Error)", 'Error', 'OK', 'Error')
        return
    }

    $policy = $policyResult.Data

    if (-not $policy.TargetGPO) {
        [System.Windows.MessageBox]::Show('Please set a Target GPO before deploying.', 'Missing Target', 'OK', 'Warning')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Deploy policy '$($policy.Name)' to GPO '$($policy.TargetGPO)'?`n`nThis will navigate to the Deployment panel.",
        'Confirm Deploy',
        'YesNo',
        'Question'
    )

    if ($confirm -eq 'Yes') {
        # Set status to deployed and navigate to deploy panel
        Set-PolicyStatus -PolicyId $script:SelectedPolicyId -Status 'Deployed' | Out-Null
        Update-PoliciesDataGrid -Window $Window
        Set-ActivePanel -PanelName 'PanelDeploy'
    }
}

function Invoke-AddRulesToPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    # Get all approved rules not in this policy
    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $currentRuleIds = @($policy.RuleIds)

    $rulesResult = Get-AllRules
    if (-not $rulesResult.Success) { return }

    $availableRules = $rulesResult.Data | Where-Object { 
        $_.Status -eq 'Approved' -and $_.Id -notin $currentRuleIds 
    }

    if ($availableRules.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No approved rules available to add.', 'No Rules', 'OK', 'Information')
        return
    }

    # For now, add all approved rules
    $confirm = [System.Windows.MessageBox]::Show(
        "Add $($availableRules.Count) approved rule(s) to this policy?",
        'Add Rules',
        'YesNo',
        'Question'
    )

    if ($confirm -eq 'Yes') {
        $ruleIds = $availableRules | Select-Object -ExpandProperty Id
        $result = Add-RuleToPolicy -PolicyId $script:SelectedPolicyId -RuleId $ruleIds
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show($result.Message, 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-RemoveRulesFromPolicy {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    $policyResult = Get-Policy -PolicyId $script:SelectedPolicyId
    if (-not $policyResult.Success) { return }
    
    $policy = $policyResult.Data
    $ruleCount = if ($policy.RuleIds) { $policy.RuleIds.Count } else { 0 }

    if ($ruleCount -eq 0) {
        [System.Windows.MessageBox]::Show('This policy has no rules to remove.', 'No Rules', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Remove all $ruleCount rule(s) from this policy?",
        'Remove Rules',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $result = Remove-RuleFromPolicy -PolicyId $script:SelectedPolicyId -RuleId $policy.RuleIds
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            Update-SelectedPolicyInfo -Window $Window
            [System.Windows.MessageBox]::Show($result.Message, 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-SelectTargetOUs {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    # Use discovered OUs from Discovery panel
    if ($script:DiscoveredOUs.Count -eq 0) {
        $confirm = [System.Windows.MessageBox]::Show(
            "No OUs discovered. Navigate to AD Discovery to scan for OUs?",
            'No OUs',
            'YesNo',
            'Question'
        )

        if ($confirm -eq 'Yes') {
            Set-ActivePanel -PanelName 'PanelDiscovery'
        }
        return
    }

    # For now, use all discovered OUs
    $ouList = $Window.FindName('PolicyTargetOUsList')
    $ouList.ItemsSource = $script:DiscoveredOUs | Select-Object -ExpandProperty DistinguishedName

    [System.Windows.MessageBox]::Show(
        "Added $($script:DiscoveredOUs.Count) OUs to target list.`nClick 'Save Targets' to apply.",
        'OUs Selected',
        'OK',
        'Information'
    )
}

function Invoke-SavePolicyTargets {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedPolicyId) {
        [System.Windows.MessageBox]::Show('Please select a policy first.', 'No Selection', 'OK', 'Information')
        return
    }

    $targetGPO = $Window.FindName('TxtTargetGPO').Text
    $targetOUs = @($Window.FindName('PolicyTargetOUsList').ItemsSource)

    try {
        $result = Set-PolicyTarget -PolicyId $script:SelectedPolicyId -TargetOUs $targetOUs -TargetGPO $targetGPO
        
        if ($result.Success) {
            Update-PoliciesDataGrid -Window $Window
            [System.Windows.MessageBox]::Show('Policy targets saved.', 'Success', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== DEPLOYMENT PANEL HANDLERS =====

function Initialize-DeploymentPanel {
    param([System.Windows.Window]$Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllJobs', 'BtnFilterPendingJobs', 'BtnFilterRunningJobs',
        'BtnFilterCompletedJobs', 'BtnFilterFailedJobs'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterJobs(.+)') {
                        $filter = $Matches[1]
                        Update-DeploymentFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreateDeployment', 'BtnRefreshDeployments', 'BtnDeployJob',
        'BtnStopDeployment', 'BtnCancelSelected', 'BtnViewDeployLog'
    )

    foreach ($btnName in $actionButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                    param($sender, $e)
                    Invoke-ButtonAction -Action $sender.Tag
                }.GetNewClosure())
        }
    }

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                Update-SelectedJobInfo -Window $script:MainWindow
            })
    }

    # Load policies into combo box
    $policyCombo = $Window.FindName('CboDeployPolicy')
    if ($policyCombo -and (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        $result = Get-AllPolicies -Status 'Active'
        if ($result.Success -and $result.Data) {
            $policyCombo.ItemsSource = $result.Data
        }
    }

    # Wire up GPO dropdown to show/hide custom textbox
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    if ($gpoCombo -and $customGpoBox) {
        $gpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $script:MainWindow.FindName('TxtDeployCustomGPO')
                if ($customBox) {
                    if ($selectedItem -and $selectedItem.Tag -eq 'Custom') {
                        $customBox.Visibility = 'Visible'
                    }
                    else {
                        $customBox.Visibility = 'Collapsed'
                    }
                }
            })
    }

    # Check module status
    Update-ModuleStatus -Window $Window

    # Initial load
    Update-DeploymentJobsDataGrid -Window $Window
}

function Update-ModuleStatus {
    param([System.Windows.Window]$Window)

    $gpStatus = $Window.FindName('TxtGPModuleStatus')
    $alStatus = $Window.FindName('TxtALModuleStatus')

    if ($gpStatus) {
        $hasGP = Get-Module -ListAvailable -Name GroupPolicy
        $gpStatus.Text = if ($hasGP) { 'Available' } else { 'Not Installed' }
        $gpStatus.Foreground = if ($hasGP) { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(129, 199, 132))
        }
        else { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(229, 115, 115))
        }
    }

    if ($alStatus) {
        $hasAL = Get-Command -Name 'Set-AppLockerPolicy' -ErrorAction SilentlyContinue
        $alStatus.Text = if ($hasAL) { 'Available' } else { 'Not Available' }
        $alStatus.Foreground = if ($hasAL) { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(129, 199, 132))
        }
        else { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 213, 79))
        }
    }
}

function script:Update-DeploymentJobsDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if (-not $dataGrid) { return }

    if (-not (Get-Command -Name 'Get-AllDeploymentJobs' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

    try {
        $result = Get-AllDeploymentJobs
        if (-not $result.Success) {
            $dataGrid.ItemsSource = $null
            return
        }

        $jobs = $result.Data

        # Apply filter
        if ($script:CurrentDeploymentFilter -and $script:CurrentDeploymentFilter -ne 'All') {
            $jobs = $jobs | Where-Object { $_.Status -eq $script:CurrentDeploymentFilter }
        }

        # Add display properties
        $displayData = $jobs | ForEach-Object {
            $job = $_
            $props = @{}
            $_.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            $props['ProgressDisplay'] = "$($_.Progress)%"
            $props['CreatedDisplay'] = if ($_.CreatedAt) { ([datetime]$_.CreatedAt).ToString('MM/dd HH:mm') } else { '' }
            [PSCustomObject]$props
        }

        $dataGrid.ItemsSource = @($displayData)

        # Update counters
        $allJobs = (Get-AllDeploymentJobs).Data
        Update-JobCounters -Window $Window -Jobs $allJobs
    }
    catch {
        Write-Log -Level Error -Message "Failed to update deployment grid: $($_.Exception.Message)"
        $dataGrid.ItemsSource = $null
    }
}

function Update-JobCounters {
    param(
        [System.Windows.Window]$Window,
        [array]$Jobs
    )

    $total = if ($Jobs) { $Jobs.Count } else { 0 }
    $pending = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $running = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Running' }).Count } else { 0 }
    $completed = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Completed' }).Count } else { 0 }

    $Window.FindName('TxtJobTotalCount').Text = "$total"
    $Window.FindName('TxtJobPendingCount').Text = "$pending"
    $Window.FindName('TxtJobRunningCount').Text = "$running"
    $Window.FindName('TxtJobCompletedCount').Text = "$completed"
}

function script:Update-DeploymentFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    $script:CurrentDeploymentFilter = $Filter
    Update-DeploymentJobsDataGrid -Window $Window
}

function Update-SelectedJobInfo {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    $selectedItem = $dataGrid.SelectedItem
    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($selectedItem) {
        $script:SelectedDeploymentJobId = $selectedItem.JobId
        $messageBox.Text = $selectedItem.Message
        $progressBar.Value = $selectedItem.Progress
    }
    else {
        $script:SelectedDeploymentJobId = $null
        $messageBox.Text = 'Select a deployment job to view details'
        $progressBar.Value = 0
    }
}

function Invoke-CreateDeploymentJob {
    param([System.Windows.Window]$Window)

    $policyCombo = $Window.FindName('CboDeployPolicy')
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    $scheduleCombo = $Window.FindName('CboDeploySchedule')

    if (-not $policyCombo.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a policy to deploy.', 'Missing Policy', 'OK', 'Warning')
        return
    }

    # Get GPO name from dropdown or custom textbox
    $selectedGpo = $gpoCombo.SelectedItem
    $gpoName = if ($selectedGpo -and $selectedGpo.Tag -eq 'Custom') {
        $customGpoBox.Text
    }
    elseif ($selectedGpo) {
        $selectedGpo.Tag
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($gpoName)) {
        [System.Windows.MessageBox]::Show('Please select or enter a target GPO name.', 'Missing GPO', 'OK', 'Warning')
        return
    }

    $schedule = switch ($scheduleCombo.SelectedIndex) {
        0 { 'Manual' }
        1 { 'Immediate' }
        2 { 'Scheduled' }
        default { 'Manual' }
    }

    try {
        $policy = $policyCombo.SelectedItem
        $result = New-DeploymentJob -PolicyId $policy.PolicyId -GPOName $gpoName -Schedule $schedule

        if ($result.Success) {
            # Reset custom GPO box if used
            if ($customGpoBox) { $customGpoBox.Text = '' }
            Update-DeploymentJobsDataGrid -Window $Window
            [System.Windows.MessageBox]::Show(
                "Deployment job created for policy '$($policy.Name)'.`nTarget GPO: $gpoName",
                'Success',
                'OK',
                'Information'
            )
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-DeploySelectedJob {
    param([System.Windows.Window]$Window)

    if ($script:DeploymentInProgress) {
        Show-Toast -Message 'A deployment is already in progress.' -Type 'Warning'
        return
    }

    if (-not $script:SelectedDeploymentJobId) {
        Show-Toast -Message 'Please select a deployment job.' -Type 'Warning'
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Start deployment now? This will apply the policy to the target GPO.',
        'Confirm Deployment',
        'YesNo',
        'Question'
    )

    if ($confirm -ne 'Yes') { return }

    # Update UI state
    $script:DeploymentInProgress = $true
    $script:DeploymentCancelled = $false
    Update-DeploymentUIState -Window $Window -Deploying $true
    Update-DeploymentProgress -Window $Window -Text 'Initializing deployment...' -Percent 5

    # Create synchronized hashtable for cross-thread communication
    $script:DeploySyncHash = [hashtable]::Synchronized(@{
        Window     = $Window
        JobId      = $script:SelectedDeploymentJobId
        Result     = $null
        Error      = $null
        IsComplete = $false
        Progress   = 10
        StatusText = 'Loading modules...'
    })

    # Create and configure runspace
    $script:DeployRunspace = [runspacefactory]::CreateRunspace()
    $script:DeployRunspace.ApartmentState = 'STA'
    $script:DeployRunspace.ThreadOptions = 'ReuseThread'
    $script:DeployRunspace.Open()
    $script:DeployRunspace.SessionStateProxy.SetVariable('SyncHash', $script:DeploySyncHash)

    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:DeployRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:DeployPowerShell = [powershell]::Create()
    $script:DeployPowerShell.Runspace = $script:DeployRunspace

    [void]$script:DeployPowerShell.AddScript({
        param($SyncHash, $ModulePath)
        
        try {
            # Import the module in this runspace
            $SyncHash.StatusText = 'Loading modules...'
            $SyncHash.Progress = 15
            
            $manifestPath = Join-Path $ModulePath 'GA-AppLocker.psd1'
            if (Test-Path $manifestPath) {
                Import-Module $manifestPath -Force -ErrorAction Stop
            }
            else {
                throw "Module not found at: $manifestPath"
            }
            
            $SyncHash.StatusText = 'Executing deployment...'
            $SyncHash.Progress = 30
            
            # Execute the deployment
            $result = Start-Deployment -JobId $SyncHash.JobId
            
            $SyncHash.Progress = 90
            $SyncHash.StatusText = 'Finalizing...'
            $SyncHash.Result = $result
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
            $SyncHash.Progress = 100
        }
    })

    [void]$script:DeployPowerShell.AddArgument($script:DeploySyncHash)
    [void]$script:DeployPowerShell.AddArgument($modulePath)

    # Start async execution
    $script:DeployAsyncResult = $script:DeployPowerShell.BeginInvoke()

    # Create DispatcherTimer to poll for completion and update UI
    $script:DeployTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DeployTimer.Interval = [TimeSpan]::FromMilliseconds(200)

    $script:DeployTimer.Add_Tick({
        $syncHash = $script:DeploySyncHash
        $win = $syncHash.Window

        # Update progress
        Update-DeploymentProgress -Window $win -Text $syncHash.StatusText -Percent $syncHash.Progress

        # Check if cancelled
        if ($script:DeploymentCancelled) {
            $script:DeployTimer.Stop()

            # Clean up runspace
            if ($script:DeployPowerShell) {
                $script:DeployPowerShell.Stop()
                $script:DeployPowerShell.Dispose()
            }
            if ($script:DeployRunspace) {
                $script:DeployRunspace.Close()
                $script:DeployRunspace.Dispose()
            }

            $script:DeploymentInProgress = $false
            Update-DeploymentUIState -Window $win -Deploying $false
            Update-DeploymentProgress -Window $win -Text 'Deployment cancelled' -Percent 0
            Show-Toast -Message 'Deployment cancelled.' -Type 'Warning'
            return
        }

        # Check if complete
        if ($syncHash.IsComplete) {
            $script:DeployTimer.Stop()

            # End the async operation
            try {
                $script:DeployPowerShell.EndInvoke($script:DeployAsyncResult)
            }
            catch { }

            # Clean up runspace
            if ($script:DeployPowerShell) { $script:DeployPowerShell.Dispose() }
            if ($script:DeployRunspace) {
                $script:DeployRunspace.Close()
                $script:DeployRunspace.Dispose()
            }

            $script:DeploymentInProgress = $false
            Update-DeploymentUIState -Window $win -Deploying $false
            Update-DeploymentJobsDataGrid -Window $win

            if ($syncHash.Error) {
                Update-DeploymentProgress -Window $win -Text "Error: $($syncHash.Error)" -Percent 0
                Show-Toast -Message "Deployment error: $($syncHash.Error)" -Type 'Error'
            }
            elseif ($syncHash.Result -and $syncHash.Result.Success) {
                Update-DeploymentProgress -Window $win -Text 'Deployment complete' -Percent 100
                $successMsg = if ($syncHash.Result.Message) { $syncHash.Result.Message } else { 'Deployment completed successfully.' }
                Show-Toast -Message $successMsg -Type 'Success'
            }
            else {
                $errorMsg = if ($syncHash.Result) { $syncHash.Result.Error } else { 'Unknown error' }
                Update-DeploymentProgress -Window $win -Text "Failed: $errorMsg" -Percent 0
                Show-Toast -Message "Deployment failed: $errorMsg" -Type 'Error'
            }
        }
    })

    # Start the timer
    $script:DeployTimer.Start()
}

function Invoke-StopDeployment {
    param([System.Windows.Window]$Window)

    if (-not $script:DeploymentInProgress) {
        Show-Toast -Message 'No deployment in progress.' -Type 'Info'
        return
    }

    # Signal cancellation - the timer tick handler will clean up
    $script:DeploymentCancelled = $true
}

function Update-DeploymentUIState {
    param(
        [System.Windows.Window]$Window,
        [bool]$Deploying
    )

    $btnDeploy = $Window.FindName('BtnDeployJob')
    $btnStop = $Window.FindName('BtnStopDeployment')

    if ($btnDeploy) { $btnDeploy.IsEnabled = -not $Deploying }
    if ($btnStop) { $btnStop.IsEnabled = $Deploying }
}

function Update-DeploymentProgress {
    param(
        [System.Windows.Window]$Window,
        [string]$Text,
        [int]$Percent
    )

    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($messageBox) { $messageBox.Text = $Text }
    if ($progressBar) { $progressBar.Value = $Percent }
}

function Invoke-CancelDeploymentJob {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedDeploymentJobId) {
        [System.Windows.MessageBox]::Show('Please select a deployment job to cancel.', 'No Selection', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Cancel this deployment job?',
        'Confirm Cancel',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    try {
        $result = Stop-Deployment -JobId $script:SelectedDeploymentJobId

        if ($result.Success) {
            Update-DeploymentJobsDataGrid -Window $Window
            [System.Windows.MessageBox]::Show('Deployment cancelled.', 'Cancelled', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Show-DeploymentLog {
    param([System.Windows.Window]$Window)

    try {
        $result = Get-DeploymentHistory -Limit 50

        if (-not $result.Success -or -not $result.Data -or $result.Data.Count -eq 0) {
            [System.Windows.MessageBox]::Show('No deployment history available.', 'No History', 'OK', 'Information')
            return
        }

        $log = $result.Data | ForEach-Object {
            "$($_.Timestamp) | $($_.Action) | $($_.Details) | $($_.User)"
        }

        $logText = "DEPLOYMENT HISTORY (Last 50 entries)`n" + ('=' * 50) + "`n`n"
        $logText += ($log -join "`n")

        [System.Windows.MessageBox]::Show($logText, 'Deployment Log', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== SETUP PANEL HANDLERS =====

function Initialize-SetupPanel {
    param([System.Windows.Window]$Window)

    # Wire up Setup tab buttons
    $btnInitWinRM = $Window.FindName('BtnInitializeWinRM')
    if ($btnInitWinRM) { $btnInitWinRM.Add_Click({ Invoke-ButtonAction -Action 'InitializeWinRM' }) }

    $btnToggleWinRM = $Window.FindName('BtnToggleWinRM')
    if ($btnToggleWinRM) { $btnToggleWinRM.Add_Click({ Invoke-ButtonAction -Action 'ToggleWinRM' }) }

    $btnInitGPOs = $Window.FindName('BtnInitializeAppLockerGPOs')
    if ($btnInitGPOs) { $btnInitGPOs.Add_Click({ Invoke-ButtonAction -Action 'InitializeAppLockerGPOs' }) }

    $btnInitAD = $Window.FindName('BtnInitializeADStructure')
    if ($btnInitAD) { $btnInitAD.Add_Click({ Invoke-ButtonAction -Action 'InitializeADStructure' }) }

    $btnInitAll = $Window.FindName('BtnInitializeAll')
    if ($btnInitAll) { $btnInitAll.Add_Click({ Invoke-ButtonAction -Action 'InitializeAll' }) }

    # Update status on load
    Update-SetupStatus -Window $Window
}

function Update-SetupStatus {
    param([System.Windows.Window]$Window)

    try {
        if (-not (Get-Command -Name 'Get-SetupStatus' -ErrorAction SilentlyContinue)) {
            return
        }

        $status = Get-SetupStatus

        if ($status.Success -and $status.Data) {
            # Update WinRM status
            $winrmStatus = $Window.FindName('TxtWinRMStatus')
            if ($winrmStatus -and $status.Data.WinRM) {
                $winrmStatus.Text = $status.Data.WinRM.Status
                $winrmStatus.Foreground = switch ($status.Data.WinRM.Status) {
                    'Enabled' { [System.Windows.Media.Brushes]::LightGreen }
                    'Disabled' { [System.Windows.Media.Brushes]::Orange }
                    default { [System.Windows.Media.Brushes]::Gray }
                }
            }

            # Update GPO statuses
            foreach ($gpo in $status.Data.AppLockerGPOs) {
                $statusControl = $Window.FindName("TxtGPO_$($gpo.Type)_Status")
                if ($statusControl) {
                    $statusControl.Text = $gpo.Status
                    $statusControl.Foreground = if ($gpo.Exists) { 
                        [System.Windows.Media.Brushes]::LightGreen 
                    }
                    else { 
                        [System.Windows.Media.Brushes]::Gray 
                    }
                }
            }
        }
    }
    catch {
        # Silently fail - status display is optional
    }
}

function Invoke-InitializeWinRM {
    param([System.Windows.Window]$Window)

    try {
        if (-not (Get-Command -Name 'Initialize-WinRMGPO' -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show('Setup module not available.', 'Error', 'OK', 'Error')
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "This will create the 'AppLocker-EnableWinRM' GPO and link it to the domain root.`n`nThis enables WinRM on ALL computers in the domain.`n`nContinue?",
            'Initialize WinRM GPO',
            'YesNo',
            'Warning'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-WinRMGPO

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "WinRM GPO created successfully!`n`nGPO: $($result.Data.GPOName)`nLinked to: $($result.Data.LinkedTo)",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-ToggleWinRM {
    param([System.Windows.Window]$Window)

    try {
        $status = Get-SetupStatus
        if (-not $status.Success -or -not $status.Data.WinRM.Exists) {
            [System.Windows.MessageBox]::Show('WinRM GPO does not exist. Initialize it first.', 'Not Found', 'OK', 'Warning')
            return
        }

        $isEnabled = $status.Data.WinRM.Status -eq 'Enabled'

        if ($isEnabled) {
            $result = Disable-WinRMGPO
            $action = 'disabled'
        }
        else {
            $result = Enable-WinRMGPO
            $action = 'enabled'
        }

        if ($result.Success) {
            [System.Windows.MessageBox]::Show("WinRM GPO link $action.", 'Success', 'OK', 'Information')
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-InitializeAppLockerGPOs {
    param([System.Windows.Window]$Window)

    try {
        if (-not (Get-Command -Name 'Initialize-AppLockerGPOs' -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show('Setup module not available.', 'Error', 'OK', 'Error')
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "This will create three AppLocker GPOs:`n`n" +
            "- AppLocker-DC (linked to Domain Controllers OU)`n" +
            "- AppLocker-Servers (linked to Servers OU)`n" +
            "- AppLocker-Workstations (linked to Computers OU)`n`n" +
            "Continue?",
            'Initialize AppLocker GPOs',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerGPOs

        if ($result.Success) {
            $summary = $result.Data | ForEach-Object { "- $($_.Name): $($_.Status)" }
            [System.Windows.MessageBox]::Show(
                "AppLocker GPOs created!`n`n$($summary -join "`n")",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-InitializeADStructure {
    param([System.Windows.Window]$Window)

    try {
        if (-not (Get-Command -Name 'Initialize-ADStructure' -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show('Setup module not available.', 'Error', 'OK', 'Error')
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "This will create the AppLocker OU and security groups:`n`n" +
            "OU: AppLocker (at domain root)`n`n" +
            "Groups:`n" +
            "- AppLocker-Admins`n" +
            "- AppLocker-Exempt`n" +
            "- AppLocker-Audit`n" +
            "- AppLocker-Users`n" +
            "- AppLocker-Installers`n" +
            "- AppLocker-Developers`n`n" +
            "Continue?",
            'Initialize AD Structure',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-ADStructure

        if ($result.Success) {
            $groupSummary = $result.Data.Groups | ForEach-Object { "- $($_.Name): $($_.Status)" }
            [System.Windows.MessageBox]::Show(
                "AD Structure created!`n`n" +
                "OU: $($result.Data.OUPath)`n`n" +
                "Groups:`n$($groupSummary -join "`n")",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-InitializeAll {
    param([System.Windows.Window]$Window)

    try {
        if (-not (Get-Command -Name 'Initialize-AppLockerEnvironment' -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show('Setup module not available.', 'Error', 'OK', 'Error')
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "This will run ALL initialization steps:`n`n" +
            "1. Create WinRM GPO (linked to domain root)`n" +
            "2. Create AppLocker GPOs (DC, Servers, Workstations)`n" +
            "3. Create AppLocker OU and security groups`n`n" +
            "This requires Domain Admin permissions.`n`n" +
            "Continue?",
            'Full Initialization',
            'YesNo',
            'Warning'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerEnvironment

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "Full initialization complete!`n`n" +
                "WinRM GPO: $(if ($result.Data.WinRM.Success) { 'Success' } else { 'Failed' })`n" +
                "AppLocker GPOs: $(if ($result.Data.AppLockerGPOs.Success) { 'Success' } else { 'Failed' })`n" +
                "AD Structure: $(if ($result.Data.ADStructure.Success) { 'Success' } else { 'Failed' })",
                'Initialization Complete',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== WINDOW INITIALIZATION =====
function Initialize-MainWindow {
    param(
        [System.Windows.Window]$Window
    )

    # Store window reference for script-level access
    $script:MainWindow = $Window

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

    # Initialize Setup panel (Settings > Setup tab)
    try {
        Initialize-SetupPanel -Window $Window
        Write-Log -Message 'Setup panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Setup panel init failed: $($_.Exception.Message)"
    }

    # Update domain info in status bar and dashboard
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        
        # Status bar
        $domainText = $Window.FindName('DomainText')
        if ($domainText -and $computerSystem.PartOfDomain) {
            $domainText.Text = "Domain: $($computerSystem.Domain)"
        }
        
        # Dashboard System Info
        $sysComputer = $Window.FindName('SysInfoComputer')
        if ($sysComputer) { $sysComputer.Text = $env:COMPUTERNAME }
        
        $sysDomain = $Window.FindName('SysInfoDomain')
        if ($sysDomain) {
            if ($computerSystem.PartOfDomain) {
                $sysDomain.Text = $computerSystem.Domain
            }
            else {
                $sysDomain.Text = "Not domain joined"
            }
        }
        
        $sysUser = $Window.FindName('SysInfoUser')
        if ($sysUser) { $sysUser.Text = "$env:USERDOMAIN\$env:USERNAME" }
        
        $sysDataPath = $Window.FindName('SysInfoDataPath')
        if ($sysDataPath -and (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue)) {
            $dataPath = Get-AppLockerDataPath
            # Insert line break after AppData for better display
            $sysDataPath.Text = $dataPath -replace '(AppData\\)', "`$1`n"
        }
    }
    catch {
        # Silently fail - not critical
    }

    # Update data path in settings
    $settingsPath = $Window.FindName('SettingsDataPath')
    if ($settingsPath -and (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue)) {
        $settingsPath.Text = Get-AppLockerDataPath
    }

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

    Write-Log -Message 'Main window initialized'
}
#endregion
