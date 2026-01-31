#region Setup Panel Functions
# Setup.ps1 - Setup panel handlers
function Initialize-SetupPanel {
    param([System.Windows.Window]$Window)

    # Wire up Setup tab buttons
    $btnInitWinRM = $Window.FindName('BtnInitializeWinRM')
    if ($btnInitWinRM) { $btnInitWinRM.Add_Click({ Invoke-ButtonAction -Action 'InitializeWinRM' }) }

    $btnToggleWinRM = $Window.FindName('BtnToggleWinRM')
    if ($btnToggleWinRM) { $btnToggleWinRM.Add_Click({ Invoke-ButtonAction -Action 'ToggleWinRM' }) }

    $btnRemoveWinRM = $Window.FindName('BtnRemoveWinRM')
    if ($btnRemoveWinRM) { $btnRemoveWinRM.Add_Click({ Invoke-ButtonAction -Action 'RemoveWinRM' }) }

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
    param([System.Windows.Window]$Window)

    try {
        # Use try-catch - Get-Command fails in WPF context
        $status = $null
        try { $status = Get-SetupStatus } catch { return }
        if (-not $status) { return }

        if ($status.Success -and $status.Data) {
            # Update WinRM status
            $winrmStatus = $Window.FindName('TxtWinRMStatus')
            if ($winrmStatus -and $status.Data.WinRM) {
                $winrmStatus.Text = $status.Data.WinRM.Status
                $winrmStatus.Foreground = switch ($status.Data.WinRM.Status) {
                    'Enabled' { [System.Windows.Media.Brushes]::LightGreen }
                    'Disabled' { [System.Windows.Media.Brushes]::Orange }
                    default { [System.Windows.Media.Brushes]::Gray }
                }
            }

            # Update GPO statuses
            foreach ($gpo in $status.Data.AppLockerGPOs) {
                $statusControl = $Window.FindName("TxtGPO_$($gpo.Type)_Status")
                if ($statusControl) {
                    $statusControl.Text = $gpo.Status
                    $statusControl.Foreground = if ($gpo.Exists) { 
                        [System.Windows.Media.Brushes]::LightGreen 
                    }
                    else { 
                        [System.Windows.Media.Brushes]::Gray 
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
    param([System.Windows.Window]$Window)

    try {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will create the 'AppLocker-EnableWinRM' GPO and link it to the domain root.`n`nThis enables WinRM on ALL computers in the domain.`n`nContinue?",
            'Initialize WinRM GPO',
            'YesNo',
            'Warning'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-WinRMGPO

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "WinRM GPO created successfully!`n`nGPO: $($result.Data.GPOName)`nLinked to: $($result.Data.LinkedTo)",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-ToggleWinRM {
    param([System.Windows.Window]$Window)

    try {
        $status = Get-SetupStatus
        if (-not $status.Success -or -not $status.Data.WinRM.Exists) {
            [System.Windows.MessageBox]::Show('WinRM GPO does not exist. Initialize it first.', 'Not Found', 'OK', 'Warning')
            return
        }

        $isEnabled = $status.Data.WinRM.Status -eq 'Enabled'

        if ($isEnabled) {
            $result = Disable-WinRMGPO
            $action = 'disabled'
        }
        else {
            $result = Enable-WinRMGPO
            $action = 'enabled'
        }

        if ($result.Success) {
            [System.Windows.MessageBox]::Show("WinRM GPO link $action.", 'Success', 'OK', 'Information')
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-RemoveWinRMGPO {
    param([System.Windows.Window]$Window)

    try {
        $status = Get-SetupStatus
        if (-not $status.Success -or -not $status.Data.WinRM.Exists) {
            [System.Windows.MessageBox]::Show('WinRM GPO does not exist. Nothing to remove.', 'Not Found', 'OK', 'Warning')
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "This will PERMANENTLY remove the 'AppLocker-EnableWinRM' GPO and all its links.`n`n" +
            "WinRM service auto-start settings may persist on target machines until manually changed or gpupdate /force is run.`n`n" +
            "Are you sure?",
            'Remove WinRM GPO',
            'YesNo',
            'Warning'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Remove-WinRMGPO

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "WinRM GPO removed.`n`n$($result.Data.Note)",
                'Removed',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-InitializeAppLockerGPOs {
    param([System.Windows.Window]$Window)

    try {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will create three AppLocker GPOs:`n`n" +
            "- AppLocker-DC (linked to Domain Controllers OU)`n" +
            "- AppLocker-Servers (linked to Servers OU)`n" +
            "- AppLocker-Workstations (linked to Computers OU)`n`n" +
            "Continue?",
            'Initialize AppLocker GPOs',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerGPOs

        if ($result.Success) {
            $summary = $result.Data | ForEach-Object { "- $($_.Name): $($_.Status)" }
            [System.Windows.MessageBox]::Show(
                "AppLocker GPOs created!`n`n$($summary -join "`n")",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-InitializeADStructure {
    param([System.Windows.Window]$Window)

    try {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will create the AppLocker OU and security groups:`n`n" +
            "OU: AppLocker (at domain root)`n`n" +
            "Groups:`n" +
            "- AppLocker-Admins`n" +
            "- AppLocker-Exempt`n" +
            "- AppLocker-Audit`n" +
            "- AppLocker-Users`n" +
            "- AppLocker-Installers`n" +
            "- AppLocker-Developers`n`n" +
            "Continue?",
            'Initialize AD Structure',
            'YesNo',
            'Question'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-ADStructure

        if ($result.Success) {
            $groupSummary = $result.Data.Groups | ForEach-Object { "- $($_.Name): $($_.Status)" }
            [System.Windows.MessageBox]::Show(
                "AD Structure created!`n`n" +
                "OU: $($result.Data.OUPath)`n`n" +
                "Groups:`n$($groupSummary -join "`n")",
                'Success',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-InitializeAll {
    param([System.Windows.Window]$Window)

    try {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will run ALL initialization steps:`n`n" +
            "1. Create WinRM GPO (linked to domain root)`n" +
            "2. Create AppLocker GPOs (DC, Servers, Workstations)`n" +
            "3. Create AppLocker OU and security groups`n`n" +
            "This requires Domain Admin permissions.`n`n" +
            "Continue?",
            'Full Initialization',
            'YesNo',
            'Warning'
        )

        if ($confirm -ne 'Yes') { return }

        $result = Initialize-AppLockerEnvironment

        if ($result.Success) {
            [System.Windows.MessageBox]::Show(
                "Full initialization complete!`n`n" +
                "WinRM GPO: $(if ($result.Data.WinRM.Success) { 'Success' } else { 'Failed' })`n" +
                "AppLocker GPOs: $(if ($result.Data.AppLockerGPOs.Success) { 'Success' } else { 'Failed' })`n" +
                "AD Structure: $(if ($result.Data.ADStructure.Success) { 'Success' } else { 'Failed' })",
                'Initialization Complete',
                'OK',
                'Information'
            )
            Update-SetupStatus -Window $Window
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== WINDOW INITIALIZATION =====
#endregion
