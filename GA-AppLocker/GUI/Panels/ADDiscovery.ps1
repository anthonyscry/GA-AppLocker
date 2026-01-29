#region AD Discovery Panel Functions
# ADDiscovery.ps1 - AD/OU discovery and machine selection

# Script-scoped handler storage for cleanup
$script:ADDiscovery_Handlers = @{}

function Initialize-DiscoveryPanel {
    param([System.Windows.Window]$Window)
    
    # Clean up any existing handlers first to prevent accumulation
    Unregister-DiscoveryPanelEvents -Window $Window

    # Wire up Refresh Domain button
    $btnRefresh = $Window.FindName('BtnRefreshDomain')
    if ($btnRefresh) {
        $script:ADDiscovery_Handlers['btnRefresh'] = { Invoke-ButtonAction -Action 'RefreshDomain' }
        $btnRefresh.Add_Click($script:ADDiscovery_Handlers['btnRefresh'])
    }

    # Wire up Test Connectivity button
    $btnTest = $Window.FindName('BtnTestConnectivity')
    if ($btnTest) {
        $script:ADDiscovery_Handlers['btnTest'] = { Invoke-ButtonAction -Action 'TestConnectivity' }
        $btnTest.Add_Click($script:ADDiscovery_Handlers['btnTest'])
    }
}

function Unregister-DiscoveryPanelEvents {
    <#
    .SYNOPSIS
        Removes all registered event handlers from Discovery panel.
    .DESCRIPTION
        Called when switching away from the panel to prevent handler accumulation
        and memory leaks.
    #>
    param([System.Windows.Window]$Window)
    
    if (-not $Window) { $Window = $global:GA_MainWindow }
    if (-not $Window) { return }
    
    # Remove Refresh button handler
    if ($script:ADDiscovery_Handlers['btnRefresh']) {
        $btnRefresh = $Window.FindName('BtnRefreshDomain')
        if ($btnRefresh) {
            try { $btnRefresh.Remove_Click($script:ADDiscovery_Handlers['btnRefresh']) } catch { }
        }
    }
    
    # Remove Test button handler
    if ($script:ADDiscovery_Handlers['btnTest']) {
        $btnTest = $Window.FindName('BtnTestConnectivity')
        if ($btnTest) {
            try { $btnTest.Remove_Click($script:ADDiscovery_Handlers['btnTest']) } catch { }
        }
    }
    
    # Clear stored handlers
    $script:ADDiscovery_Handlers = @{}
}

function global:Invoke-DomainRefresh {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

    $domainLabel = $Window.FindName('DiscoveryDomainLabel')
    $machineCount = $Window.FindName('DiscoveryMachineCount')
    $treeView = $Window.FindName('OUTreeView')

    # Update status
    if ($domainLabel) { $domainLabel.Text = 'Domain: Connecting...' }

    # Define the work to be done
    $discoveryWork = {
        $result = @{
            DomainResult = $null
            OUResult = $null
            ComputerResult = $null
        }
        
        # Get domain info
        $result.DomainResult = Get-DomainInfo
        if ($result.DomainResult.Success) {
            # Get OU tree
            $result.OUResult = Get-OUTree
            
            # Get all computers
            $rootDN = $result.DomainResult.Data.DistinguishedName
            $result.ComputerResult = Get-ComputersByOU -OUDistinguishedNames @($rootDN)
        }
        
        return $result
    }

    # Define the completion handler
    $onComplete = {
        param($Result)
        
        if ($Result.DomainResult.Success) {
            if ($domainLabel) {
                $domainLabel.Text = "Domain: $($Result.DomainResult.Data.DnsRoot)"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
            }

            # Update OU tree
            if ($Result.OUResult.Success -and $treeView) {
                $script:DiscoveredOUs = $Result.OUResult.Data
                Update-OUTreeView -TreeView $treeView -OUs $Result.OUResult.Data
            }

            # Update machine grid
            if ($Result.ComputerResult.Success) {
                $script:DiscoveredMachines = $Result.ComputerResult.Data
                Update-MachineDataGrid -Window $Window -Machines $Result.ComputerResult.Data
                Update-WorkflowBreadcrumb -Window $Window

                if ($machineCount) {
                    $machineCount.Text = "$($Result.ComputerResult.Data.Count) machines discovered"
                }
            }
        }
        else {
            $errorMsg = $Result.DomainResult.Error
            if ($domainLabel) {
                # Show short error in label
                $shortError = if ($errorMsg.Length -gt 50) { $errorMsg.Substring(0, 50) + '...' } else { $errorMsg }
                $domainLabel.Text = "Domain: Error - $shortError"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            }
            # Update tree view to show error state
            if ($treeView) {
                $treeView.Items.Clear()
                $errorItem = [System.Windows.Controls.TreeViewItem]::new()
                $errorItem.Header = "Unable to connect to domain"
                $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                $treeView.Items.Add($errorItem)
            }
            # Show full error in toast
            if (Get-Command -Name 'Show-Toast' -ErrorAction SilentlyContinue) {
                Show-Toast -Message "Domain discovery failed: $errorMsg" -Type 'Error' -Duration 8000
            }
        }
    }

    $onError = {
        param($ErrorMessage)
        if ($domainLabel) {
            # Show short error in label
            $shortError = if ($ErrorMessage.Length -gt 50) { $ErrorMessage.Substring(0, 50) + '...' } else { $ErrorMessage }
            $domainLabel.Text = "Domain: Error - $shortError"
            $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
        # Update tree view to show error state
        if ($treeView) {
            $treeView.Items.Clear()
            $errorItem = [System.Windows.Controls.TreeViewItem]::new()
            $errorItem.Header = "Unable to connect to domain"
            $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            $treeView.Items.Add($errorItem)
        }
        # Show full error in toast
        if (Get-Command -Name 'Show-Toast' -ErrorAction SilentlyContinue) {
            Show-Toast -Message "Domain discovery failed: $ErrorMessage" -Type 'Error' -Duration 8000
        }
    }

    # Run domain discovery synchronously - async runspaces have module import issues
    # Domain discovery is quick and doesn't need background execution
    try {
        # Show loading indicator
        if (Get-Command -Name 'Show-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Show-LoadingOverlay -Message 'Discovering domain...' -SubMessage 'Querying Active Directory'
        }

        $result = & $discoveryWork

        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }

        & $onComplete -Result $result
    }
    catch {
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        & $onError -ErrorMessage $_.Exception.Message
    }
}

function global:Update-OUTreeView {
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [array]$OUs
    )

    try {
        $TreeView.Items.Clear()

        if (-not $OUs -or $OUs.Count -eq 0) {
            $emptyItem = [System.Windows.Controls.TreeViewItem]::new()
            $emptyItem.Header = "No OUs found"
            $emptyItem.Foreground = [System.Windows.Media.Brushes]::Gray
            $TreeView.Items.Add($emptyItem)
            return
        }

        # Build hierarchical tree
        $root = $OUs | Where-Object { $_.Depth -eq 0 } | Select-Object -First 1
        if ($root) {
            # Create TreeViewItem directly here instead of calling another function
            $rootItem = [System.Windows.Controls.TreeViewItem]::new()
            # Use BMP-safe chars (PS 5.1 [char] is 16-bit, cannot represent emoji > 0xFFFF)
            $rootIcon = switch ($root.MachineType) {
                'DomainController' { [char]0x2302 }  # ⌂
                'Server'           { [char]0x25A3 }  # ▣
                'Workstation'      { [char]0x25A1 }  # □
                default            { [char]0x25C7 }  # ◇
            }
            $rootHeader = "$rootIcon $($root.Name)"
            if ($root.ComputerCount -gt 0) { $rootHeader += " ($($root.ComputerCount))" }
            $rootItem.Header = $rootHeader
            $rootItem.Tag = $root.DistinguishedName
            $rootItem.Foreground = [System.Windows.Media.Brushes]::White

            # Add child OUs recursively
            Add-ChildOUsToTreeItem -ParentItem $rootItem -ParentOU $root -AllOUs $OUs

            $TreeView.Items.Add($rootItem)
            $rootItem.IsExpanded = $true
        }
        else {
            $noRootItem = [System.Windows.Controls.TreeViewItem]::new()
            $noRootItem.Header = "No root OU found"
            $noRootItem.Foreground = [System.Windows.Media.Brushes]::Gray
            $TreeView.Items.Add($noRootItem)
        }
    }
    catch {
        # Show error in tree
        $TreeView.Items.Clear()
        $errorItem = [System.Windows.Controls.TreeViewItem]::new()
        $errorItem.Header = "Error building tree: $($_.Exception.Message)"
        $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        $TreeView.Items.Add($errorItem)
    }
}

function global:Add-ChildOUsToTreeItem {
    <#
    .SYNOPSIS
        Recursively adds child OUs to a TreeViewItem.
    .DESCRIPTION
        Helper function that builds the OU tree structure inline
        to avoid function resolution issues in closure contexts.
    #>
    param(
        [System.Windows.Controls.TreeViewItem]$ParentItem,
        $ParentOU,
        [array]$AllOUs
    )

    # Find direct children
    $children = $AllOUs | Where-Object {
        $_.DistinguishedName -ne $ParentOU.DistinguishedName -and
        $_.DistinguishedName -like "*,$($ParentOU.DistinguishedName)" -and
        $_.Depth -eq ($ParentOU.Depth + 1)
    }

    foreach ($child in $children) {
        $childItem = [System.Windows.Controls.TreeViewItem]::new()

        # Use BMP-safe chars (PS 5.1 [char] is 16-bit, cannot represent emoji > 0xFFFF)
        $icon = switch ($child.MachineType) {
            'DomainController' { [char]0x2302 }  # ⌂
            'Server'           { [char]0x25A3 }  # ▣
            'Workstation'      { [char]0x25A1 }  # □
            default            { [char]0x25C7 }  # ◇
        }

        $header = "$icon $($child.Name)"
        if ($child.ComputerCount -gt 0) { $header += " ($($child.ComputerCount))" }

        $childItem.Header = $header
        $childItem.Tag = $child.DistinguishedName
        $childItem.Foreground = [System.Windows.Media.Brushes]::White

        # Recursively add grandchildren
        Add-ChildOUsToTreeItem -ParentItem $childItem -ParentOU $child -AllOUs $AllOUs

        $ParentItem.Items.Add($childItem)
    }
}

function global:New-TreeViewItem {
    <#
    .SYNOPSIS
        Creates a TreeViewItem for an OU (legacy function kept for compatibility).
    #>
    param($OU, $AllOUs)

    # Use BMP-safe chars (PS 5.1 [char] is 16-bit, cannot represent emoji > 0xFFFF)
    $icon = switch ($OU.MachineType) {
        'DomainController' { [char]0x2302 }  # ⌂
        'Server'           { [char]0x25A3 }  # ▣
        'Workstation'      { [char]0x25A1 }  # □
        default            { [char]0x25C7 }  # ◇
    }

    $header = "$icon $($OU.Name)"
    if ($OU.ComputerCount -gt 0) {
        $header += " ($($OU.ComputerCount))"
    }

    $item = [System.Windows.Controls.TreeViewItem]::new()
    $item.Header = $header
    $item.Tag = $OU.DistinguishedName
    $item.Foreground = [System.Windows.Media.Brushes]::White

    # Add child OUs using the helper function
    Add-ChildOUsToTreeItem -ParentItem $item -ParentOU $OU -AllOUs $AllOUs

    return $item
}

function global:Update-MachineDataGrid {
    param(
        [System.Windows.Window]$Window,
        [array]$Machines
    )

    $dataGrid = $Window.FindName('MachineDataGrid')
    if ($dataGrid) {
        # Add status icon + IsChecked property for checkbox binding
        # Wrap in @() to ensure array for DataGrid ItemsSource (PS 5.1 compatible)
        $machinesWithIcon = @($Machines | ForEach-Object {
            $statusIcon = switch ($_.IsOnline) {
                $true  { [char]0x2714 }   # ✔ (online)
                $false { [char]0x2716 }   # ✖ (offline)
                default { [char]0x2013 }  # – (unknown)
            }
            $_ | Add-Member -NotePropertyName 'StatusIcon' -NotePropertyValue $statusIcon -Force
            # Add IsChecked for checkbox binding (default unchecked)
            if (-not ($_.PSObject.Properties.Name -contains 'IsChecked')) {
                $_ | Add-Member -NotePropertyName 'IsChecked' -NotePropertyValue $false -Force
            }
            # Output the object once (do NOT use -PassThru above, it causes duplicate output)
            $_
        })

        $dataGrid.ItemsSource = $machinesWithIcon
    }
}

function global:Get-CheckedMachines {
    <#
    .SYNOPSIS
        Returns machines with IsChecked = $true from the MachineDataGrid.
    .DESCRIPTION
        If no machines are checked, returns an empty array.
        Used by Test Connectivity and Scanner to operate on selected machines only.
    #>
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('MachineDataGrid')
    if (-not $dataGrid -or -not $dataGrid.ItemsSource) { return @() }

    $checked = @($dataGrid.ItemsSource | Where-Object { $_.IsChecked -eq $true })
    return $checked
}

function global:Invoke-ConnectivityTest {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

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

    # Use checked machines if any are checked; otherwise fall back to all discovered machines
    $checkedMachines = Get-CheckedMachines -Window $Window
    if ($checkedMachines.Count -gt 0) {
        $machines = $checkedMachines
        if ($machineCount) { $machineCount.Text = "Testing $($machines.Count) checked machines..." }
    }
    else {
        $machines = $script:DiscoveredMachines
    }

    $onComplete = {
        param($Result)
        if ($Result.Success) {
            $script:DiscoveredMachines = $Result.Data
            Update-MachineDataGrid -Window $Window -Machines $Result.Data
            Update-WorkflowBreadcrumb -Window $Window

            $summary = $Result.Summary
            if ($machineCount) {
                $machineCount.Text = "$($summary.OnlineCount)/$($summary.TotalMachines) online, $($summary.WinRMAvailable) WinRM"
            }
        }
    }

    # Run connectivity test synchronously - async runspaces have module import issues
    try {
        if (Get-Command -Name 'Show-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Show-LoadingOverlay -Message 'Testing connectivity...' -SubMessage "Checking $($machines.Count) machines"
        }

        $testResult = Test-MachineConnectivity -Machines $machines

        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }

        & $onComplete -Result $testResult
    }
    catch {
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        if ($machineCount) {
            $machineCount.Text = "Error: $($_.Exception.Message)"
        }
    }
}

#endregion
