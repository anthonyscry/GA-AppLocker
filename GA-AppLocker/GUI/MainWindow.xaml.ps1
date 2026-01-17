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

#region ===== SAFE LOGGING WRAPPER =====
# Wrapper to safely call module functions from code-behind scope
function script:Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message $Message -Level $Level -NoConsole
    }
}
#endregion

#region ===== BUTTON ACTION DISPATCHER =====
# Central dispatcher for button clicks - avoids closure scope issues
# Using global scope so scriptblocks can access it
function global:Invoke-ButtonAction {
    param([string]$Action)

    $win = $global:GA_MainWindow
    if (-not $win) { return }

    switch ($Action) {
        # Navigation
        'NavDashboard' { Set-ActivePanel -PanelName 'PanelDashboard' }
        'NavDiscovery' { Set-ActivePanel -PanelName 'PanelDiscovery' }
        'NavScanner' { Set-ActivePanel -PanelName 'PanelScanner' }
        'NavRules' { Set-ActivePanel -PanelName 'PanelRules' }
        'NavPolicy' { Set-ActivePanel -PanelName 'PanelPolicy' }
        'NavDeploy' { Set-ActivePanel -PanelName 'PanelDeploy' }
        'NavSettings' { Set-ActivePanel -PanelName 'PanelSettings' }
        # Discovery panel
        'RefreshDomain' { Invoke-DomainRefresh -Window $win }
        'TestConnectivity' { Invoke-ConnectivityTest -Window $win }
        # Credentials panel
        'SaveCredential' { Invoke-SaveCredential -Window $win }
        'RefreshCredentials' { Update-CredentialsDataGrid -Window $win }
        'TestCredential' { Invoke-TestSelectedCredential -Window $win }
        'DeleteCredential' { Invoke-DeleteSelectedCredential -Window $win }
        'SetDefaultCredential' { Invoke-SetDefaultCredential -Window $win }
    }
}
#endregion

#region ===== SCRIPT-LEVEL VARIABLES =====
# Store window reference for event handlers (global for scriptblock access)
$global:GA_MainWindow = $null
$script:MainWindow = $null
$script:DiscoveredOUs = @()
$script:DiscoveredMachines = @()
#endregion

#region ===== NAVIGATION HANDLERS =====
# Panel visibility management
function Set-ActivePanel {
    param([string]$PanelName)

    # Try script scope first, fall back to global
    $Window = $script:MainWindow
    if (-not $Window) { $Window = $global:GA_MainWindow }
    if (-not $Window) { return }

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
    Write-Log -Message "Navigated to: $PanelName"
}

# Wire up navigation event handlers
function Initialize-Navigation {
    param([System.Windows.Window]$Window)

    # Store window reference
    $script:MainWindow = $Window
    $global:GA_MainWindow = $Window

    # Register each nav button directly - no closures needed
    $btn = $Window.FindName('NavDashboard')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDashboard' }) }

    $btn = $Window.FindName('NavDiscovery')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDiscovery' }) }

    $btn = $Window.FindName('NavScanner')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavScanner' }) }

    $btn = $Window.FindName('NavRules')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavRules' }) }

    $btn = $Window.FindName('NavPolicy')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavPolicy' }) }

    $btn = $Window.FindName('NavDeploy')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavDeploy' }) }

    $btn = $Window.FindName('NavSettings')
    if ($btn) { $btn.Add_Click({ Invoke-ButtonAction -Action 'NavSettings' }) }
}
#endregion

#region ===== DISCOVERY PANEL HANDLERS =====

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

#region ===== CREDENTIALS PANEL HANDLERS =====

function Initialize-CredentialsPanel {
    param([System.Windows.Window]$Window)

    # Wire up Save Credential button
    $btnSave = $Window.FindName('BtnSaveCredential')
    if ($btnSave) {
        $btnSave.Add_Click({ Invoke-ButtonAction -Action 'SaveCredential' })
    }

    # Wire up Refresh Credentials button
    $btnRefresh = $Window.FindName('BtnRefreshCredentials')
    if ($btnRefresh) {
        $btnRefresh.Add_Click({ Invoke-ButtonAction -Action 'RefreshCredentials' })
    }

    # Wire up Test Credential button
    $btnTest = $Window.FindName('BtnTestCredential')
    if ($btnTest) {
        $btnTest.Add_Click({ Invoke-ButtonAction -Action 'TestCredential' })
    }

    # Wire up Delete Credential button
    $btnDelete = $Window.FindName('BtnDeleteCredential')
    if ($btnDelete) {
        $btnDelete.Add_Click({ Invoke-ButtonAction -Action 'DeleteCredential' })
    }

    # Wire up Set Default button
    $btnSetDefault = $Window.FindName('BtnSetDefaultCredential')
    if ($btnSetDefault) {
        $btnSetDefault.Add_Click({ Invoke-ButtonAction -Action 'SetDefaultCredential' })
    }

    # Load existing credentials
    try {
        Update-CredentialsDataGrid -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load credentials: $($_.Exception.Message)"
    }
}

function Invoke-SaveCredential {
    param([System.Windows.Window]$Window)

    $profileName = $Window.FindName('CredProfileName')
    $tierCombo = $Window.FindName('CredTierCombo')
    $username = $Window.FindName('CredUsername')
    $password = $Window.FindName('CredPassword')
    $description = $Window.FindName('CredDescription')
    $setAsDefault = $Window.FindName('CredSetAsDefault')

    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($profileName.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a profile name.', 'Validation Error', 'OK', 'Warning')
        return
    }

    if ([string]::IsNullOrWhiteSpace($username.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a username.', 'Validation Error', 'OK', 'Warning')
        return
    }

    if ($password.SecurePassword.Length -eq 0) {
        [System.Windows.MessageBox]::Show('Please enter a password.', 'Validation Error', 'OK', 'Warning')
        return
    }

    # Build PSCredential
    $securePassword = $password.SecurePassword
    $credential = [PSCredential]::new($username.Text, $securePassword)

    # Get tier from combo box
    $tier = $tierCombo.SelectedIndex

    # Create credential profile
    $params = @{
        Name        = $profileName.Text
        Credential  = $credential
        Tier        = $tier
        Description = $description.Text
    }

    if ($setAsDefault.IsChecked) {
        $params.SetAsDefault = $true
    }

    $result = New-CredentialProfile @params

    if ($result.Success) {
        [System.Windows.MessageBox]::Show(
            "Credential profile '$($profileName.Text)' saved successfully.",
            'Success',
            'OK',
            'Information'
        )

        # Clear form
        $profileName.Text = ''
        $username.Text = ''
        $password.Clear()
        $description.Text = ''
        $setAsDefault.IsChecked = $false

        # Refresh grid
        Update-CredentialsDataGrid -Window $Window
    }
    else {
        [System.Windows.MessageBox]::Show(
            "Failed to save credential: $($result.Error)",
            'Error',
            'OK',
            'Error'
        )
    }
}

function Update-CredentialsDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    if (-not $dataGrid) { return }

    $result = Get-AllCredentialProfiles

    if ($result.Success -and $result.Data) {
        # Add display properties
        $displayData = $result.Data | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'IsDefaultDisplay' -NotePropertyValue $(if ($_.IsDefault) { 'Yes' } else { '' }) -PassThru -Force |
                 Add-Member -NotePropertyName 'LastTestDisplay' -NotePropertyValue $(
                    if ($_.LastTestResult) {
                        $status = if ($_.LastTestResult.Success) { 'Passed' } else { 'Failed' }
                        "$status - $($_.LastTestResult.TestTime)"
                    } else { 'Not tested' }
                 ) -PassThru -Force
        }
        $dataGrid.ItemsSource = $displayData
    }
    else {
        $dataGrid.ItemsSource = $null
    }
}

function Invoke-TestSelectedCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    $testTarget = $Window.FindName('CredTestTarget')
    $resultBorder = $Window.FindName('CredTestResultBorder')
    $resultText = $Window.FindName('CredTestResultText')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to test.', 'No Selection', 'OK', 'Information')
        return
    }

    if ([string]::IsNullOrWhiteSpace($testTarget.Text)) {
        [System.Windows.MessageBox]::Show('Please enter a target hostname to test against.', 'No Target', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem
    $resultBorder.Visibility = 'Visible'
    $resultText.Text = "Testing credential '$($selectedProfile.Name)' against $($testTarget.Text)..."
    $resultText.Foreground = [System.Windows.Media.Brushes]::White

    # Run test
    $testResult = Test-CredentialProfile -Name $selectedProfile.Name -ComputerName $testTarget.Text

    if ($testResult.Success) {
        $resultText.Text = "SUCCESS: Credential '$($selectedProfile.Name)' authenticated to $($testTarget.Text)`n" +
                           "Ping: Passed | WinRM: Passed"
        $resultText.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    else {
        $resultText.Text = "FAILED: $($testResult.Error)`n"
        if ($testResult.Data) {
            $resultText.Text += "Ping: $(if ($testResult.Data.PingSuccess) { 'Passed' } else { 'Failed' }) | " +
                                "WinRM: $(if ($testResult.Data.WinRMSuccess) { 'Passed' } else { 'Failed' })`n" +
                                "Error: $($testResult.Data.ErrorMessage)"
        }
        $resultText.Foreground = [System.Windows.Media.Brushes]::OrangeRed
    }

    # Refresh grid to show updated test result
    Update-CredentialsDataGrid -Window $Window
}

function Invoke-DeleteSelectedCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete credential profile '$($selectedProfile.Name)'?",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $result = Remove-CredentialProfile -Name $selectedProfile.Name

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "Credential profile '$($selectedProfile.Name)' deleted.",
                'Deleted',
                'OK',
                'Information'
            )
            Update-CredentialsDataGrid -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show(
                "Failed to delete: $($result.Error)",
                'Error',
                'OK',
                'Error'
            )
        }
    }
}

function Invoke-SetDefaultCredential {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a credential profile to set as default.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    # Get existing profile
    $profileResult = Get-CredentialProfile -Name $selectedProfile.Name
    if (-not $profileResult.Success) {
        [System.Windows.MessageBox]::Show("Profile not found: $($profileResult.Error)", 'Error', 'OK', 'Error')
        return
    }

    $profile = $profileResult.Data

    # Clear other defaults for same tier
    $allProfiles = Get-AllCredentialProfiles
    if ($allProfiles.Success) {
        foreach ($p in $allProfiles.Data) {
            if ($p.Tier -eq $profile.Tier -and $p.Name -ne $profile.Name -and $p.IsDefault) {
                $p.IsDefault = $false
                $credPath = Get-CredentialStoragePath
                $profilePath = Join-Path $credPath "$($p.Id).json"
                $p | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8
            }
        }
    }

    # Set this profile as default
    $profile.IsDefault = $true
    $credPath = Get-CredentialStoragePath
    $profilePath = Join-Path $credPath "$($profile.Id).json"
    $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8

    [System.Windows.MessageBox]::Show(
        "Credential profile '$($selectedProfile.Name)' set as default for Tier $($profile.Tier).",
        'Default Set',
        'OK',
        'Information'
    )

    Update-CredentialsDataGrid -Window $Window
}

#endregion

#region ===== WINDOW INITIALIZATION =====
function Initialize-MainWindow {
    param(
        [System.Windows.Window]$Window
    )

    # Store window reference for script-level and global access
    $script:MainWindow = $Window
    $global:GA_MainWindow = $Window

    # DEBUG: Log to console to verify function is running
    Write-Host "[DEBUG] Initialize-MainWindow starting..." -ForegroundColor Yellow

    # Set up navigation
    try {
        Initialize-Navigation -Window $Window
        Write-Host "[DEBUG] Navigation initialized" -ForegroundColor Green
    }
    catch {
        Write-Host "[DEBUG] Navigation init failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # TEMPORARILY DISABLED - testing if this causes the close
    <#
    # Initialize Discovery panel
    try {
        Initialize-DiscoveryPanel -Window $Window
        Write-Log -Message 'Discovery panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Discovery panel init failed: $($_.Exception.Message)"
    }

    # Initialize Credentials panel
    try {
        Initialize-CredentialsPanel -Window $Window
        Write-Log -Message 'Credentials panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Credentials panel init failed: $($_.Exception.Message)"
    }
    #>

    Write-Host "[DEBUG] Initialize-MainWindow completed" -ForegroundColor Yellow

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
    if ($settingsPath -and (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue)) {
        $settingsPath.Text = Get-AppLockerDataPath
    }

    Write-Log -Message 'Main window initialized'
}
#endregion
