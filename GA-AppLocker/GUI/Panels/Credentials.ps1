#region Credentials Panel Functions
# Credentials.ps1 - Credential profile management

# Script-scoped handler storage for cleanup
$script:Credentials_Handlers = @{}

function Initialize-CredentialsPanel {
    param($Window)
    
    # Clean up any existing handlers first to prevent accumulation
    Unregister-CredentialsPanelEvents -Window $Window

    # Wire up Save Credential button
    $btnSave = $Window.FindName('BtnSaveCredential')
    if ($btnSave) {
        $script:Credentials_Handlers['btnSave'] = { Invoke-ButtonAction -Action 'SaveCredential' }
        $btnSave.Add_Click($script:Credentials_Handlers['btnSave'])
    }

    # Wire up Refresh Credentials button
    $btnRefresh = $Window.FindName('BtnRefreshCredentials')
    if ($btnRefresh) {
        $script:Credentials_Handlers['btnRefresh'] = { Invoke-ButtonAction -Action 'RefreshCredentials' }
        $btnRefresh.Add_Click($script:Credentials_Handlers['btnRefresh'])
    }

    # Wire up Test Credential button
    $btnTest = $Window.FindName('BtnTestCredential')
    if ($btnTest) {
        $script:Credentials_Handlers['btnTest'] = { Invoke-ButtonAction -Action 'TestCredential' }
        $btnTest.Add_Click($script:Credentials_Handlers['btnTest'])
    }

    # Wire up Delete Credential button
    $btnDelete = $Window.FindName('BtnDeleteCredential')
    if ($btnDelete) {
        $script:Credentials_Handlers['btnDelete'] = { Invoke-ButtonAction -Action 'DeleteCredential' }
        $btnDelete.Add_Click($script:Credentials_Handlers['btnDelete'])
    }

    # Wire up Set Default button
    $btnSetDefault = $Window.FindName('BtnSetDefaultCredential')
    if ($btnSetDefault) {
        $script:Credentials_Handlers['btnSetDefault'] = { Invoke-ButtonAction -Action 'SetDefaultCredential' }
        $btnSetDefault.Add_Click($script:Credentials_Handlers['btnSetDefault'])
    }

    # Load existing credentials
    try {
        Update-CredentialsDataGrid -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load credentials: $($_.Exception.Message)"
    }
}

function Unregister-CredentialsPanelEvents {
    <#
    .SYNOPSIS
        Removes all registered event handlers from Credentials panel.
    .DESCRIPTION
        Called when switching away from the panel to prevent handler accumulation
        and memory leaks.
    #>
    param($Window)
    
    if (-not $Window) { $Window = $global:GA_MainWindow }
    if (-not $Window) { return }
    
    $buttons = @(
        @{ Key = 'btnSave'; Name = 'BtnSaveCredential' },
        @{ Key = 'btnRefresh'; Name = 'BtnRefreshCredentials' },
        @{ Key = 'btnTest'; Name = 'BtnTestCredential' },
        @{ Key = 'btnDelete'; Name = 'BtnDeleteCredential' },
        @{ Key = 'btnSetDefault'; Name = 'BtnSetDefaultCredential' }
    )
    
    foreach ($btn in $buttons) {
        if ($script:Credentials_Handlers[$btn.Key]) {
            $control = $Window.FindName($btn.Name)
            if ($control) {
                try { $control.Remove_Click($script:Credentials_Handlers[$btn.Key]) } catch { Write-AppLockerLog -Message "[Credentials] Failed to remove click handler for '$($btn.Name)': $_" -Level DEBUG }
            }
        }
    }
    
    # Clear stored handlers
    $script:Credentials_Handlers = @{}
}

function global:Invoke-SaveCredential {
    param($Window)

    $profileName = $Window.FindName('CredProfileName')
    $tierCombo = $Window.FindName('CredTierCombo')
    $username = $Window.FindName('CredUsername')
    $password = $Window.FindName('CredPassword')
    $description = $Window.FindName('CredDescription')
    $setAsDefault = $Window.FindName('CredSetAsDefault')

    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($profileName.Text)) {
        Show-AppLockerMessageBox 'Please enter a profile name.' 'Validation Error' 'OK' 'Warning'
        return
    }

    if ([string]::IsNullOrWhiteSpace($username.Text)) {
        Show-AppLockerMessageBox 'Please enter a username.' 'Validation Error' 'OK' 'Warning'
        return
    }

    if ($password.SecurePassword.Length -eq 0) {
        Show-AppLockerMessageBox 'Please enter a password.' 'Validation Error' 'OK' 'Warning'
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
        Show-AppLockerMessageBox "Credential profile '$($profileName.Text)' saved successfully." 'Success' 'OK' 'Information'

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
        Show-AppLockerMessageBox "Failed to save credential: $($result.Error)" 'Error' 'OK' 'Error'
    }
}

function global:Update-CredentialsDataGrid {
    param($Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    if (-not $dataGrid) { return }

    $result = Get-AllCredentialProfiles

    if ($result.Success -and $result.Data) {
        # Ensure Data is always an array (PS 5.1 compatible)
        $profileList = @($result.Data)
        
        # Add display properties - wrap result in @() to ensure array for DataGrid ItemsSource
        $displayData = @($profileList | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'IsDefaultDisplay' -NotePropertyValue $(if ($_.IsDefault) { 'Yes' } else { '' }) -PassThru -Force |
            Add-Member -NotePropertyName 'LastTestDisplay' -NotePropertyValue $(
                if ($_.LastTestResult) {
                    $status = if ($_.LastTestResult.Success) { 'Passed' } else { 'Failed' }
                    "$status - $($_.LastTestResult.TestTime)"
                }
                else { 'Not tested' }
            ) -PassThru -Force
        })
        $dataGrid.ItemsSource = $displayData
    }
    else {
        $dataGrid.ItemsSource = $null
    }
}

function global:Invoke-TestSelectedCredential {
    param($Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')
    $testTarget = $Window.FindName('CredTestTarget')
    $resultBorder = $Window.FindName('CredTestResultBorder')
    $resultText = $Window.FindName('CredTestResultText')

    if (-not $dataGrid.SelectedItem) {
        Show-AppLockerMessageBox 'Please select a credential profile to test.' 'No Selection' 'OK' 'Information'
        return
    }

    if ([string]::IsNullOrWhiteSpace($testTarget.Text)) {
        Show-AppLockerMessageBox 'Please enter a target hostname to test against.' 'No Target' 'OK' 'Information'
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

function global:Invoke-DeleteSelectedCredential {
    param($Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        Show-AppLockerMessageBox 'Please select a credential profile to delete.' 'No Selection' 'OK' 'Information'
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    $confirm = Show-AppLockerMessageBox "Are you sure you want to delete credential profile '$($selectedProfile.Name)'?" 'Confirm Delete' 'YesNo' 'Warning'

    if ($confirm -eq 'Yes') {
        $result = Remove-CredentialProfile -Name $selectedProfile.Name

        if ($result.Success) {
            Show-AppLockerMessageBox "Credential profile '$($selectedProfile.Name)' deleted." 'Deleted' 'OK' 'Information'
            Update-CredentialsDataGrid -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed to delete: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
}

function global:Invoke-SetDefaultCredential {
    param($Window)

    $dataGrid = $Window.FindName('CredentialsDataGrid')

    if (-not $dataGrid.SelectedItem) {
        Show-AppLockerMessageBox 'Please select a credential profile to set as default.' 'No Selection' 'OK' 'Information'
        return
    }

    $selectedProfile = $dataGrid.SelectedItem

    # Get existing profile
    $profileResult = Get-CredentialProfile -Name $selectedProfile.Name
    if (-not $profileResult.Success) {
        Show-AppLockerMessageBox "Profile not found: $($profileResult.Error)" 'Error' 'OK' 'Error'
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

    Show-AppLockerMessageBox "Credential profile '$($selectedProfile.Name)' set as default for Tier $($profile.Tier)." 'Default Set' 'OK' 'Information'

    Update-CredentialsDataGrid -Window $Window
}

#endregion
