#region Dashboard Panel Functions
# Dashboard.ps1 - Dashboard panel initialization and stats

$global:GA_DashboardToggleBusy = $false
$global:GA_DashboardToggleEnabledSnapshot = @{}

function global:Set-DashboardToggleInterlock {
    param(
        $Window,
        [switch]$Busy,
        [switch]$RestoreEnabled
    )

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $toggleNames = @(
        'BtnDashToggleEnableWinRM',
        'BtnDashToggleGpoDC',
        'BtnDashToggleGpoServers',
        'BtnDashToggleGpoWks'
    )

    if ($Busy) {
        $global:GA_DashboardToggleEnabledSnapshot = @{}
        foreach ($name in $toggleNames) {
            $btn = $win.FindName($name)
            if ($btn) {
                $global:GA_DashboardToggleEnabledSnapshot[$name] = [bool]$btn.IsEnabled
                $btn.IsEnabled = $false
                $btn.Opacity = 0.65
            }
        }

        $busyLabel = $win.FindName('TxtDashToggleBusyStatus')
        if ($busyLabel) {
            $busyLabel.Text = 'Applying changes...'
            $busyLabel.Visibility = 'Visible'
        }

        try { $win.Cursor = [System.Windows.Input.Cursors]::Wait } catch { }
        try { Request-UiRender -Window $win } catch { }
        return
    }

    foreach ($name in $toggleNames) {
        $btn = $win.FindName($name)
        if (-not $btn) { continue }

        $btn.Opacity = 1.0
        if ($RestoreEnabled -and $global:GA_DashboardToggleEnabledSnapshot.ContainsKey($name)) {
            $btn.IsEnabled = [bool]$global:GA_DashboardToggleEnabledSnapshot[$name]
        }
    }

    $busyLabel = $win.FindName('TxtDashToggleBusyStatus')
    if ($busyLabel) {
        $busyLabel.Text = ''
        $busyLabel.Visibility = 'Collapsed'
    }

    $global:GA_DashboardToggleEnabledSnapshot = @{}
    try { $win.Cursor = [System.Windows.Input.Cursors]::Arrow } catch { }
}

function Initialize-DashboardPanel {
    param($Window)

    # Wire up navigation buttons
    $btnGoToScanner = $Window.FindName('BtnDashGoToScanner')
    if ($btnGoToScanner) { $btnGoToScanner.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btnGoToRules = $Window.FindName('BtnDashGoToRules')
    if ($btnGoToRules) { $btnGoToRules.Add_Click({ Invoke-ButtonAction -Action 'NavRules' }) }

    # Wire up Getting Started buttons
    $btnGS1 = $Window.FindName('BtnGettingStarted1')
    if ($btnGS1) { $btnGS1.Add_Click({ Invoke-ButtonAction -Action 'NavDiscovery' }) }

    $btnGS2 = $Window.FindName('BtnGettingStarted2')
    if ($btnGS2) { $btnGS2.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btnGS3 = $Window.FindName('BtnGettingStarted3')
    if ($btnGS3) { $btnGS3.Add_Click({ Invoke-ButtonAction -Action 'NavRules' }) }

    $btnGS4 = $Window.FindName('BtnGettingStarted4')
    if ($btnGS4) { $btnGS4.Add_Click({ Invoke-ButtonAction -Action 'NavPolicy' }) }

    $btnGS5 = $Window.FindName('BtnGettingStarted5')
    if ($btnGS5) { $btnGS5.Add_Click({ Invoke-ButtonAction -Action 'NavDeploy' }) }

    $dashButtons = @(
        'BtnDashToggleEnableWinRM',
        'BtnDashToggleGpoDC',
        'BtnDashToggleGpoServers',
        'BtnDashToggleGpoWks'
    )
    foreach ($btnName in $dashButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                param($sender, $e)
                if ($sender -and -not $sender.IsEnabled) { return }
                if ($global:GA_DashboardToggleBusy) { return }

                $global:GA_DashboardToggleBusy = $true
                $dashWindow = if ($Window) { $Window } else { $global:GA_MainWindow }
                Set-DashboardToggleInterlock -Window $dashWindow -Busy

                $refreshSucceeded = $true
                try {
                    Invoke-ButtonAction -Action $sender.Tag
                }
                finally {
                    try {
                        Invoke-DashboardGpoRefresh -Window $dashWindow
                    }
                    catch {
                        $refreshSucceeded = $false
                    }

                    $global:GA_DashboardToggleBusy = $false
                    if ($refreshSucceeded) {
                        Set-DashboardToggleInterlock -Window $dashWindow
                    }
                    else {
                        Set-DashboardToggleInterlock -Window $dashWindow -RestoreEnabled
                    }
                }
            }.GetNewClosure())
        }
    }

    # Load dashboard data (async to avoid blocking UI thread on low-perf systems)
    try { Update-DashboardStats -Window $Window -Async } catch { Update-DashboardStats -Window $Window }
    try { Update-ModuleStatus -Window $Window } catch { }
    try { Invoke-DashboardGpoRefresh -Window $Window } catch { }
}

function global:Update-DashboardGpoToggles {
    param(
        $Window,
        $Status
    )

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    # Simplified parameter handling - use -not operator for reliable PSCustomObject null check
    if (-not $Status) {
        try { $status = Get-SetupStatus } catch { $status = $null }
    }
    else {
        $status = $Status
    }
    $hasGP = Get-Module -ListAvailable -Name GroupPolicy

    $toggleEnable = $win.FindName('BtnDashToggleEnableWinRM')
    $toggleEnableLabel = $win.FindName('TxtDashEnableWinRMLabel')
    $toggleGpoDC = $win.FindName('BtnDashToggleGpoDC')
    $toggleGpoServers = $win.FindName('BtnDashToggleGpoServers')
    $toggleGpoWks = $win.FindName('BtnDashToggleGpoWks')

    # DIAGNOSTIC: Check each disable condition individually
    $statusNull = ($null -eq $status)
    $statusNotSuccess = if ($status) { -not $status.Success } else { $true }
    $dataNull = if ($status) { ($null -eq $status.Data) } else { $true }
    $noGP = -not $hasGP
    try {
        Write-AppLockerLog -Message "UpdateGpoToggles DIAGNOSTIC: statusNull=$statusNull, statusNotSuccess=$statusNotSuccess, dataNull=$dataNull, noGP=$noGP" -Level DEBUG -NoConsole
    } catch { }

    if (-not $status -or -not $status.Success -or -not $status.Data -or -not $hasGP) {
        if ($toggleEnable) { $toggleEnable.IsEnabled = $false; $toggleEnable.IsChecked = $false }
        if ($toggleGpoDC) { $toggleGpoDC.IsEnabled = $false; $toggleGpoDC.IsChecked = $false }
        if ($toggleGpoServers) { $toggleGpoServers.IsEnabled = $false; $toggleGpoServers.IsChecked = $false }
        if ($toggleGpoWks) { $toggleGpoWks.IsEnabled = $false; $toggleGpoWks.IsChecked = $false }
        if ($toggleEnableLabel) { $toggleEnableLabel.Text = 'Enable WinRM' }
        return
    }
    if ($toggleEnable -and $status.Data.WinRM) {
        $winrmExists = $true
        if ($status.Data.WinRM.PSObject.Properties.Name -contains 'Exists') {
            $winrmExists = [bool]$status.Data.WinRM.Exists
        }
        $isEnabled = ($status.Data.WinRM.Status -eq 'Enabled')
        $toggleEnable.IsChecked = $isEnabled
        $toggleEnable.IsEnabled = [bool]$hasGP -and $winrmExists
        # Keep label constant - toggle state (checked/unchecked) indicates status
        if ($toggleEnableLabel) { $toggleEnableLabel.Text = 'Enable WinRM' }
    }

    if ($status.Data.AppLockerGPOs) {
        foreach ($gpo in $status.Data.AppLockerGPOs) {
            $toggle = switch ($gpo.Type) {
                'DC' { $win.FindName('BtnDashToggleGpoDC') }
                'Servers' { $win.FindName('BtnDashToggleGpoServers') }
                'Workstations' { $win.FindName('BtnDashToggleGpoWks') }
                default { $null }
            }

            if ($toggle) {
                if (-not $hasGP -or -not $gpo.Exists) {
                    $toggle.IsEnabled = $false
                    $toggle.IsChecked = $false
                }
                else {
                    $toggle.IsEnabled = $true
                    $toggle.IsChecked = ($gpo.GpoState -eq 'Enabled')
                }
            }
        }
    }
}

function global:Invoke-DashboardGpoRefresh {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    # Call Get-SetupStatus synchronously on UI thread (fast operation, ~100-500ms)
    # Async runspace approach failed because module-scoped variables ($script:DefaultGPONames)
    # aren't available in runspace context, causing silent failures
    try {
        $status = Get-SetupStatus
        
        # DIAGNOSTIC: Log Get-SetupStatus result for debugging GPO toggle issues
        $hasGP = Get-Module -ListAvailable -Name GroupPolicy
        $statusSuccess = if ($status) { $status.Success } else { $false }
        $statusDataNull = ($null -eq $status.Data)
        $winrmExists = if ($status.Data -and $status.Data.WinRM) { $status.Data.WinRM.Exists } else { "N/A" }
        $gpoCount = if ($status.Data -and $status.Data.AppLockerGPOs) { $status.Data.AppLockerGPOs.Count } else { 0 }
        try { 
            Write-AppLockerLog -Message "DashboardGpoRefresh DIAGNOSTIC: Success=$statusSuccess, DataIsNull=$statusDataNull, hasGP=$([bool]$hasGP), WinRMExists=$winrmExists, GPOCount=$gpoCount" -Level INFO -NoConsole 
        } catch { }
        
        Update-DashboardGpoToggles -Window $win -Status $status
    }
    catch {
        Update-DashboardGpoToggles -Window $win -Status $null
        try { Write-AppLockerLog -Level Warning -Message "Dashboard GPO status refresh failed: $($_.Exception.Message)" -NoConsole } catch { }
    }
}

function global:Invoke-DashboardStatsRefresh {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    if ($global:GA_DashboardStatsInProgress) { return }
    $global:GA_DashboardStatsInProgress = $true

    $machineCount = if ($script:DiscoveredMachines) { $script:DiscoveredMachines.Count } else { 0 }
    $currentArtifacts = if ($script:CurrentScanArtifacts) { $script:CurrentScanArtifacts.Count } else { 0 }
    $cachedArtifacts = if ($script:CachedTotalArtifacts) { $script:CachedTotalArtifacts } else { $null }
    $modulePath = (Get-Module GA-AppLocker).ModuleBase

    $global:GA_DashboardStats_Window = $win

    $bgWork = {
        param($ModulePath, $MachineCount, $CurrentArtifacts, $CachedArtifacts)

        $modulesDir = Join-Path $ModulePath 'Modules'
        foreach ($mod in @('GA-AppLocker.Core', 'GA-AppLocker.Storage', 'GA-AppLocker.Scanning', 'GA-AppLocker.Policy')) {
            $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
            if (Test-Path $modPath) {
                try { Import-Module $modPath -Force -ErrorAction Stop } catch { }
            }
        }

        $stats = [PSCustomObject]@{
            MachineCount = $MachineCount
            ArtifactCount = if ($CachedArtifacts) { $CachedArtifacts } else { $CurrentArtifacts }
            RuleCounts = $null
            PendingRules = @()
            PolicyCount = 0
            RecentScans = @()
        }

        try {
            $countsResult = Get-RuleCounts
            if ($countsResult.Success) {
                $stats.RuleCounts = $countsResult
            }
        }
        catch { }

        if ($stats.RuleCounts) {
            try {
                $pendingItems = [System.Collections.Generic.List[PSCustomObject]]::new()
                $pendingData = Get-RulesFromDatabase -Status 'Pending' -Take 10
                if ($pendingData) {
                    foreach ($rule in @($pendingData)) {
                        [void]$pendingItems.Add([PSCustomObject]@{
                            Type = $rule.RuleType
                            Name = $rule.Name
                        })
                    }
                }
                $stats.PendingRules = @($pendingItems)
            }
            catch { }
        }

        try {
            $stats.PolicyCount = Get-PolicyCount
        }
        catch { }

        try {
            $scansResult = Get-ScanResults
            if ($scansResult.Success -and $scansResult.Data) {
                $scanData = @($scansResult.Data)
                $stats.RecentScans = @($scanData | Select-Object -First 5 | ForEach-Object {
                        $dateDisplay = ''
                        if ($_.Date) {
                            try {
                                $dateValue = $_.Date
                                if ($dateValue -is [PSCustomObject] -and $dateValue.DateTime) {
                                    $dateDisplay = ([datetime]$dateValue.DateTime).ToString('MM/dd HH:mm')
                                }
                                elseif ($dateValue -is [datetime]) {
                                    $dateDisplay = $dateValue.ToString('MM/dd HH:mm')
                                }
                                elseif ($dateValue -is [string]) {
                                    $dateDisplay = ([datetime]$dateValue).ToString('MM/dd HH:mm')
                                }
                            }
                            catch { }
                        }
                        [PSCustomObject]@{
                            Name  = $_.ScanName
                            Date  = $dateDisplay
                            Count = "$($_.Artifacts) items"
                        }
                    })
            }
        }
        catch { }

        return $stats
    }

    $onComplete = {
        param($Result)
        $winRef = $global:GA_DashboardStats_Window
        $global:GA_DashboardStatsInProgress = $false
        $global:GA_DashboardStats_Window = $null

        if (-not $winRef -or -not $Result) { return }

        Invoke-UIUpdate {
            Apply-DashboardStats -Window $winRef -Stats $Result
        }
    }

    $onTimeout = {
        param($TimeoutMessage)
        $global:GA_DashboardStatsInProgress = $false
        $global:GA_DashboardStats_Window = $null
        try { Write-Log -Level Warning -Message "Dashboard stats refresh timed out: $TimeoutMessage" } catch { }
    }

    Invoke-BackgroundWork -ScriptBlock $bgWork `
        -ArgumentList @($modulePath, $machineCount, $currentArtifacts, $cachedArtifacts) `
        -OnComplete $onComplete `
        -OnTimeout $onTimeout `
        -NoLoadingOverlay `
        -TimeoutSeconds 60
}

function global:Apply-DashboardStats {
    param(
        $Window,
        $Stats
    )

    if (-not $Stats) { return }

    $statMachines = $Window.FindName('StatMachines')
    if ($statMachines) { $statMachines.Text = $Stats.MachineCount.ToString() }

    $statArtifacts = $Window.FindName('StatArtifacts')
    if ($statArtifacts) { $statArtifacts.Text = $Stats.ArtifactCount.ToString() }

    if ($Stats.RuleCounts) {
        $statRules = $Window.FindName('StatRules')
        $statPending = $Window.FindName('StatPending')
        $statApproved = $Window.FindName('StatApproved')
        $statRejected = $Window.FindName('StatRejected')

        if ($statRules) { $statRules.Text = $Stats.RuleCounts.Total.ToString() }

        if ($statPending) {
            $pendingCount = if ($Stats.RuleCounts.ByStatus['Pending']) { $Stats.RuleCounts.ByStatus['Pending'] } else { 0 }
            $statPending.Text = $pendingCount.ToString()
        }
        if ($statApproved) {
            $approvedCount = if ($Stats.RuleCounts.ByStatus['Approved']) { $Stats.RuleCounts.ByStatus['Approved'] } else { 0 }
            $statApproved.Text = $approvedCount.ToString()
        }
        if ($statRejected) {
            $rejectedCount = if ($Stats.RuleCounts.ByStatus['Rejected']) { $Stats.RuleCounts.ByStatus['Rejected'] } else { 0 }
            $statRejected.Text = $rejectedCount.ToString()
        }

        $pendingList = $Window.FindName('DashPendingRules')
        if ($pendingList -and $Stats.PendingRules) {
            $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            foreach ($rule in @($Stats.PendingRules)) {
                [void]$items.Add([PSCustomObject]@{
                    Type = $rule.Type
                    Name = $rule.Name
                })
            }
            $pendingList.ItemsSource = $items
        }
    }

    $statPolicies = $Window.FindName('StatPolicies')
    if ($statPolicies) { $statPolicies.Text = $Stats.PolicyCount.ToString() }

    $scansList = $Window.FindName('DashRecentScans')
    if ($scansList -and $Stats.RecentScans) {
        $scansList.ItemsSource = $Stats.RecentScans
    }

    Update-DashboardCharts -Window $Window -CountsResult $Stats.RuleCounts
    try { Request-UiRender -Window $Window } catch { }
}

function global:Update-DashboardStats {
    [CmdletBinding()]
    param(
        $Window,
        [switch]$Async
    )

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    if ($Async -or $win.Dispatcher.CheckAccess()) {
        try {
            Invoke-DashboardStatsRefresh -Window $win
            return
        } catch { }
    }

    if (-not $win.Dispatcher.CheckAccess()) {
        try {
            $win.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{ Invoke-DashboardStatsRefresh -Window $win }
            ) | Out-Null
            return
        } catch { }
    }

    $Window = $win

    # Update stats from actual data
    try {
        # Update charts (uses Get-RuleCounts - fast)
        Update-DashboardCharts -Window $Window
        
        # Machines count (null-safe)
        $statMachines = $Window.FindName('StatMachines')
        if ($statMachines) { 
            $machineCount = if ($script:DiscoveredMachines) { $script:DiscoveredMachines.Count } else { 0 }
            $statMachines.Text = $machineCount.ToString()
        }

        # Artifacts count - use cached count or current session only (skip slow file reads on startup)
        $statArtifacts = $Window.FindName('StatArtifacts')
        if ($statArtifacts) { 
            $totalArtifacts = 0
            # Count current session artifacts only (fast)
            if ($script:CurrentScanArtifacts) {
                $totalArtifacts += $script:CurrentScanArtifacts.Count
            }
            # Use cached artifact count if available (set when user visits Scanner panel)
            if ($script:CachedTotalArtifacts) {
                $totalArtifacts = $script:CachedTotalArtifacts
            }
            $statArtifacts.Text = $totalArtifacts.ToString()
        }

        # Rules count - use Get-RuleCounts for fast counting from index (no file I/O)
        $statRules = $Window.FindName('StatRules')
        $statPending = $Window.FindName('StatPending')
        $statApproved = $Window.FindName('StatApproved')
        $statRejected = $Window.FindName('StatRejected')
        $countsResult = Get-RuleCounts
        if ($countsResult.Success) {
            # Total rules count
            if ($statRules) { 
                $statRules.Text = $countsResult.Total.ToString() 
            }
            
            # Pending = Rules awaiting approval
            if ($statPending) {
                $pendingCount = if ($countsResult.ByStatus['Pending']) { $countsResult.ByStatus['Pending'] } else { 0 }
                $statPending.Text = $pendingCount.ToString()
            }
            
            # Approved count
            if ($statApproved) {
                $approvedCount = if ($countsResult.ByStatus['Approved']) { $countsResult.ByStatus['Approved'] } else { 0 }
                $statApproved.Text = $approvedCount.ToString()
            }
            
            # Rejected count
            if ($statRejected) {
                $rejectedCount = if ($countsResult.ByStatus['Rejected']) { $countsResult.ByStatus['Rejected'] } else { 0 }
                $statRejected.Text = $rejectedCount.ToString()
            }

            # Populate pending rules list - use direct Storage query for just 10 items
            # The index already has Name and RuleType fields, so no file I/O needed
            $pendingList = $Window.FindName('DashPendingRules')
            if ($pendingList) {
                try {
                    # Get-RulesFromDatabase returns array directly (not result object)
                    $pendingData = Get-RulesFromDatabase -Status 'Pending' -Take 10
                    if ($pendingData -and $pendingData.Count -gt 0) {
                        $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                        foreach ($rule in $pendingData) {
                            [void]$items.Add([PSCustomObject]@{
                                Type = $rule.RuleType
                                Name = $rule.Name
                            })
                        }
                        $pendingList.ItemsSource = $items
                    }
                } catch {
                    Write-AppLockerLog -Message "Failed to populate pending rules list: $($_.Exception.Message)" -Level 'ERROR'
                }
            }
        }

        # Policies count (fast count, no JSON parsing)
        $statPolicies = $Window.FindName('StatPolicies')
        $policyCount = Get-PolicyCount
        if ($statPolicies) {
            $statPolicies.Text = $policyCount.ToString()
        }

        # Recent scans
        $scansList = $Window.FindName('DashRecentScans')
        if ($scansList) {
            $scansResult = Get-ScanResults
            if ($scansResult.Success -and $scansResult.Data) {
                # Ensure Data is always an array
                $scanData = @($scansResult.Data)
                $recentScans = @($scanData | Select-Object -First 5 | ForEach-Object {
                        # Safely parse Date (may be DateTime, string, or PSCustomObject from JSON)
                        $dateDisplay = ''
                        if ($_.Date) {
                            try {
                                $dateValue = $_.Date
                                if ($dateValue -is [PSCustomObject] -and $dateValue.DateTime) {
                                    $dateDisplay = ([datetime]$dateValue.DateTime).ToString('MM/dd HH:mm')
                                }
                                elseif ($dateValue -is [datetime]) {
                                    $dateDisplay = $dateValue.ToString('MM/dd HH:mm')
                                }
                                elseif ($dateValue -is [string]) {
                                    $dateDisplay = ([datetime]$dateValue).ToString('MM/dd HH:mm')
                                }
                            } catch { }
                        }
                        [PSCustomObject]@{
                            Name  = $_.ScanName
                            Date  = $dateDisplay
                            Count = "$($_.Artifacts) items"
                        }
                    })
                $scansList.ItemsSource = $recentScans
            }
        }

        try { Request-UiRender -Window $Window } catch { }
    }
    catch {
        Write-Log -Level Warning -Message "Failed to update dashboard stats: $($_.Exception.Message)"
    }
}

function Update-DashboardCharts {
    <#
    .SYNOPSIS
        Updates the dashboard chart widgets with current data.
        
    .NOTES
        Uses Get-RuleCounts for fast O(n) counting from index instead of
        Get-AllRules which loads full payloads from disk (slow with many rules).
    #>
    param(
        $Window,
        $CountsResult
    )
    
    try {
        $countsResult = $CountsResult
        if (-not $countsResult) {
            $countsResult = Get-RuleCounts
        }
        if (-not $countsResult.Success) { return }
        
        $totalRules = $countsResult.Total
        
        if ($totalRules -eq 0) { return }
        
        # Get counts by status (already grouped in result)
        $approved = if ($countsResult.ByStatus['Approved']) { $countsResult.ByStatus['Approved'] } else { 0 }
        $pending = if ($countsResult.ByStatus['Pending']) { $countsResult.ByStatus['Pending'] } else { 0 }
        $rejected = if ($countsResult.ByStatus['Rejected']) { $countsResult.ByStatus['Rejected'] } else { 0 }
        $review = if ($countsResult.ByStatus['Review']) { $countsResult.ByStatus['Review'] } else { 0 }
        
        # Get counts by rule type (already grouped in result)
        $publisherCount = if ($countsResult.ByRuleType['Publisher']) { $countsResult.ByRuleType['Publisher'] } else { 0 }
        $hashCount = if ($countsResult.ByRuleType['Hash']) { $countsResult.ByRuleType['Hash'] } else { 0 }
        $pathCount = if ($countsResult.ByRuleType['Path']) { $countsResult.ByRuleType['Path'] } else { 0 }
        
        # Calculate max for scaling (use 200 pixels as max width)
        $maxBarWidth = 200
        $maxStatus = [Math]::Max([Math]::Max($approved, $pending), [Math]::Max($rejected, $review))
        $maxType = [Math]::Max([Math]::Max($publisherCount, $hashCount), $pathCount)
        
        if ($maxStatus -eq 0) { $maxStatus = 1 }
        if ($maxType -eq 0) { $maxType = 1 }
        
        # Update Status Chart bars and labels
        $barApproved = $Window.FindName('ChartBarApproved')
        $barPending = $Window.FindName('ChartBarPending')
        $barRejected = $Window.FindName('ChartBarRejected')
        $barReview = $Window.FindName('ChartBarReview')
        
        $labelApproved = $Window.FindName('ChartLabelApproved')
        $labelPending = $Window.FindName('ChartLabelPending')
        $labelRejected = $Window.FindName('ChartLabelRejected')
        $labelReview = $Window.FindName('ChartLabelReview')
        $labelTotal = $Window.FindName('ChartTotalRules')
        
        if ($barApproved) { $barApproved.Width = [Math]::Max(($approved / $maxStatus) * $maxBarWidth, 2) }
        if ($barPending) { $barPending.Width = [Math]::Max(($pending / $maxStatus) * $maxBarWidth, 2) }
        if ($barRejected) { $barRejected.Width = [Math]::Max(($rejected / $maxStatus) * $maxBarWidth, 2) }
        if ($barReview) { $barReview.Width = [Math]::Max(($review / $maxStatus) * $maxBarWidth, 2) }
        
        if ($labelApproved) { $labelApproved.Text = $approved.ToString() }
        if ($labelPending) { $labelPending.Text = $pending.ToString() }
        if ($labelRejected) { $labelRejected.Text = $rejected.ToString() }
        if ($labelReview) { $labelReview.Text = $review.ToString() }
        if ($labelTotal) { $labelTotal.Text = $totalRules.ToString() }
        
        # Update Type Chart bars and labels
        $barPublisher = $Window.FindName('ChartBarPublisher')
        $barHash = $Window.FindName('ChartBarHash')
        $barPath = $Window.FindName('ChartBarPath')
        
        $labelPublisher = $Window.FindName('ChartLabelPublisher')
        $labelHash = $Window.FindName('ChartLabelHash')
        $labelPath = $Window.FindName('ChartLabelPath')
        
        if ($barPublisher) { $barPublisher.Width = [Math]::Max(($publisherCount / $maxType) * $maxBarWidth, 2) }
        if ($barHash) { $barHash.Width = [Math]::Max(($hashCount / $maxType) * $maxBarWidth, 2) }
        if ($barPath) { $barPath.Width = [Math]::Max(($pathCount / $maxType) * $maxBarWidth, 2) }
        
        if ($labelPublisher) { $labelPublisher.Text = $publisherCount.ToString() }
        if ($labelHash) { $labelHash.Text = $hashCount.ToString() }
        if ($labelPath) { $labelPath.Text = $pathCount.ToString() }
    }
    catch {
        Write-Log -Level Warning -Message "Failed to update dashboard charts: $($_.Exception.Message)"
    }
}

#endregion
