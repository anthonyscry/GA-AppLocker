<#
.SYNOPSIS
    Code-behind for MainWindow.xaml

.DESCRIPTION
    Handles navigation events and panel switching for the
    GA-AppLocker Dashboard main window.

.NOTES
    This file is loaded by Start-AppLockerDashboard after
    the XAML window is created.
#>

#region ===== SCRIPT-LEVEL VARIABLES =====
# Store window reference for event handlers
$script:MainWindow = $null
$script:DiscoveredOUs = @()
$script:DiscoveredMachines = @()
#endregion

#region ===== NAVIGATION HANDLERS =====
# Panel visibility management (script scope for event handler access)
function script:Set-ActivePanel {
    param([string]$PanelName)

    if (-not $script:MainWindow) { return }
    $Window = $script:MainWindow

    # All panel names
    $panels = @(
        'PanelDashboard',
        'PanelDiscovery',
        'PanelScanner',
        'PanelRules',
        'PanelPolicy',
        'PanelDeploy',
        'PanelSettings'
    )

    # Nav button names mapped to panels
    $navMap = @{
        'NavDashboard' = 'PanelDashboard'
        'NavDiscovery' = 'PanelDiscovery'
        'NavScanner'   = 'PanelScanner'
        'NavRules'     = 'PanelRules'
        'NavPolicy'    = 'PanelPolicy'
        'NavDeploy'    = 'PanelDeploy'
        'NavSettings'  = 'PanelSettings'
    }

    # Hide all panels
    foreach ($panel in $panels) {
        $element = $Window.FindName($panel)
        if ($element) {
            $element.Visibility = 'Collapsed'
        }
    }

    # Show selected panel
    $targetPanel = $Window.FindName($PanelName)
    if ($targetPanel) {
        $targetPanel.Visibility = 'Visible'
    }

    # Update nav button states
    foreach ($navName in $navMap.Keys) {
        $navButton = $Window.FindName($navName)
        if ($navButton) {
            if ($navMap[$navName] -eq $PanelName) {
                $navButton.Tag = 'Active'
            }
            else {
                $navButton.Tag = $null
            }
        }
    }

    # Log navigation
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message "Navigated to: $PanelName" -NoConsole
    }
}

# Wire up navigation event handlers
function Initialize-Navigation {
    param([System.Windows.Window]$Window)

    $navButtons = @(
        @{ Name = 'NavDashboard'; Panel = 'PanelDashboard' },
        @{ Name = 'NavDiscovery'; Panel = 'PanelDiscovery' },
        @{ Name = 'NavScanner';   Panel = 'PanelScanner' },
        @{ Name = 'NavRules';     Panel = 'PanelRules' },
        @{ Name = 'NavPolicy';    Panel = 'PanelPolicy' },
        @{ Name = 'NavDeploy';    Panel = 'PanelDeploy' },
        @{ Name = 'NavSettings';  Panel = 'PanelSettings' }
    )

    foreach ($nav in $navButtons) {
        $navButton = $Window.FindName($nav.Name)
        if ($navButton) {
            $panelName = $nav.Panel
            $navButton.Add_Click({
                script:Set-ActivePanel -PanelName $panelName
            }.GetNewClosure())
        }
    }
}
#endregion

#region ===== DISCOVERY PANEL HANDLERS =====

function Initialize-DiscoveryPanel {
    param([System.Windows.Window]$Window)

    # Wire up Refresh Domain button
    $btnRefresh = $Window.FindName('BtnRefreshDomain')
    if ($btnRefresh) {
        $btnRefresh.Add_Click({
            Invoke-DomainRefresh -Window $Window
        }.GetNewClosure())
    }

    # Wire up Test Connectivity button
    $btnTest = $Window.FindName('BtnTestConnectivity')
    if ($btnTest) {
        $btnTest.Add_Click({
            Invoke-ConnectivityTest -Window $Window
        }.GetNewClosure())
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

        $summary = $testResult.Summary
        if ($machineCount) {
            $machineCount.Text = "$($summary.OnlineCount)/$($summary.TotalMachines) online, $($summary.WinRMAvailable) WinRM"
        }
    }
}
#endregion

#region ===== WINDOW INITIALIZATION =====
function Initialize-MainWindow {
    param(
        [System.Windows.Window]$Window
    )

    # Store window reference for script-level access
    $script:MainWindow = $Window

    # Set up navigation
    Initialize-Navigation -Window $Window

    # Initialize Discovery panel
    Initialize-DiscoveryPanel -Window $Window

    # Update domain info in status bar
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $domainText = $Window.FindName('DomainText')
        if ($domainText -and $computerSystem.PartOfDomain) {
            $domainText.Text = "Domain: $($computerSystem.Domain)"
        }
    }
    catch {
        # Silently fail - not critical
    }

    # Update data path in settings
    $settingsPath = $Window.FindName('SettingsDataPath')
    if ($settingsPath) {
        $settingsPath.Text = Get-AppLockerDataPath
    }

    Write-AppLockerLog -Message 'Main window initialized'
}
#endregion
