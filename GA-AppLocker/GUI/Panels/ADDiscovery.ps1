#region AD Discovery Panel Functions
# ADDiscovery.ps1 - AD/OU discovery and machine selection

# Script-scoped handler storage for cleanup
$script:ADDiscovery_Handlers = @{}
$script:ADDiscovery_FilterTimer = $null
$script:ADDiscovery_FilterWindow = $null
$script:ADDiscovery_FilterText = ''

function Initialize-DiscoveryPanel {
    param($Window)
    
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

    # Wire up Refresh Machines button
    $btnRefreshMachines = $Window.FindName('BtnRefreshMachines')
    if ($btnRefreshMachines) {
        $script:ADDiscovery_Handlers['btnRefreshMachines'] = {
            $win = $script:MainWindow
            if (-not $win) { $win = $global:GA_MainWindow }
            if ($script:DiscoveredMachines -and $script:DiscoveredMachines.Count -gt 0) {
                Update-MachineDataGrid -Window $win -Machines $script:DiscoveredMachines
                $machineCount = $win.FindName('DiscoveryMachineCount')
                if ($machineCount) {
                    $machineCount.Text = "$($script:DiscoveredMachines.Count) machines"
                }
            }
        }
        $btnRefreshMachines.Add_Click($script:ADDiscovery_Handlers['btnRefreshMachines'])
    }

    # Wire up DataGrid SelectionChanged to update selected count
    $dataGrid = $Window.FindName('MachineDataGrid')
    if ($dataGrid) {
        $script:ADDiscovery_Handlers['dataGridSelection'] = {
            param($sender, $e)
            $win = $script:MainWindow
            if (-not $win) { $win = $global:GA_MainWindow }
            $selectedCount = $win.FindName('TxtMachineSelectedCount')
            if ($selectedCount) {
                $count = 0
                if ($sender.SelectedItems) {
                    try { $count = @($sender.SelectedItems).Count } catch { $count = 0 }
                }
                $selectedCount.Text = "Selected: $count"
            }
        }
        $dataGrid.Add_SelectionChanged($script:ADDiscovery_Handlers['dataGridSelection'])
    }

    # Wire up text filter box for machine search (debounced)
    $filterBox = $Window.FindName('MachineFilterBox')
    if ($filterBox) {
        $script:ADDiscovery_FilterWindow = $Window

        if (-not $script:ADDiscovery_FilterTimer) {
            $script:ADDiscovery_FilterTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:ADDiscovery_FilterTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        }

        if ($script:ADDiscovery_Handlers['filterTimerTick']) {
            $script:ADDiscovery_FilterTimer.Remove_Tick($script:ADDiscovery_Handlers['filterTimerTick'])
        }

        $script:ADDiscovery_Handlers['filterTimerTick'] = {
            param($sender, $e)
            $sender.Stop()

            if (-not $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) { return }

            $text = $script:ADDiscovery_FilterText
            if ([string]::IsNullOrEmpty($text)) {
                $filtered = $script:DiscoveredMachines
            }
            else {
                $filtered = @($script:DiscoveredMachines | Where-Object {
                    $_.Hostname -like "*$text*" -or
                    $_.MachineType -like "*$text*" -or
                    $_.OperatingSystem -like "*$text*" -or
                    $_.DistinguishedName -like "*$text*"
                })
            }

            $win = $script:ADDiscovery_FilterWindow
            if (-not $win) { $win = $script:MainWindow }
            if (-not $win) { $win = $global:GA_MainWindow }
            if (-not $win) { return }

            Update-MachineDataGrid -Window $win -Machines $filtered

            $machineCount = $win.FindName('DiscoveryMachineCount')
            if ($machineCount) {
                if ([string]::IsNullOrEmpty($text)) {
                    $machineCount.Text = "$($filtered.Count) machines"
                }
                else {
                    $machineCount.Text = "$($filtered.Count) of $($script:DiscoveredMachines.Count) machines (filter: '$text')"
                }
            }
        }
        $script:ADDiscovery_FilterTimer.Add_Tick($script:ADDiscovery_Handlers['filterTimerTick'])

        $script:ADDiscovery_Handlers['filterBox'] = {
            param($sender, $e)
            $script:ADDiscovery_FilterText = $sender.Text.Trim()
            if ($script:ADDiscovery_FilterTimer) {
                $script:ADDiscovery_FilterTimer.Stop()
                $script:ADDiscovery_FilterTimer.Start()
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

    # Wire up Select All / Clear OUs buttons
    $btnSelectAllOUs = $Window.FindName('BtnSelectAllOUs')
    if ($btnSelectAllOUs) {
        $script:ADDiscovery_Handlers['BtnSelectAllOUs'] = {
            param($sender, $e)
            Show-Toast -Message "Bulk OU selection is not yet available." -Type 'Info'
        }
        $btnSelectAllOUs.Add_Click($script:ADDiscovery_Handlers['BtnSelectAllOUs'])
    }

    $btnClearOUs = $Window.FindName('BtnClearOUs')
    if ($btnClearOUs) {
        $script:ADDiscovery_Handlers['BtnClearOUs'] = {
            param($sender, $e)
            # Reset filter to show all machines
            if ($script:DiscoveredMachines) {
                Update-MachineDataGrid -Window $Window -Machines $script:DiscoveredMachines
                
                $machineCount = $Window.FindName('DiscoveryMachineCount')
                if ($machineCount) {
                    $machineCount.Text = "$($script:DiscoveredMachines.Count) machines"
                }
            }
        }
        $btnClearOUs.Add_Click($script:ADDiscovery_Handlers['BtnClearOUs'])
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
    param($Window)
    
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

    # Remove filter debounce timer handler
    if ($script:ADDiscovery_Handlers['filterTimerTick'] -and $script:ADDiscovery_FilterTimer) {
        try { $script:ADDiscovery_FilterTimer.Remove_Tick($script:ADDiscovery_Handlers['filterTimerTick']) } catch { }
        try { $script:ADDiscovery_FilterTimer.Stop() } catch { }
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
    
    # Clear stored handlers/state
    $script:ADDiscovery_Handlers = @{}
    $script:ADDiscovery_FilterWindow = $null
    $script:ADDiscovery_FilterText = ''
}

function global:Invoke-DomainRefresh {
    param(
        $Window,
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
            if ($Result.OUResult -and $Result.OUResult.Success -and $treeView) {
                $script:DiscoveredOUs = $Result.OUResult.Data
                Update-OUTreeView -TreeView $treeView -OUs $Result.OUResult.Data
            }
            elseif ($treeView) {
                # Clear "Loading..." placeholder and show error or empty state
                $treeView.Items.Clear()
                $ouErrorItem = [System.Windows.Controls.TreeViewItem]::new()
                $ouErrMsg = if ($Result.OUResult -and $Result.OUResult.Error) { $Result.OUResult.Error } else { 'OU enumeration returned no data' }
                $ouErrorItem.Header = $ouErrMsg
                $ouErrorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                [void]$treeView.Items.Add($ouErrorItem)
            }

            # Update machine grid — merge new AD data with existing connectivity status
            if ($Result.ComputerResult -and $Result.ComputerResult.Success) {
                $newMachines = $Result.ComputerResult.Data

                # Preserve connectivity results (IsOnline, WinRMStatus) from prior Test-MachineConnectivity
                if ($script:DiscoveredMachines -and $script:DiscoveredMachines.Count -gt 0) {
                    $oldByHost = @{}
                    foreach ($m in $script:DiscoveredMachines) {
                        if ($m.Hostname) { $oldByHost[$m.Hostname] = $m }
                    }
                    foreach ($m in $newMachines) {
                        $old = $oldByHost[$m.Hostname]
                        if ($old) {
                            # Copy connectivity fields from previous test results
                            if ($null -ne $old.IsOnline) {
                                $m | Add-Member -NotePropertyName 'IsOnline' -NotePropertyValue $old.IsOnline -Force
                            }
                            if ($old.WinRMStatus -and $old.WinRMStatus -ne 'Unknown') {
                                $m | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue $old.WinRMStatus -Force
                            }
                        }
                    }
                }

                $script:DiscoveredMachines = $newMachines
                Update-MachineDataGrid -Window $Window -Machines $newMachines
                Update-WorkflowBreadcrumb -Window $Window

                if ($machineCount) {
                    # Show connectivity summary if we have test results, otherwise just count
                    $onlineCount = @($newMachines | Where-Object { $_.IsOnline -eq $true }).Count
                    $winrmCount = @($newMachines | Where-Object { $_.WinRMStatus -eq 'Available' }).Count
                    if ($onlineCount -gt 0) {
                        $machineCount.Text = "$($newMachines.Count) machines ($onlineCount online, $winrmCount WinRM)"
                    } else {
                        $machineCount.Text = "$($newMachines.Count) machines discovered"
                    }
                }
            }
        }
        else {
            $errorMsg = if ($Result.DomainResult -and $Result.DomainResult.Error) { $Result.DomainResult.Error } else { 'Unknown error' }
            if ($domainLabel) {
                # Show short error in label
                $shortError = if ($errorMsg -and $errorMsg.Length -gt 50) { $errorMsg.Substring(0, 50) + '...' } else { $errorMsg }
                $domainLabel.Text = "Domain: Error - $shortError"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            }
            # Update tree view to show error state
            if ($treeView) {
                $treeView.Items.Clear()
                $errorItem = [System.Windows.Controls.TreeViewItem]::new()
                $errorItem.Header = "Unable to connect to domain"
                $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                [void]$treeView.Items.Add($errorItem)
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
            $shortError = if ($ErrorMessage -and $ErrorMessage.Length -gt 50) { $ErrorMessage.Substring(0, 50) + '...' } else { $ErrorMessage }
            $domainLabel.Text = "Domain: Error - $shortError"
            $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
        # Update tree view to show error state
        if ($treeView) {
            $treeView.Items.Clear()
            $errorItem = [System.Windows.Controls.TreeViewItem]::new()
            $errorItem.Header = "Unable to connect to domain"
            $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            [void]$treeView.Items.Add($errorItem)
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
            [void]$TreeView.Items.Add($emptyItem)
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

            [void]$TreeView.Items.Add($rootItem)
            $rootItem.IsExpanded = $true
        }
        else {
            $noRootItem = [System.Windows.Controls.TreeViewItem]::new()
            $noRootItem.Header = "No root OU found"
            $noRootItem.Foreground = [System.Windows.Media.Brushes]::Gray
            [void]$TreeView.Items.Add($noRootItem)
        }
    }
    catch {
        # Show error in tree
        $TreeView.Items.Clear()
        $errorItem = [System.Windows.Controls.TreeViewItem]::new()
        $errorItem.Header = "Error building tree: $($_.Exception.Message)"
        $errorItem.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        [void]$TreeView.Items.Add($errorItem)
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

        [void]$ParentItem.Items.Add($childItem)
    }
}

function global:Update-MachineDataGrid {
    param(
        $Window,
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
        Uses multiple fallback methods to get selected rows from the DataGrid:
        1. SelectedItems collection (multi-select via Shift/Ctrl+click)
        2. SelectedItem property (single item click)
        3. SelectedIndex + Items[index] (last resort)
        
        WPF DataGrid has known issues with SelectedItems.Count returning 0 in PowerShell
        COM interop scenarios, even when rows are visually selected. Multiple fallbacks
        ensure we catch the selection regardless of how it was made.
        
        Filters out non-machine objects (e.g. WPF NewItemPlaceholder).
        Used by Test Connectivity and Scanner to operate on selected machines only.
    #>
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) {
        try { Write-AppLockerLog -Message "Get-CheckedMachines: No window available" -Level DEBUG -NoConsole } catch { }
        return @()
    }

    $dataGrid = $win.FindName('MachineDataGrid')
    if (-not $dataGrid) {
        try { Write-AppLockerLog -Message "Get-CheckedMachines: MachineDataGrid not found" -Level DEBUG -NoConsole } catch { }
        return @()
    }

    # Log diagnostic info for debugging selection issues
    $itemsCount = if ($dataGrid.Items) { @($dataGrid.Items).Count } else { 0 }
    $selectedItemsCount = 0
    if ($dataGrid.SelectedItems) {
        try { $selectedItemsCount = @($dataGrid.SelectedItems).Count } catch { $selectedItemsCount = 0 }
    }
    $selectedIndex = $dataGrid.SelectedIndex
    $hasSelectedItem = ($null -ne $dataGrid.SelectedItem)
    try { 
        Write-AppLockerLog -Message "Get-CheckedMachines: DataGrid has $itemsCount items, SelectedItems=$selectedItemsCount, SelectedIndex=$selectedIndex, HasSelectedItem=$hasSelectedItem" -Level INFO -NoConsole 
    } catch { }

    $selected = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Helper function to check if an item is a valid machine object
    $isValidMachine = {
        param($item)
        if ($null -eq $item) { return $false }
        if ($null -eq $item.PSObject) { return $false }
        if ($item.PSObject.Properties.Name -notcontains 'Hostname') { return $false }
        return $true
    }

    # Method 1: Try SelectedItems collection (multi-select)
    if ($dataGrid.SelectedItems) {
        try {
            foreach ($item in $dataGrid.SelectedItems) {
                if (& $isValidMachine $item) {
                    [void]$selected.Add($item)
                }
            }
        } catch {
            try { Write-AppLockerLog -Message "Get-CheckedMachines: SelectedItems enumeration failed: $($_.Exception.Message)" -Level DEBUG -NoConsole } catch { }
        }
    }

    # Method 2: Fallback to SelectedItem (single selection) if SelectedItems yielded nothing
    if ($selected.Count -eq 0 -and $dataGrid.SelectedItem) {
        try { Write-AppLockerLog -Message "Get-CheckedMachines: SelectedItems empty, trying SelectedItem fallback" -Level DEBUG -NoConsole } catch { }
        if (& $isValidMachine $dataGrid.SelectedItem) {
            [void]$selected.Add($dataGrid.SelectedItem)
        }
    }

    # Method 3: Fallback to SelectedIndex if still nothing
    if ($selected.Count -eq 0 -and $selectedIndex -ge 0 -and $dataGrid.Items -and $selectedIndex -lt $itemsCount) {
        try { Write-AppLockerLog -Message "Get-CheckedMachines: Trying SelectedIndex fallback (index=$selectedIndex)" -Level DEBUG -NoConsole } catch { }
        try {
            $item = $dataGrid.Items[$selectedIndex]
            if (& $isValidMachine $item) {
                [void]$selected.Add($item)
            }
        } catch {
            try { Write-AppLockerLog -Message "Get-CheckedMachines: SelectedIndex fallback failed: $($_.Exception.Message)" -Level DEBUG -NoConsole } catch { }
        }
    }

    try { Write-AppLockerLog -Message "Get-CheckedMachines: Returning $($selected.Count) valid machines" -Level INFO -NoConsole } catch { }
    return $selected.ToArray()
}

function global:Invoke-ConnectivityTest {
    param(
        $Window,
        [switch]$Async
    )

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }

    if ($null -eq $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) {
        Show-AppLockerMessageBox 'No machines discovered. Click "Refresh Domain" first.' 'No Machines' 'OK' 'Information'
        return
    }

    $machineCount = $win.FindName('DiscoveryMachineCount')
    if ($machineCount) { $machineCount.Text = 'Testing connectivity...' }

    # Use selected machines if any are selected; otherwise fall back to all discovered machines
    # Wrap in @() to ensure array context is preserved (PS pipeline can lose array wrapper)
    $checkedMachines = @(Get-CheckedMachines -Window $win)
    try { Write-AppLockerLog -Message "Invoke-ConnectivityTest: Get-CheckedMachines returned $($checkedMachines.Count) machines" -Level DEBUG -NoConsole } catch { }

    if ($checkedMachines.Count -gt 0) {
        $machines = $checkedMachines
        if ($machineCount) { $machineCount.Text = "Testing $($machines.Count) selected machines..." }
        try { Write-AppLockerLog -Message "Invoke-ConnectivityTest: Testing $($machines.Count) SELECTED machines" -Level INFO -NoConsole } catch { }
    }
    else {
        $machines = $script:DiscoveredMachines
        try { Write-AppLockerLog -Message "Invoke-ConnectivityTest: No selection, testing ALL $($machines.Count) discovered machines" -Level INFO -NoConsole } catch { }
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

            # Update DataGrid immediately so WinRM status appears without manual refresh
            $machinesForGrid = $script:DiscoveredMachines
            $activeFilterText = if ($script:ADDiscovery_FilterText) { $script:ADDiscovery_FilterText.Trim() } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($activeFilterText)) {
                $machinesForGrid = @($script:DiscoveredMachines | Where-Object {
                    $_.Hostname -like "*$activeFilterText*" -or
                    $_.MachineType -like "*$activeFilterText*" -or
                    $_.OperatingSystem -like "*$activeFilterText*" -or
                    $_.DistinguishedName -like "*$activeFilterText*"
                })
            }

            Update-MachineDataGrid -Window $win -Machines $machinesForGrid

            $dataGrid = $win.FindName('MachineDataGrid')
            if ($dataGrid) {
                $dataGrid.Items.Refresh()
            }
            try { Request-UiRender -Window $win } catch { }
            
            Update-WorkflowBreadcrumb -Window $win

            $summary = $Result.Summary
            if ($machineCount) {
                $machineCount.Text = "$($summary.OnlineCount)/$($summary.TotalMachines) online, $($summary.WinRMAvailable) WinRM"
            }
            Show-Toast -Message "Connectivity complete. WinRM available: $($summary.WinRMAvailable). Return to Scanner to select targets." -Type 'Info'
            try { global:Update-WinRMAvailableCount -Window $win } catch { }
        }
    }.GetNewClosure()

    $onError = {
        param($ErrorMessage)
        if ($machineCount) {
            $machineCount.Text = "Error: $ErrorMessage"
        }
        try { Write-Log -Level Warning -Message "Connectivity test failed: $ErrorMessage" } catch { }
    }

    try {
        Invoke-AsyncOperation -ScriptBlock {
            param($Machines)
            Test-MachineConnectivity -Machines $Machines
        } -Arguments @{ Machines = $machines } -LoadingMessage 'Testing connectivity...' -LoadingSubMessage "Checking $($machines.Count) machines" -TimeoutSeconds 600 -OnComplete {
            param($Result)
            & $onComplete -Result $Result
        } -OnError {
            param($ErrorMessage)
            & $onError -ErrorMessage $ErrorMessage
        }
        return
    }
    catch { }

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
