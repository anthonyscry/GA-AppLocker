#region Setup Panel Functions
# Setup.ps1 - Setup panel handlers
function Initialize-SetupPanel {
    param($Window)

    # Wire up Setup tab buttons - WinRM GPOs
    $btnInitWinRM = $Window.FindName('BtnInitializeWinRM')
    if ($btnInitWinRM) { $btnInitWinRM.Add_Click({ Invoke-ButtonAction -Action 'InitializeWinRM' }) }

    $btnToggleEnable = $Window.FindName('BtnToggleEnableWinRM')
    if ($btnToggleEnable) { $btnToggleEnable.Add_Click({ Invoke-ButtonAction -Action 'ToggleEnableWinRM' }) }

    $btnRemoveEnable = $Window.FindName('BtnRemoveEnableWinRM')
    if ($btnRemoveEnable) { $btnRemoveEnable.Add_Click({ Invoke-ButtonAction -Action 'RemoveEnableWinRM' }) }

    $btnToggleDisable = $Window.FindName('BtnToggleDisableWinRM')
    if ($btnToggleDisable) { $btnToggleDisable.Add_Click({ Invoke-ButtonAction -Action 'ToggleDisableWinRM' }) }

    $btnRemoveDisable = $Window.FindName('BtnRemoveDisableWinRM')
    if ($btnRemoveDisable) { $btnRemoveDisable.Add_Click({ Invoke-ButtonAction -Action 'RemoveDisableWinRM' }) }

    $btnInitGPOs = $Window.FindName('BtnInitializeAppLockerGPOs')
    if ($btnInitGPOs) { $btnInitGPOs.Add_Click({ Invoke-ButtonAction -Action 'InitializeAppLockerGPOs' }) }

    $btnInitAD = $Window.FindName('BtnInitializeADStructure')
    if ($btnInitAD) { $btnInitAD.Add_Click({ Invoke-ButtonAction -Action 'InitializeADStructure' }) }

    $btnInitAll = $Window.FindName('BtnInitializeAll')
    if ($btnInitAll) { $btnInitAll.Add_Click({ Invoke-ButtonAction -Action 'InitializeAll' }) }

    # Update status on load
    Update-SetupStatus -Window $Window
}

function Update-SetupStatus {
    param($Window)

    try {
        # Use try-catch - Get-Command fails in WPF context
        $status = $null
        try { $status = Get-SetupStatus } catch { return }
        if (-not $status) { return }

        if ($status.Success -and $status.Data) {
            # Update EnableWinRM GPO status
            $enableStatus = $Window.FindName('TxtEnableWinRMStatus')
            if ($enableStatus -and $status.Data.WinRM) {
                $enableStatus.Text = $status.Data.WinRM.Status
                $enableStatus.Foreground = switch ($status.Data.WinRM.Status) {
                    'Enabled' { [System.Windows.Media.Brushes]::LightGreen }
                    'Disabled' { [System.Windows.Media.Brushes]::Orange }
                    default { [System.Windows.Media.Brushes]::Gray }
                }
            }

            # Update EnableWinRM toggle button label
            $btnToggleEnable = $Window.FindName('BtnToggleEnableWinRM')
            if ($btnToggleEnable -and $status.Data.WinRM) {
                if ($status.Data.WinRM.Status -eq 'Enabled') {
                    $btnToggleEnable.Content = 'Disable Link'
                } else {
                    $btnToggleEnable.Content = 'Enable Link'
                }
            }

            # Update DisableWinRM GPO status
            $disableStatus = $Window.FindName('TxtDisableWinRMStatus')
            if ($disableStatus -and $status.Data.DisableWinRM) {
                $disableStatus.Text = $status.Data.DisableWinRM.Status
                $disableStatus.Foreground = switch ($status.Data.DisableWinRM.Status) {
                    'Enabled' { [System.Windows.Media.Brushes]::LightGreen }
                    'Disabled' { [System.Windows.Media.Brushes]::Orange }
                    default { [System.Windows.Media.Brushes]::Gray }
                }
            }

            # Update DisableWinRM toggle button label
            $btnToggleDisable = $Window.FindName('BtnToggleDisableWinRM')
            if ($btnToggleDisable -and $status.Data.DisableWinRM) {
                if ($status.Data.DisableWinRM.Status -eq 'Enabled') {
                    $btnToggleDisable.Content = 'Disable Link'
                } else {
                    $btnToggleDisable.Content = 'Enable Link'
                }
            }

            # Update GPO statuses
            foreach ($gpo in $status.Data.AppLockerGPOs) {
                $statusControl = $Window.FindName("TxtGPO_$($gpo.Type)_Status")
                if ($statusControl) {
                    $statusControl.Text = $gpo.Status
                    $statusControl.Foreground = if (-not $gpo.Exists) {
                        [System.Windows.Media.Brushes]::Gray
                    }
                    elseif ($gpo.GpoState -eq 'Enabled') {
                        [System.Windows.Media.Brushes]::LightGreen
                    }
                    elseif ($gpo.GpoState -eq 'Disabled') {
                        [System.Windows.Media.Brushes]::Orange
                    }
                    else {
                        [System.Windows.Media.Brushes]::LightGreen
                    }
                }
            }
        }
    }
    catch {
        # Silently fail - status display is optional
    }
}

function global:Invoke-InitializeWinRM {
    param($Window)

    try {
        $confirm = Show-AppLockerMessageBox "This will create two WinRM GPOs linked to the domain root:`n`n1. AppLocker-EnableWinRM - enables WinRM on all computers`n2. AppLocker-DisableWinRM - tattoo removal (link starts disabled)`n`nRequires Domain Admin permissions.`n`nContinue?" 'Initialize WinRM GPOs' 'YesNo' 'Warning'

        if ($confirm -ne 'Yes') { return }

        Show-LoadingOverlay -Message 'Creating WinRM GPOs...' -SubMessage 'Setting up Enable + Disable GPOs'

        # Create Enable GPO (linked + enabled)
        $enableResult = Initialize-WinRMGPO

        # Create Disable GPO (linked + enforced - but Initialize-DisableWinRMGPO also disables the Enable link)
        $disableResult = Initialize-DisableWinRMGPO

        # Fix link states: Enable GPO active, Disable GPO inactive (ready but not applied)
        try {
            Enable-WinRMGPO -GPOName 'AppLocker-EnableWinRM' -ErrorAction SilentlyContinue
            Disable-WinRMGPO -GPOName 'AppLocker-DisableWinRM' -ErrorAction SilentlyContinue
        } catch { Write-Log -Level Warning -Message "WinRM GPO link state update failed: $($_.Exception.Message)" }

        Hide-LoadingOverlay

        $summary = @()
        if ($enableResult.Success) { $summary += "EnableWinRM: Created" } else { $summary += "EnableWinRM: Failed - $($enableResult.Error)" }
        if ($disableResult.Success) { $summary += "DisableWinRM: Created (link disabled)" } else { $summary += "DisableWinRM: Failed - $($disableResult.Error)" }

        if ($enableResult.Success -or $disableResult.Success) {
            Show-AppLockerMessageBox "WinRM GPOs initialized!`n`n$($summary -join "`n")" 'Success' 'OK' 'Information'
        }
        else {
            Show-AppLockerMessageBox "Both GPOs failed:`n`n$($summary -join "`n")" 'Error' 'OK' 'Error'
        }

        Update-SetupStatus -Window $Window
    }
    catch {
        Hide-LoadingOverlay
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-ToggleWinRMGPO {
    param(
        $Window,
        [string]$GPOName,
        [string]$StatusProperty
    )

    try {
        $status = Get-SetupStatus
        if (-not $status.Success) {
            Show-AppLockerMessageBox 'Could not read GPO status.' 'Error' 'OK' 'Error'
            return
        }

        $gpoStatus = $status.Data.$StatusProperty
        if (-not $gpoStatus -or -not $gpoStatus.Exists) {
            Show-AppLockerMessageBox "GPO '$GPOName' does not exist. Initialize WinRM GPOs first." 'Not Found' 'OK' 'Warning'
            return
        }

        $isEnabled = $gpoStatus.Status -eq 'Enabled'

        if ($isEnabled) {
            $result = Disable-WinRMGPO -GPOName $GPOName
            $action = 'disabled'
        }
        else {
            $result = Enable-WinRMGPO -GPOName $GPOName
            $action = 'enabled'
        }

        if ($result.Success) {
            $message = "$GPOName link $action."

            # Mutual exclusivity: when ENABLING one GPO, auto-disable the opposite
            if ($action -eq 'enabled') {
                $oppositeGPO = $null
                $oppositeProperty = $null
                if ($GPOName -eq 'AppLocker-EnableWinRM') {
                    $oppositeGPO = 'AppLocker-DisableWinRM'
                    $oppositeProperty = 'DisableWinRM'
                }
                elseif ($GPOName -eq 'AppLocker-DisableWinRM') {
                    $oppositeGPO = 'AppLocker-EnableWinRM'
                    $oppositeProperty = 'WinRM'
                }

                if ($oppositeGPO) {
                    $oppositeStatus = $status.Data.$oppositeProperty
                    if ($oppositeStatus -and $oppositeStatus.Exists -and $oppositeStatus.Status -eq 'Enabled') {
                        $disableOpposite = Disable-WinRMGPO -GPOName $oppositeGPO
                        if ($disableOpposite.Success) {
                            $message += "`n$oppositeGPO link auto-disabled (mutually exclusive)."
                        }
                    }
                }
            }

            Show-AppLockerMessageBox $message 'Success' 'OK' 'Information'
            Update-SetupStatus -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-RemoveWinRMGPOByName {
    param(
        $Window,
        [string]$GPOName,
        [string]$StatusProperty,
        [string]$RemoveFunction
    )

    try {
        $status = Get-SetupStatus
        if (-not $status.Success) {
            Show-AppLockerMessageBox 'Could not read GPO status.' 'Error' 'OK' 'Error'
            return
        }

        $gpoStatus = $status.Data.$StatusProperty
        if (-not $gpoStatus -or -not $gpoStatus.Exists) {
            Show-AppLockerMessageBox "GPO '$GPOName' does not exist. Nothing to remove." 'Not Found' 'OK' 'Warning'
            return
        }

        $confirm = Show-AppLockerMessageBox "This will PERMANENTLY remove '$GPOName' and all its links.`n`nAre you sure?" "Remove $GPOName" 'YesNo' 'Warning'

        if ($confirm -ne 'Yes') { return }

        $result = & $RemoveFunction -GPOName $GPOName

        if ($result.Success) {
            Show-AppLockerMessageBox "$GPOName removed." 'Removed' 'OK' 'Information'
            Update-SetupStatus -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-InitializeAppLockerGPOs {
    param($Window)

    try {
        $confirm = Show-AppLockerMessageBox "This will create three AppLocker GPOs:`n`n- AppLocker-DC (linked to Domain Controllers OU)`n- AppLocker-Servers (linked to Servers OU)`n- AppLocker-Workstations (linked to Computers OU)`n`nContinue?" 'Initialize AppLocker GPOs' 'YesNo' 'Question'

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerGPOs

        if ($result.Success) {
            $summary = $result.Data | ForEach-Object { "- $($_.Name): $($_.Status)" }
            Show-AppLockerMessageBox "AppLocker GPOs created!`n`n$($summary -join "`n")" 'Success' 'OK' 'Information'
            Update-SetupStatus -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-InitializeADStructure {
    param($Window)

    try {
        $confirm = Show-AppLockerMessageBox "This will create the AppLocker OU and security groups:`n`nOU: AppLocker (at domain root)`n`nGroups:`n- AppLocker-Admins`n- AppLocker-Exempt`n- AppLocker-Audit`n- AppLocker-Users`n- AppLocker-Installers`n- AppLocker-Developers`n`nContinue?" 'Initialize AD Structure' 'YesNo' 'Question'

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-ADStructure

        if ($result.Success) {
            $groupSummary = $result.Data.Groups | ForEach-Object { "- $($_.Name): $($_.Status)" }
            Show-AppLockerMessageBox "AD Structure created!`n`nOU: $($result.Data.OUPath)`n`nGroups:`n$($groupSummary -join "`n")" 'Success' 'OK' 'Information'
            Update-SetupStatus -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-InitializeAll {
    param($Window)

    try {
        $confirm = Show-AppLockerMessageBox "This will run ALL initialization steps:`n`n1. Create WinRM GPOs (Enable + Disable, linked to domain root)`n2. Create AppLocker GPOs (DC, Servers, Workstations)`n3. Create AppLocker OU and security groups`n`nThis requires Domain Admin permissions.`n`nContinue?" 'Full Initialization' 'YesNo' 'Warning'

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerEnvironment

        if ($result.Success) {
            Show-AppLockerMessageBox "Full initialization complete!`n`nEnable WinRM GPO: $(if ($result.Data.WinRM.Success) { 'Success' } else { 'Failed' })`nDisable WinRM GPO: $(if ($result.Data.DisableWinRM.Success) { 'Success' } else { 'Failed' })`nAppLocker GPOs: $(if ($result.Data.AppLockerGPOs.Success) { 'Success' } else { 'Failed' })`nAD Structure: $(if ($result.Data.ADStructure.Success) { 'Success' } else { 'Failed' })" 'Initialization Complete' 'OK' 'Information'
            Update-SetupStatus -Window $Window
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

#endregion

#region ===== WINDOW INITIALIZATION =====
#endregion
