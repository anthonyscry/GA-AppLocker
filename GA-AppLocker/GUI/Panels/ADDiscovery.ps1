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

    # Wire up text filter box for machine search
    $filterBox = $Window.FindName('MachineFilterBox')
    if ($filterBox) {
        $script:ADDiscovery_Handlers['filterBox'] = {
            param($sender, $e)
            if (-not $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) { return }

            $text = $sender.Text.Trim()
            if ([string]::IsNullOrEmpty($text)) {
                $filtered = $script:DiscoveredMachines
            } else {
                $filtered = @($script:DiscoveredMachines | Where-Object {
                    $_.Hostname -like "*$text*" -or
                    $_.MachineType -like "*$text*" -or
                    $_.OperatingSystem -like "*$text*" -or
                    $_.DistinguishedName -like "*$text*"
                })
            }

            $win = $script:MainWindow
            if (-not $win) { $win = $global:GA_MainWindow }
            Update-MachineDataGrid -Window $win -Machines $filtered

            $machineCount = $win.FindName('DiscoveryMachineCount')
            if ($machineCount) {
                if ([string]::IsNullOrEmpty($text)) {
                    $machineCount.Text = "$($filtered.Count) machines"
                } else {
                    $machineCount.Text = "$($filtered.Count) of $($script:DiscoveredMachines.Count) machines (filter: '$text')"
                }
            }
        }
        $filterBox.Add_TextChanged($script:ADDiscovery_Handlers['filterBox'])
    }

    # Wire up machine type filter buttons (All, Workstations, Servers, DCs, Online)
    $filterButtons = @{
        'BtnFilterAll'          = { $null }
        'BtnFilterWorkstations' = { 'Workstation' }
        'BtnFilterServers'      = { 'Server' }
        'BtnFilterDCs'          = { 'DomainController' }
        'BtnFilterOnline'       = { 'Online' }
    }
    foreach ($btnName in $filterButtons.Keys) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $filterValue = $filterButtons[$btnName]
            $script:ADDiscovery_Handlers[$btnName] = {
                param($sender, $e)
                if (-not $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) { return }

                # Determine filter type from button name
                $clickedName = $sender.Name
                $filterType = switch ($clickedName) {
                    'BtnFilterAll'          { $null }
                    'BtnFilterWorkstations' { 'Workstation' }
                    'BtnFilterServers'      { 'Server' }
                    'BtnFilterDCs'          { 'DomainController' }
                    'BtnFilterOnline'       { 'Online' }
                }

                # Apply filter
                if (-not $filterType) {
                    $filtered = $script:DiscoveredMachines
                } elseif ($filterType -eq 'Online') {
                    $filtered = @($script:DiscoveredMachines | Where-Object { $_.IsOnline -eq $true })
                } else {
                    $filtered = @($script:DiscoveredMachines | Where-Object { $_.MachineType -eq $filterType })
                }

                $win = $script:MainWindow
                if (-not $win) { $win = $global:GA_MainWindow }
                Update-MachineDataGrid -Window $win -Machines $filtered

                $machineCount = $win.FindName('DiscoveryMachineCount')
                if ($machineCount) {
                    if (-not $filterType) {
                        $machineCount.Text = "$($filtered.Count) machines"
                    } else {
                        $machineCount.Text = "$($filtered.Count) of $($script:DiscoveredMachines.Count) machines ($filterType)"
                    }
                }

                # Update button visual states — highlight active filter
                $allBtnNames = @('BtnFilterAll','BtnFilterWorkstations','BtnFilterServers','BtnFilterDCs','BtnFilterOnline')
                foreach ($name in $allBtnNames) {
                    $b = $win.FindName($name)
                    if ($b) {
                        if ($name -eq $clickedName) {
                            $b.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x3E, 0x3E, 0x42))
                            $b.Foreground = [System.Windows.Media.Brushes]::White
                        } else {
                            $b.Background = [System.Windows.Media.Brushes]::Transparent
                            $b.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x99, 0x99, 0x99))
                        }
                    }
                }
            }
            $btn.Add_Click($script:ADDiscovery_Handlers[$btnName])
        }
    }

    # Wire up OUTreeView selection to filter machines (Bug 3: missing feature)
    $treeView = $Window.FindName('OUTreeView')
    if ($treeView) {
        $script:ADDiscovery_Handlers['treeViewSelected'] = {
            param($sender, $e)
            $selectedItem = $sender.SelectedItem
            if ($null -eq $selectedItem) { return }
            $selectedDN = $selectedItem.Tag
            if (-not $selectedDN) { return }

            if (-not $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) { return }

            # Filter machines whose DistinguishedName ends with the selected OU's DN
            $filtered = @($script:DiscoveredMachines | Where-Object {
                $_.DistinguishedName -like "*,$selectedDN" -or
                $_.DistinguishedName -like "*$selectedDN"
            })

            Update-MachineDataGrid -Window $Window -Machines $filtered

            $machineCount = $Window.FindName('DiscoveryMachineCount')
            if ($machineCount) {
                $machineCount.Text = "$($filtered.Count) of $($script:DiscoveredMachines.Count) machines (filtered by OU)"
            }
        }
        $treeView.Add_SelectedItemChanged($script:ADDiscovery_Handlers['treeViewSelected'])
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
    
    # Remove filter box handler
    if ($script:ADDiscovery_Handlers['filterBox']) {
        $filterBox = $Window.FindName('MachineFilterBox')
        if ($filterBox) {
            try { $filterBox.Remove_TextChanged($script:ADDiscovery_Handlers['filterBox']) } catch { }
        }
    }
    
    # Remove filter button handlers
    foreach ($btnName in @('BtnFilterAll','BtnFilterWorkstations','BtnFilterServers','BtnFilterDCs','BtnFilterOnline')) {
        if ($script:ADDiscovery_Handlers[$btnName]) {
            $btn = $Window.FindName($btnName)
            if ($btn) {
                try { $btn.Remove_Click($script:ADDiscovery_Handlers[$btnName]) } catch { }
            }
        }
    }

    # Remove TreeView selection handler
    if ($script:ADDiscovery_Handlers['treeViewSelected']) {
        $treeView = $Window.FindName('OUTreeView')
        if ($treeView) {
            try { $treeView.Remove_SelectedItemChanged($script:ADDiscovery_Handlers['treeViewSelected']) } catch { }
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
        # Add status icon property for display
        # Wrap in @() to ensure array for DataGrid ItemsSource (PS 5.1 compatible)
        $machinesWithIcon = @($Machines | ForEach-Object {
            $statusIcon = switch ($_.IsOnline) {
                $true  { [char]0x2714 }   # ✔ (online)
                $false { [char]0x2716 }   # ✖ (offline)
                default { [char]0x2013 }  # – (unknown)
            }
            $_ | Add-Member -NotePropertyName 'StatusIcon' -NotePropertyValue $statusIcon -Force
            # Output the object once (do NOT use -PassThru above, it causes duplicate output)
            $_
        })

        $dataGrid.ItemsSource = $machinesWithIcon
    }
}

function global:Get-CheckedMachines {
    <#
    .SYNOPSIS
        Returns selected (highlighted) machines from the MachineDataGrid.
    .DESCRIPTION
        Uses DataGrid's built-in SelectedItems (blue highlight rows via click/Shift/Ctrl).
        If no machines are selected, returns an empty array.
        Filters out non-machine objects (e.g. WPF NewItemPlaceholder).
        Used by Test Connectivity and Scanner to operate on selected machines only.
    #>
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('MachineDataGrid')
    if (-not $dataGrid -or $dataGrid.SelectedItems.Count -eq 0) { return @() }

    $selected = @($dataGrid.SelectedItems | Where-Object {
        $_ -ne $null -and
        $_.PSObject -ne $null -and
        $_.PSObject.Properties.Name -contains 'Hostname'
    })
    return $selected
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
            # Merge tested results back into the full machine list (don't overwrite)
            # This preserves untested machines when only a subset was checked
            $testedByHost = @{}
            foreach ($m in $Result.Data) {
                $testedByHost[$m.Hostname] = $m
            }
            for ($i = 0; $i -lt $script:DiscoveredMachines.Count; $i++) {
                $host_ = $script:DiscoveredMachines[$i].Hostname
                if ($testedByHost.ContainsKey($host_)) {
                    $script:DiscoveredMachines[$i] = $testedByHost[$host_]
                }
            }

            Update-MachineDataGrid -Window $Window -Machines $script:DiscoveredMachines
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
