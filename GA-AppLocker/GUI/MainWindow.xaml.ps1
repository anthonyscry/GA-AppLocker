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
        # Scanner panel
        'StartScan' { Invoke-StartArtifactScan -Window $win }
        'StopScan' { Invoke-StopArtifactScan -Window $win }
        'ImportArtifacts' { Invoke-ImportArtifacts -Window $win }
        'ExportArtifacts' { Invoke-ExportArtifacts -Window $win }
        'RefreshScans' { Update-SavedScansList -Window $win }
        'LoadScan' { Invoke-LoadSelectedScan -Window $win }
        'DeleteScan' { Invoke-DeleteSelectedScan -Window $win }
        'SelectMachines' { Invoke-SelectMachinesForScan -Window $win }
        'FilterArtifacts' { Update-ArtifactFilter -Window $win -Filter $args[0] }
    }
}
#endregion

#region ===== SCRIPT-LEVEL VARIABLES =====
# Store window reference for event handlers (global for scriptblock access)
$global:GA_MainWindow = $null
$script:MainWindow = $null
$script:DiscoveredOUs = @()
$script:DiscoveredMachines = @()
$script:SelectedScanMachines = @()
$script:CurrentScanArtifacts = @()
$script:ScanInProgress = $false
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

#region ===== SCANNER PANEL HANDLERS =====

function Initialize-ScannerPanel {
    param([System.Windows.Window]$Window)

    # Wire up main action buttons
    $btnStart = $Window.FindName('BtnStartScan')
    if ($btnStart) { $btnStart.Add_Click({ Invoke-ButtonAction -Action 'StartScan' }) }

    $btnStop = $Window.FindName('BtnStopScan')
    if ($btnStop) { $btnStop.Add_Click({ Invoke-ButtonAction -Action 'StopScan' }) }

    $btnImport = $Window.FindName('BtnImportArtifacts')
    if ($btnImport) { $btnImport.Add_Click({ Invoke-ButtonAction -Action 'ImportArtifacts' }) }

    $btnExport = $Window.FindName('BtnExportArtifacts')
    if ($btnExport) { $btnExport.Add_Click({ Invoke-ButtonAction -Action 'ExportArtifacts' }) }

    # Wire up configuration buttons
    $btnSelectMachines = $Window.FindName('BtnSelectMachines')
    if ($btnSelectMachines) { $btnSelectMachines.Add_Click({ Invoke-ButtonAction -Action 'SelectMachines' }) }

    $btnBrowsePath = $Window.FindName('BtnBrowsePath')
    if ($btnBrowsePath) { $btnBrowsePath.Add_Click({ Invoke-BrowseScanPath -Window $global:GA_MainWindow }) }

    $btnResetPaths = $Window.FindName('BtnResetPaths')
    if ($btnResetPaths) { $btnResetPaths.Add_Click({ 
        $txtPaths = $global:GA_MainWindow.FindName('TxtScanPaths')
        if ($txtPaths) { $txtPaths.Text = "C:\Program Files`nC:\Program Files (x86)" }
    }) }

    # Wire up saved scans buttons
    $btnRefreshScans = $Window.FindName('BtnRefreshScans')
    if ($btnRefreshScans) { $btnRefreshScans.Add_Click({ Invoke-ButtonAction -Action 'RefreshScans' }) }

    $btnLoadScan = $Window.FindName('BtnLoadScan')
    if ($btnLoadScan) { $btnLoadScan.Add_Click({ Invoke-ButtonAction -Action 'LoadScan' }) }

    $btnDeleteScan = $Window.FindName('BtnDeleteScan')
    if ($btnDeleteScan) { $btnDeleteScan.Add_Click({ Invoke-ButtonAction -Action 'DeleteScan' }) }

    # Wire up filter buttons
    $filterButtons = @{
        'BtnFilterAllArtifacts' = 'All'
        'BtnFilterExe' = 'EXE'
        'BtnFilterDll' = 'DLL'
        'BtnFilterMsi' = 'MSI'
        'BtnFilterScript' = 'Script'
        'BtnFilterSigned' = 'Signed'
        'BtnFilterUnsigned' = 'Unsigned'
    }

    foreach ($btnName in $filterButtons.Keys) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $filterType = $filterButtons[$btnName]
            $btn.Add_Click({ 
                param($sender, $e)
                $filter = $sender.Content -replace '[^a-zA-Z]', ''
                Update-ArtifactFilter -Window $global:GA_MainWindow -Filter $filter
            }.GetNewClosure())
        }
    }

    # Wire up text filter
    $filterBox = $Window.FindName('ArtifactFilterBox')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
            Update-ArtifactDataGrid -Window $global:GA_MainWindow
        })
    }

    # Load saved scans list
    try {
        Update-SavedScansList -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load saved scans: $($_.Exception.Message)"
    }
}

function Invoke-StartArtifactScan {
    param([System.Windows.Window]$Window)

    if ($script:ScanInProgress) {
        [System.Windows.MessageBox]::Show('A scan is already in progress.', 'Scan Active', 'OK', 'Warning')
        return
    }

    # Get scan configuration
    $scanLocal = $Window.FindName('ChkScanLocal').IsChecked
    $scanRemote = $Window.FindName('ChkScanRemote').IsChecked
    $includeEvents = $Window.FindName('ChkIncludeEventLogs').IsChecked
    $saveResults = $Window.FindName('ChkSaveResults').IsChecked
    $scanName = $Window.FindName('TxtScanName').Text
    $pathsText = $Window.FindName('TxtScanPaths').Text

    # Validate
    if (-not $scanLocal -and -not $scanRemote) {
        [System.Windows.MessageBox]::Show('Please select at least one scan type (Local or Remote).', 'Configuration Error', 'OK', 'Warning')
        return
    }

    if ($scanRemote -and $script:SelectedScanMachines.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Remote scan selected but no machines are selected. Go to AD Discovery first or select Local scan.', 'No Machines', 'OK', 'Warning')
        return
    }

    if ([string]::IsNullOrWhiteSpace($scanName)) {
        $scanName = "Scan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Window.FindName('TxtScanName').Text = $scanName
    }

    # Parse paths
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($pathsText)) {
        $paths = $pathsText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # Update UI state
    $script:ScanInProgress = $true
    Update-ScanUIState -Window $Window -Scanning $true
    Update-ScanProgress -Window $Window -Text "Starting scan: $scanName" -Percent 0

    try {
        # Build scan parameters
        $scanParams = @{
            SaveResults = $saveResults
            ScanName    = $scanName
        }

        if ($scanLocal) { $scanParams.ScanLocal = $true }
        if ($includeEvents) { $scanParams.IncludeEventLogs = $true }
        if ($paths.Count -gt 0) { $scanParams.Paths = $paths }
        if ($scanRemote -and $script:SelectedScanMachines.Count -gt 0) {
            $scanParams.Machines = $script:SelectedScanMachines
        }

        Update-ScanProgress -Window $Window -Text "Scanning..." -Percent 25

        # Execute scan (synchronous for now - async would require background jobs)
        $result = Start-ArtifactScan @scanParams

        if ($result.Success) {
            $script:CurrentScanArtifacts = $result.Data.Artifacts
            Update-ArtifactDataGrid -Window $Window
            Update-ScanProgress -Window $Window -Text "Scan complete: $($result.Summary.TotalArtifacts) artifacts" -Percent 100

            # Update counters
            $Window.FindName('ScanArtifactCount').Text = "$($result.Summary.TotalArtifacts) artifacts"
            $Window.FindName('ScanSignedCount').Text = "$($result.Summary.SignedArtifacts)"
            $Window.FindName('ScanUnsignedCount').Text = "$($result.Summary.UnsignedArtifacts)"
            $Window.FindName('ScanStatusLabel').Text = "Complete"
            $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

            # Refresh saved scans list
            Update-SavedScansList -Window $Window

            [System.Windows.MessageBox]::Show(
                "Scan completed successfully!`n`n" +
                "Total Artifacts: $($result.Summary.TotalArtifacts)`n" +
                "Signed: $($result.Summary.SignedArtifacts)`n" +
                "Unsigned: $($result.Summary.UnsignedArtifacts)`n" +
                "Machines: $($result.Summary.SuccessfulMachines)/$($result.Summary.TotalMachines)",
                'Scan Complete',
                'OK',
                'Information'
            )
        }
        else {
            Update-ScanProgress -Window $Window -Text "Scan failed: $($result.Error)" -Percent 0
            $Window.FindName('ScanStatusLabel').Text = "Failed"
            $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
            
            [System.Windows.MessageBox]::Show("Scan failed: $($result.Error)", 'Scan Error', 'OK', 'Error')
        }
    }
    catch {
        Update-ScanProgress -Window $Window -Text "Error: $($_.Exception.Message)" -Percent 0
        $Window.FindName('ScanStatusLabel').Text = "Error"
        $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
        
        [System.Windows.MessageBox]::Show("Scan error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
    finally {
        $script:ScanInProgress = $false
        Update-ScanUIState -Window $Window -Scanning $false
    }
}

function Invoke-StopArtifactScan {
    param([System.Windows.Window]$Window)

    # For now, just flag to stop - actual cancellation would require CancellationToken
    $script:ScanInProgress = $false
    Update-ScanUIState -Window $Window -Scanning $false
    Update-ScanProgress -Window $Window -Text "Scan cancelled" -Percent 0
    $Window.FindName('ScanStatusLabel').Text = "Cancelled"
    $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::Orange
}

function Update-ScanUIState {
    param(
        [System.Windows.Window]$Window,
        [bool]$Scanning
    )

    $btnStart = $Window.FindName('BtnStartScan')
    $btnStop = $Window.FindName('BtnStopScan')

    if ($btnStart) { $btnStart.IsEnabled = -not $Scanning }
    if ($btnStop) { $btnStop.IsEnabled = $Scanning }
}

function Update-ScanProgress {
    param(
        [System.Windows.Window]$Window,
        [string]$Text,
        [int]$Percent
    )

    $progressText = $Window.FindName('ScanProgressText')
    $progressBar = $Window.FindName('ScanProgressBar')
    $progressPercent = $Window.FindName('ScanProgressPercent')

    if ($progressText) { $progressText.Text = $Text }
    if ($progressBar) { $progressBar.Value = $Percent }
    if ($progressPercent) { $progressPercent.Text = if ($Percent -gt 0) { "$Percent%" } else { '' } }

    # Force UI update
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-ArtifactDataGrid {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('ArtifactDataGrid')
    if (-not $dataGrid) { return }

    $artifacts = $script:CurrentScanArtifacts
    if (-not $artifacts) {
        $dataGrid.ItemsSource = $null
        return
    }

    # Apply text filter
    $filterBox = $Window.FindName('ArtifactFilterBox')
    $filterText = if ($filterBox) { $filterBox.Text } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($filterText)) {
        $artifacts = $artifacts | Where-Object {
            $_.FileName -like "*$filterText*" -or
            $_.Publisher -like "*$filterText*" -or
            $_.Path -like "*$filterText*"
        }
    }

    # Add display properties
    $displayData = $artifacts | ForEach-Object {
        $signedIcon = if ($_.IsSigned) { [char]0x2714 } else { [char]0x2718 }
        $_ | Add-Member -NotePropertyName 'SignedIcon' -NotePropertyValue $signedIcon -PassThru -Force
    }

    $dataGrid.ItemsSource = $displayData
}

function Update-ArtifactFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    # Reset button styles
    $allButtons = @('BtnFilterAllArtifacts', 'BtnFilterExe', 'BtnFilterDll', 'BtnFilterMsi', 'BtnFilterScript', 'BtnFilterSigned', 'BtnFilterUnsigned')
    foreach ($btnName in $allButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
        }
    }

    # Highlight active filter
    $activeBtn = switch ($Filter) {
        'All' { 'BtnFilterAllArtifacts' }
        'EXE' { 'BtnFilterExe' }
        'DLL' { 'BtnFilterDll' }
        'MSI' { 'BtnFilterMsi' }
        'Script' { 'BtnFilterScript' }
        'Signed' { 'BtnFilterSigned' }
        'Unsigned' { 'BtnFilterUnsigned' }
    }

    $btn = $Window.FindName($activeBtn)
    if ($btn) {
        $btn.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(62, 62, 66))
    }

    # Filter artifacts
    $baseArtifacts = $script:CurrentScanArtifacts
    if (-not $baseArtifacts) { return }

    $filtered = switch ($Filter) {
        'All' { $baseArtifacts }
        'EXE' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'EXE' } }
        'DLL' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'DLL' } }
        'MSI' { $baseArtifacts | Where-Object { $_.ArtifactType -eq 'MSI' } }
        'Script' { $baseArtifacts | Where-Object { $_.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS') } }
        'Signed' { $baseArtifacts | Where-Object { $_.IsSigned } }
        'Unsigned' { $baseArtifacts | Where-Object { -not $_.IsSigned } }
        default { $baseArtifacts }
    }

    # Temporarily replace current artifacts for display
    $original = $script:CurrentScanArtifacts
    $script:CurrentScanArtifacts = $filtered
    Update-ArtifactDataGrid -Window $Window
    $script:CurrentScanArtifacts = $original
}

function Update-SavedScansList {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox) { return }

    if (-not (Get-Command -Name 'Get-ScanResults' -ErrorAction SilentlyContinue)) {
        return
    }

    $result = Get-ScanResults
    if ($result.Success -and $result.Data) {
        $listBox.ItemsSource = $result.Data
    }
    else {
        $listBox.ItemsSource = $null
    }
}

function Invoke-LoadSelectedScan {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a saved scan to load.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedScan = $listBox.SelectedItem
    $result = Get-ScanResults -ScanId $selectedScan.ScanId

    if ($result.Success) {
        $script:CurrentScanArtifacts = $result.Data.Artifacts
        Update-ArtifactDataGrid -Window $Window

        # Update counters
        $signed = ($result.Data.Artifacts | Where-Object { $_.IsSigned }).Count
        $unsigned = $result.Data.Artifacts.Count - $signed
        $Window.FindName('ScanArtifactCount').Text = "$($result.Data.Artifacts.Count) artifacts"
        $Window.FindName('ScanSignedCount').Text = "$signed"
        $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
        $Window.FindName('ScanStatusLabel').Text = "Loaded"
        $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightBlue

        Update-ScanProgress -Window $Window -Text "Loaded: $($selectedScan.ScanName)" -Percent 100
    }
    else {
        [System.Windows.MessageBox]::Show("Failed to load scan: $($result.Error)", 'Error', 'OK', 'Error')
    }
}

function Invoke-DeleteSelectedScan {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a saved scan to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $selectedScan = $listBox.SelectedItem

    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete scan '$($selectedScan.ScanName)'?",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )

    if ($confirm -eq 'Yes') {
        $scanPath = Join-Path (Get-AppLockerDataPath) 'Scans'
        $scanFile = Join-Path $scanPath "$($selectedScan.ScanId).json"
        
        if (Test-Path $scanFile) {
            Remove-Item -Path $scanFile -Force
            [System.Windows.MessageBox]::Show("Scan '$($selectedScan.ScanName)' deleted.", 'Deleted', 'OK', 'Information')
            Update-SavedScansList -Window $Window
        }
    }
}

function Invoke-ImportArtifacts {
    param([System.Windows.Window]$Window)

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Import Artifacts'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json|All Files (*.*)|*.*'
    $dialog.FilterIndex = 1

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            
            $artifacts = switch ($extension) {
                '.csv' { Import-Csv -Path $dialog.FileName }
                '.json' { Get-Content -Path $dialog.FileName -Raw | ConvertFrom-Json }
                default { throw "Unsupported file format: $extension" }
            }

            $script:CurrentScanArtifacts = $artifacts
            Update-ArtifactDataGrid -Window $Window

            # Update counters
            $signed = ($artifacts | Where-Object { $_.IsSigned }).Count
            $unsigned = $artifacts.Count - $signed
            $Window.FindName('ScanArtifactCount').Text = "$($artifacts.Count) artifacts"
            $Window.FindName('ScanSignedCount').Text = "$signed"
            $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
            $Window.FindName('ScanStatusLabel').Text = "Imported"
            $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

            [System.Windows.MessageBox]::Show(
                "Imported $($artifacts.Count) artifacts from file.",
                'Import Complete',
                'OK',
                'Information'
            )
        }
        catch {
            [System.Windows.MessageBox]::Show("Import failed: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-ExportArtifacts {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No artifacts to export. Run a scan first.', 'No Data', 'OK', 'Information')
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Artifacts'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json'
    $dialog.FilterIndex = 1
    $dialog.FileName = "Artifacts_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            
            switch ($extension) {
                '.csv' { $script:CurrentScanArtifacts | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8 }
                '.json' { $script:CurrentScanArtifacts | ConvertTo-Json -Depth 5 | Set-Content -Path $dialog.FileName -Encoding UTF8 }
            }

            [System.Windows.MessageBox]::Show(
                "Exported $($script:CurrentScanArtifacts.Count) artifacts to:`n$($dialog.FileName)",
                'Export Complete',
                'OK',
                'Information'
            )
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function Invoke-BrowseScanPath {
    param([System.Windows.Window]$Window)

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Select a folder to scan'
    $dialog.ShowNewFolderButton = $false

    if ($dialog.ShowDialog() -eq 'OK') {
        $txtPaths = $Window.FindName('TxtScanPaths')
        if ($txtPaths) {
            if ([string]::IsNullOrWhiteSpace($txtPaths.Text)) {
                $txtPaths.Text = $dialog.SelectedPath
            }
            else {
                $txtPaths.Text += "`n$($dialog.SelectedPath)"
            }
        }
    }
}

function Invoke-SelectMachinesForScan {
    param([System.Windows.Window]$Window)

    # Use machines from Discovery panel
    if ($script:DiscoveredMachines.Count -eq 0) {
        $confirm = [System.Windows.MessageBox]::Show(
            "No machines discovered. Would you like to navigate to AD Discovery to scan for machines?",
            'No Machines',
            'YesNo',
            'Question'
        )

        if ($confirm -eq 'Yes') {
            Set-ActivePanel -PanelName 'PanelDiscovery'
        }
        return
    }

    # For now, use all discovered machines
    # TODO: Add a proper selection dialog
    $script:SelectedScanMachines = $script:DiscoveredMachines

    # Update the machine list display
    $machineList = $Window.FindName('ScanMachineList')
    $machineCount = $Window.FindName('ScanMachineCount')

    if ($machineList) {
        $machineList.ItemsSource = $script:SelectedScanMachines | Select-Object -ExpandProperty Hostname
    }

    if ($machineCount) {
        $machineCount.Text = "$($script:SelectedScanMachines.Count)"
    }

    # Enable remote scan checkbox
    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) { $chkRemote.IsChecked = $true }

    [System.Windows.MessageBox]::Show(
        "Selected $($script:SelectedScanMachines.Count) machines for scanning.",
        'Machines Selected',
        'OK',
        'Information'
    )
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

    # Initialize navigation buttons
    try {
        Initialize-Navigation -Window $Window
        Write-Log -Message 'Navigation initialized'
    }
    catch {
        Write-Log -Level Error -Message "Navigation init failed: $($_.Exception.Message)"
    }
    
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
    
    # Initialize Scanner panel
    try {
        Initialize-ScannerPanel -Window $Window
        Write-Log -Message 'Scanner panel initialized'
    }
    catch {
        Write-Log -Level Error -Message "Scanner panel init failed: $($_.Exception.Message)"
    }

    # Update domain info in status bar and dashboard
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        
        # Status bar
        $domainText = $Window.FindName('DomainText')
        if ($domainText -and $computerSystem.PartOfDomain) {
            $domainText.Text = "Domain: $($computerSystem.Domain)"
        }
        
        # Dashboard System Info
        $sysComputer = $Window.FindName('SysInfoComputer')
        if ($sysComputer) { $sysComputer.Text = $env:COMPUTERNAME }
        
        $sysDomain = $Window.FindName('SysInfoDomain')
        if ($sysDomain) {
            if ($computerSystem.PartOfDomain) {
                $sysDomain.Text = $computerSystem.Domain
            } else {
                $sysDomain.Text = "Not domain joined"
            }
        }
        
        $sysUser = $Window.FindName('SysInfoUser')
        if ($sysUser) { $sysUser.Text = "$env:USERDOMAIN\$env:USERNAME" }
        
        $sysDataPath = $Window.FindName('SysInfoDataPath')
        if ($sysDataPath -and (Get-Command -Name 'Get-AppLockerDataPath' -ErrorAction SilentlyContinue)) {
            $dataPath = Get-AppLockerDataPath
            # Insert line break after AppData for better display
            $sysDataPath.Text = $dataPath -replace '(AppData\\)', "`$1`n"
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
