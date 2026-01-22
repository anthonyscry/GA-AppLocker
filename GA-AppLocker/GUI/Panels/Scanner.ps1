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
        
        # Fallback to comprehensive defaults
        if (-not $paths) {
            $paths = @(
                'C:\Program Files',
                'C:\Program Files (x86)',
                'C:\Windows\System32',
                'C:\Windows\SysWOW64',
                'C:\ProgramData',
                'C:\Windows\Microsoft.NET',
                "$env:LOCALAPPDATA\Programs",
                "$env:LOCALAPPDATA\Microsoft\WindowsApps"
            )
        }
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
    if ($btnBrowsePath) { $btnBrowsePath.Add_Click({ Invoke-BrowseScanPath -Window $script:MainWindow }) }

    $btnResetPaths = $Window.FindName('BtnResetPaths')
    if ($btnResetPaths) {
        $btnResetPaths.Add_Click({ 
                $txtPaths = $script:MainWindow.FindName('TxtScanPaths')
                if ($txtPaths) { 
                    $defaultPaths = @(
                        'C:\Program Files',
                        'C:\Program Files (x86)',
                        'C:\Windows\System32',
                        'C:\Windows\SysWOW64',
                        'C:\ProgramData',
                        'C:\Windows\Microsoft.NET',
                        "$env:LOCALAPPDATA\Programs",
                        "$env:LOCALAPPDATA\Microsoft\WindowsApps"
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

    # Wire up filter buttons
    $filterButtons = @{
        'BtnFilterAllArtifacts' = 'All'
        'BtnFilterExe'          = 'EXE'
        'BtnFilterDll'          = 'DLL'
        'BtnFilterMsi'          = 'MSI'
        'BtnFilterScript'       = 'Script'
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
                    if ($script:MainWindow) {
                        Update-ArtifactFilter -Window $script:MainWindow -Filter $filter
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
            if ($script:MainWindow) {
                Update-ArtifactDataGrid -Window $script:MainWindow
            }
        })
        
        $filterBox.Add_TextChanged({
            # Reset and restart timer on each keystroke
            $script:ArtifactFilterTimer.Stop()
            $script:ArtifactFilterTimer.Start()
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

function Invoke-StopArtifactScan {
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
}

function global:Update-ArtifactFilter {
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

    # Store filter state and refresh grid
    $script:CurrentArtifactFilter = $Filter
    Update-ArtifactDataGrid -Window $Window
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
        # Wrap in array to ensure WPF binding works with single item
        $listBox.ItemsSource = @($result.Data)
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
            # Merge: add new artifacts, avoiding duplicates by hash
            $existingHashes = @($script:CurrentScanArtifacts | ForEach-Object { $_.SHA256Hash })
            $newArtifacts = @($result.Data.Artifacts | Where-Object { $_.SHA256Hash -notin $existingHashes })
            $script:CurrentScanArtifacts = @($script:CurrentScanArtifacts) + $newArtifacts
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

            $allArtifacts = @()
            $fileCount = 0
            
            foreach ($filePath in $dialog.FileNames) {
                $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
                
                $artifacts = switch ($extension) {
                    '.csv' { @(Import-Csv -Path $filePath) }
                    '.json' { @(Get-Content -Path $filePath -Raw | ConvertFrom-Json) }
                    default { throw "Unsupported file format: $extension" }
                }
                
                $allArtifacts += $artifacts
                $fileCount++
            }

            if ($mergeMode) {
                # Merge: add new artifacts, avoiding duplicates by hash
                $existingHashes = @($script:CurrentScanArtifacts | ForEach-Object { $_.SHA256Hash })
                $newArtifacts = @($allArtifacts | Where-Object { $_.SHA256Hash -notin $existingHashes })
                $script:CurrentScanArtifacts = @($script:CurrentScanArtifacts) + $newArtifacts
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

function Show-MachineSelectionDialog {
    param(
        [System.Windows.Window]$ParentWindow,
        [array]$Machines
    )
    
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select Machines for Scanning"
        Width="500" Height="450"
        WindowStartupLocation="CenterOwner"
        Background="#1E1E1E"
        ResizeMode="CanResize">
    <Window.Resources>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Margin" Value="5,3"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#3C3C3C"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="BorderBrush" Value="#3C3C3C"/>
            <Setter Property="Padding" Value="5"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Select machines to include in the scan:" 
                   Foreground="#E0E0E0" FontSize="14" Margin="15,15,15,5"/>
        
        <Grid Grid.Row="1" Margin="15,5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TxtFilter" Grid.Column="0" Margin="0,0,10,0"/>
            <Button x:Name="BtnSelectAll" Grid.Column="1" Content="Select All" Width="80"/>
            <Button x:Name="BtnSelectNone" Grid.Column="2" Content="Clear All" Width="80"/>
        </Grid>
        
        <Border Grid.Row="2" Margin="15,5" Background="#2D2D2D" BorderBrush="#3C3C3C" BorderThickness="1">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="MachineStack"/>
            </ScrollViewer>
        </Border>
        
        <TextBlock Grid.Row="3" x:Name="TxtSelectionCount" 
                   Foreground="#888888" Margin="15,5" FontSize="12"/>
        
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="15">
            <Button x:Name="BtnOK" Content="OK" Width="80" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Cancel" Width="80" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dialogXaml))
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $ParentWindow
    
    $machineStack = $dialog.FindName('MachineStack')
    $txtFilter = $dialog.FindName('TxtFilter')
    $txtCount = $dialog.FindName('TxtSelectionCount')
    $btnSelectAll = $dialog.FindName('BtnSelectAll')
    $btnSelectNone = $dialog.FindName('BtnSelectNone')
    $btnOK = $dialog.FindName('BtnOK')
    $btnCancel = $dialog.FindName('BtnCancel')
    
    foreach ($machine in $Machines) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $ouDisplay = if ($machine.OU) { $machine.OU } else { 'Unknown OU' }
        $cb.Content = "$($machine.Hostname) - $ouDisplay"
        $cb.IsChecked = $true
        $cb.Tag = $machine
        $cb.Foreground = [System.Windows.Media.Brushes]::White
        $cb.Margin = [System.Windows.Thickness]::new(5, 3, 5, 3)
        $machineStack.Children.Add($cb)
    }
    
    $updateCount = {
        $selected = 0
        foreach ($cb in $machineStack.Children) { if ($cb.IsChecked) { $selected++ } }
        $txtCount.Text = "$selected of $($Machines.Count) machines selected"
    }.GetNewClosure()
    & $updateCount
    
    $txtFilter.Add_TextChanged({
        $filter = $txtFilter.Text.ToLower()
        foreach ($cb in $machineStack.Children) {
            $cb.Visibility = if ($cb.Content.ToString().ToLower().Contains($filter)) { 'Visible' } else { 'Collapsed' }
        }
    }.GetNewClosure())
    
    $btnSelectAll.Add_Click({ 
        foreach ($cb in $machineStack.Children) { $cb.IsChecked = $true }
        & $updateCount
    }.GetNewClosure())
    
    $btnSelectNone.Add_Click({ 
        foreach ($cb in $machineStack.Children) { $cb.IsChecked = $false }
        & $updateCount
    }.GetNewClosure())
    
    $script:DialogResult = $null
    
    $btnOK.Add_Click({
        $script:DialogResult = @()
        foreach ($cb in $machineStack.Children) {
            if ($cb.IsChecked) { $script:DialogResult += $cb.Tag }
        }
        $dialog.DialogResult = $true
        $dialog.Close()
    }.GetNewClosure())
    
    $btnCancel.Add_Click({
        $dialog.DialogResult = $false
        $dialog.Close()
    }.GetNewClosure())
    
    $result = $dialog.ShowDialog()
    
    if ($result -eq $true) { return $script:DialogResult }
    return $null
}

function Invoke-SelectMachinesForScan {
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


#endregion
#endregion
