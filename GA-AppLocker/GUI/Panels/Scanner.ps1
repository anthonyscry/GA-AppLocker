#region Scanner Panel Functions
# Scanner.ps1 - Scanner panel handlers
function Initialize-ScannerPanel {
    param([System.Windows.Window]$Window)

    # Initialize scan paths from config or defaults
    $txtPaths = $Window.FindName('TxtScanPaths')
    if ($txtPaths) {
        $paths = $null
        try {
            $config = Get-AppLockerConfig
            if ($config.DefaultScanPaths) {
                $paths = $config.DefaultScanPaths
            }
        }
        catch { }
        
        # Use clean default paths (ProgramData included)
        $paths = @(
            'C:\Program Files',
            'C:\Program Files (x86)',
            'C:\ProgramData',
            'C:\Windows\System32',
            'C:\Windows\SysWOW64'
        )
        $txtPaths.Text = $paths -join "`n"
    }

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

    # High risk paths checkbox handler - add/remove paths from textbox
    $chkHighRisk = $Window.FindName('ChkIncludeHighRisk')
    if ($chkHighRisk) {
        $chkHighRisk.Add_Checked({
            $txtPaths = $global:GA_MainWindow.FindName('TxtScanPaths')
            if ($txtPaths) {
                $highRiskPaths = @(
                    "# --- HIGH RISK PATHS ---",
                    [Environment]::GetFolderPath('UserProfile') + '\Downloads',
                    [Environment]::GetFolderPath('Desktop'),
                    $env:TEMP
                ) -join "`n"
                $txtPaths.Text = $txtPaths.Text.TrimEnd() + "`n" + $highRiskPaths
            }
        })
        $chkHighRisk.Add_Unchecked({
            $txtPaths = $global:GA_MainWindow.FindName('TxtScanPaths')
            if ($txtPaths) {
                # Remove high risk section
                $lines = $txtPaths.Text -split "`n" | Where-Object { 
                    $_ -notmatch "HIGH RISK PATHS" -and 
                    $_ -notmatch "\\Downloads$" -and 
                    $_ -notmatch "\\Desktop$" -and
                    $_ -notmatch "\\Temp$" -and
                    $_ -notmatch "\\Local\\Temp$"
                }
                $txtPaths.Text = ($lines -join "`n").TrimEnd()
            }
        })
    }

    $btnResetPaths = $Window.FindName('BtnResetPaths')
    if ($btnResetPaths) {
        $btnResetPaths.Add_Click({ 
                $txtPaths = $global:GA_MainWindow.FindName('TxtScanPaths')
                $chkHighRisk = $global:GA_MainWindow.FindName('ChkIncludeHighRisk')
                if ($chkHighRisk) { $chkHighRisk.IsChecked = $false }
                if ($txtPaths) { 
                    $defaultPaths = @(
                        'C:\Program Files',
                        'C:\Program Files (x86)',
                        'C:\ProgramData',
                        'C:\Windows\System32',
                        'C:\Windows\SysWOW64'
                    ) -join "`n"
                    $txtPaths.Text = $defaultPaths
                }
            }) 
    }

    # Wire up saved scans buttons
    $btnRefreshScans = $Window.FindName('BtnRefreshScans')
    if ($btnRefreshScans) { $btnRefreshScans.Add_Click({ Invoke-ButtonAction -Action 'RefreshScans' }) }

    $btnLoadScan = $Window.FindName('BtnLoadScan')
    if ($btnLoadScan) { $btnLoadScan.Add_Click({ Invoke-ButtonAction -Action 'LoadScan' }) }

    $btnDeleteScan = $Window.FindName('BtnDeleteScan')
    if ($btnDeleteScan) { $btnDeleteScan.Add_Click({ Invoke-ButtonAction -Action 'DeleteScan' }) }

    # Wire up wizard launch button (Generate tab - replaces old dedupe/exclusion controls)
    $btnWizard = $Window.FindName('BtnLaunchRuleWizardFromScanner')
    if ($btnWizard) { $btnWizard.Add_Click({ Invoke-ButtonAction -Action 'LaunchRuleWizard' }) }

    # Wire up filter buttons
    $filterButtons = @{
        'BtnFilterAllArtifacts' = 'All'
        'BtnFilterExe'          = 'EXE'
        'BtnFilterDll'          = 'DLL'
        'BtnFilterMsi'          = 'MSI'
        'BtnFilterScript'       = 'Script'
        'BtnFilterAppx'         = 'Appx'
        'BtnFilterSigned'       = 'Signed'
        'BtnFilterUnsigned'     = 'Unsigned'
    }

    foreach ($btnName in $filterButtons.Keys) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $filterValue = $filterButtons[$btnName]
            # Store filter value in button's Tag for reliable retrieval
            $btn.Tag = $filterValue
            $btn.Add_Click({ 
                    param($sender, $e)
                    $filter = $sender.Tag
                    if ($global:GA_MainWindow) {
                        Update-ArtifactFilter -Window $global:GA_MainWindow -Filter $filter
                    }
                })
        }
    }

    # Wire up text filter with debounce for better performance
    $filterBox = $Window.FindName('ArtifactFilterBox')
    if ($filterBox) {
        # Create debounce timer (300ms delay)
        $script:ArtifactFilterTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:ArtifactFilterTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:ArtifactFilterTimer.Add_Tick({
            $script:ArtifactFilterTimer.Stop()
            if ($global:GA_MainWindow) {
                Update-ArtifactDataGrid -Window $global:GA_MainWindow
            }
        })
        
        $filterBox.Add_TextChanged({
            # Reset and restart timer on each keystroke
            $script:ArtifactFilterTimer.Stop()
            $script:ArtifactFilterTimer.Start()
        })
    }

    # Wire up Generate Rules from Artifacts button (launches wizard)
    # Note: Dedupe/exclusion UI moved to wizard - functions kept for programmatic use
    $btnGenerateFromArtifacts = $Window.FindName('BtnGenerateFromArtifacts')
    if ($btnGenerateFromArtifacts) {
        $btnGenerateFromArtifacts.Add_Click({
            Invoke-LaunchRuleWizard -Window $global:GA_MainWindow
        })
    }

    # Wire up Select All / Deselect All buttons for ArtifactDataGrid
    $btnSelectAll = $Window.FindName('BtnSelectAllArtifacts')
    if ($btnSelectAll) {
        $btnSelectAll.Add_Click({
            Invoke-SelectAllArtifacts -Window $global:GA_MainWindow -SelectAll $true
        })
    }
    
    $btnDeselectAll = $Window.FindName('BtnDeselectAllArtifacts')
    if ($btnDeselectAll) {
        $btnDeselectAll.Add_Click({
            Invoke-SelectAllArtifacts -Window $global:GA_MainWindow -SelectAll $false
        })
    }
    
    # Wire up DataGrid selection changed for count update
    $artifactGrid = $Window.FindName('ArtifactDataGrid')
    if ($artifactGrid) {
        $artifactGrid.Add_SelectionChanged({
            Update-ArtifactSelectionCount -Window $global:GA_MainWindow
        })
    }

    # Load saved scans list
    try {
        Update-SavedScansList -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load saved scans: $($_.Exception.Message)"
    }
    
    # Wire up scheduled scan buttons
    $btnCreateSchedule = $Window.FindName('BtnCreateSchedule')
    if ($btnCreateSchedule) { $btnCreateSchedule.Add_Click({ Invoke-ButtonAction -Action 'CreateScheduledScan' }) }
    
    $btnRunScheduleNow = $Window.FindName('BtnRunScheduleNow')
    if ($btnRunScheduleNow) { $btnRunScheduleNow.Add_Click({ Invoke-ButtonAction -Action 'RunScheduledScanNow' }) }
    
    $btnDeleteSchedule = $Window.FindName('BtnDeleteSchedule')
    if ($btnDeleteSchedule) { $btnDeleteSchedule.Add_Click({ Invoke-ButtonAction -Action 'DeleteScheduledScan' }) }
    
    # Load scheduled scans list
    try {
        Initialize-ScheduledScansList -Window $Window
    }
    catch {
        Write-Log -Level Error -Message "Failed to load scheduled scans: $($_.Exception.Message)"
    }
}

function global:Invoke-StartArtifactScan {
    param([System.Windows.Window]$Window)

    if ($script:ScanInProgress) {
        [System.Windows.MessageBox]::Show('A scan is already in progress.', 'Scan Active', 'OK', 'Warning')
        return
    }

    # Get scan configuration
    $scanLocal = $Window.FindName('ChkScanLocal').IsChecked
    $scanRemote = $Window.FindName('ChkScanRemote').IsChecked
    $includeEvents = $Window.FindName('ChkIncludeEventLogs').IsChecked
    $includeHighRisk = $Window.FindName('ChkIncludeHighRisk').IsChecked
    $skipDllScanning = $Window.FindName('ChkSkipDllScanning').IsChecked
    $includeAppx = $Window.FindName('ChkIncludeAppx').IsChecked
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

    # Add high risk paths if checkbox is checked
    if ($includeHighRisk) {
        $highRiskPaths = @(
            [Environment]::GetFolderPath('UserProfile') + '\Downloads',
            [Environment]::GetFolderPath('Desktop'),
            $env:TEMP,
            $env:LOCALAPPDATA + '\Temp'
        ) | Where-Object { Test-Path $_ }
        
        $paths = @($paths) + $highRiskPaths | Select-Object -Unique
        Write-Log -Message "Including high risk paths: $($highRiskPaths -join ', ')"
    }

    # Update UI state
    $script:ScanInProgress = $true
    $script:ScanCancelled = $false
    Update-ScanUIState -Window $Window -Scanning $true
    Update-ScanProgress -Window $Window -Text "Starting scan: $scanName" -Percent 5

    # Build scan parameters
    $scanParams = @{
        SaveResults = $saveResults
        ScanName    = $scanName
    }

    if ($scanLocal) { $scanParams.ScanLocal = $true }
    if ($includeEvents) { $scanParams.IncludeEventLogs = $true }
    if ($skipDllScanning) { $scanParams.SkipDllScanning = $true }
    if ($includeAppx) { $scanParams.IncludeAppx = $true }
    if ($paths.Count -gt 0) { $scanParams.Paths = $paths }
    if ($scanRemote -and $script:SelectedScanMachines.Count -gt 0) {
        $scanParams.Machines = $script:SelectedScanMachines
    }

    # Create a synchronized hashtable for cross-thread communication
    $script:ScanSyncHash = [hashtable]::Synchronized(@{
            Window     = $Window
            Params     = $scanParams
            Result     = $null
            Error      = $null
            IsComplete = $false
            Progress   = 10
            StatusText = "Initializing scan..."
        })

    # Create and start the background runspace
    $script:ScanRunspace = [runspacefactory]::CreateRunspace()
    $script:ScanRunspace.ApartmentState = 'STA'
    $script:ScanRunspace.ThreadOptions = 'ReuseThread'
    $script:ScanRunspace.Open()
    $script:ScanRunspace.SessionStateProxy.SetVariable('SyncHash', $script:ScanSyncHash)

    # Import module path for the runspace
    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:ScanRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:ScanPowerShell = [powershell]::Create()
    $script:ScanPowerShell.Runspace = $script:ScanRunspace
    
    [void]$script:ScanPowerShell.AddScript({
            param($SyncHash, $ModulePath)
        
            try {
                # Import the module in this runspace
                $SyncHash.StatusText = "Loading modules..."
                $SyncHash.Progress = 15
            
                $manifestPath = Join-Path $ModulePath "GA-AppLocker.psd1"
                if (Test-Path $manifestPath) {
                    Import-Module $manifestPath -Force -ErrorAction Stop
                }
                else {
                    throw "Module not found at: $manifestPath"
                }
            
                $SyncHash.StatusText = "Scanning files..."
                $SyncHash.Progress = 25
            
                # Execute the scan - clone params and add SyncHash for progress reporting
                $scanParams = @{}
                foreach ($key in $SyncHash.Params.Keys) {
                    $scanParams[$key] = $SyncHash.Params[$key]
                }
                $scanParams.SyncHash = $SyncHash
                $result = Start-ArtifactScan @scanParams
            
                $SyncHash.Progress = 90
                $SyncHash.StatusText = "Processing results..."
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
    
    [void]$script:ScanPowerShell.AddArgument($script:ScanSyncHash)
    [void]$script:ScanPowerShell.AddArgument($modulePath)

    # Start async execution
    $script:ScanAsyncResult = $script:ScanPowerShell.BeginInvoke()

    # Create a DispatcherTimer to poll for completion and update UI
    $script:ScanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ScanTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    
    $script:ScanTimer.Add_Tick({
            $syncHash = $script:ScanSyncHash
            $win = $syncHash.Window
        
            # Update progress
            Update-ScanProgress -Window $win -Text $syncHash.StatusText -Percent $syncHash.Progress
        
            # Check if cancelled
            if ($script:ScanCancelled) {
                $script:ScanTimer.Stop()
            
                # Clean up runspace
                if ($script:ScanPowerShell) {
                    $script:ScanPowerShell.Stop()
                    $script:ScanPowerShell.Dispose()
                }
                if ($script:ScanRunspace) {
                    $script:ScanRunspace.Close()
                    $script:ScanRunspace.Dispose()
                }
            
                $script:ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
                Update-ScanProgress -Window $win -Text "Scan cancelled" -Percent 0
                $win.FindName('ScanStatusLabel').Text = "Cancelled"
                $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::Orange
                return
            }
        
            # Check if complete
            if ($syncHash.IsComplete) {
                $script:ScanTimer.Stop()
            
                # End the async operation
                try {
                    $script:ScanPowerShell.EndInvoke($script:ScanAsyncResult)
                }
                catch { }
            
                # Clean up runspace
                if ($script:ScanPowerShell) { $script:ScanPowerShell.Dispose() }
                if ($script:ScanRunspace) { 
                    $script:ScanRunspace.Close()
                    $script:ScanRunspace.Dispose() 
                }
            
                $script:ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
            
                if ($syncHash.Error) {
                    Update-ScanProgress -Window $win -Text "Error: $($syncHash.Error)" -Percent 0
                    $win.FindName('ScanStatusLabel').Text = "Error"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    [System.Windows.MessageBox]::Show("Scan error: $($syncHash.Error)", 'Error', 'OK', 'Error')
                }
                elseif ($syncHash.Result -and $syncHash.Result.Success) {
                    $result = $syncHash.Result
                    $script:CurrentScanArtifacts = $result.Data.Artifacts
                    Update-ArtifactDataGrid -Window $win
                    Update-ScanProgress -Window $win -Text "Scan complete: $($result.Summary.TotalArtifacts) artifacts" -Percent 100

                    # Update counters
                    $win.FindName('ScanArtifactCount').Text = "$($result.Summary.TotalArtifacts) artifacts"
                    $preGen = $win.FindName('TxtArtifactCountPreGen')
                    if ($preGen) { $preGen.Text = "$($result.Summary.TotalArtifacts)" }
                    $win.FindName('ScanSignedCount').Text = "$($result.Summary.SignedArtifacts)"
                    $win.FindName('ScanUnsignedCount').Text = "$($result.Summary.UnsignedArtifacts)"
                    $win.FindName('ScanStatusLabel').Text = "Complete"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

                    # Refresh saved scans list
                    Update-SavedScansList -Window $win
                    
                    # Update workflow breadcrumb
                    Update-WorkflowBreadcrumb -Window $win

                    Show-Toast -Message "Scan complete: $($result.Summary.TotalArtifacts) artifacts found ($($result.Summary.SignedArtifacts) signed)." -Type 'Success'
                }
                else {
                    $errorMsg = if ($syncHash.Result) { $syncHash.Result.Error } else { "Unknown error" }
                    Update-ScanProgress -Window $win -Text "Scan failed: $errorMsg" -Percent 0
                    $win.FindName('ScanStatusLabel').Text = "Failed"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    [System.Windows.MessageBox]::Show("Scan failed: $errorMsg", 'Scan Error', 'OK', 'Error')
                }
            }
        })
    
    # Start the timer
    $script:ScanTimer.Start()
}

function global:Invoke-StopArtifactScan {
    param([System.Windows.Window]$Window)

    # Signal cancellation - the timer tick handler will clean up
    $script:ScanCancelled = $true
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

    # Note: DoEvents() removed - anti-pattern that causes re-entrancy issues
    # Note: Async pattern implemented via runspaces for scanning and deployment operations
}

function script:Update-ArtifactDataGrid {
    param([System.Windows.Window]$Window)

    try {
        $dataGrid = $Window.FindName('ArtifactDataGrid')
        if (-not $dataGrid) { return }

        $artifacts = $script:CurrentScanArtifacts
        if (-not $artifacts) {
            $dataGrid.ItemsSource = $null
            return
        }

        # Apply type filter first
        $typeFilter = $script:CurrentArtifactFilter
        if ($typeFilter -and $typeFilter -ne 'All') {
            $artifacts = switch ($typeFilter) {
                'EXE' { @($artifacts | Where-Object { $_.ArtifactType -eq 'EXE' }) }
                'DLL' { @($artifacts | Where-Object { $_.ArtifactType -eq 'DLL' }) }
                'MSI' { @($artifacts | Where-Object { $_.ArtifactType -eq 'MSI' }) }
                'Script' { @($artifacts | Where-Object { $_.ArtifactType -in @('PS1', 'BAT', 'CMD', 'VBS', 'JS') }) }
                'Appx' { @($artifacts | Where-Object { $_.CollectionType -eq 'Appx' }) }
                'Signed' { @($artifacts | Where-Object { $_.IsSigned }) }
                'Unsigned' { @($artifacts | Where-Object { -not $_.IsSigned }) }
                default { $artifacts }
            }
        }

        # Apply text filter
        $filterBox = $Window.FindName('ArtifactFilterBox')
        $filterText = if ($filterBox) { $filterBox.Text } else { '' }

        if (-not [string]::IsNullOrWhiteSpace($filterText)) {
            $artifacts = @($artifacts | Where-Object {
                $_.FileName -like "*$filterText*" -or
                $_.Publisher -like "*$filterText*" -or
                $_.FilePath -like "*$filterText*"
            })
        }

        # Add display properties
        $displayData = @($artifacts | ForEach-Object {
            $signedIcon = if ($_.IsSigned) { [char]0x2714 } else { [char]0x2718 }
            $_ | Add-Member -NotePropertyName 'SignedIcon' -NotePropertyValue $signedIcon -PassThru -Force
        })

        $dataGrid.ItemsSource = $displayData
        
        # Update row count display
        $totalCount = if ($script:CurrentScanArtifacts) { $script:CurrentScanArtifacts.Count } else { 0 }
        $filteredCount = $displayData.Count
        
        $txtTotal = $Window.FindName('TxtArtifactTotalCount')
        $txtFiltered = $Window.FindName('TxtArtifactFilteredCount')
        if ($txtTotal) { $txtTotal.Text = "$totalCount" }
        if ($txtFiltered) { $txtFiltered.Text = "$filteredCount" }
        
        # Update selection count
        Update-ArtifactSelectionCount -Window $Window
    }
    catch {
        if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
            Write-AppLockerLog -Message "Error updating artifact grid: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
}

function global:Update-ArtifactFilter {
    param(
        [System.Windows.Window]$Window,
        [string]$Filter
    )

    # Reset button styles
    $allButtons = @('BtnFilterAllArtifacts', 'BtnFilterExe', 'BtnFilterDll', 'BtnFilterMsi', 'BtnFilterScript', 'BtnFilterAppx', 'BtnFilterSigned', 'BtnFilterUnsigned')
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
        'Appx' { 'BtnFilterAppx' }
        'Signed' { 'BtnFilterSigned' }
        'Unsigned' { 'BtnFilterUnsigned' }
    }

    $btn = $Window.FindName($activeBtn)
    if ($btn) {
        $btn.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(62, 62, 66))
    }

    # Store filter state and refresh grid
    $script:CurrentArtifactFilter = $Filter
    Update-ArtifactDataGrid -Window $Window
}

function global:Invoke-SelectAllArtifacts {
    <#
    .SYNOPSIS
        Selects or deselects all artifacts in the ArtifactDataGrid.
    #>
    param(
        [System.Windows.Window]$Window,
        [bool]$SelectAll = $true
    )
    
    $dataGrid = $Window.FindName('ArtifactDataGrid')
    if (-not $dataGrid) { return }
    
    if ($SelectAll) {
        $dataGrid.SelectAll()
    }
    else {
        $dataGrid.UnselectAll()
    }
    
    Update-ArtifactSelectionCount -Window $Window
}

function global:Update-ArtifactSelectionCount {
    <#
    .SYNOPSIS
        Updates the selected artifact count display.
    #>
    param([System.Windows.Window]$Window)
    
    $dataGrid = $Window.FindName('ArtifactDataGrid')
    $countText = $Window.FindName('TxtSelectedArtifactCount')
    
    if (-not $dataGrid -or -not $countText) { return }
    
    $selectedCount = $dataGrid.SelectedItems.Count
    $countText.Text = "$selectedCount"
}

function global:Update-SavedScansList {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox) { return }

    if (-not (Get-Command -Name 'Get-ScanResults' -ErrorAction SilentlyContinue)) {
        return
    }

    $result = Get-ScanResults
    if ($result.Success -and $result.Data) {
        # Wrap in array to ensure WPF binding works with single item
        $listBox.ItemsSource = @($result.Data)
    }
    else {
        $listBox.ItemsSource = $null
    }
}

function global:Invoke-LoadSelectedScan {
    param([System.Windows.Window]$Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a saved scan to load.', 'No Selection', 'OK', 'Information')
        return
    }

    # Check if we should merge with existing artifacts
    $mergeMode = $false
    if ($script:CurrentScanArtifacts -and $script:CurrentScanArtifacts.Count -gt 0) {
        $response = [System.Windows.MessageBox]::Show(
            "You have $($script:CurrentScanArtifacts.Count) artifacts loaded.`n`nYes = Merge (add to existing)`nNo = Replace (clear existing)",
            'Merge or Replace?',
            'YesNoCancel',
            'Question'
        )
        if ($response -eq 'Cancel') { return }
        $mergeMode = ($response -eq 'Yes')
    }

    $selectedScan = $listBox.SelectedItem
    $result = Get-ScanResults -ScanId $selectedScan.ScanId

    if ($result.Success) {
        if ($mergeMode) {
            # Merge: add new artifacts, avoiding duplicates by hash (O(n+m) with HashSet)
            $existingHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($a in $script:CurrentScanArtifacts) {
                if ($a.SHA256Hash) { [void]$existingHashes.Add($a.SHA256Hash) }
            }
            $newArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($a in $result.Data.Artifacts) {
                if ($a.SHA256Hash -and -not $existingHashes.Contains($a.SHA256Hash)) {
                    $newArtifacts.Add($a)
                }
            }
            $script:CurrentScanArtifacts = @($script:CurrentScanArtifacts) + $newArtifacts.ToArray()
            $statusText = "Merged (+$($newArtifacts.Count) new)"
        }
        else {
            $script:CurrentScanArtifacts = $result.Data.Artifacts
            $statusText = "Loaded"
        }
        
        Update-ArtifactDataGrid -Window $Window

        # Update counters
        $signed = ($script:CurrentScanArtifacts | Where-Object { $_.IsSigned }).Count
        $unsigned = $script:CurrentScanArtifacts.Count - $signed
        $Window.FindName('ScanArtifactCount').Text = "$($script:CurrentScanArtifacts.Count) artifacts"
        $preGen = $Window.FindName('TxtArtifactCountPreGen')
        if ($preGen) { $preGen.Text = "$($script:CurrentScanArtifacts.Count)" }
        $Window.FindName('ScanSignedCount').Text = "$signed"
        $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
        $Window.FindName('ScanStatusLabel').Text = $statusText
        $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightBlue

        Update-ScanProgress -Window $Window -Text "$statusText`: $($selectedScan.ScanName)" -Percent 100
    }
    else {
        [System.Windows.MessageBox]::Show("Failed to load scan: $($result.Error)", 'Error', 'OK', 'Error')
    }
}

function global:Invoke-DeleteSelectedScan {
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

function global:Invoke-ImportArtifacts {
    param([System.Windows.Window]$Window)

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Import Artifacts (select multiple files with Ctrl+Click)'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json|All Files (*.*)|*.*'
    $dialog.FilterIndex = 1
    $dialog.Multiselect = $true

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            # Check if we should merge with existing artifacts
            $mergeMode = $false
            if ($script:CurrentScanArtifacts -and $script:CurrentScanArtifacts.Count -gt 0) {
                $response = [System.Windows.MessageBox]::Show(
                    "You have $($script:CurrentScanArtifacts.Count) artifacts loaded.`n`nYes = Merge (add to existing)`nNo = Replace (clear existing)",
                    'Merge or Replace?',
                    'YesNoCancel',
                    'Question'
                )
                if ($response -eq 'Cancel') { return }
                $mergeMode = ($response -eq 'Yes')
            }

            $allArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
            $fileCount = 0
            
            foreach ($filePath in $dialog.FileNames) {
                $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
                
                $artifacts = switch ($extension) {
                    '.csv' { @(Import-Csv -Path $filePath) }
                    '.json' { @(Get-Content -Path $filePath -Raw | ConvertFrom-Json) }
                    default { throw "Unsupported file format: $extension" }
                }
                
                foreach ($a in $artifacts) { $allArtifacts.Add($a) }
                $fileCount++
            }

            if ($mergeMode) {
                # Merge: add new artifacts, avoiding duplicates by hash (O(n+m) with HashSet)
                $existingHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($a in $script:CurrentScanArtifacts) {
                    if ($a.SHA256Hash) { [void]$existingHashes.Add($a.SHA256Hash) }
                }
                $newArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($a in $allArtifacts) {
                    if ($a.SHA256Hash -and -not $existingHashes.Contains($a.SHA256Hash)) {
                        $newArtifacts.Add($a)
                    }
                }
                $script:CurrentScanArtifacts = @($script:CurrentScanArtifacts) + $newArtifacts.ToArray()
                $statusText = "Merged (+$($newArtifacts.Count) new)"
                $messageText = "Merged $($newArtifacts.Count) new artifacts from $fileCount file(s).`nTotal: $($script:CurrentScanArtifacts.Count) artifacts"
            }
            else {
                $script:CurrentScanArtifacts = $allArtifacts
                $statusText = "Imported"
                $messageText = "Imported $($allArtifacts.Count) artifacts from $fileCount file(s)."
            }
            
            Update-ArtifactDataGrid -Window $Window

            # Update counters
            $signed = ($script:CurrentScanArtifacts | Where-Object { $_.IsSigned }).Count
            $unsigned = $script:CurrentScanArtifacts.Count - $signed
            $Window.FindName('ScanArtifactCount').Text = "$($script:CurrentScanArtifacts.Count) artifacts"
            $preGen = $Window.FindName('TxtArtifactCountPreGen')
            if ($preGen) { $preGen.Text = "$($script:CurrentScanArtifacts.Count)" }
            $Window.FindName('ScanSignedCount').Text = "$signed"
            $Window.FindName('ScanUnsignedCount').Text = "$unsigned"
            $Window.FindName('ScanStatusLabel').Text = $statusText
            $Window.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::LightGreen

            [System.Windows.MessageBox]::Show($messageText, 'Import Complete', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show("Import failed: $($_.Exception.Message)", 'Error', 'OK', 'Error')
        }
    }
}

function global:Invoke-ExportArtifacts {
    param([System.Windows.Window]$Window)

    # Get artifacts from DataGrid (respects current filters)
    $dataGrid = $Window.FindName('ArtifactDataGrid')
    $artifacts = if ($dataGrid -and $dataGrid.ItemsSource) {
        @($dataGrid.ItemsSource)
    } else {
        @()
    }
    
    if ($artifacts.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No artifacts to export. Run a scan or adjust filters.', 'No Data', 'OK', 'Information')
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Artifacts (Current Filtered View)'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json'
    $dialog.FilterIndex = 1
    $dialog.FileName = "Artifacts_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            
            # Remove display-only properties for cleaner export
            $exportData = $artifacts | Select-Object FileName, FilePath, ArtifactType, Publisher, 
                ProductName, FileVersion, IsSigned, SHA256Hash, FileSize, ComputerName
            
            switch ($extension) {
                '.csv' { $exportData | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8 }
                '.json' { $exportData | ConvertTo-Json -Depth 5 | Set-Content -Path $dialog.FileName -Encoding UTF8 }
            }

            $totalCount = if ($script:CurrentScanArtifacts) { $script:CurrentScanArtifacts.Count } else { 0 }
            $filterInfo = if ($artifacts.Count -lt $totalCount) { " (filtered from $totalCount total)" } else { "" }
            
            [System.Windows.MessageBox]::Show(
                "Exported $($artifacts.Count) artifacts$filterInfo to:`n$($dialog.FileName)",
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

# Note: Show-MachineSelectionDialog is now in GUI/Dialogs/ScannerDialogs.ps1

function global:Invoke-SelectMachinesForScan {
    param([System.Windows.Window]$Window)

    if ($script:DiscoveredMachines.Count -eq 0) {
        $confirm = [System.Windows.MessageBox]::Show(
            "No machines discovered. Would you like to navigate to AD Discovery to scan for machines?",
            'No Machines', 'YesNo', 'Question')
        if ($confirm -eq 'Yes') { Set-ActivePanel -PanelName 'PanelDiscovery' }
        return
    }

    $selectedMachines = Show-MachineSelectionDialog -ParentWindow $Window -Machines $script:DiscoveredMachines
    
    if ($null -eq $selectedMachines -or $selectedMachines.Count -eq 0) { return }
    
    $script:SelectedScanMachines = $selectedMachines

    $machineList = $Window.FindName('ScanMachineList')
    $machineCount = $Window.FindName('ScanMachineCount')

    if ($machineList) { $machineList.ItemsSource = $script:SelectedScanMachines | Select-Object -ExpandProperty Hostname }
    if ($machineCount) { $machineCount.Text = "$($script:SelectedScanMachines.Count)" }

    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) { $chkRemote.IsChecked = $true }

    Show-Toast -Message "Selected $($script:SelectedScanMachines.Count) machines for scanning" -Type 'Success'
}

# Deduplicates scan artifacts by selected mode (Smart, Publisher, PublisherProduct, Hash)
# Programmatic use only - UI moved to Rule Generation Wizard
# Kept for backward compatibility and scripting scenarios
function global:Invoke-DedupeArtifacts {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message 'No artifacts loaded. Run a scan first.' -Type 'Warning'
        return
    }

    # Get dedupe mode from dropdown
    $dedupeMode = 'Hash'
    $cboMode = $Window.FindName('CboDedupeMode')
    if ($cboMode -and $cboMode.SelectedItem) {
        $dedupeMode = $cboMode.SelectedItem.Tag
    }

    $originalCount = $script:CurrentScanArtifacts.Count

    # Build hash set for O(n) deduplication
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueArtifacts = [System.Collections.Generic.List[object]]::new()

    foreach ($artifact in $script:CurrentScanArtifacts) {
        $key = switch ($dedupeMode) {
            'Smart' {
                # Smart: Publisher+Product for signed, Hash for unsigned (matches Smart rule generation)
                if ($artifact.IsSigned -and $artifact.Publisher) {
                    $product = if ($artifact.ProductName) { $artifact.ProductName } else { 'Unknown' }
                    "PUB|$($artifact.Publisher)|$product"
                } else {
                    # Unsigned: use hash
                    if ($artifact.SHA256Hash) { $artifact.SHA256Hash } 
                    else { "$($artifact.FilePath)|$($artifact.FileSize)" }
                }
            }
            'Publisher' {
                # Dedupe by publisher name only (one artifact per vendor)
                if ($artifact.Publisher) {
                    "PUB|$($artifact.Publisher)"
                } else {
                    # No publisher: fall back to hash
                    if ($artifact.SHA256Hash) { $artifact.SHA256Hash } 
                    else { "$($artifact.FilePath)|$($artifact.FileSize)" }
                }
            }
            'PublisherProduct' {
                # Dedupe by publisher + product (one artifact per product)
                if ($artifact.Publisher) {
                    $product = if ($artifact.ProductName) { $artifact.ProductName } else { 'Unknown' }
                    "PUB|$($artifact.Publisher)|$product"
                } else {
                    # No publisher: fall back to hash
                    if ($artifact.SHA256Hash) { $artifact.SHA256Hash } 
                    else { "$($artifact.FilePath)|$($artifact.FileSize)" }
                }
            }
            default {
                # Hash mode: exact file match
                if ($artifact.SHA256Hash) { $artifact.SHA256Hash } 
                else { "$($artifact.FilePath)|$($artifact.FileSize)" }
            }
        }
        
        if ($seen.Add($key)) {
            $uniqueArtifacts.Add($artifact)
        }
    }

    $removed = $originalCount - $uniqueArtifacts.Count
    $script:CurrentScanArtifacts = $uniqueArtifacts

    # Update displays
    Update-ArtifactDataGrid -Window $Window
    
    $artifactCount = $Window.FindName('ScanArtifactCount')
    if ($artifactCount) { $artifactCount.Text = "$($uniqueArtifacts.Count) artifacts" }
    
    $preGenCount = $Window.FindName('TxtArtifactCountPreGen')
    if ($preGenCount) { $preGenCount.Text = "$($uniqueArtifacts.Count)" }

    $modeText = switch ($dedupeMode) { 'Smart' { 'smart' }; 'Publisher' { 'publisher' }; 'PublisherProduct' { 'publisher+product' }; default { 'hash' } }
    if ($removed -gt 0) {
        Show-Toast -Message "Removed $removed duplicates (by $modeText). $($uniqueArtifacts.Count) unique remaining." -Type 'Success'
        Write-Log -Message "Deduplicated artifacts by $modeText`: $originalCount -> $($uniqueArtifacts.Count) ($removed removed)"
    } else {
        Show-Toast -Message "No duplicates found by $modeText. All $($uniqueArtifacts.Count) artifacts unique." -Type 'Info'
    }
}

# Applies exclusion filters to scan artifacts based on checkbox selections
# Programmatic use only - UI moved to Rule Generation Wizard
# Kept for backward compatibility and scripting scenarios
function global:Invoke-ApplyArtifactExclusions {
    param([System.Windows.Window]$Window)

    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message 'No artifacts loaded. Run a scan first.' -Type 'Warning'
        return
    }

    # Get exclusion checkboxes
    $excludeDll = $Window.FindName('ChkExcludeDll').IsChecked
    $excludeJs = $Window.FindName('ChkExcludeJs').IsChecked
    $excludeScripts = $Window.FindName('ChkExcludeScripts').IsChecked
    $excludeUnsigned = $Window.FindName('ChkExcludeUnsigned').IsChecked

    if (-not $excludeDll -and -not $excludeJs -and -not $excludeScripts -and -not $excludeUnsigned) {
        Show-Toast -Message 'No exclusions selected.' -Type 'Info'
        return
    }

    $originalCount = $script:CurrentScanArtifacts.Count
    $excluded = @()

    # Build list of extensions to exclude
    $excludeExtensions = @()
    if ($excludeDll) { $excludeExtensions += '.dll' }
    if ($excludeJs) { $excludeExtensions += '.js' }
    if ($excludeScripts) { $excludeExtensions += @('.ps1', '.bat', '.cmd', '.vbs', '.wsf') }

    # Filter artifacts
    $filtered = $script:CurrentScanArtifacts | Where-Object {
        $dominated = $false
        
        # Check extension exclusions
        if ($excludeExtensions.Count -gt 0) {
            $ext = $_.Extension
            if (-not $ext -and $_.FileName) { $ext = [System.IO.Path]::GetExtension($_.FileName) }
            if ($ext -and $excludeExtensions -contains $ext.ToLower()) { $dominated = $true }
        }
        
        # Check unsigned exclusion
        if (-not $dominated -and $excludeUnsigned -and -not $_.IsSigned) { $dominated = $true }
        
        -not $dominated
    }

    $script:CurrentScanArtifacts = @($filtered)
    $removedCount = $originalCount - $script:CurrentScanArtifacts.Count

    # Update displays
    Update-ArtifactDataGrid -Window $Window
    
    $artifactCount = $Window.FindName('ScanArtifactCount')
    if ($artifactCount) { $artifactCount.Text = "$($script:CurrentScanArtifacts.Count) artifacts" }
    
    $preGenCount = $Window.FindName('TxtArtifactCountPreGen')
    if ($preGenCount) { $preGenCount.Text = "$($script:CurrentScanArtifacts.Count)" }

    # Build exclusion description
    $excludeDesc = @()
    if ($excludeDll) { $excludeDesc += 'DLLs' }
    if ($excludeJs) { $excludeDesc += 'JS' }
    if ($excludeScripts) { $excludeDesc += 'Scripts' }
    if ($excludeUnsigned) { $excludeDesc += 'Unsigned' }

    Show-Toast -Message "Excluded $removedCount artifacts ($($excludeDesc -join ', ')). $($script:CurrentScanArtifacts.Count) remaining." -Type 'Success'
    Write-Log -Message "Applied exclusions ($($excludeDesc -join ', ')): $originalCount -> $($script:CurrentScanArtifacts.Count) ($removedCount removed)"
}

#endregion

#region ===== SCHEDULED SCANS =====
function global:Initialize-ScheduledScansList {
    <#
    .SYNOPSIS
        Loads scheduled scans into the ScheduledScansList ListBox.
    #>
    param([System.Windows.Window]$Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox) { return }
    
    if (-not (Get-Command -Name 'Get-ScheduledScans' -ErrorAction SilentlyContinue)) {
        return
    }
    
    try {
        $result = Get-ScheduledScans
        if ($result.Success -and $result.Data -and $result.Data.Count -gt 0) {
            # Format for display - matches XAML DataTemplate bindings: Name, Schedule, Time
            # Backend returns: Id, Name, Schedule, Time, Enabled, NextRunAt
            $displayItems = @($result.Data | ForEach-Object {
                $status = if ($_.Enabled) { '' } else { '[OFF] ' }
                [PSCustomObject]@{
                    Name = "$status$($_.Name)"
                    Schedule = $_.Schedule
                    Time = $_.Time
                    ScheduleId = $_.Id           # Backend uses 'Id' not 'ScheduleId'
                    Enabled = $_.Enabled
                }
            })
            $listBox.ItemsSource = $displayItems
        }
        else {
            $listBox.ItemsSource = $null
        }
    }
    catch {
        Write-Log -Level Error -Message "Failed to load scheduled scans: $($_.Exception.Message)"
        $listBox.ItemsSource = $null
    }
}

function global:Invoke-CreateScheduledScan {
    <#
    .SYNOPSIS
        Creates a new scheduled scan from UI values.
    #>
    param([System.Windows.Window]$Window)
    
    if (-not (Get-Command -Name 'New-ScheduledScan' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Scheduled scan functions not available.' -Type 'Error'
        return
    }
    
    # Get UI values
    $txtName = $Window.FindName('TxtScheduleName')
    $cboType = $Window.FindName('CboScheduleType')
    $txtTime = $Window.FindName('TxtScheduleTime')
    $chkEnabled = $Window.FindName('ChkScheduleEnabled')
    $txtPaths = $Window.FindName('TxtScanPaths')
    
    # Validate inputs
    $scheduleName = if ($txtName) { $txtName.Text.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($scheduleName)) {
        $scheduleName = "Schedule_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if ($txtName) { $txtName.Text = $scheduleName }
    }
    
    $scheduleType = 'Daily'
    if ($cboType -and $cboType.SelectedItem) {
        $selectedItem = $cboType.SelectedItem
        if ($selectedItem -is [System.Windows.Controls.ComboBoxItem]) {
            $scheduleType = $selectedItem.Content.ToString()
        }
        elseif ($selectedItem.Content) {
            $scheduleType = $selectedItem.Content.ToString()
        }
        else {
            $scheduleType = $selectedItem.ToString()
        }
    }
    
    $scheduleTime = if ($txtTime) { $txtTime.Text.Trim() } else { '02:00' }
    if ([string]::IsNullOrWhiteSpace($scheduleTime)) {
        $scheduleTime = '02:00'
    }
    
    # Validate time format (HH:mm)
    if ($scheduleTime -notmatch '^\d{1,2}:\d{2}$') {
        Show-Toast -Message "Invalid time format. Use HH:mm (e.g., 02:00 or 14:30)" -Type 'Warning'
        return
    }
    
    $enabled = if ($chkEnabled) { $chkEnabled.IsChecked } else { $true }
    
    # Get scan paths
    $paths = @()
    if ($txtPaths -and -not [string]::IsNullOrWhiteSpace($txtPaths.Text)) {
        $paths = $txtPaths.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' }
    }
    
    if ($paths.Count -eq 0) {
        $paths = @(
            'C:\Program Files',
            'C:\Program Files (x86)',
            'C:\ProgramData'
        )
    }
    
    # Get other scan options
    $skipDll = $Window.FindName('ChkSkipDllScanning')
    $includeEvents = $Window.FindName('ChkIncludeEventLogs')
    
    try {
        Show-LoadingOverlay -Message "Creating scheduled scan..."
        
        # Note: Parameter names match backend New-ScheduledScan function
        $params = @{
            Name = $scheduleName
            Schedule = $scheduleType       # Backend expects 'Schedule' not 'ScheduleType'
            Time = $scheduleTime           # Backend expects 'Time' not 'ScheduleTime'
            ScanPaths = $paths             # Backend expects 'ScanPaths' not 'Paths'
        }
        
        if ($enabled) {
            $params.Enabled = $true
        }
        
        if ($skipDll -and $skipDll.IsChecked) {
            $params.SkipDllScanning = $true
        }
        
        $result = New-ScheduledScan @params
        
        Hide-LoadingOverlay
        
        if ($result.Success) {
            Show-Toast -Message "Scheduled scan '$scheduleName' created successfully." -Type 'Success'
            
            # Clear name field for next entry
            if ($txtName) { $txtName.Text = '' }
            
            # Refresh the list
            Initialize-ScheduledScansList -Window $Window
        }
        else {
            Show-Toast -Message "Failed to create schedule: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error creating schedule: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-RunScheduledScanNow {
    <#
    .SYNOPSIS
        Runs the selected scheduled scan immediately.
    #>
    param([System.Windows.Window]$Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to run.' -Type 'Warning'
        return
    }
    
    if (-not (Get-Command -Name 'Invoke-ScheduledScan' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Scheduled scan functions not available.' -Type 'Error'
        return
    }
    
    $selectedSchedule = $listBox.SelectedItem
    $scheduleId = $selectedSchedule.ScheduleId
    $scheduleName = $selectedSchedule.Name
    
    $confirm = [System.Windows.MessageBox]::Show(
        "Run scheduled scan '$scheduleName' now?",
        'Confirm Run',
        'YesNo',
        'Question'
    )
    
    if ($confirm -ne 'Yes') { return }
    
    try {
        Show-LoadingOverlay -Message "Starting scheduled scan '$scheduleName'..."
        
        # Backend Invoke-ScheduledScan expects -Id parameter
        $result = Invoke-ScheduledScan -Id $scheduleId
        
        Hide-LoadingOverlay
        
        if ($result.Success) {
            Show-Toast -Message "Scheduled scan '$scheduleName' started. Check History tab for results." -Type 'Success'
            
            # Optionally refresh saved scans list to show new results
            Update-SavedScansList -Window $Window
        }
        else {
            Show-Toast -Message "Failed to run scan: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Hide-LoadingOverlay
        Show-Toast -Message "Error running scan: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-DeleteScheduledScan {
    <#
    .SYNOPSIS
        Deletes the selected scheduled scan.
    #>
    param([System.Windows.Window]$Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to delete.' -Type 'Warning'
        return
    }
    
    if (-not (Get-Command -Name 'Remove-ScheduledScan' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Scheduled scan functions not available.' -Type 'Error'
        return
    }
    
    $selectedSchedule = $listBox.SelectedItem
    $scheduleId = $selectedSchedule.ScheduleId
    $scheduleName = $selectedSchedule.Name
    
    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete scheduled scan '$scheduleName'?`n`nThis will also remove the Windows Task Scheduler task.",
        'Confirm Delete',
        'YesNo',
        'Warning'
    )
    
    if ($confirm -ne 'Yes') { return }
    
    try {
        # Backend Remove-ScheduledScan expects -Id parameter
        $result = Remove-ScheduledScan -Id $scheduleId
        
        if ($result.Success) {
            Show-Toast -Message "Scheduled scan '$scheduleName' deleted." -Type 'Success'
            Initialize-ScheduledScansList -Window $Window
        }
        else {
            Show-Toast -Message "Failed to delete: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error deleting schedule: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-ToggleScheduledScan {
    <#
    .SYNOPSIS
        Toggles the enabled state of the selected scheduled scan.
    #>
    param([System.Windows.Window]$Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to toggle.' -Type 'Warning'
        return
    }
    
    if (-not (Get-Command -Name 'Set-ScheduledScanEnabled' -ErrorAction SilentlyContinue)) {
        Show-Toast -Message 'Scheduled scan functions not available.' -Type 'Error'
        return
    }
    
    $selectedSchedule = $listBox.SelectedItem
    $scheduleId = $selectedSchedule.ScheduleId
    $scheduleName = $selectedSchedule.Name
    $newState = -not $selectedSchedule.Enabled
    
    try {
        # Backend Set-ScheduledScanEnabled expects -Id parameter
        $result = Set-ScheduledScanEnabled -Id $scheduleId -Enabled $newState
        
        if ($result.Success) {
            $stateText = if ($newState) { 'enabled' } else { 'disabled' }
            Show-Toast -Message "Scheduled scan '$scheduleName' $stateText." -Type 'Success'
            Initialize-ScheduledScansList -Window $Window
        }
        else {
            Show-Toast -Message "Failed to update: $($result.Error)" -Type 'Error'
        }
    }
    catch {
        Show-Toast -Message "Error updating schedule: $($_.Exception.Message)" -Type 'Error'
    }
}
#endregion

#region ===== RULE GENERATION =====
function global:Invoke-LaunchRuleWizard {
    <#
    .SYNOPSIS
        Launches the Rule Generation Wizard with current scan artifacts.
        The wizard shows a 3-step UI: Configure -> Preview -> Generate
    #>
    param([System.Windows.Window]$Window)
    
    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message "No artifacts available. Run a scan first." -Type 'Warning'
        return
    }
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Write-Log -Message "Launching Rule Generation Wizard with $artifactCount artifacts"
    
    # Check if wizard overlay exists in XAML (not just the PS function)
    $wizardOverlay = $Window.FindName('RuleWizardOverlay')
    
    if ($wizardOverlay -and (Get-Command -Name 'Initialize-RuleGenerationWizard' -ErrorAction SilentlyContinue)) {
        # Launch the 3-step wizard UI
        try {
            Initialize-RuleGenerationWizard -Artifacts $script:CurrentScanArtifacts
            return
        } catch {
            Write-Log -Level Warning -Message "Wizard failed, using confirmation dialog: $($_.Exception.Message)"
        }
    }
    
    # Fallback: Show configuration dialog before generating (wizard UI not available)
    $dialogResult = Show-RuleGenerationConfigDialog -ArtifactCount $artifactCount
    
    if (-not $dialogResult -or -not $dialogResult.Confirmed) {
        Write-Log -Message "Rule generation cancelled by user"
        return
    }
    
    # User confirmed - proceed with generation using their settings
    Invoke-DirectRuleGenerationWithSettings -Window $Window -Settings $dialogResult
}

function global:Show-RuleGenerationConfigDialog {
    <#
    .SYNOPSIS
        Shows a configuration dialog for rule generation settings.
    #>
    param([int]$ArtifactCount)
    
    # Create dialog XAML
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rule Generation Settings" 
        Width="450" Height="480"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#1E1E1E">
    <Window.Resources>
        <SolidColorBrush x:Key="FgBrush" Color="#E0E0E0"/>
        <SolidColorBrush x:Key="MutedBrush" Color="#808080"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#0078D4"/>
        <SolidColorBrush x:Key="ControlBg" Color="#2D2D30"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#3F3F46"/>
        <SolidColorBrush x:Key="HoverBrush" Color="#3E3E42"/>
        
        <!-- ComboBox ToggleButton Template -->
        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition/>
                    <ColumnDefinition Width="20"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" Background="#2D2D30" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="2"/>
                <Border Grid.Column="0" Background="#2D2D30" BorderBrush="#3F3F46" BorderThickness="0,0,1,0" CornerRadius="2,0,0,2" Margin="1"/>
                <Path x:Name="Arrow" Grid.Column="1" Fill="#E0E0E0" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
            </Grid>
        </ControlTemplate>
        
        <!-- ComboBox Template -->
        <ControlTemplate x:Key="DarkComboBoxTemplate" TargetType="ComboBox">
            <Grid>
                <ToggleButton Name="ToggleButton" Template="{StaticResource ComboBoxToggleButton}" 
                              IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" 
                              Focusable="false" ClickMode="Press"/>
                <ContentPresenter Name="ContentSite" IsHitTestVisible="False" 
                                  Content="{TemplateBinding SelectionBoxItem}" 
                                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                  ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                  Margin="8,4,28,4" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" 
                       AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                    <Grid Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                        <Border x:Name="DropDownBorder" Background="#2D2D30" BorderBrush="#3F3F46" BorderThickness="1"/>
                        <ScrollViewer Margin="2" SnapsToDevicePixels="True">
                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                        </ScrollViewer>
                    </Grid>
                </Popup>
            </Grid>
        </ControlTemplate>
        
        <!-- ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Template" Value="{StaticResource DarkComboBoxTemplate}"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Height" Value="32"/>
        </Style>
        
        <!-- ComboBoxItem Style -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#3E3E42"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#3E3E42"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock Text="Configure Rule Generation" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource FgBrush}"/>
            <TextBlock Text="$ArtifactCount artifacts will be processed" Foreground="{StaticResource MutedBrush}" Margin="0,5,0,0"/>
        </StackPanel>
        
        <!-- Settings -->
        <StackPanel Grid.Row="1">
            <!-- Publisher Granularity -->
            <TextBlock Text="Publisher Granularity" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <ComboBox x:Name="CboPublisherLevel" Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                      BorderBrush="{StaticResource BorderBrush}" Padding="8,6" Margin="0,0,0,15">
                <ComboBoxItem Content="Publisher + Product (Recommended)" Tag="PublisherProduct" IsSelected="True"/>
                <ComboBoxItem Content="Publisher + Product + Version" Tag="PublisherProductVersion"/>
                <ComboBoxItem Content="Publisher Only" Tag="Publisher"/>
                <ComboBoxItem Content="Publisher + Product + Version + FileName" Tag="PublisherProductVersionFileName"/>
            </ComboBox>
            
            <!-- Rule Action -->
            <TextBlock Text="Rule Action" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,15">
                <RadioButton x:Name="RbAllow" Content="Allow" Foreground="{StaticResource FgBrush}" IsChecked="True" Margin="0,0,20,0"/>
                <RadioButton x:Name="RbDeny" Content="Deny" Foreground="{StaticResource FgBrush}"/>
            </StackPanel>
            
            <!-- Target Group -->
            <TextBlock Text="Target Group" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <ComboBox x:Name="CboTargetGroup" Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                      BorderBrush="{StaticResource BorderBrush}" Padding="8,6" Margin="0,0,0,15">
                <ComboBoxItem Content="Everyone" Tag="S-1-1-0" IsSelected="True"/>
                <ComboBoxItem Content="Administrators" Tag="S-1-5-32-544"/>
                <ComboBoxItem Content="Users" Tag="S-1-5-32-545"/>
            </ComboBox>
            
            <!-- Unsigned File Handling -->
            <TextBlock Text="Unsigned File Handling" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <ComboBox x:Name="CboUnsignedMode" Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                      BorderBrush="{StaticResource BorderBrush}" Padding="8,6" Margin="0,0,0,15">
                <ComboBoxItem Content="Hash (Recommended)" Tag="Hash" IsSelected="True"/>
                <ComboBoxItem Content="Path" Tag="Path"/>
                <ComboBoxItem Content="Skip (Don't create rules)" Tag="Skip"/>
            </ComboBox>
            
            <!-- Initial Status -->
            <TextBlock Text="Initial Status" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <ComboBox x:Name="CboStatus" Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                      BorderBrush="{StaticResource BorderBrush}" Padding="8,6" Margin="0,0,0,15">
                <ComboBoxItem Content="Pending (Requires approval)" Tag="Pending" IsSelected="True"/>
                <ComboBoxItem Content="Approved" Tag="Approved"/>
            </ComboBox>
        </StackPanel>
        
        <!-- Buttons -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button x:Name="BtnCancel" Content="Cancel" Width="100" Padding="10,8" Margin="0,0,10,0"
                    Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                    BorderBrush="{StaticResource BorderBrush}"/>
            <Button x:Name="BtnGenerate" Content="Generate Rules" Width="120" Padding="10,8"
                    Background="{StaticResource AccentBrush}" Foreground="White" BorderBrush="{StaticResource AccentBrush}"/>
        </StackPanel>
    </Grid>
</Window>
"@

    try {
        # Parse XAML
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dialogXaml))
        $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
        
        # Get controls
        $cboPublisherLevel = $dialog.FindName('CboPublisherLevel')
        $rbAllow = $dialog.FindName('RbAllow')
        $rbDeny = $dialog.FindName('RbDeny')
        $cboTargetGroup = $dialog.FindName('CboTargetGroup')
        $cboUnsignedMode = $dialog.FindName('CboUnsignedMode')
        $cboStatus = $dialog.FindName('CboStatus')
        $btnCancel = $dialog.FindName('BtnCancel')
        $btnGenerate = $dialog.FindName('BtnGenerate')
        
        # Result object
        $result = @{ Confirmed = $false }
        
        # Button handlers
        $btnCancel.Add_Click({ $dialog.DialogResult = $false; $dialog.Close() })
        $btnGenerate.Add_Click({
            $result.Confirmed = $true
            $result.PublisherLevel = $cboPublisherLevel.SelectedItem.Tag
            $result.Action = if ($rbAllow.IsChecked) { 'Allow' } else { 'Deny' }
            $result.TargetSid = $cboTargetGroup.SelectedItem.Tag
            $result.UnsignedMode = $cboUnsignedMode.SelectedItem.Tag
            $result.Status = $cboStatus.SelectedItem.Tag
            $dialog.DialogResult = $true
            $dialog.Close()
        })
        
        # Show dialog
        $dialogResult = $dialog.ShowDialog()
        
        if ($result.Confirmed) {
            return [PSCustomObject]$result
        }
        return $null
    }
    catch {
        Write-Log -Level Error -Message "Failed to show config dialog: $($_.Exception.Message)"
        return $null
    }
}

function global:Invoke-DirectRuleGenerationWithSettings {
    <#
    .SYNOPSIS
        Generates rules using settings from the configuration dialog.
    #>
    param(
        [System.Windows.Window]$Window,
        [PSCustomObject]$Settings
    )
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Show-Toast -Message "Generating rules from $artifactCount artifacts..." -Type 'Info'
    Write-Log -Message "Starting batch rule generation for $artifactCount artifacts"
    Write-Log -Message "Settings: PublisherLevel=$($Settings.PublisherLevel), Action=$($Settings.Action), UnsignedMode=$($Settings.UnsignedMode)"
    
    # Show loading overlay
    if (Get-Command -Name 'Show-LoadingOverlay' -ErrorAction SilentlyContinue) {
        Show-LoadingOverlay -Message "Generating Rules..." -SubMessage "Processing $artifactCount artifacts..."
    }
    
    try {
        # Use batch generation with user's settings from dialog
        $result = Invoke-BatchRuleGeneration -Artifacts $script:CurrentScanArtifacts `
            -Mode 'Smart' `
            -Action $Settings.Action `
            -Status $Settings.Status `
            -DedupeMode 'Smart' `
            -PublisherLevel $Settings.PublisherLevel `
            -UserOrGroupSid $Settings.TargetSid `
            -UnsignedMode $Settings.UnsignedMode
        
        # Hide loading overlay
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        
        # Show results
        $msg = "Created $($result.RulesCreated) rules"
        if ($result.AlreadyExisted -gt 0) { $msg += " ($($result.AlreadyExisted) already existed)" }
        Show-Toast -Message $msg -Type 'Success'
        Write-Log -Message "Batch generation complete: $($result.RulesCreated) created, $($result.AlreadyExisted) existed"
        
        # Navigate to Rules panel to see results
        if (Get-Command -Name 'Set-ActivePanel' -ErrorAction SilentlyContinue) {
            Set-ActivePanel -PanelName 'PanelRules'
        }
        
        # Auto-refresh the Rules DataGrid to show newly created rules
        if (Get-Command -Name 'Update-RulesDataGrid' -ErrorAction SilentlyContinue) {
            Update-RulesDataGrid -Window $Window
        }
    }
    catch {
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        Show-Toast -Message "Generation failed: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Batch generation failed: $($_.Exception.Message)"
    }
}

function global:Invoke-DirectRuleGeneration {
    <#
    .SYNOPSIS
        Generates rules directly without wizard UI. Called after user confirmation.
    #>
    param([System.Windows.Window]$Window)
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Show-Toast -Message "Generating rules from $artifactCount artifacts (Smart mode)..." -Type 'Info'
    Write-Log -Message "Starting batch rule generation for $artifactCount artifacts"
    
    # Show loading overlay
    if (Get-Command -Name 'Show-LoadingOverlay' -ErrorAction SilentlyContinue) {
        Show-LoadingOverlay -Message "Generating Rules..." -SubMessage "Processing $artifactCount artifacts..."
    }
    
    try {
        # Read Publisher Granularity from Rules panel ComboBox
        $pubLevelCombo = $Window.FindName('CboPublisherLevel')
        $publisherLevel = if ($pubLevelCombo -and $pubLevelCombo.SelectedItem -and $pubLevelCombo.SelectedItem.Tag) {
            $tag = $pubLevelCombo.SelectedItem.Tag
            Write-Log -Message "Publisher Granularity: $tag (from $($pubLevelCombo.SelectedItem.Content))"
            $tag
        } else {
            Write-Log -Message "Publisher Granularity: PublisherProduct (default)"
            'PublisherProduct'
        }
        
        # Read Rule Action (Allow/Deny)
        $rbAllow = $Window.FindName('RbRuleAllow')
        $action = if ($rbAllow -and $rbAllow.IsChecked) { 'Allow' } else { 'Deny' }
        Write-Log -Message "Rule Action: $action"
        
        # Read Target Group
        $targetCombo = $Window.FindName('CboRuleTargetGroup')
        $targetSid = if ($targetCombo -and $targetCombo.SelectedItem -and $targetCombo.SelectedItem.Tag) {
            $targetCombo.SelectedItem.Tag
        } else {
            'S-1-1-0'  # Everyone
        }
        Write-Log -Message "Target Group SID: $targetSid"
        
        # Read Unsigned File Handling mode
        $unsignedCombo = $Window.FindName('CboUnsignedMode')
        $unsignedMode = if ($unsignedCombo -and $unsignedCombo.SelectedItem -and $unsignedCombo.SelectedItem.Tag) {
            $tag = $unsignedCombo.SelectedItem.Tag
            Write-Log -Message "Unsigned File Handling: $tag (from $($unsignedCombo.SelectedItem.Content))"
            $tag
        } else {
            Write-Log -Message "Unsigned File Handling: Hash (default)"
            'Hash'
        }
        
        # Use batch generation with user's settings
        $result = Invoke-BatchRuleGeneration -Artifacts $script:CurrentScanArtifacts `
            -Mode 'Smart' `
            -Action $action `
            -Status 'Pending' `
            -DedupeMode 'Smart' `
            -PublisherLevel $publisherLevel `
            -UserOrGroupSid $targetSid `
            -UnsignedMode $unsignedMode
        
        # Hide loading overlay
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        
        # Show results
        $msg = "Created $($result.RulesCreated) rules"
        if ($result.AlreadyExisted -gt 0) { $msg += " ($($result.AlreadyExisted) already existed)" }
        Show-Toast -Message $msg -Type 'Success'
        Write-Log -Message "Batch generation complete: $($result.RulesCreated) created, $($result.AlreadyExisted) existed"
        
        # Navigate to Rules panel to see results
        if (Get-Command -Name 'Set-ActivePanel' -ErrorAction SilentlyContinue) {
            Set-ActivePanel -PanelName 'PanelRules'
        }
        
        # Auto-refresh the Rules DataGrid to show newly created rules
        if (Get-Command -Name 'Update-RulesDataGrid' -ErrorAction SilentlyContinue) {
            Update-RulesDataGrid -Window $Window
        }
    }
    catch {
        if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
            Hide-LoadingOverlay
        }
        Show-Toast -Message "Generation failed: $($_.Exception.Message)" -Type 'Error'
        Write-Log -Level Error -Message "Batch generation failed: $($_.Exception.Message)"
    }
}
#endregion
#endregion
