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
            try { $btnRefresh.Remove_Click($script:ADDiscovery_Handlers['btnRefresh']) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove BtnRefreshDomain click handler: $_" -Level DEBUG }
        }
    }

    # Remove Test button handler
    if ($script:ADDiscovery_Handlers['btnTest']) {
        $btnTest = $Window.FindName('BtnTestConnectivity')
        if ($btnTest) {
            try { $btnTest.Remove_Click($script:ADDiscovery_Handlers['btnTest']) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove BtnTestConnectivity click handler: $_" -Level DEBUG }
        }
    }

    # Remove filter box handler
    if ($script:ADDiscovery_Handlers['filterBox']) {
        $filterBox = $Window.FindName('MachineFilterBox')
        if ($filterBox) {
            try { $filterBox.Remove_TextChanged($script:ADDiscovery_Handlers['filterBox']) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove MachineFilterBox text changed handler: $_" -Level DEBUG }
        }
    }

    # Remove filter debounce timer handler
    if ($script:ADDiscovery_Handlers['filterTimerTick'] -and $script:ADDiscovery_FilterTimer) {
        try { $script:ADDiscovery_FilterTimer.Remove_Tick($script:ADDiscovery_Handlers['filterTimerTick']) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove filter timer tick handler: $_" -Level DEBUG }
        try { $script:ADDiscovery_FilterTimer.Stop() } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to stop filter debounce timer: $_" -Level DEBUG }
    }

    # Remove filter button handlers
    foreach ($btnName in @('BtnFilterAll','BtnFilterWorkstations','BtnFilterServers','BtnFilterDCs','BtnFilterOnline')) {
        if ($script:ADDiscovery_Handlers[$btnName]) {
            $btn = $Window.FindName($btnName)
            if ($btn) {
                try { $btn.Remove_Click($script:ADDiscovery_Handlers[$btnName]) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove $btnName click handler: $_" -Level DEBUG }
            }
        }
    }

    # Remove TreeView selection handler
    if ($script:ADDiscovery_Handlers['treeViewSelected']) {
        $treeView = $Window.FindName('OUTreeView')
        if ($treeView) {
            try { $treeView.Remove_SelectedItemChanged($script:ADDiscovery_Handlers['treeViewSelected']) } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to remove OUTreeView selection handler: $_" -Level DEBUG }
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
        $machinesWithIcon = @($Machines | Where-Object { $_ -ne $null } | ForEach-Object {
            $statusIcon = switch ($_.IsOnline) {
                $true  { [char]0x2714 }   # check (online)
                $false { [char]0x2716 }   # x (offline)
                default { [char]0x2013 }  # dash (unknown)
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

    if ($global:GA_ConnTest_InProgress) {
        Show-Toast -Message 'Connectivity test already running. Please wait.' -Type 'Info'
        return
    }

    if ($null -eq $script:DiscoveredMachines -or $script:DiscoveredMachines.Count -eq 0) {
        Show-AppLockerMessageBox 'No machines discovered. Click "Refresh Domain" first.' 'No Machines' 'OK' 'Information'
        return
    }

    $machineCount = $win.FindName('DiscoveryMachineCount')
    if ($machineCount) { $machineCount.Text = 'Testing connectivity...' }

    $checkedMachines = @(Get-CheckedMachines -Window $win)
    if ($checkedMachines.Count -gt 0) {
        $machines = $checkedMachines
    }
    else {
        $machines = $script:DiscoveredMachines
    }

    # Build plain hostname array (serializable for background runspace)
    $hostnameList = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $machines) {
        if ($m -and $m.Hostname) { [void]$hostnameList.Add([string]$m.Hostname) }
    }
    $hostnames = $hostnameList.ToArray()

    if ($hostnames.Count -eq 0) {
        Show-Toast -Message 'No valid hostnames selected for connectivity test.' -Type 'Warning'
        return
    }

    # Stash cross-scope data in $global: for the OnComplete callback
    # (OnComplete runs on UI thread but outside the original $script: scope)
    $global:GA_ConnTest_Machines     = $machines
    $global:GA_ConnTest_AllMachines  = $script:DiscoveredMachines
    $global:GA_ConnTest_FilterText   = $script:ADDiscovery_FilterText
    $global:GA_ConnTest_InProgress   = $true

    # Self-contained background scriptblock (NO module imports)
    $bgWork = {
        param([string[]]$Hostnames, [int]$PingTimeoutMs, [int]$WinrmDeadlineSec)

        $pingResults = @{}
        $winrmResults = @{}
        $onlineCount = 0
        $winrmCount = 0

        # Ping phase: parallel runspace pool
        if ($Hostnames.Count -le 5) {
            foreach ($h in $Hostnames) {
                try {
                    $ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$h' AND Timeout=$PingTimeoutMs" -ErrorAction SilentlyContinue
                    $pingResults[$h] = ($null -ne $ping -and $ping.StatusCode -eq 0)
                }
                catch { $pingResults[$h] = $false }
            }
        }
        else {
            $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min(20, $Hostnames.Count))
            $pool.Open()
            $jobs = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($h in $Hostnames) {
                $p = [PowerShell]::Create()
                $p.RunspacePool = $pool
                [void]$p.AddScript({
                    param($hn, $t)
                    try {
                        $ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$hn' AND Timeout=$t" -ErrorAction Stop
                        return @{ Hostname = $hn; Success = ($null -ne $ping -and $ping.StatusCode -eq 0) }
                    }
                    catch { return @{ Hostname = $hn; Success = $false } }
                }).AddArgument($h).AddArgument($PingTimeoutMs)
                [void]$jobs.Add([PSCustomObject]@{ PS = $p; Handle = $p.BeginInvoke(); Host = $h })
            }
            $perPingWaitMs = [Math]::Max(1000, $PingTimeoutMs + 5000)
            foreach ($j in $jobs) {
                try {
                    if ($j.Handle.AsyncWaitHandle.WaitOne([int]$perPingWaitMs)) {
                        $r = $j.PS.EndInvoke($j.Handle)
                        if ($r -and $r.Hostname) { $pingResults[$r.Hostname] = $r.Success }
                        else { $pingResults[$j.Host] = $false }
                    }
                    else { $pingResults[$j.Host] = $false; try { $j.PS.Stop() } catch { } }
                }
                catch { $pingResults[$j.Host] = $false }
                finally { $j.PS.Dispose() }
            }
            $pool.Close(); $pool.Dispose()
        }

        $onlineHosts = [System.Collections.Generic.List[string]]::new()
        foreach ($h in $Hostnames) {
            if ($pingResults[$h]) { $onlineCount++; [void]$onlineHosts.Add($h) }
        }

        # WinRM phase: parallel runspace pool for online hosts
        if ($onlineHosts.Count -gt 0) {
            $pool2 = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min(20, $onlineHosts.Count))
            $pool2.Open()
            $jobs2 = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($h in $onlineHosts) {
                $p = [PowerShell]::Create()
                $p.RunspacePool = $pool2
                [void]$p.AddScript({
                    param($hn)
                    try { $null = Test-WSMan -ComputerName $hn -ErrorAction Stop; return @{ Hostname = $hn; Available = $true } }
                    catch { return @{ Hostname = $hn; Available = $false } }
                }).AddArgument($h)
                [void]$jobs2.Add([PSCustomObject]@{ PS = $p; Handle = $p.BeginInvoke(); Host = $h })
            }
            $perWinrmWaitMs = [Math]::Max(1000, $WinrmDeadlineSec * 1000)
            foreach ($j in $jobs2) {
                try {
                    if ($j.Handle.AsyncWaitHandle.WaitOne([int]$perWinrmWaitMs)) {
                        $r = $j.PS.EndInvoke($j.Handle)
                        if ($r -and $r.Hostname) { $winrmResults[$r.Hostname] = $r.Available }
                        else { $winrmResults[$j.Host] = $false }
                    }
                    else { $winrmResults[$j.Host] = $false; try { $j.PS.Stop() } catch { } }
                }
                catch { $winrmResults[$j.Host] = $false }
                finally { $j.PS.Dispose() }
            }
            $pool2.Close(); $pool2.Dispose()
            foreach ($h in $onlineHosts) { if ($winrmResults[$h]) { $winrmCount++ } }
        }

        return @{ PingResults = $pingResults; WinrmResults = $winrmResults; OnlineCount = $onlineCount; WinrmCount = $winrmCount; TotalCount = $Hostnames.Count }
    }

    # OnComplete runs on UI thread -- uses $global: for cross-scope data
    $onComplete = {
        param($bg)
        $win = $global:GA_MainWindow
        $machines     = $global:GA_ConnTest_Machines
        $allMachines  = $global:GA_ConnTest_AllMachines
        $filterText   = $global:GA_ConnTest_FilterText

        # Map results onto machine objects
        foreach ($m in $machines) {
            if ($null -eq $m) { continue }
            $h = $m.Hostname
            $isOnline = $false
            if ($bg -and $bg.PingResults -and $bg.PingResults.ContainsKey($h)) {
                $isOnline = [bool]$bg.PingResults[$h]
            }
            if ($m.PSObject.Properties['IsOnline']) { $m.IsOnline = $isOnline }
            else { $m | Add-Member -NotePropertyName 'IsOnline' -NotePropertyValue $isOnline -Force }

            $winrmStatus = 'Offline'
            if ($isOnline) {
                $winrmAvail = $false
                if ($bg -and $bg.WinrmResults -and $bg.WinrmResults.ContainsKey($h)) {
                    $winrmAvail = [bool]$bg.WinrmResults[$h]
                }
                $winrmStatus = if ($winrmAvail) { 'Available' } else { 'Unavailable' }
            }
            if ($m.PSObject.Properties['WinRMStatus']) { $m.WinRMStatus = $winrmStatus }
            else { $m | Add-Member -NotePropertyName 'WinRMStatus' -NotePropertyValue $winrmStatus -Force }
        }

        # Merge tested machines back into the full discovered list
        $testedByHost = @{}
        foreach ($m in $machines) {
            if ($null -ne $m -and $m.Hostname) { $testedByHost[$m.Hostname] = $m }
        }
        if ($allMachines -and $allMachines.Count -gt 0) {
            for ($i = 0; $i -lt $allMachines.Count; $i++) {
                $h_ = $allMachines[$i].Hostname
                if ($h_ -and $testedByHost.ContainsKey($h_)) { $allMachines[$i] = $testedByHost[$h_] }
            }
        }

        # Refresh DataGrid
        $machinesForGrid = if ($allMachines) { $allMachines } else { $machines }
        $ft = if ($filterText) { $filterText.Trim() } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($ft)) {
            $machinesForGrid = @($machinesForGrid | Where-Object {
                $_ -ne $null -and ($_.Hostname -like "*$ft*" -or $_.MachineType -like "*$ft*" -or $_.OperatingSystem -like "*$ft*" -or $_.DistinguishedName -like "*$ft*")
            })
        }
        Update-MachineDataGrid -Window $win -Machines $machinesForGrid
        $dataGrid = $win.FindName('MachineDataGrid')
        if ($dataGrid) { $dataGrid.Items.Refresh() }
        try { Update-WorkflowBreadcrumb -Window $win } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to update workflow breadcrumb after connectivity test: $_" -Level DEBUG }

        $onlineN = if ($bg) { $bg.OnlineCount } else { 0 }
        $winrmN  = if ($bg) { $bg.WinrmCount } else { 0 }
        $totalN  = if ($bg) { $bg.TotalCount } else { 0 }
        $mc = $win.FindName('DiscoveryMachineCount')
        if ($mc) { $mc.Text = "$onlineN/$totalN online, $winrmN WinRM" }
        Show-Toast -Message "Connectivity complete. WinRM available: $winrmN." -Type 'Info'
        try { global:Update-WinRMAvailableCount -Window $win } catch { Write-AppLockerLog -Message "[ADDiscovery] Failed to update WinRM available count after connectivity test: $_" -Level DEBUG }

        # Cleanup globals
        $global:GA_ConnTest_Machines    = $null
        $global:GA_ConnTest_AllMachines = $null
        $global:GA_ConnTest_FilterText  = $null
        $global:GA_ConnTest_InProgress  = $false
    }

    $onTimeout = {
        param($TimeoutMessage)
        $win = $global:GA_MainWindow
        if ($win) {
            $mc = $win.FindName('DiscoveryMachineCount')
            if ($mc) { $mc.Text = 'Connectivity test timed out' }
        }
        Show-Toast -Message "$TimeoutMessage Try fewer machines or re-run connectivity test." -Type 'Warning'

        # Cleanup globals
        $global:GA_ConnTest_Machines    = $null
        $global:GA_ConnTest_AllMachines = $null
        $global:GA_ConnTest_FilterText  = $null
        $global:GA_ConnTest_InProgress  = $false
    }

    # Scale timeout by runspace batches (20 max concurrency)
    $batchCount = [Math]::Ceiling([double]$hostnames.Count / 20.0)
    $dynamicTimeout = [Math]::Max(90, [int](60 + ($batchCount * 45)))

    Invoke-BackgroundWork -ScriptBlock $bgWork `
        -ArgumentList @($hostnames, 5000, 30) `
        -OnComplete $onComplete `
        -OnTimeout $onTimeout `
        -LoadingMessage 'Testing connectivity...' `
        -LoadingSubMessage "Checking $($hostnames.Count) machines (ping + WinRM)" `
        -TimeoutSeconds $dynamicTimeout
}

#endregion
