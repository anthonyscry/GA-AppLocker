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
    }.GetNewClosure()

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
    }.GetNewClosure()

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
        # Wrap in @() to ensure array for DataGrid ItemsSource (PS 5.1 compatible)
        $machinesWithIcon = @($Machines | ForEach-Object {
            $statusIcon = switch ($_.IsOnline) {
                $true { '&#x1F7E2;' }
                $false { '&#x1F534;' }
                default { '&#x26AA;' }
            }
            $_ | Add-Member -NotePropertyName 'StatusIcon' -NotePropertyValue $statusIcon -PassThru -Force
        })

        $dataGrid.ItemsSource = $machinesWithIcon
    }
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

    $machines = $script:DiscoveredMachines

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
    }.GetNewClosure()

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
