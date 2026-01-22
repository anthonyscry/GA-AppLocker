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
            if ($domainLabel) {
                $domainLabel.Text = "Domain: Error - $($Result.DomainResult.Error)"
                $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            }
        }
    }.GetNewClosure()

    $onError = {
        param($ErrorMessage)
        if ($domainLabel) {
            $domainLabel.Text = "Domain: Error - $ErrorMessage"
            $domainLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
    }.GetNewClosure()

    # Use async if requested and available
    if ($Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
        Invoke-AsyncOperation -ScriptBlock $discoveryWork -LoadingMessage 'Discovering domain...' -LoadingSubMessage 'Querying Active Directory' -OnComplete $onComplete -OnError $onError
    }
    else {
        # Synchronous fallback
        try {
            $result = & $discoveryWork
            & $onComplete -Result $result
        }
        catch {
            & $onError -ErrorMessage $_.Exception.Message
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

    # Use async if requested and available
    if ($Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
        Invoke-AsyncOperation -ScriptBlock {
            param($Machines)
            Test-MachineConnectivity -Machines $Machines
        } -Arguments @{ Machines = $machines } -LoadingMessage 'Testing connectivity...' -LoadingSubMessage "Checking $($machines.Count) machines" -OnComplete $onComplete
    }
    else {
        # Synchronous fallback
        $testResult = Test-MachineConnectivity -Machines $machines
        & $onComplete -Result $testResult
    }
}

#endregion
