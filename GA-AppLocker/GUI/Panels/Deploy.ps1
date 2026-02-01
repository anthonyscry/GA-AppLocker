#region Deploy Panel Functions
# Deploy.ps1 - Deploy panel handlers
function Initialize-DeploymentPanel {
    param($Window)

    # Wire up filter buttons
    $filterButtons = @(
        'BtnFilterAllJobs', 'BtnFilterPendingJobs', 'BtnFilterRunningJobs',
        'BtnFilterCompletedJobs', 'BtnFilterFailedJobs'
    )

    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                    param($sender, $e)
                    $tag = $sender.Tag
                    if ($tag -match 'FilterJobs(.+)') {
                        $filter = $Matches[1]
                        Update-DeploymentFilter -Window $global:GA_MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreateDeployment', 'BtnRefreshDeployments', 'BtnDeployJob',
        'BtnStopDeployment', 'BtnCancelSelected', 'BtnViewDeployLog',
        'BtnBackupGpoPolicy', 'BtnExportPolicyXml', 'BtnImportPolicyXml',
        'BtnSaveDeployPolicyChanges',
        'BtnToggleGpoLinkDC', 'BtnToggleGpoLinkServers', 'BtnToggleGpoLinkWks'
    )

    foreach ($btnName in $actionButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $btn.Add_Click({
                    param($sender, $e)
                    Invoke-ButtonAction -Action $sender.Tag
                }.GetNewClosure())
        }
    }

    # Wire up DataGrid selection changed
    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if ($dataGrid) {
        $dataGrid.Add_SelectionChanged({
                param($sender, $e)
                Update-SelectedJobInfo -Window $global:GA_MainWindow
            })
    }

    # Load policies into combo box
    global:Refresh-DeployPolicyCombo -Window $Window

    # Wire up GPO dropdown to show/hide custom textbox
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    if ($gpoCombo -and $customGpoBox) {
        $gpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $global:GA_MainWindow.FindName('TxtDeployCustomGPO')
                if ($customBox) {
                    if ($selectedItem -and $selectedItem.Tag -eq 'Custom') {
                        $customBox.Visibility = 'Visible'
                    }
                    else {
                        $customBox.Visibility = 'Collapsed'
                    }
                }
            })
    }

    # Wire up Create policy combo selection changed to load edit fields
    $policyCombo = $Window.FindName('CboDeployPolicy')
    if ($policyCombo) {
        $policyCombo.Add_SelectionChanged({
                param($sender, $e)
                Update-DeployPolicyEditTab -Window $global:GA_MainWindow -Source 'Create'
            })
    }

    # Wire up Edit policy combo selection changed to load edit fields
    $editPolicyCombo = $Window.FindName('CboDeployEditPolicy')
    if ($editPolicyCombo) {
        $editPolicyCombo.Add_SelectionChanged({
                param($sender, $e)
                Update-DeployPolicyEditTab -Window $global:GA_MainWindow -Source 'Edit'
            })
    }

    # Wire up edit GPO dropdown to show/hide custom textbox
    $editGpoCombo = $Window.FindName('CboDeployEditGPO')
    $editCustomGpoBox = $Window.FindName('TxtDeployEditCustomGPO')
    if ($editGpoCombo -and $editCustomGpoBox) {
        $editGpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $global:GA_MainWindow.FindName('TxtDeployEditCustomGPO')
                if ($customBox) {
                    if ($selectedItem -and $selectedItem.Tag -eq 'Custom') {
                        $customBox.Visibility = 'Visible'
                    }
                    else {
                        $customBox.Visibility = 'Collapsed'
                    }
                }
            })
    }

    # Check module status
    Update-ModuleStatus -Window $Window

    # Check AppLocker GPO link status
    Update-AppLockerGpoLinkStatus -Window $Window

    # Initial load - sync mode (async hangs on module import in runspace)
    Update-DeploymentJobsDataGrid -Window $Window
}

function Update-ModuleStatus {
    param($Window)

    $gpStatus = $Window.FindName('TxtGPModuleStatus')
    $alStatus = $Window.FindName('TxtALModuleStatus')

    if ($gpStatus) {
        $hasGP = Get-Module -ListAvailable -Name GroupPolicy
        $gpStatus.Text = if ($hasGP) { 'Available' } else { 'Not Installed' }
        $gpStatus.Foreground = if ($hasGP) { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(129, 199, 132))
        }
        else { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(229, 115, 115))
        }
    }

    if ($alStatus) {
        $hasAL = Get-Command -Name 'Set-AppLockerPolicy' -ErrorAction SilentlyContinue
        $alStatus.Text = if ($hasAL) { 'Available' } else { 'Not Available' }
        $alStatus.Foreground = if ($hasAL) { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(129, 199, 132))
        }
        else { 
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 213, 79))
        }
    }
}

function global:Refresh-DeployPolicyCombo {
    <#
    .SYNOPSIS
        Refreshes the policy dropdowns on the Deployment panel (Create + Edit tabs).
    #>
    param($Window)

    $policyCombo = $Window.FindName('CboDeployPolicy')
    $editPolicyCombo = $Window.FindName('CboDeployEditPolicy')

    if (-not $policyCombo -and -not $editPolicyCombo) {
        Write-Log -Message 'Refresh-DeployPolicyCombo: No policy combo controls found' -Level 'Warning'
        return
    }

    try {
        if ($policyCombo) { $policyCombo.Items.Clear() }
        if ($editPolicyCombo) { $editPolicyCombo.Items.Clear() }

        # Load Active and Draft policies (anything deployable)
        $result = Get-AllPolicies
        if (-not $result.Success) {
            Write-Log -Message "Refresh-DeployPolicyCombo: Get-AllPolicies failed: $($result.Error)" -Level 'Warning'
            return
        }

        if (-not $result.Data -or @($result.Data).Count -eq 0) {
            Write-Log -Message 'Refresh-DeployPolicyCombo: No policies found on disk' -Level 'Info'
            return
        }

        $deployable = @($result.Data | Where-Object { $_.Status -eq 'Active' -or $_.Status -eq 'Draft' })
        Write-Log -Message "Refresh-DeployPolicyCombo: Found $(@($result.Data).Count) total policies, $($deployable.Count) deployable (Active/Draft)"

        foreach ($policy in $deployable) {
            $displayText = "$($policy.Name) (Phase $($policy.Phase)) - $($policy.Status)"

            if ($policyCombo) {
                $item = [System.Windows.Controls.ComboBoxItem]::new()
                $item.Content = $displayText
                $item.Tag = $policy
                $policyCombo.Items.Add($item) | Out-Null
            }

            if ($editPolicyCombo) {
                $editItem = [System.Windows.Controls.ComboBoxItem]::new()
                $editItem.Content = $displayText
                $editItem.Tag = $policy
                $editPolicyCombo.Items.Add($editItem) | Out-Null
            }
        }

        Write-Log -Message "Refresh-DeployPolicyCombo: Loaded $($deployable.Count) policies into dropdown(s)"
    }
    catch {
        Write-Log -Message "Refresh-DeployPolicyCombo: Exception - $($_.Exception.Message)" -Level 'Error'
    }
}

function global:Update-DeploymentJobsDataGrid {
    param(
        $Window,
        [switch]$Async
    )

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if (-not $dataGrid) { return }

    # Capture filter state
    $deployFilter = $script:CurrentDeploymentFilter

    # Define the data processing logic
    $processJobsData = {
        param($Result, $DeployFilter, $DataGrid)
        
        if (-not $Result.Success) {
            $DataGrid.ItemsSource = $null
            return
        }

        $jobs = $Result.Data

        # Apply filter
        if ($DeployFilter -and $DeployFilter -ne 'All') {
            $jobs = $jobs | Where-Object { $_.Status -eq $DeployFilter }
        }

        # Add display properties
        $displayData = $jobs | ForEach-Object {
            $job = $_
            $props = @{}
            $_.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            $props['ProgressDisplay'] = "$($_.Progress)%"
            # Safely parse CreatedAt (may be DateTime, string, or PSCustomObject from JSON)
            $createdDisplay = ''
            if ($_.CreatedAt) {
                try {
                    $dateValue = $_.CreatedAt
                    if ($dateValue -is [PSCustomObject] -and $dateValue.DateTime) {
                        $createdDisplay = ([datetime]$dateValue.DateTime).ToString('MM/dd HH:mm')
                    }
                    elseif ($dateValue -is [datetime]) {
                        $createdDisplay = $dateValue.ToString('MM/dd HH:mm')
                    }
                    elseif ($dateValue -is [string]) {
                        $createdDisplay = ([datetime]$dateValue).ToString('MM/dd HH:mm')
                    }
                } catch { }
            }
            $props['CreatedDisplay'] = $createdDisplay
            [PSCustomObject]$props
        }

        $DataGrid.ItemsSource = @($displayData)
        
        # Update counters
        Update-JobCounters -Window $Window -Jobs $Result.Data
    }

    # Use async for initial/refresh loads
    if ($Async) {
        Invoke-AsyncOperation -ScriptBlock { Get-AllDeploymentJobs } -LoadingMessage 'Loading deployment jobs...' -OnComplete {
            param($Result)
            & $processJobsData $Result $deployFilter $dataGrid
        }.GetNewClosure() -OnError {
            param($ErrorMessage)
            Write-Log -Level Error -Message "Failed to load deployment jobs: $ErrorMessage"
        }.GetNewClosure()
    }
    else {
        # Synchronous fallback
        try {
            $result = Get-AllDeploymentJobs
            & $processJobsData $result $deployFilter $dataGrid
        }
        catch {
            Write-Log -Level Error -Message "Failed to update deployment grid: $($_.Exception.Message)"
            $dataGrid.ItemsSource = $null
        }
    }
}

function Update-JobCounters {
    param(
        $Window,
        [array]$Jobs
    )

    $total = if ($Jobs) { $Jobs.Count } else { 0 }
    $pending = if ($Jobs) { @($Jobs | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $running = if ($Jobs) { @($Jobs | Where-Object { $_.Status -eq 'Running' }).Count } else { 0 }
    $completed = if ($Jobs) { @($Jobs | Where-Object { $_.Status -eq 'Completed' }).Count } else { 0 }

    $ctrl = $Window.FindName('TxtJobTotalCount');     if ($ctrl) { $ctrl.Text = "$total" }
    $ctrl = $Window.FindName('TxtJobPendingCount');   if ($ctrl) { $ctrl.Text = "$pending" }
    $ctrl = $Window.FindName('TxtJobRunningCount');   if ($ctrl) { $ctrl.Text = "$running" }
    $ctrl = $Window.FindName('TxtJobCompletedCount'); if ($ctrl) { $ctrl.Text = "$completed" }
}

function global:Update-DeploymentFilter {
    param(
        $Window,
        [string]$Filter
    )

    $script:CurrentDeploymentFilter = $Filter

    # Grey pill visual toggle for filter buttons
    $activePillBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
    $filterButtons = @(
        'BtnFilterAllJobs', 'BtnFilterPendingJobs', 'BtnFilterRunningJobs',
        'BtnFilterCompletedJobs', 'BtnFilterFailedJobs'
    )
    $colorMap = @{
        'BtnFilterAllJobs'       = [System.Windows.Media.Brushes]::White
        'BtnFilterPendingJobs'   = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF8C00')
        'BtnFilterRunningJobs'   = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4')
        'BtnFilterCompletedJobs' = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#107C10')
        'BtnFilterFailedJobs'    = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D13438')
    }
    $btnNameMap = @{
        'All'       = 'BtnFilterAllJobs'
        'Pending'   = 'BtnFilterPendingJobs'
        'Running'   = 'BtnFilterRunningJobs'
        'Completed' = 'BtnFilterCompletedJobs'
        'Failed'    = 'BtnFilterFailedJobs'
    }

    # Reset all to inactive (transparent bg + original color)
    foreach ($btnName in $filterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = $colorMap[$btnName]
        }
    }

    # Highlight active filter (grey pill bg + white text)
    $activeBtnName = $btnNameMap[$Filter]
    if ($activeBtnName) {
        $btn = $Window.FindName($activeBtnName)
        if ($btn) {
            $btn.Background = $activePillBg
            $btn.Foreground = [System.Windows.Media.Brushes]::White
        }
    }

    Update-DeploymentJobsDataGrid -Window $Window
}

function global:Update-SelectedJobInfo {
    param($Window)

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if (-not $dataGrid) { return }
    $selectedItem = $dataGrid.SelectedItem
    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($selectedItem) {
        $script:SelectedDeploymentJobId = $selectedItem.JobId
        if ($messageBox)  { $messageBox.Text = $selectedItem.Message }
        if ($progressBar) { $progressBar.Value = $selectedItem.Progress }
    }
    else {
        $script:SelectedDeploymentJobId = $null
        if ($messageBox)  { $messageBox.Text = 'Select a deployment job to view details' }
        if ($progressBar) { $progressBar.Value = 0 }
    }
}

function global:Invoke-CreateDeploymentJob {
    param($Window)

    $policyCombo = $Window.FindName('CboDeployPolicy')
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    $scheduleCombo = $Window.FindName('CboDeploySchedule')

    if (-not $policyCombo.SelectedItem) {
        Show-AppLockerMessageBox 'Please select a policy to deploy.' 'Missing Policy' 'OK' 'Warning'
        return
    }

    # Get GPO name from dropdown or custom textbox
    $selectedGpo = $gpoCombo.SelectedItem
    $gpoName = if ($selectedGpo -and $selectedGpo.Tag -eq 'Custom') {
        $customGpoBox.Text
    }
    elseif ($selectedGpo) {
        $selectedGpo.Tag
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($gpoName)) {
        Show-AppLockerMessageBox 'Please select or enter a target GPO name.' 'Missing GPO' 'OK' 'Warning'
        return
    }

    $schedule = switch ($scheduleCombo.SelectedIndex) {
        0 { 'Manual' }
        1 { 'Immediate' }
        2 { 'Scheduled' }
        default { 'Manual' }
    }

    try {
        $policy = $policyCombo.SelectedItem.Tag
        $result = New-DeploymentJob -PolicyId $policy.PolicyId -GPOName $gpoName -Schedule $schedule

        if ($result.Success) {
            # Reset custom GPO box if used
            if ($customGpoBox) { $customGpoBox.Text = '' }
            Update-DeploymentJobsDataGrid -Window $Window
            Show-AppLockerMessageBox "Deployment job created for policy '$($policy.Name)'.`nTarget GPO: $gpoName" 'Success' 'OK' 'Information'
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-DeploySelectedJob {
    param($Window)

    if ($script:DeploymentInProgress) {
        Show-Toast -Message 'A deployment is already in progress.' -Type 'Warning'
        return
    }

    if (-not $script:SelectedDeploymentJobId) {
        Show-Toast -Message 'Please select a deployment job.' -Type 'Warning'
        return
    }

    $confirm = Show-AppLockerMessageBox 'Start deployment now? This will apply the policy to the target GPO.' 'Confirm Deployment' 'YesNo' 'Question'

    if ($confirm -ne 'Yes') { return }

    # Update UI state
    $script:DeploymentInProgress = $true
    $script:DeploymentCancelled = $false
    Update-DeploymentUIState -Window $Window -Deploying $true
    Update-DeploymentProgress -Window $Window -Text 'Initializing deployment...' -Percent 5

    # Create synchronized hashtable for cross-thread communication
    $script:DeploySyncHash = [hashtable]::Synchronized(@{
        Window     = $Window
        JobId      = $script:SelectedDeploymentJobId
        Result     = $null
        Error      = $null
        IsComplete = $false
        Progress   = 10
        StatusText = 'Loading modules...'
    })

    # Create and configure runspace
    $script:DeployRunspace = [runspacefactory]::CreateRunspace()
    $script:DeployRunspace.ApartmentState = 'STA'
    $script:DeployRunspace.ThreadOptions = 'ReuseThread'
    $script:DeployRunspace.Open()
    $script:DeployRunspace.SessionStateProxy.SetVariable('SyncHash', $script:DeploySyncHash)

    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:DeployRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:DeployPowerShell = [powershell]::Create()
    $script:DeployPowerShell.Runspace = $script:DeployRunspace

    [void]$script:DeployPowerShell.AddScript({
        param($SyncHash, $ModulePath)
        
        try {
            # Import the module in this runspace
            $SyncHash.StatusText = 'Loading modules...'
            $SyncHash.Progress = 15
            
            $manifestPath = Join-Path $ModulePath 'GA-AppLocker.psd1'
            if (Test-Path $manifestPath) {
                Import-Module $manifestPath -Force -ErrorAction Stop
            }
            else {
                throw "Module not found at: $manifestPath"
            }
            
            $SyncHash.StatusText = 'Executing deployment...'
            $SyncHash.Progress = 30
            
            # Execute the deployment
            $result = Start-Deployment -JobId $SyncHash.JobId
            
            $SyncHash.Progress = 90
            $SyncHash.StatusText = 'Finalizing...'
            $SyncHash.Result = $result
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
            $SyncHash.Progress = 100
        }
    })

    [void]$script:DeployPowerShell.AddArgument($script:DeploySyncHash)
    [void]$script:DeployPowerShell.AddArgument($modulePath)

    # Start async execution
    $script:DeployAsyncResult = $script:DeployPowerShell.BeginInvoke()

    # Create DispatcherTimer to poll for completion and update UI
    $script:DeployTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DeployTimer.Interval = [TimeSpan]::FromMilliseconds(200)

    $script:DeployTimer.Add_Tick({
        $syncHash = $script:DeploySyncHash
        $win = $syncHash.Window

        # Update progress
        Update-DeploymentProgress -Window $win -Text $syncHash.StatusText -Percent $syncHash.Progress

        # Check if cancelled
        if ($script:DeploymentCancelled) {
            $script:DeployTimer.Stop()

            # Clean up runspace
            if ($script:DeployPowerShell) {
                $script:DeployPowerShell.Stop()
                $script:DeployPowerShell.Dispose()
            }
            if ($script:DeployRunspace) {
                $script:DeployRunspace.Close()
                $script:DeployRunspace.Dispose()
            }

            $script:DeploymentInProgress = $false
            Update-DeploymentUIState -Window $win -Deploying $false
            Update-DeploymentProgress -Window $win -Text 'Deployment cancelled' -Percent 0
            Show-Toast -Message 'Deployment cancelled.' -Type 'Warning'
            return
        }

        # Check if complete
        if ($syncHash.IsComplete) {
            $script:DeployTimer.Stop()

            # End the async operation
            try {
                $script:DeployPowerShell.EndInvoke($script:DeployAsyncResult)
            }
            catch { }

            # Clean up runspace
            if ($script:DeployPowerShell) { $script:DeployPowerShell.Dispose() }
            if ($script:DeployRunspace) {
                $script:DeployRunspace.Close()
                $script:DeployRunspace.Dispose()
            }

            $script:DeploymentInProgress = $false
            Update-DeploymentUIState -Window $win -Deploying $false
            Update-DeploymentJobsDataGrid -Window $win

            if ($syncHash.Error) {
                Update-DeploymentProgress -Window $win -Text "Error: $($syncHash.Error)" -Percent 0
                Show-Toast -Message "Deployment error: $($syncHash.Error)" -Type 'Error'
            }
            elseif ($syncHash.Result -and $syncHash.Result.Success) {
                Update-DeploymentProgress -Window $win -Text 'Deployment complete' -Percent 100
                $successMsg = if ($syncHash.Result.Message) { $syncHash.Result.Message } else { 'Deployment completed successfully.' }
                Show-Toast -Message $successMsg -Type 'Success'
            }
            else {
                $errorMsg = if ($syncHash.Result) { $syncHash.Result.Error } else { 'Unknown error' }
                Update-DeploymentProgress -Window $win -Text "Failed: $errorMsg" -Percent 0
                Show-Toast -Message "Deployment failed: $errorMsg" -Type 'Error'
            }
        }
    })

    # Start the timer
    $script:DeployTimer.Start()
}

function global:Invoke-StopDeployment {
    param($Window)

    if (-not $script:DeploymentInProgress) {
        Show-Toast -Message 'No deployment in progress.' -Type 'Info'
        return
    }

    # Signal cancellation - the timer tick handler will clean up
    $script:DeploymentCancelled = $true
}

function Update-DeploymentUIState {
    param(
        $Window,
        [bool]$Deploying
    )

    $btnDeploy = $Window.FindName('BtnDeployJob')
    $btnStop = $Window.FindName('BtnStopDeployment')

    if ($btnDeploy) { $btnDeploy.IsEnabled = -not $Deploying }
    if ($btnStop) { $btnStop.IsEnabled = $Deploying }
}

function Update-DeploymentProgress {
    param(
        $Window,
        [string]$Text,
        [int]$Percent
    )

    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($messageBox) { $messageBox.Text = $Text }
    if ($progressBar) { $progressBar.Value = $Percent }
}

function global:Invoke-CancelDeploymentJob {
    param($Window)

    if (-not $script:SelectedDeploymentJobId) {
        Show-AppLockerMessageBox 'Please select a deployment job to cancel.' 'No Selection' 'OK' 'Information'
        return
    }

    $confirm = Show-AppLockerMessageBox 'Cancel this deployment job?' 'Confirm Cancel' 'YesNo' 'Warning'

    if ($confirm -ne 'Yes') { return }

    try {
        $result = Stop-Deployment -JobId $script:SelectedDeploymentJobId

        if ($result.Success) {
            Update-DeploymentJobsDataGrid -Window $Window
            Show-AppLockerMessageBox 'Deployment cancelled.' 'Cancelled' 'OK' 'Information'
        }
        else {
            Show-AppLockerMessageBox "Failed: $($result.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Show-DeploymentLog {
    param($Window)

    try {
        $result = Get-AllDeploymentJobs
        if (-not $result.Success -or -not $result.Data -or @($result.Data).Count -eq 0) {
            Show-AppLockerMessageBox 'No deployment jobs found.' 'No Jobs' 'OK' 'Information'
            return
        }

        $logText = "DEPLOYMENT JOBS`n" + ('=' * 60) + "`n`n"
        foreach ($job in $result.Data) {
            $created = ''
            try {
                if ($job.CreatedAt -is [datetime]) { $created = $job.CreatedAt.ToString('yyyy-MM-dd HH:mm') }
                elseif ($job.CreatedAt) { $created = ([datetime]$job.CreatedAt).ToString('yyyy-MM-dd HH:mm') }
            } catch { }
            $logText += "Policy:   $($job.PolicyName)`n"
            $logText += "GPO:      $($job.GPOName)`n"
            $logText += "Status:   $($job.Status)`n"
            $logText += "Progress: $($job.Progress)%`n"
            $logText += "Created:  $created`n"
            $logText += "Message:  $($job.Message)`n"
            $logText += ('-' * 60) + "`n"
        }

        Show-AppLockerMessageBox $logText 'Deployment Job Details' 'OK' 'Information'
    }
    catch {
        Show-AppLockerMessageBox "Error: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-BackupGpoPolicy {
    <#
    .SYNOPSIS
        Backs up the current AppLocker policy from a GPO to an XML file.
    #>
    param($Window)

    # Ask which GPO to backup from
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $gpoName = if ($gpoCombo -and $gpoCombo.SelectedItem -and $gpoCombo.SelectedItem.Tag -ne 'Custom') {
        $gpoCombo.SelectedItem.Tag
    } else {
        'AppLocker-Servers'
    }

    $confirm = Show-AppLockerMessageBox "Backup current AppLocker policy from GPO '$gpoName'?`n`nThis will use Get-AppLockerPolicy to export the`neffective policy to an XML backup file." 'Backup GPO Policy' 'YesNo' 'Question'
    
    if ($confirm -ne 'Yes') { return }

    # Pick save location
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = 'XML Files (*.xml)|*.xml'
    $saveDialog.FileName = "AppLocker-Backup-$gpoName-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
    $saveDialog.Title = 'Save AppLocker Policy Backup'

    if (-not $saveDialog.ShowDialog()) { return }
    $outputPath = $saveDialog.FileName

    Show-LoadingOverlay -Message "Backing up policy from GPO '$gpoName'..." -SubMessage 'Please wait'

    try {
        # Try Get-AppLockerPolicy from GPO
        $hasAL = Get-Command -Name 'Get-AppLockerPolicy' -ErrorAction SilentlyContinue
        if (-not $hasAL) {
            Hide-LoadingOverlay
            Show-AppLockerMessageBox "Get-AppLockerPolicy cmdlet not available.`n`nInstall RSAT or the AppLocker PowerShell module." 'Module Not Found' 'OK' 'Warning'
            return
        }

        # Try GPO-based backup first, fall back to local effective policy
        $policy = $null
        $source = ''
        try {
            $hasGP = Get-Module -ListAvailable -Name GroupPolicy
            if ($hasGP) {
                Import-Module GroupPolicy -ErrorAction Stop
                $gpo = Get-GPO -Name $gpoName -ErrorAction Stop
                $policy = Get-AppLockerPolicy -Id $gpo.Id -Domain $gpo.DomainName -Xml
                $source = "GPO: $gpoName"
            }
        } catch {
            Write-Log -Level Warning -Message "GPO policy backup failed, falling back to effective: $($_.Exception.Message)"
        }

        if (-not $policy) {
            # Fallback: get effective local policy
            $policy = Get-AppLockerPolicy -Effective -Xml
            $source = 'Effective (Local)'
        }

        if ($policy) {
            [System.IO.File]::WriteAllText($outputPath, $policy)
            Hide-LoadingOverlay
            Show-Toast -Message "Policy backed up from $source" -Type 'Success'
            Show-AppLockerMessageBox "Policy backup saved to:`n$outputPath`n`nSource: $source" 'Backup Complete' 'OK' 'Information'
        } else {
            Hide-LoadingOverlay
            Show-AppLockerMessageBox 'No AppLocker policy found.' 'Empty' 'OK' 'Warning'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-AppLockerMessageBox "Backup failed: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-ExportDeployPolicyXml {
    <#
    .SYNOPSIS
        Exports a GA-AppLocker policy to AppLocker XML format.
    #>
    param($Window)

    # Get policies
    $result = Get-AllPolicies
    if (-not $result.Success -or @($result.Data).Count -eq 0) {
        Show-AppLockerMessageBox 'No policies found to export.' 'No Policies' 'OK' 'Warning'
        return
    }

    # Use currently selected policy from the Create tab combo, or show picker
    $policyCombo = $Window.FindName('CboDeployPolicy')
    $selectedPolicy = $null
    if ($policyCombo -and $policyCombo.SelectedItem) {
        $selectedPolicy = $policyCombo.SelectedItem.Tag
    }

    if (-not $selectedPolicy) {
        Show-AppLockerMessageBox 'Please select a policy from the Create tab first.' 'No Selection' 'OK' 'Information'
        return
    }

    # Pick save location
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = 'XML Files (*.xml)|*.xml'
    $saveDialog.FileName = "$($selectedPolicy.Name).xml"
    $saveDialog.Title = 'Export Policy to XML'

    if (-not $saveDialog.ShowDialog()) { return }

    Show-LoadingOverlay -Message "Exporting policy '$($selectedPolicy.Name)'..." -SubMessage 'Please wait'

    try {
        $exportResult = Export-PolicyToXml -PolicyId $selectedPolicy.PolicyId -OutputPath $saveDialog.FileName
        Hide-LoadingOverlay

        if ($exportResult.Success) {
            Show-Toast -Message "Policy exported to XML" -Type 'Success'
            Show-AppLockerMessageBox "Policy '$($selectedPolicy.Name)' exported to:`n$($saveDialog.FileName)" 'Export Complete' 'OK' 'Information'
        } else {
            Show-AppLockerMessageBox "Export failed: $($exportResult.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-AppLockerMessageBox "Export failed: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Invoke-ImportDeployPolicyXml {
    <#
    .SYNOPSIS
        Imports rules from an AppLocker XML policy file.
    #>
    param($Window)

    $openDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openDialog.Filter = 'XML Files (*.xml)|*.xml|All Files (*.*)|*.*'
    $openDialog.Title = 'Import AppLocker Policy XML'

    if (-not $openDialog.ShowDialog()) { return }

    Show-LoadingOverlay -Message 'Importing rules from XML...' -SubMessage $openDialog.FileName

    try {
        $importResult = Import-RulesFromXml -Path $openDialog.FileName
        Hide-LoadingOverlay

        if ($importResult.Success) {
            $count = if ($importResult.Data) { @($importResult.Data).Count } else { 0 }
            Show-Toast -Message "Imported $count rules from XML" -Type 'Success'
            Show-AppLockerMessageBox "Imported $count rule(s) from:`n$($openDialog.FileName)`n`nRules are in Pending status. Go to Rules panel to review." 'Import Complete' 'OK' 'Information'
        } else {
            Show-AppLockerMessageBox "Import failed: $($importResult.Error)" 'Error' 'OK' 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-AppLockerMessageBox "Import failed: $($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

function global:Update-DeployPolicyEditTab {
    <#
    .SYNOPSIS
        Populates the Deploy Edit tab fields from the selected policy.
        Accepts -Source 'Edit' to use the Edit tab's own dropdown, or 'Create' for the Create tab's.
    #>
    param(
        $Window,
        [string]$Source = 'Edit'
    )

    # Determine which combo triggered the update
    $comboName = if ($Source -eq 'Create') { 'CboDeployPolicy' } else { 'CboDeployEditPolicy' }
    $policyCombo = $Window.FindName($comboName)

    $txtName = $Window.FindName('TxtDeployEditPolicyName')
    $txtDesc = $Window.FindName('TxtDeployEditPolicyDesc')
    $cboGPO = $Window.FindName('CboDeployEditGPO')
    $txtCustomGPO = $Window.FindName('TxtDeployEditCustomGPO')

    if (-not $policyCombo -or -not $policyCombo.SelectedItem) {
        # No policy selected - clear fields
        if ($txtName) { $txtName.Text = '' }
        if ($txtDesc) { $txtDesc.Text = '' }
        if ($cboGPO) { $cboGPO.SelectedIndex = 0 }
        if ($txtCustomGPO) { $txtCustomGPO.Text = ''; $txtCustomGPO.Visibility = 'Collapsed' }
        return
    }

    $policy = $policyCombo.SelectedItem.Tag
    if (-not $policy) { return }

    # Sync the other combo to match (so both tabs stay in sync)
    $otherComboName = if ($Source -eq 'Create') { 'CboDeployEditPolicy' } else { 'CboDeployPolicy' }
    $otherCombo = $Window.FindName($otherComboName)
    if ($otherCombo -and $otherCombo.Items.Count -gt 0) {
        # Find the matching policy by PolicyId in the other combo
        for ($i = 0; $i -lt $otherCombo.Items.Count; $i++) {
            $otherItem = $otherCombo.Items[$i]
            if ($otherItem.Tag -and $otherItem.Tag.PolicyId -eq $policy.PolicyId) {
                if ($otherCombo.SelectedIndex -ne $i) {
                    $otherCombo.SelectedIndex = $i
                }
                break
            }
        }
    }

    if ($txtName) { $txtName.Text = if ($policy.Name) { $policy.Name } else { '' } }
    if ($txtDesc) { $txtDesc.Text = if ($policy.Description) { $policy.Description } else { '' } }

    # Set Target GPO dropdown
    if ($cboGPO) {
        $gpoValue = if ($policy.TargetGPO) { $policy.TargetGPO } else { '' }
        $matched = $false
        for ($i = 0; $i -lt $cboGPO.Items.Count; $i++) {
            $item = $cboGPO.Items[$i]
            if ($item.Tag -eq $gpoValue) {
                $cboGPO.SelectedIndex = $i
                $matched = $true
                break
            }
        }
        if (-not $matched -and $gpoValue.Length -gt 0) {
            # Custom GPO name
            for ($i = 0; $i -lt $cboGPO.Items.Count; $i++) {
                if ($cboGPO.Items[$i].Tag -eq 'Custom') {
                    $cboGPO.SelectedIndex = $i
                    break
                }
            }
            if ($txtCustomGPO) {
                $txtCustomGPO.Text = $gpoValue
                $txtCustomGPO.Visibility = 'Visible'
            }
        }
        elseif ($txtCustomGPO) {
            $txtCustomGPO.Text = ''
            $txtCustomGPO.Visibility = 'Collapsed'
        }
    }
}

function global:Invoke-SaveDeployPolicyChanges {
    <#
    .SYNOPSIS
        Saves policy name, description, and target GPO changes from the Deploy Edit tab.
    #>
    param($Window)

    # Get the selected policy from the Edit tab combo (fall back to Create tab combo)
    $editCombo = $Window.FindName('CboDeployEditPolicy')
    $createCombo = $Window.FindName('CboDeployPolicy')
    $policyCombo = if ($editCombo -and $editCombo.SelectedItem) { $editCombo } 
                   elseif ($createCombo -and $createCombo.SelectedItem) { $createCombo }
                   else { $null }

    if (-not $policyCombo -or -not $policyCombo.SelectedItem) {
        Show-Toast -Message 'Please select a policy to edit.' -Type 'Warning'
        return
    }

    $policy = $policyCombo.SelectedItem.Tag
    if (-not $policy -or -not $policy.PolicyId) {
        Show-Toast -Message 'Invalid policy selected.' -Type 'Warning'
        return
    }

    $txtName = $Window.FindName('TxtDeployEditPolicyName')
    $editName = if ($txtName) { $txtName.Text.Trim() } else { '' }

    if ([string]::IsNullOrWhiteSpace($editName)) {
        Show-Toast -Message 'Policy name cannot be empty.' -Type 'Warning'
        return
    }

    $txtDesc = $Window.FindName('TxtDeployEditPolicyDesc')
    $editDesc = if ($txtDesc) { $txtDesc.Text.Trim() } else { '' }

    # Get target GPO from dropdown or custom textbox
    $cboGPO = $Window.FindName('CboDeployEditGPO')
    $txtCustomGPO = $Window.FindName('TxtDeployEditCustomGPO')
    $selectedGpoItem = if ($cboGPO) { $cboGPO.SelectedItem } else { $null }
    $targetGPO = if ($selectedGpoItem -and $selectedGpoItem.Tag -eq 'Custom') {
        if ($txtCustomGPO) { $txtCustomGPO.Text.Trim() } else { '' }
    }
    elseif ($selectedGpoItem) {
        [string]$selectedGpoItem.Tag
    }
    else {
        ''
    }

    try {
        $result = Update-Policy -Id $policy.PolicyId -Name $editName -Description $editDesc -TargetGPO $targetGPO

        if ($result.Success) {
            Show-Toast -Message "Policy '$editName' updated." -Type 'Success'
            # Refresh the policy combo to show updated name
            global:Refresh-DeployPolicyCombo -Window $Window
        }
        else {
            Show-Toast -Message "Failed: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error: $($_.Exception.Message)" -Type 'Error'
    }
}

#region GPO Link Control

function global:Update-AppLockerGpoLinkStatus {
    <#
    .SYNOPSIS
        Checks link status for the 3 AppLocker GPOs and updates the Deploy Actions pill toggles.
    #>
    param($Window)

    # GPO name -> UI control suffix mapping
    $gpoMap = @(
        @{ Name = 'AppLocker-DC';           Suffix = 'DC';      Target = 'OU=Domain Controllers' }
        @{ Name = 'AppLocker-Servers';      Suffix = 'Servers';  Target = 'CN=Computers' }
        @{ Name = 'AppLocker-Workstations'; Suffix = 'Wks';      Target = 'CN=Computers' }
    )

    # Pill color palette
    $pillEnabled  = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#107C10')   # green
    $pillDisabled = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')   # dark grey
    $pillNotLinked = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
    $fgWhite  = [System.Windows.Media.Brushes]::White
    $fgOrange = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF8C00')
    $fgGray   = [System.Windows.Media.Brushes]::Gray

    $hasGP = Get-Module -ListAvailable -Name GroupPolicy
    if (-not $hasGP) {
        foreach ($gpo in $gpoMap) {
            $btnCtrl = $Window.FindName("BtnToggleGpoLink$($gpo.Suffix)")
            if ($btnCtrl) {
                $btnCtrl.Content = 'No GP Module'
                $btnCtrl.Background = $pillDisabled
                $btnCtrl.Foreground = $fgGray
                $btnCtrl.IsEnabled = $false
            }
        }
        return
    }

    try {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue

        # Get domain DN for building full OU paths
        $domainDN = $null
        try {
            $domainDN = ([adsi]"LDAP://RootDSE").defaultNamingContext[0]
        } catch { Write-AppLockerLog -Message "Failed to get domain DN via LDAP RootDSE: $($_.Exception.Message)" -Level 'DEBUG' }

        foreach ($gpo in $gpoMap) {
            $btnCtrl = $Window.FindName("BtnToggleGpoLink$($gpo.Suffix)")
            if (-not $btnCtrl) { continue }

            $gpoObj = Get-GPO -Name $gpo.Name -ErrorAction SilentlyContinue
            if (-not $gpoObj) {
                $btnCtrl.Content = 'Not Created'
                $btnCtrl.Background = $pillDisabled
                $btnCtrl.Foreground = $fgGray
                $btnCtrl.IsEnabled = $false
                continue
            }

            $btnCtrl.IsEnabled = $true

            # Try to find the link at the default target OU
            $link = $null
            if ($domainDN) {
                $fullTarget = "$($gpo.Target),$domainDN"
                try {
                    $link = Get-GPInheritance -Target $fullTarget -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty GpoLinks |
                            Where-Object { $_.DisplayName -eq $gpo.Name }
                } catch { Write-AppLockerLog -Message "Failed to query GPO link for '$($gpo.Name)' at '$fullTarget': $($_.Exception.Message)" -Level 'DEBUG' }
            }

            if ($link) {
                if ($link.Enabled) {
                    $btnCtrl.Content = 'Enabled'
                    $btnCtrl.Background = $pillEnabled
                    $btnCtrl.Foreground = $fgWhite
                }
                else {
                    $btnCtrl.Content = 'Disabled'
                    $btnCtrl.Background = $pillDisabled
                    $btnCtrl.Foreground = $fgOrange
                }
            }
            else {
                # GPO exists but not linked at default OU
                $btnCtrl.Content = 'Not Linked'
                $btnCtrl.Background = $pillNotLinked
                $btnCtrl.Foreground = $fgGray
            }
        }
    }
    catch {
        Write-Log -Message "Update-AppLockerGpoLinkStatus: $($_.Exception.Message)" -Level 'Error'
    }
}

function global:Invoke-ToggleAppLockerGpoLink {
    <#
    .SYNOPSIS
        Toggles the link state for an AppLocker GPO (DC, Servers, or Workstations).
    #>
    param(
        $Window,
        [ValidateSet('DC', 'Servers', 'Workstations')]
        [string]$GPOType
    )

    $nameMap = @{ DC = 'AppLocker-DC'; Servers = 'AppLocker-Servers'; Workstations = 'AppLocker-Workstations' }
    $targetMap = @{ DC = 'OU=Domain Controllers'; Servers = 'CN=Computers'; Workstations = 'CN=Computers' }
    $suffixMap = @{ DC = 'DC'; Servers = 'Servers'; Workstations = 'Wks' }

    $gpoName = $nameMap[$GPOType]
    $suffix = $suffixMap[$GPOType]

    try {
        $hasGP = Get-Module -ListAvailable -Name GroupPolicy
        if (-not $hasGP) {
            Show-AppLockerMessageBox 'GroupPolicy module not available. Install RSAT.' 'Missing Module' 'OK' 'Warning'
            return
        }
        Import-Module GroupPolicy -ErrorAction Stop

        $gpoObj = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if (-not $gpoObj) {
            Show-AppLockerMessageBox "GPO '$gpoName' does not exist.`nCreate it from the Setup panel first." 'Not Found' 'OK' 'Warning'
            return
        }

        $domainDN = ([adsi]"LDAP://RootDSE").defaultNamingContext[0]
        $fullTarget = "$($targetMap[$GPOType]),$domainDN"

        # Check current link state
        $link = $null
        try {
            $link = Get-GPInheritance -Target $fullTarget -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty GpoLinks |
                    Where-Object { $_.DisplayName -eq $gpoName }
        } catch { Write-AppLockerLog -Message "Failed to query GPO link for '$gpoName' at '$fullTarget': $($_.Exception.Message)" -Level 'DEBUG' }

        if (-not $link) {
            # GPO exists but isn't linked — offer to create link
            $answer = Show-AppLockerMessageBox "'$gpoName' is not linked to '$fullTarget'.`n`nCreate the link now?" 'Not Linked' 'YesNo' 'Question'
            if ($answer -ne 'Yes') { return }

            New-GPLink -Name $gpoName -Target $fullTarget -ErrorAction Stop
            Show-Toast -Message "$gpoName linked and enabled" -Type 'Success'
        }
        elseif ($link.Enabled) {
            Set-GPLink -Name $gpoName -Target $fullTarget -LinkEnabled No -ErrorAction Stop
            Show-Toast -Message "$gpoName link disabled" -Type 'Info'
        }
        else {
            Set-GPLink -Name $gpoName -Target $fullTarget -LinkEnabled Yes -ErrorAction Stop
            Show-Toast -Message "$gpoName link enabled" -Type 'Success'
        }

        # Refresh status display
        Update-AppLockerGpoLinkStatus -Window $Window
    }
    catch {
        Show-AppLockerMessageBox "Error toggling $gpoName link:`n$($_.Exception.Message)" 'Error' 'OK' 'Error'
    }
}

#endregion

#endregion

#region ===== SETUP PANEL HANDLERS =====

#endregion
