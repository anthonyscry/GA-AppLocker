#region AD Discovery Panel Functions
# ADDiscovery.ps1 - AD/OU discovery and machine selection

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
