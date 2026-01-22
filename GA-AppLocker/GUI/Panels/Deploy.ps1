#region Deploy Panel Functions
# Deploy.ps1 - Deploy panel handlers
function Initialize-DeploymentPanel {
    param([System.Windows.Window]$Window)

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
                        Update-DeploymentFilter -Window $script:MainWindow -Filter $filter
                    }
                }.GetNewClosure())
        }
    }

    # Wire up action buttons
    $actionButtons = @(
        'BtnCreateDeployment', 'BtnRefreshDeployments', 'BtnDeployJob',
        'BtnStopDeployment', 'BtnCancelSelected', 'BtnViewDeployLog'
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
                Update-SelectedJobInfo -Window $script:MainWindow
            })
    }

    # Load policies into combo box
    $policyCombo = $Window.FindName('CboDeployPolicy')
    if ($policyCombo -and (Get-Command -Name 'Get-AllPolicies' -ErrorAction SilentlyContinue)) {
        $result = Get-AllPolicies -Status 'Active'
        if ($result.Success -and $result.Data) {
            $policyCombo.ItemsSource = $result.Data
        }
    }

    # Wire up GPO dropdown to show/hide custom textbox
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    if ($gpoCombo -and $customGpoBox) {
        $gpoCombo.Add_SelectionChanged({
                param($sender, $e)
                $selectedItem = $sender.SelectedItem
                $customBox = $script:MainWindow.FindName('TxtDeployCustomGPO')
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

    # Initial load - use async to keep UI responsive
    Update-DeploymentJobsDataGrid -Window $Window -Async
}

function Update-ModuleStatus {
    param([System.Windows.Window]$Window)

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

function script:Update-DeploymentJobsDataGrid {
    param(
        [System.Windows.Window]$Window,
        [switch]$Async
    )

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    if (-not $dataGrid) { return }

    if (-not (Get-Command -Name 'Get-AllDeploymentJobs' -ErrorAction SilentlyContinue)) {
        $dataGrid.ItemsSource = $null
        return
    }

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
            $props['CreatedDisplay'] = if ($_.CreatedAt) { ([datetime]$_.CreatedAt).ToString('MM/dd HH:mm') } else { '' }
            [PSCustomObject]$props
        }

        $DataGrid.ItemsSource = @($displayData)
        
        # Update counters
        Update-JobCounters -Window $Window -Jobs $Result.Data
    }

    # Use async for initial/refresh loads
    if ($Async -and (Get-Command -Name 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
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
        [System.Windows.Window]$Window,
        [array]$Jobs
    )

    $total = if ($Jobs) { $Jobs.Count } else { 0 }
    $pending = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Pending' }).Count } else { 0 }
    $running = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Running' }).Count } else { 0 }
    $completed = if ($Jobs) { ($Jobs | Where-Object { $_.Status -eq 'Completed' }).Count } else { 0 }

    $Window.FindName('TxtJobTotalCount').Text = "$total"
    $Window.FindName('TxtJobPendingCount').Text = "$pending"
    $Window.FindName('TxtJobRunningCount').Text = "$running"
    $Window.FindName('TxtJobCompletedCount').Text = "$completed"
}

function global:Update-DeploymentFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    $script:CurrentDeploymentFilter = $Filter
    Update-DeploymentJobsDataGrid -Window $Window
}

function Update-SelectedJobInfo {
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('DeploymentJobsDataGrid')
    $selectedItem = $dataGrid.SelectedItem
    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($selectedItem) {
        $script:SelectedDeploymentJobId = $selectedItem.JobId
        $messageBox.Text = $selectedItem.Message
        $progressBar.Value = $selectedItem.Progress
    }
    else {
        $script:SelectedDeploymentJobId = $null
        $messageBox.Text = 'Select a deployment job to view details'
        $progressBar.Value = 0
    }
}

function Invoke-CreateDeploymentJob {
    param([System.Windows.Window]$Window)

    $policyCombo = $Window.FindName('CboDeployPolicy')
    $gpoCombo = $Window.FindName('CboDeployTargetGPO')
    $customGpoBox = $Window.FindName('TxtDeployCustomGPO')
    $scheduleCombo = $Window.FindName('CboDeploySchedule')

    if (-not $policyCombo.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a policy to deploy.', 'Missing Policy', 'OK', 'Warning')
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
        [System.Windows.MessageBox]::Show('Please select or enter a target GPO name.', 'Missing GPO', 'OK', 'Warning')
        return
    }

    $schedule = switch ($scheduleCombo.SelectedIndex) {
        0 { 'Manual' }
        1 { 'Immediate' }
        2 { 'Scheduled' }
        default { 'Manual' }
    }

    try {
        $policy = $policyCombo.SelectedItem
        $result = New-DeploymentJob -PolicyId $policy.PolicyId -GPOName $gpoName -Schedule $schedule

        if ($result.Success) {
            # Reset custom GPO box if used
            if ($customGpoBox) { $customGpoBox.Text = '' }
            Update-DeploymentJobsDataGrid -Window $Window
            [System.Windows.MessageBox]::Show(
                "Deployment job created for policy '$($policy.Name)'.`nTarget GPO: $gpoName",
                'Success',
                'OK',
                'Information'
            )
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Invoke-DeploySelectedJob {
    param([System.Windows.Window]$Window)

    if ($script:DeploymentInProgress) {
        Show-Toast -Message 'A deployment is already in progress.' -Type 'Warning'
        return
    }

    if (-not $script:SelectedDeploymentJobId) {
        Show-Toast -Message 'Please select a deployment job.' -Type 'Warning'
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Start deployment now? This will apply the policy to the target GPO.',
        'Confirm Deployment',
        'YesNo',
        'Question'
    )

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

function Invoke-StopDeployment {
    param([System.Windows.Window]$Window)

    if (-not $script:DeploymentInProgress) {
        Show-Toast -Message 'No deployment in progress.' -Type 'Info'
        return
    }

    # Signal cancellation - the timer tick handler will clean up
    $script:DeploymentCancelled = $true
}

function Update-DeploymentUIState {
    param(
        [System.Windows.Window]$Window,
        [bool]$Deploying
    )

    $btnDeploy = $Window.FindName('BtnDeployJob')
    $btnStop = $Window.FindName('BtnStopDeployment')

    if ($btnDeploy) { $btnDeploy.IsEnabled = -not $Deploying }
    if ($btnStop) { $btnStop.IsEnabled = $Deploying }
}

function Update-DeploymentProgress {
    param(
        [System.Windows.Window]$Window,
        [string]$Text,
        [int]$Percent
    )

    $messageBox = $Window.FindName('TxtDeploymentMessage')
    $progressBar = $Window.FindName('DeploymentProgressBar')

    if ($messageBox) { $messageBox.Text = $Text }
    if ($progressBar) { $progressBar.Value = $Percent }
}

function Invoke-CancelDeploymentJob {
    param([System.Windows.Window]$Window)

    if (-not $script:SelectedDeploymentJobId) {
        [System.Windows.MessageBox]::Show('Please select a deployment job to cancel.', 'No Selection', 'OK', 'Information')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        'Cancel this deployment job?',
        'Confirm Cancel',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne 'Yes') { return }

    try {
        $result = Stop-Deployment -JobId $script:SelectedDeploymentJobId

        if ($result.Success) {
            Update-DeploymentJobsDataGrid -Window $Window
            [System.Windows.MessageBox]::Show('Deployment cancelled.', 'Cancelled', 'OK', 'Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Failed: $($result.Error)", 'Error', 'OK', 'Error')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

function Show-DeploymentLog {
    param([System.Windows.Window]$Window)

    try {
        $result = Get-DeploymentHistory -Limit 50

        if (-not $result.Success -or -not $result.Data -or $result.Data.Count -eq 0) {
            [System.Windows.MessageBox]::Show('No deployment history available.', 'No History', 'OK', 'Information')
            return
        }

        $log = $result.Data | ForEach-Object {
            "$($_.Timestamp) | $($_.Action) | $($_.Details) | $($_.User)"
        }

        $logText = "DEPLOYMENT HISTORY (Last 50 entries)`n" + ('=' * 50) + "`n`n"
        $logText += ($log -join "`n")

        [System.Windows.MessageBox]::Show($logText, 'Deployment Log', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
    }
}

#endregion

#region ===== SETUP PANEL HANDLERS =====

#endregion
