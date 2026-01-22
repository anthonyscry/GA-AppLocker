#region Dashboard Panel Functions
# Dashboard.ps1 - Dashboard panel initialization and stats

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

    # Bulk approve trusted vendors button
    $btnApproveTrusted = $Window.FindName('BtnDashApproveTrusted')
    if ($btnApproveTrusted) { $btnApproveTrusted.Add_Click({ Invoke-ButtonAction -Action 'ApproveTrustedVendors' }) }

    # Remove duplicates button
    $btnRemoveDuplicates = $Window.FindName('BtnDashRemoveDuplicates')
    if ($btnRemoveDuplicates) { $btnRemoveDuplicates.Add_Click({ Invoke-ButtonAction -Action 'RemoveDuplicateRules' }) }

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

        # Artifacts count - sum from all saved scans + current session
        $statArtifacts = $Window.FindName('StatArtifacts')
        if ($statArtifacts) { 
            $totalArtifacts = 0
            # Count current session artifacts
            if ($script:CurrentScanArtifacts) {
                $totalArtifacts += $script:CurrentScanArtifacts.Count
            }
            # Also count from saved scans
            $scansResult = Get-ScanResults
            if ($scansResult.Success -and $scansResult.Data) {
                $scanData = @($scansResult.Data)
                foreach ($scan in $scanData) {
                    if ($scan.Artifacts) {
                        $totalArtifacts += [int]$scan.Artifacts
                    }
                }
            }
            $statArtifacts.Text = $totalArtifacts.ToString()
        }

        # Rules count
        $statRules = $Window.FindName('StatRules')
        $statPending = $Window.FindName('StatPending')
        $statApproved = $Window.FindName('StatApproved')
        $statRejected = $Window.FindName('StatRejected')
        $rulesResult = Get-AllRules
        if ($rulesResult.Success) {
            $allRules = @($rulesResult.Data)
            # Rules = Total rules count
            if ($statRules) { 
                $statRules.Text = $allRules.Count.ToString() 
            }
            
            # Group by status for counts
            $statusGroups = $allRules | Group-Object Status
            
            # Pending = Rules awaiting approval
            if ($statPending) {
                $pendingCount = ($statusGroups | Where-Object Name -eq 'Pending' | Select-Object -ExpandProperty Count) -as [int]
                $statPending.Text = $(if ($pendingCount) { $pendingCount } else { 0 }).ToString()
            }
            
            # Approved count
            if ($statApproved) {
                $approvedCount = ($statusGroups | Where-Object Name -eq 'Approved' | Select-Object -ExpandProperty Count) -as [int]
                $statApproved.Text = $(if ($approvedCount) { $approvedCount } else { 0 }).ToString()
            }
            
            # Rejected count
            if ($statRejected) {
                $rejectedCount = ($statusGroups | Where-Object Name -eq 'Rejected' | Select-Object -ExpandProperty Count) -as [int]
                $statRejected.Text = $(if ($rejectedCount) { $rejectedCount } else { 0 }).ToString()
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
