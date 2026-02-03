#region Dashboard Panel Functions
# Dashboard.ps1 - Dashboard panel initialization and stats

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
                Invoke-ButtonAction -Action $sender.Tag
                try { global:Update-DashboardGpoToggles -Window $global:GA_MainWindow } catch { }
            }.GetNewClosure())
        }
    }

    # Load dashboard data
    Update-DashboardStats -Window $Window
    try { Update-ModuleStatus -Window $Window } catch { }
    try { Update-DashboardGpoToggles -Window $Window } catch { }
}

function global:Update-DashboardGpoToggles {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $status = $null
    try { $status = Get-SetupStatus } catch { }
    $hasGP = Get-Module -ListAvailable -Name GroupPolicy

    $toggleEnable = $win.FindName('BtnDashToggleEnableWinRM')
    $toggleEnableLabel = $win.FindName('TxtDashEnableWinRMLabel')
    $toggleGpoDC = $win.FindName('BtnDashToggleGpoDC')
    $toggleGpoServers = $win.FindName('BtnDashToggleGpoServers')
    $toggleGpoWks = $win.FindName('BtnDashToggleGpoWks')

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
        if ($toggleEnableLabel) { $toggleEnableLabel.Text = if ($isEnabled) { 'Disable WinRM' } else { 'Enable WinRM' } }
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

function global:Update-DashboardStats {
    param($Window)

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
    param($Window)
    
    try {
        $countsResult = Get-RuleCounts
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
