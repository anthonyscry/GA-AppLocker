#region Scanner Panel Functions
# Scanner.ps1 - Scanner panel handlers
function Initialize-ScannerPanel {
    param($Window)

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
        catch { Write-Log -Level Warning -Message "Failed to load scan config: $($_.Exception.Message)" }
        
        # Fall back to clean defaults if config didn't provide paths
        if (-not $paths -or $paths.Count -eq 0) {
            $paths = @(
                'C:\Program Files',
                'C:\Program Files (x86)',
                'C:\ProgramData',
                'C:\Windows\System32',
                'C:\Windows\SysWOW64'
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

    $btnRemoveMachines = $Window.FindName('BtnRemoveScanMachines')
    if ($btnRemoveMachines) { $btnRemoveMachines.Add_Click({ Invoke-RemoveScanMachines -Window $global:GA_MainWindow }) }

    $btnClearMachines = $Window.FindName('BtnClearScanMachines')
    if ($btnClearMachines) { $btnClearMachines.Add_Click({ Invoke-ClearScanMachines -Window $global:GA_MainWindow }) }

    $btnBrowsePath = $Window.FindName('BtnBrowsePath')
    if ($btnBrowsePath) { $btnBrowsePath.Add_Click({ Invoke-BrowseScanPath -Window $global:GA_MainWindow }) }

    # Remote scan toggle - show/hide machines section
    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) {
        $chkRemote.Add_Checked({
            try { global:Update-ScanRemoteSectionVisibility -Window $global:GA_MainWindow } catch { }
        })
        $chkRemote.Add_Unchecked({
            try { global:Update-ScanRemoteSectionVisibility -Window $global:GA_MainWindow } catch { }
        })
        try { global:Update-ScanRemoteSectionVisibility -Window $Window } catch { }
    }

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

function global:Update-ScanRemoteSectionVisibility {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $chkRemote = $win.FindName('ChkScanRemote')
    $section = $win.FindName('ScanMachinesSection')
    if (-not $section) { return }

    $isRemote = if ($chkRemote) { [bool]$chkRemote.IsChecked } else { $false }
    $section.Visibility = if ($isRemote) { 'Visible' } else { 'Collapsed' }

    if ($isRemote) {
        try { global:Update-WinRMAvailableCount -Window $win } catch { }
    }
}

function global:Update-WinRMAvailableCount {
    param($Window)

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $txt = $win.FindName('TxtWinRMAvailableCount')
    if (-not $txt) { return }

    $available = @($script:DiscoveredMachines | Where-Object { $_.WinRMStatus -eq 'Available' })
    $txt.Text = "WinRM available: $($available.Count)"
}

function global:Invoke-StartArtifactScan {
    param($Window)

    if ($script:ScanInProgress) {
        Show-Toast -Message 'A scan is already in progress.' -Type 'Warning'
        return
    }

    # Get scan configuration (null-safe FindName access)
    $chk = $Window.FindName('ChkScanLocal');        $scanLocal = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkScanRemote');       $scanRemote = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkIncludeEventLogs'); $includeEvents = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkIncludeHighRisk');  $includeHighRisk = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkSkipDllScanning');  $skipDllScanning = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkSkipWshScanning');  $skipWshScanning = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkSkipShellScanning');$skipShellScanning = if ($chk) { $chk.IsChecked } else { $false }
    $chk = $Window.FindName('ChkIncludeAppx');      $includeAppx = if ($chk) { $chk.IsChecked } else { $true }
    $chk = $Window.FindName('ChkSaveResults');      $saveResults = if ($chk) { $chk.IsChecked } else { $true }
    $txt = $Window.FindName('TxtScanName');          $scanName = if ($txt) { $txt.Text } else { '' }
    $txt = $Window.FindName('TxtScanPaths');         $pathsText = if ($txt) { $txt.Text } else { '' }

    # Validate
    if (-not $scanLocal -and -not $scanRemote) {
        Show-Toast -Message 'Please select at least one scan type (Local or Remote).' -Type 'Warning'
        return
    }

    # Check elevation for local scans (required to access C:\Program Files, C:\Windows\System32)
    if ($scanLocal) {
        $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isElevated) {
            Show-Toast -Message "Local scans require Administrator privileges to access system directories (Program Files, Windows).`n`nPlease restart as Administrator or use Remote Scan via WinRM." -Type 'Error'
            return
        }
    }

    if ($scanRemote -and (-not $script:SelectedScanMachines -or $script:SelectedScanMachines.Count -eq 0)) {
        Show-Toast -Message "Remote scan selected but no machines have been added. Use AD Discovery to add machines or uncheck Remote." -Type 'Warning'
        return
    }

    if ([string]::IsNullOrWhiteSpace($scanName)) {
        $scanName = "Scan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $txtName = $Window.FindName('TxtScanName')
        if ($txtName) { $txtName.Text = $scanName }
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
    $global:GA_ScanInProgress = $true
    $script:ScanCancelled = $false
    Update-ScanUIState -Window $Window -Scanning $true
    Update-ScanProgress -Window $Window -Text "Starting scan: $scanName" -Percent 5
    $statusLabel = $Window.FindName('ScanStatusLabel')
    if ($statusLabel) {
        $statusLabel.Text = 'Running'
        $statusLabel.Foreground = [System.Windows.Media.Brushes]::Gold
    }
    if (Get-Command -Name 'Show-LoadingOverlay' -ErrorAction SilentlyContinue) {
        Show-LoadingOverlay -Message 'Scan in progress...' -SubMessage "Starting scan: $scanName"
    }
    try { Request-UiRender -Window $Window } catch { }

    # Build scan parameters
    $scanParams = @{
        SaveResults = $saveResults
        ScanName    = $scanName
    }

    if ($scanLocal) { $scanParams.ScanLocal = $true }
    if ($includeEvents) { $scanParams.IncludeEventLogs = $true }
    if ($skipDllScanning) { $scanParams.SkipDllScanning = $true }
    if ($skipWshScanning) { $scanParams.SkipWshScanning = $true }
    if ($skipShellScanning) { $scanParams.SkipShellScanning = $true }
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

    # Create and start the background runspace (MTA -- no STA/ReuseThread overhead)
    $script:ScanRunspace = [runspacefactory]::CreateRunspace()
    $script:ScanRunspace.ApartmentState = 'MTA'
    $script:ScanRunspace.Open()
    $script:ScanRunspace.SessionStateProxy.SetVariable('SyncHash', $script:ScanSyncHash)

    # Import ONLY the scanning sub-modules (not the full 10-module root GA-AppLocker.psd1)
    # This avoids importing GUI, Deployment, Validation, etc. which are not needed for scanning
    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:ScanRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:ScanPowerShell = [powershell]::Create()
    $script:ScanPowerShell.Runspace = $script:ScanRunspace
    
    [void]$script:ScanPowerShell.AddScript({
            param($SyncHash, $ModulePath)
        
            try {
                $SyncHash.StatusText = "Loading scan modules..."
                $SyncHash.Progress = 15
            
                # Import only the sub-modules needed for scanning (fast: 3 modules instead of 10)
                $modulesDir = Join-Path $ModulePath 'Modules'
                $requiredModules = @('GA-AppLocker.Core', 'GA-AppLocker.Scanning', 'GA-AppLocker.Credentials')
                foreach ($mod in $requiredModules) {
                    $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
                    if (Test-Path $modPath) {
                        Import-Module $modPath -Force -ErrorAction Stop
                    }
                }
            
                $machineCount = if ($SyncHash.Params.Machines) { $SyncHash.Params.Machines.Count } else { 0 }
                $localText = if ($SyncHash.Params.ScanLocal) { 'local + ' } else { '' }
                $SyncHash.StatusText = "Scanning ${localText}${machineCount} remote machine(s)..."
                $SyncHash.Progress = 25
            
                # Execute the scan
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
            if (Get-Command -Name 'Update-LoadingText' -ErrorAction SilentlyContinue) {
                Update-LoadingText -Message 'Scan in progress...' -SubMessage $syncHash.StatusText
            }
        
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
                $global:GA_ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
                Update-ScanProgress -Window $win -Text "Scan cancelled" -Percent 0
                if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
                    Hide-LoadingOverlay
                }
                
                $statusLabel = $win.FindName('ScanStatusLabel')
                if ($statusLabel) {
                    $statusLabel.Text = "Cancelled"
                    $statusLabel.Foreground = [System.Windows.Media.Brushes]::Orange
                }
                return
            }
        
            # Check if complete
            if ($syncHash.IsComplete) {
                $script:ScanTimer.Stop()
            
                # End the async operation
                try {
                    $script:ScanPowerShell.EndInvoke($script:ScanAsyncResult)
                }
                catch { Write-AppLockerLog -Message "Scan EndInvoke cleanup: $($_.Exception.Message)" -Level 'DEBUG' }
            
                # Clean up runspace
                if ($script:ScanPowerShell) { $script:ScanPowerShell.Dispose() }
                if ($script:ScanRunspace) { 
                    $script:ScanRunspace.Close()
                    $script:ScanRunspace.Dispose() 
                }
            
                $script:ScanInProgress = $false
                $global:GA_ScanInProgress = $false
                Update-ScanUIState -Window $win -Scanning $false
                if (Get-Command -Name 'Hide-LoadingOverlay' -ErrorAction SilentlyContinue) {
                    Hide-LoadingOverlay
                }
            
                if ($syncHash.Error) {
                    Update-ScanProgress -Window $win -Text "Error: $($syncHash.Error)" -Percent 0
                    $statusLabel = $win.FindName('ScanStatusLabel')
                    if ($statusLabel) {
                        $statusLabel.Text = "Error"
                        $statusLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    }
                    Show-Toast -Message "Scan error: $($syncHash.Error)" -Type 'Error'
                }
                elseif ($syncHash.Result -and $syncHash.Result.Success) {
                    $result = $syncHash.Result
                    $script:CurrentScanArtifacts = $result.Data.Artifacts
                    Update-ArtifactDataGrid -Window $win
                    Update-ScanProgress -Window $win -Text "Scan complete: $($result.Summary.TotalArtifacts) artifacts" -Percent 100

                    # Update counters
                    $countLabel = $win.FindName('ScanArtifactCount')
                    if ($countLabel) { $countLabel.Text = "$($result.Summary.TotalArtifacts) artifacts" }
                    
                    $preGen = $win.FindName('TxtArtifactCountPreGen')
                    if ($preGen) { $preGen.Text = "$($result.Summary.TotalArtifacts)" }
                    
                    $signedLabel = $win.FindName('ScanSignedCount')
                    if ($signedLabel) { $signedLabel.Text = "$($result.Summary.SignedArtifacts)" }
                    
                    $unsignedLabel = $win.FindName('ScanUnsignedCount')
                    if ($unsignedLabel) { $unsignedLabel.Text = "$($result.Summary.UnsignedArtifacts)" }
                    
                    $statusLabel = $win.FindName('ScanStatusLabel')
                    if ($statusLabel) {
                        $statusLabel.Text = "Complete"
                        $statusLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
                    }

                    # Refresh saved scans list
                    Update-SavedScansList -Window $win
                    
                    # Update workflow breadcrumb
                    Update-WorkflowBreadcrumb -Window $win

                    # Build per-machine feedback so user sees which machines succeeded/failed
                    $toastMsg = "Scan complete: $($result.Summary.TotalArtifacts) artifacts found ($($result.Summary.SignedArtifacts) signed)."
                    $toastType = 'Success'
                    if ($result.Summary.MachineResults -and $result.Summary.MachineResults.Count -gt 0) {
                        $failed = @($result.Summary.MachineResults.GetEnumerator() | Where-Object { -not $_.Value.Success })
                        $succeeded = @($result.Summary.MachineResults.GetEnumerator() | Where-Object { $_.Value.Success })
                        if ($failed.Count -gt 0) {
                            $failedNames = ($failed | ForEach-Object { $_.Key }) -join ', '
                            $succeededNames = ($succeeded | ForEach-Object { "$($_.Key)($($_.Value.ArtifactCount))" }) -join ', '
                            $toastMsg = "Scan partial: $($result.Summary.TotalArtifacts) artifacts from $($succeeded.Count) machine(s). "
                            if ($succeededNames) { $toastMsg += "OK: $succeededNames. " }
                            $toastMsg += "FAILED: $failedNames"
                            # Show failure reasons in a message box so user knows WHY
                            $failDetails = ($failed | ForEach-Object {
                                $reason = if ($_.Value.Error) { $_.Value.Error } else { 'No response (check WinRM/firewall)' }
                                "  $($_.Key): $reason"
                            }) -join "`n"
                            Write-AppLockerLog -Message "Partial scan: $($failed.Count) machine(s) failed.`n$failDetails" -Level 'WARN'
                            Show-Toast -Message "Scan partial: $($result.Summary.TotalArtifacts) artifacts; $($failed.Count) machine(s) failed. See log for details." -Type 'Warning'
                            $toastType = 'Warning'
                        }
                    }
                    Show-Toast -Message $toastMsg -Type $toastType
                }
                else {
                    $errorMsg = if ($syncHash.Result) { $syncHash.Result.Error } else { "Unknown error" }
                    Update-ScanProgress -Window $win -Text "Scan failed: $errorMsg" -Percent 0
                    $win.FindName('ScanStatusLabel').Text = "Failed"
                    $win.FindName('ScanStatusLabel').Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    Show-Toast -Message "Scan failed: $errorMsg" -Type 'Error'
                }
            }
        })
    
    # Start the timer
    $script:ScanTimer.Start()
}

function global:Invoke-StopArtifactScan {
    param($Window)

    # Signal cancellation - the timer tick handler will clean up
    $script:ScanCancelled = $true
}

function global:Update-ScanUIState {
    param(
        $Window,
        [bool]$Scanning
    )

    $btnStart = $Window.FindName('BtnStartScan')
    $btnStop = $Window.FindName('BtnStopScan')

    if ($btnStart) { $btnStart.IsEnabled = -not $Scanning }
    if ($btnStop) { $btnStop.IsEnabled = $Scanning }

    if ($Window) {
        $Window.Cursor = if ($Scanning) { [System.Windows.Input.Cursors]::Wait } else { [System.Windows.Input.Cursors]::Arrow }
    }
}

function global:Update-ScanProgress {
    param(
        $Window,
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

function global:Update-ArtifactDataGrid {
    param($Window)

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
                'Appx' { @($artifacts | Where-Object { $_.CollectionType -eq 'Appx' -or $_.ArtifactType -eq 'APPX' }) }
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
        Write-Log -Level Error -Message "Error updating artifact grid: $($_.Exception.Message)"
    }
}

function global:Update-ArtifactFilter {
    param(
        $Window,
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
        $Window,
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
    param($Window)
    
    $dataGrid = $Window.FindName('ArtifactDataGrid')
    $countText = $Window.FindName('TxtSelectedArtifactCount')
    
    if (-not $dataGrid -or -not $countText) { return }
    
    $selectedCount = $dataGrid.SelectedItems.Count
    $countText.Text = "$selectedCount"
}

function global:Update-SavedScansList {
    param($Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox) { return }

    try {
        $result = Get-ScanResults
        if ($result.Success -and $result.Data) {
            # Wrap in array to ensure WPF binding works with single item
            $listBox.ItemsSource = @($result.Data)
        }
        else {
            $listBox.ItemsSource = $null
        }
    }
    catch {
        Write-Log -Level Error -Message "Failed to refresh saved scans: $($_.Exception.Message)"
        $listBox.ItemsSource = $null
    }
}

function global:Invoke-LoadSelectedScan {
    param($Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a saved scan to load.' -Type 'Warning'
        return
    }

    # Check if we should merge with existing artifacts
    $mergeMode = $false
    if ($script:CurrentScanArtifacts -and $script:CurrentScanArtifacts.Count -gt 0) {
        $response = Show-AppLockerMessageBox "You have $($script:CurrentScanArtifacts.Count) artifacts loaded.`n`nYes = Merge (add to existing)`nNo = Replace (clear existing)" 'Merge or Replace?' 'YesNoCancel' 'Question'
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
                    [void]$newArtifacts.Add($a)
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
        $signed = @($script:CurrentScanArtifacts | Where-Object { $_.IsSigned }).Count
        $unsigned = $script:CurrentScanArtifacts.Count - $signed
        
        $countLabel = $Window.FindName('ScanArtifactCount')
        if ($countLabel) { $countLabel.Text = "$($script:CurrentScanArtifacts.Count) artifacts" }
        
        $preGen = $Window.FindName('TxtArtifactCountPreGen')
        if ($preGen) { $preGen.Text = "$($script:CurrentScanArtifacts.Count)" }
        
        $signedLabel = $Window.FindName('ScanSignedCount')
        if ($signedLabel) { $signedLabel.Text = "$signed" }
        
        $unsignedLabel = $Window.FindName('ScanUnsignedCount')
        if ($unsignedLabel) { $unsignedLabel.Text = "$unsigned" }
        
        $statusLabel = $Window.FindName('ScanStatusLabel')
        if ($statusLabel) {
            $statusLabel.Text = $statusText
            $statusLabel.Foreground = [System.Windows.Media.Brushes]::LightBlue
        }

        Update-ScanProgress -Window $Window -Text "$statusText`: $($selectedScan.ScanName)" -Percent 100
    }
    else {
        Show-Toast -Message "Failed to load scan: $($result.Error)" -Type 'Error'
    }
}

function global:Invoke-DeleteSelectedScan {
    param($Window)

    $listBox = $Window.FindName('SavedScansList')
    if (-not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a saved scan to delete.' -Type 'Warning'
        return
    }

    $selectedScan = $listBox.SelectedItem

    $confirm = Show-AppLockerMessageBox "Are you sure you want to delete scan '$($selectedScan.ScanName)'?" 'Confirm Delete' 'YesNo' 'Warning'

    if ($confirm -eq 'Yes') {
        $scanPath = Join-Path (Get-AppLockerDataPath) 'Scans'
        $scanFile = Join-Path $scanPath "$($selectedScan.ScanId).json"
        
        if (Test-Path $scanFile) {
            Remove-Item -Path $scanFile -Force
            Show-Toast -Message "Scan '$($selectedScan.ScanName)' deleted." -Type 'Success'
            Update-SavedScansList -Window $Window
        }
    }
}

function global:Invoke-ImportArtifacts {
    param($Window)

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
                $response = Show-AppLockerMessageBox "You have $($script:CurrentScanArtifacts.Count) artifacts loaded.`n`nYes = Merge (add to existing)`nNo = Replace (clear existing)" 'Merge or Replace?' 'YesNoCancel' 'Question'
                if ($response -eq 'Cancel') { return }
                $mergeMode = ($response -eq 'Yes')
            }

            $allArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()
            $fileCount = 0
            $normalizationState = @{
                CanNormalize = ($null -ne (Get-Command -Name 'Normalize-ArtifactRecord' -ErrorAction SilentlyContinue))
                Warned       = $false
                ExceptionWarned = $false
            }

            $normalizeImportedArtifact = {
                param(
                    $Artifact,
                    [string]$SourceType
                )

                if ($null -eq $Artifact) { return $null }

                $artifactRecord = $Artifact
                $artifactName = [string]$Artifact.FileName
                if ([string]::IsNullOrWhiteSpace($artifactName)) { $artifactName = '<unknown>' }
                $artifactPath = [string]$Artifact.FilePath
                if ([string]::IsNullOrWhiteSpace($artifactPath)) { $artifactPath = '<unknown>' }
                $artifactContext = "FileName='$artifactName', FilePath='$artifactPath', Source='$SourceType'"

                if ($normalizationState.CanNormalize) {
                    try {
                        $normalizedArtifact = Normalize-ArtifactRecord -Artifact $Artifact
                        if ($null -ne $normalizedArtifact) {
                            $artifactRecord = $normalizedArtifact
                        }
                        else {
                            Write-Log -Level 'Debug' -Message "ImportArtifacts: Normalize-ArtifactRecord returned null for '$($Artifact.FileName)' ($SourceType); applying fallback coercion."
                        }
                    }
                    catch {
                        if (-not $normalizationState.ExceptionWarned) {
                            Write-Log -Level 'Warning' -Message "ImportArtifacts: Normalize-ArtifactRecord failed for artifact ($artifactContext); applying fallback coercion. Subsequent normalization exceptions will be logged at DEBUG. Error: $($_.Exception.Message)"
                            $normalizationState.ExceptionWarned = $true
                        }
                        else {
                            Write-Log -Level 'Debug' -Message "ImportArtifacts: Normalize-ArtifactRecord failed; applying fallback coercion. Artifact: $artifactContext. Error: $($_.Exception.Message)"
                        }
                    }
                }

                if (-not $normalizationState.CanNormalize -and -not $normalizationState.Warned) {
                    Write-Log -Level 'Warning' -Message 'ImportArtifacts: Normalize-ArtifactRecord unavailable; applying fallback import coercion.'
                    $normalizationState.Warned = $true
                }

                # Enforce canonical import contract fields regardless of normalizer availability.
                $rawIsSigned = $null
                if ($artifactRecord.PSObject.Properties['IsSigned']) {
                    $rawIsSigned = $artifactRecord.IsSigned
                }

                $coercedIsSigned = $false
                if ($rawIsSigned -is [bool]) {
                    $coercedIsSigned = $rawIsSigned
                }
                elseif ($rawIsSigned -is [string]) {
                    $trimmedSigned = ([string]$rawIsSigned).Trim()
                    $coercedIsSigned = $trimmedSigned -match '^(?i:true|1)$'
                }
                elseif ($null -ne $rawIsSigned) {
                    try {
                        $coercedIsSigned = [int64]$rawIsSigned -eq 1
                    }
                    catch {
                        Write-Log -Level 'Debug' -Message "ImportArtifacts: Failed to coerce IsSigned '$rawIsSigned' for '$($artifactRecord.FileName)' ($SourceType); defaulting to false."
                        $coercedIsSigned = $false
                    }
                }

                if ($artifactRecord.PSObject.Properties['IsSigned']) {
                    $artifactRecord.IsSigned = $coercedIsSigned
                }
                else {
                    $artifactRecord | Add-Member -NotePropertyName 'IsSigned' -NotePropertyValue $coercedIsSigned -Force
                }

                $rawSizeBytes = $null
                $rawFileSize = $null
                if ($artifactRecord.PSObject.Properties['SizeBytes']) {
                    $rawSizeBytes = $artifactRecord.SizeBytes
                }
                if ($artifactRecord.PSObject.Properties['FileSize']) {
                    $rawFileSize = $artifactRecord.FileSize
                }

                $resolvedSizeBytes = $null
                $hasResolvedSize = $false

                if ($null -ne $rawSizeBytes -and -not [string]::IsNullOrWhiteSpace([string]$rawSizeBytes)) {
                    try {
                        $resolvedSizeBytes = [int64]$rawSizeBytes
                        $hasResolvedSize = $true
                    }
                    catch {
                        Write-Log -Level 'Debug' -Message "ImportArtifacts: Invalid SizeBytes '$rawSizeBytes' for '$($artifactRecord.FileName)' ($SourceType); trying FileSize fallback."
                    }
                }

                if (-not $hasResolvedSize -and $null -ne $rawFileSize -and -not [string]::IsNullOrWhiteSpace([string]$rawFileSize)) {
                    try {
                        $resolvedSizeBytes = [int64]$rawFileSize
                        $hasResolvedSize = $true
                    }
                    catch {
                        Write-Log -Level 'Warning' -Message "ImportArtifacts: Failed to coerce FileSize '$rawFileSize' to SizeBytes for '$($artifactRecord.FileName)' ($SourceType)."
                    }
                }

                if ($hasResolvedSize) {
                    if ($artifactRecord.PSObject.Properties['SizeBytes']) {
                        $artifactRecord.SizeBytes = $resolvedSizeBytes
                    }
                    else {
                        $artifactRecord | Add-Member -NotePropertyName 'SizeBytes' -NotePropertyValue $resolvedSizeBytes -Force
                    }
                }

                if (-not $artifactRecord.PSObject.Properties['PublisherName']) {
                    $publisherNameValue = if ($artifactRecord.PSObject.Properties['Publisher']) { [string]$artifactRecord.Publisher } else { '' }
                    $artifactRecord | Add-Member -NotePropertyName 'PublisherName' -NotePropertyValue $publisherNameValue -Force
                }

                if (-not $artifactRecord.PSObject.Properties['SignerCertificate']) {
                    $signerCertificateValue = if ($artifactRecord.PSObject.Properties['Signer']) { [string]$artifactRecord.Signer } else { '' }
                    $artifactRecord | Add-Member -NotePropertyName 'SignerCertificate' -NotePropertyValue $signerCertificateValue -Force
                }

                return $artifactRecord
            }
            
            foreach ($filePath in $dialog.FileNames) {
                $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
                
                $artifacts = switch ($extension) {
                    '.csv' {
                        $csvData = @(Import-Csv -Path $filePath)
                        $normalizedArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()

                        foreach ($item in $csvData) {
                            $normalizedArtifact = & $normalizeImportedArtifact -Artifact $item -SourceType 'CSV'
                            if ($null -ne $normalizedArtifact) {
                                [void]$normalizedArtifacts.Add($normalizedArtifact)
                            }
                        }
                        $normalizedArtifacts.ToArray()
                    }
                    '.json' {
                        $jsonData = @(Get-Content -Path $filePath -Raw | ConvertFrom-Json)
                        $normalizedArtifacts = [System.Collections.Generic.List[PSCustomObject]]::new()

                        foreach ($item in $jsonData) {
                            $normalizedArtifact = & $normalizeImportedArtifact -Artifact $item -SourceType 'JSON'
                            if ($null -ne $normalizedArtifact) {
                                [void]$normalizedArtifacts.Add($normalizedArtifact)
                            }
                        }

                        $normalizedArtifacts.ToArray()
                    }
                    default { throw "Unsupported file format: $extension" }
                }
                
                foreach ($a in $artifacts) { [void]$allArtifacts.Add($a) }
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
                        [void]$newArtifacts.Add($a)
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
            $signed = @($script:CurrentScanArtifacts | Where-Object { $_.IsSigned }).Count
            $unsigned = $script:CurrentScanArtifacts.Count - $signed
            
            $countLabel = $Window.FindName('ScanArtifactCount')
            if ($countLabel) { $countLabel.Text = "$($script:CurrentScanArtifacts.Count) artifacts" }
            
            $preGen = $Window.FindName('TxtArtifactCountPreGen')
            if ($preGen) { $preGen.Text = "$($script:CurrentScanArtifacts.Count)" }
            
            $signedLabel = $Window.FindName('ScanSignedCount')
            if ($signedLabel) { $signedLabel.Text = "$signed" }
            
            $unsignedLabel = $Window.FindName('ScanUnsignedCount')
            if ($unsignedLabel) { $unsignedLabel.Text = "$unsigned" }
            
            $statusLabel = $Window.FindName('ScanStatusLabel')
            if ($statusLabel) {
                $statusLabel.Text = $statusText
                $statusLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
            }

            Show-Toast -Message $messageText -Type 'Success'
        }
        catch {
            Show-Toast -Message "Import failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function global:Invoke-ExportArtifacts {
    param($Window)

    # Get artifacts from DataGrid (respects current filters)
    $dataGrid = $Window.FindName('ArtifactDataGrid')
    $artifacts = if ($dataGrid -and $dataGrid.ItemsSource) {
        @($dataGrid.ItemsSource)
    } else {
        @()
    }
    
    if ($artifacts.Count -eq 0) {
        Show-Toast -Message 'No artifacts to export. Run a scan or adjust filters.' -Type 'Warning'
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
            
            # Export canonical artifact contract fields (keep aligned with scan CSV output).
            $exportFields = @(
                'FileName', 'FilePath', 'Extension', 'ArtifactType', 'CollectionType',
                'Publisher', 'PublisherName', 'ProductName', 'ProductVersion', 'FileVersion',
                'IsSigned', 'SignerCertificate', 'SignatureStatus',
                'SHA256Hash', 'FileSize', 'SizeBytes', 'ComputerName'
            )
            $exportData = $artifacts | Select-Object -Property $exportFields
            
            switch ($extension) {
                '.csv' { $exportData | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8 }
                '.json' { $exportData | ConvertTo-Json -Depth 5 | Set-Content -Path $dialog.FileName -Encoding UTF8 }
            }

            $totalCount = if ($script:CurrentScanArtifacts) { $script:CurrentScanArtifacts.Count } else { 0 }
            $filterInfo = if ($artifacts.Count -lt $totalCount) { " (filtered from $totalCount total)" } else { "" }
            
            Show-Toast -Message "Exported $($artifacts.Count) artifacts$filterInfo to $($dialog.FileName)" -Type 'Success'
        }
        catch {
            Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
        }
    }
}

function Invoke-BrowseScanPath {
    param($Window)

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
    param($Window)

    if ($script:DiscoveredMachines.Count -eq 0) {
        $confirm = Show-AppLockerMessageBox "No machines discovered. Would you like to navigate to AD Discovery to scan for machines?" 'No Machines' 'YesNo' 'Question'
        if ($confirm -eq 'Yes') { Set-ActivePanel -PanelName 'PanelDiscovery' }
        return
    }

    $availableMachines = @($script:DiscoveredMachines | Where-Object { $_.WinRMStatus -eq 'Available' })
    if ($availableMachines.Count -eq 0) {
        $msg = "No machines with WinRM available.`n`nRun Test Connectivity in AD Discovery and ensure WinRM is enabled on targets."
        $confirm = Show-AppLockerMessageBox $msg 'No WinRM Targets' 'YesNo' 'Question'
        if ($confirm -eq 'Yes') {
            Set-ActivePanel -PanelName 'PanelDiscovery'
            try { Invoke-ButtonAction -Action 'TestConnectivity' } catch { }
        }
        return
    }

    # First check if any machines are checked in the Discovery DataGrid
    $checkedMachines = Get-CheckedMachines -Window $Window
    if ($checkedMachines.Count -gt 0) {
        # Use the checked machines directly -- only WinRM available
        $selectedMachines = @($checkedMachines | Where-Object { $_.WinRMStatus -eq 'Available' })
        if ($selectedMachines.Count -eq 0) {
            $msg = "Selected machines do not have WinRM available.`n`nRun Test Connectivity in AD Discovery and select WinRM-available machines."
            $confirm = Show-AppLockerMessageBox $msg 'No WinRM Targets' 'YesNo' 'Question'
            if ($confirm -eq 'Yes') {
                Set-ActivePanel -PanelName 'PanelDiscovery'
                try { Invoke-ButtonAction -Action 'TestConnectivity' } catch { }
            }
            return
        }
    }
    else {
        # No checkboxes checked -- fall back to selection dialog with WinRM-available machines
        $selectedMachines = Show-MachineSelectionDialog -ParentWindow $Window -Machines $availableMachines
    }
    
    if ($null -eq $selectedMachines) { return }
    # Ensure we have an array of valid machine objects with Hostname
    $script:SelectedScanMachines = @($selectedMachines | Where-Object {
        $_ -ne $null -and
        $_.PSObject -ne $null -and
        $_.PSObject.Properties.Name -contains 'Hostname'
    })
    if ($script:SelectedScanMachines.Count -eq 0) { return }

    $machineList = $Window.FindName('ScanMachineList')
    $machineCount = $Window.FindName('ScanMachineCount')

    if ($machineList) {
        $machineList.ItemsSource = @($script:SelectedScanMachines | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'Hostname') { $_.Hostname }
            elseif ($_.PSObject.Properties.Name -contains 'Name') { $_.Name }
            else { "$_" }
        })
    }
    if ($machineCount) { $machineCount.Text = "$($script:SelectedScanMachines.Count)" }

    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) { $chkRemote.IsChecked = $true }

    Show-Toast -Message "Selected $($script:SelectedScanMachines.Count) machines for scanning" -Type 'Success'
}

function global:Invoke-RemoveScanMachines {
    <#
    .SYNOPSIS
        Removes selected machines from the Scanner machine list.
        Supports Shift+Click and Ctrl+Click multi-select (SelectionMode=Extended).
    #>
    param($Window)

    $machineList = $Window.FindName('ScanMachineList')
    if (-not $machineList -or $machineList.SelectedItems.Count -eq 0) {
        Show-Toast -Message 'No machines selected. Use Ctrl+Click or Shift+Click to select machines to remove.' -Type 'Info'
        return
    }

    # Collect hostnames to remove (copy since SelectedItems changes during removal)
    $toRemove = @($machineList.SelectedItems)

    # Remove from the backing data
    $script:SelectedScanMachines = @($script:SelectedScanMachines | Where-Object {
        $hostname = if ($_.PSObject.Properties.Name -contains 'Hostname') { $_.Hostname }
                    elseif ($_.PSObject.Properties.Name -contains 'Name') { $_.Name }
                    else { "$_" }
        $hostname -notin $toRemove
    })

    # Update ListBox
    if ($script:SelectedScanMachines.Count -gt 0) {
        $machineList.ItemsSource = @($script:SelectedScanMachines | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'Hostname') { $_.Hostname }
            elseif ($_.PSObject.Properties.Name -contains 'Name') { $_.Name }
            else { "$_" }
        })
    } else {
        $machineList.ItemsSource = $null
    }

    # Update count
    $machineCount = $Window.FindName('ScanMachineCount')
    if ($machineCount) { $machineCount.Text = "$($script:SelectedScanMachines.Count)" }

    # Uncheck remote scan if no machines left
    if ($script:SelectedScanMachines.Count -eq 0) {
        $chkRemote = $Window.FindName('ChkScanRemote')
        if ($chkRemote) { $chkRemote.IsChecked = $false }
    }

    Show-Toast -Message "Removed $($toRemove.Count) machine(s). $($script:SelectedScanMachines.Count) remaining." -Type 'Info'
}

function global:Invoke-ClearScanMachines {
    <#
    .SYNOPSIS
        Clears all machines from the Scanner machine list.
    #>
    param($Window)

    if ($script:SelectedScanMachines.Count -eq 0) {
        Show-Toast -Message 'Machine list is already empty.' -Type 'Info'
        return
    }

    $removedCount = $script:SelectedScanMachines.Count
    $script:SelectedScanMachines = @()

    $machineList = $Window.FindName('ScanMachineList')
    if ($machineList) { $machineList.ItemsSource = $null }

    $machineCount = $Window.FindName('ScanMachineCount')
    if ($machineCount) { $machineCount.Text = "0" }

    # Uncheck remote scan
    $chkRemote = $Window.FindName('ChkScanRemote')
    if ($chkRemote) { $chkRemote.IsChecked = $false }

    Show-Toast -Message "Cleared $removedCount machine(s) from scan list." -Type 'Info'
}

# Legacy function removed - use Rule Generation Wizard for deduplication
# Was: Invoke-DedupeArtifacts

# Legacy function removed - use Rule Generation Wizard for exclusions
# Was: Invoke-ApplyArtifactExclusions

#endregion

#region ===== SCHEDULED SCANS =====
function global:Initialize-ScheduledScansList {
    <#
    .SYNOPSIS
        Loads scheduled scans into the ScheduledScansList ListBox.
    #>
    param($Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox) { return }
    
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
    param($Window)
    
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
    param($Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to run.' -Type 'Warning'
        return
    }
    
    $selectedSchedule = $listBox.SelectedItem
    $scheduleId = $selectedSchedule.ScheduleId
    $scheduleName = $selectedSchedule.Name
    
    $confirm = Show-AppLockerMessageBox "Run scheduled scan '$scheduleName' now?" 'Confirm Run' 'YesNo' 'Question'
    
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
    param($Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to delete.' -Type 'Warning'
        return
    }
    
    $selectedSchedule = $listBox.SelectedItem
    $scheduleId = $selectedSchedule.ScheduleId
    $scheduleName = $selectedSchedule.Name
    
    $confirm = Show-AppLockerMessageBox "Are you sure you want to delete scheduled scan '$scheduleName'?`n`nThis will also remove the Windows Task Scheduler task." 'Confirm Delete' 'YesNo' 'Warning'
    
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
    param($Window)
    
    $listBox = $Window.FindName('ScheduledScansList')
    if (-not $listBox -or -not $listBox.SelectedItem) {
        Show-Toast -Message 'Please select a scheduled scan to toggle.' -Type 'Warning'
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
    param($Window)
    
    if (-not $script:CurrentScanArtifacts -or $script:CurrentScanArtifacts.Count -eq 0) {
        Show-Toast -Message "No artifacts available. Run a scan first." -Type 'Warning'
        return
    }
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Write-Log -Message "Launching Rule Generation Wizard with $artifactCount artifacts"
    
    # Check if wizard overlay exists in XAML (not just the PS function)
    $wizardOverlay = $Window.FindName('RuleWizardOverlay')
    
    if ($wizardOverlay) {
        # Launch the 3-step wizard UI (use try-catch - Get-Command fails in WPF context)
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
        Width="480" Height="620"
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
                <ComboBoxItem Content="Publisher + Product + File" Tag="PublisherProductFile"/>
                <ComboBoxItem Content="Publisher Only" Tag="PublisherOnly"/>
                <ComboBoxItem Content="Exact (All fields)" Tag="Exact"/>
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
                <ComboBoxItem Content="AppLocker-Users" Tag="RESOLVE:AppLocker-Users" IsSelected="True"/>
                <ComboBoxItem Content="AppLocker-Admins" Tag="RESOLVE:AppLocker-Admins"/>
                <ComboBoxItem Content="AppLocker-Exempt" Tag="RESOLVE:AppLocker-Exempt"/>
                <ComboBoxItem Content="AppLocker-Audit" Tag="RESOLVE:AppLocker-Audit"/>
                <ComboBoxItem Content="AppLocker-Installers" Tag="RESOLVE:AppLocker-Installers"/>
                <ComboBoxItem Content="AppLocker-Developers" Tag="RESOLVE:AppLocker-Developers"/>
                <ComboBoxItem Content="Everyone" Tag="S-1-1-0"/>
                <ComboBoxItem Content="Authenticated Users" Tag="S-1-5-11"/>
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
            
            <!-- Exclusions -->
            <TextBlock Text="Exclusions" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,8"/>
            <StackPanel Margin="0,0,0,15">
                <CheckBox x:Name="ChkSkipDlls" Content="Skip DLLs (Library files)" Foreground="{StaticResource FgBrush}" Margin="0,0,0,6" IsChecked="True"/>
                <CheckBox x:Name="ChkSkipWshScripts" Content="Skip WSH Scripts (.js, .vbs, .wsf)" Foreground="{StaticResource FgBrush}" Margin="0,0,0,6" IsChecked="True"/>
                <CheckBox x:Name="ChkSkipShellScripts" Content="Skip Shell Scripts (.ps1, .bat, .cmd)" Foreground="{StaticResource FgBrush}" Margin="0,0,0,6"/>
                <CheckBox x:Name="ChkSkipUnsigned" Content="Skip Unsigned files entirely" Foreground="{StaticResource FgBrush}" Margin="0,0,0,0"/>
            </StackPanel>
            
            <!-- Initial Status -->
            <TextBlock Text="Initial Status" Foreground="{StaticResource FgBrush}" FontWeight="SemiBold" Margin="0,0,0,5"/>
            <ComboBox x:Name="CboStatus" Background="{StaticResource ControlBg}" Foreground="{StaticResource FgBrush}" 
                      BorderBrush="{StaticResource BorderBrush}" Padding="8,6" Margin="0,0,0,10">
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
        $chkSkipDlls = $dialog.FindName('ChkSkipDlls')
        $chkSkipWshScripts = $dialog.FindName('ChkSkipWshScripts')
        $chkSkipShellScripts = $dialog.FindName('ChkSkipShellScripts')
        $chkSkipUnsigned = $dialog.FindName('ChkSkipUnsigned')
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
            $rawSid = $cboTargetGroup.SelectedItem.Tag
            $result.TargetSid = if ($rawSid) { $rawSid.ToString() } else { 'S-1-5-11' }
            $result.UnsignedMode = $cboUnsignedMode.SelectedItem.Tag
            $result.Status = $cboStatus.SelectedItem.Tag
            $result.SkipDlls = $chkSkipDlls.IsChecked
            $result.SkipWshScripts = $chkSkipWshScripts.IsChecked
            $result.SkipShellScripts = $chkSkipShellScripts.IsChecked
            $result.SkipUnsigned = $chkSkipUnsigned.IsChecked
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
        Runs in a background runspace via Invoke-BackgroundWork to prevent UI freeze.
    #>
    param(
        $Window,
        [PSCustomObject]$Settings
    )
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Write-Log -Message "Starting batch rule generation for $artifactCount artifacts"

    # Stash in $global: for background runspace and OnComplete callback
    $global:GA_RuleGen_Window = $Window
    $modulePath = (Get-Module GA-AppLocker).ModuleBase

    # Background: import only needed sub-modules, run batch generation
    $bgWork = {
        param($ModulePath, $Artifacts, $GenSettings)
        
        # Import only the sub-modules needed for rule generation
        $modulesDir = Join-Path $ModulePath 'Modules'
        $requiredModules = @('GA-AppLocker.Core', 'GA-AppLocker.Storage', 'GA-AppLocker.Rules')
        foreach ($mod in $requiredModules) {
            $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
            if (Test-Path $modPath) { Import-Module $modPath -Force -ErrorAction Stop }
        }

        $resolvedSid = if ($GenSettings.TargetSid) { [string]$GenSettings.TargetSid } else { 'S-1-5-11' }
        if ($resolvedSid.StartsWith('RESOLVE:')) {
            try { $resolvedSid = Resolve-GroupSid -GroupName $resolvedSid } catch { }
        }

        $genParams = @{
            Artifacts      = $Artifacts
            Mode           = 'Smart'
            Action         = $GenSettings.Action
            Status         = $GenSettings.Status
            DedupeMode     = 'Smart'
            PublisherLevel = $GenSettings.PublisherLevel
            UserOrGroupSid = $resolvedSid
            UnsignedMode   = $GenSettings.UnsignedMode
        }
        if ($GenSettings.SkipDlls) { $genParams['SkipDlls'] = $true }
        if ($GenSettings.SkipWshScripts) { $genParams['SkipWshScripts'] = $true }
        if ($GenSettings.SkipShellScripts) { $genParams['SkipShellScripts'] = $true }
        if ($GenSettings.SkipUnsigned) { $genParams['SkipUnsigned'] = $true }

        return Invoke-BatchRuleGeneration @genParams
    }

    $onComplete = {
        param($result)
        $win = $global:GA_RuleGen_Window
        if ($result -and $result.RulesCreated -ne $null) {
            $msg = "Created $($result.RulesCreated) rules"
            if ($result.AlreadyExisted -gt 0) { $msg += " ($($result.AlreadyExisted) already existed)" }
            Show-Toast -Message $msg -Type 'Success'
        }
        else {
            Show-Toast -Message 'Rule generation completed.' -Type 'Info'
        }
        try { Refresh-RulesPanelAfterGeneration -Window $win -Navigate } catch {
            try { Set-ActivePanel -PanelName 'PanelRules' } catch { }
            try { Update-RulesDataGrid -Window $win } catch { }
        }
        $global:GA_RuleGen_Window = $null
    }

    Invoke-BackgroundWork -ScriptBlock $bgWork `
        -ArgumentList @($modulePath, $script:CurrentScanArtifacts, $Settings) `
        -OnComplete $onComplete `
        -NoLoadingOverlay `
        -LoadingMessage 'Generating Rules...' `
        -LoadingSubMessage "Processing $artifactCount artifacts..." `
        -TimeoutSeconds 300
}

function global:Invoke-DirectRuleGeneration {
    <#
    .SYNOPSIS
        Generates rules directly without wizard UI. Called after user confirmation.
        Runs in background via Invoke-BackgroundWork to prevent UI freeze.
    #>
    param($Window)
    
    $artifactCount = $script:CurrentScanArtifacts.Count
    Write-Log -Message "Starting batch rule generation for $artifactCount artifacts"

    # Read UI settings on the UI thread (WPF controls can only be accessed here)
    $pubLevelCombo = $Window.FindName('CboPublisherLevel')
    $publisherLevel = if ($pubLevelCombo -and $pubLevelCombo.SelectedItem -and $pubLevelCombo.SelectedItem.Tag) {
        $pubLevelCombo.SelectedItem.Tag
    } else { 'PublisherProduct' }

    $rbAllow = $Window.FindName('RbRuleAllow')
    $action = if ($rbAllow -and $rbAllow.IsChecked) { 'Allow' } else { 'Deny' }

    $targetCombo = $Window.FindName('CboRuleTargetGroup')
    $targetSid = if ($targetCombo -and $targetCombo.SelectedItem -and $targetCombo.SelectedItem.Tag) {
        $targetCombo.SelectedItem.Tag
    } else { 'S-1-5-11' }

    $unsignedCombo = $Window.FindName('CboUnsignedMode')
    $unsignedMode = if ($unsignedCombo -and $unsignedCombo.SelectedItem -and $unsignedCombo.SelectedItem.Tag) {
        $unsignedCombo.SelectedItem.Tag
    } else { 'Hash' }

    $global:GA_RuleGen_Window = $Window
    $modulePath = (Get-Module GA-AppLocker).ModuleBase

    $bgWork = {
        param($ModulePath, $Artifacts, $Action, $PublisherLevel, $TargetSid, $UnsignedMode)

        $modulesDir = Join-Path $ModulePath 'Modules'
        foreach ($mod in @('GA-AppLocker.Core', 'GA-AppLocker.Storage', 'GA-AppLocker.Rules')) {
            $modPath = Join-Path $modulesDir "$mod\$mod.psd1"
            if (Test-Path $modPath) { Import-Module $modPath -Force -ErrorAction Stop }
        }

        $resolvedSid = if ($TargetSid) { [string]$TargetSid } else { 'S-1-5-11' }
        if ($resolvedSid.StartsWith('RESOLVE:')) {
            try { $resolvedSid = Resolve-GroupSid -GroupName $resolvedSid } catch { }
        }

        return Invoke-BatchRuleGeneration -Artifacts $Artifacts `
            -Mode 'Smart' -Action $Action -Status 'Pending' -DedupeMode 'Smart' `
            -PublisherLevel $PublisherLevel -UserOrGroupSid $resolvedSid -UnsignedMode $UnsignedMode
    }

    $onComplete = {
        param($result)
        $win = $global:GA_RuleGen_Window
        if ($result -and $result.RulesCreated -ne $null) {
            $msg = "Created $($result.RulesCreated) rules"
            if ($result.AlreadyExisted -gt 0) { $msg += " ($($result.AlreadyExisted) already existed)" }
            Show-Toast -Message $msg -Type 'Success'
        }
        else {
            Show-Toast -Message 'Rule generation completed.' -Type 'Info'
        }
        try { Refresh-RulesPanelAfterGeneration -Window $win -Navigate } catch {
            try { Set-ActivePanel -PanelName 'PanelRules' } catch { }
            try { Update-RulesDataGrid -Window $win } catch { }
        }
        $global:GA_RuleGen_Window = $null
    }

    Invoke-BackgroundWork -ScriptBlock $bgWork `
        -ArgumentList @($modulePath, $script:CurrentScanArtifacts, $action, $publisherLevel, $targetSid, $unsignedMode) `
        -OnComplete $onComplete `
        -NoLoadingOverlay `
        -LoadingMessage 'Generating Rules...' `
        -LoadingSubMessage "Processing $artifactCount artifacts..." `
        -TimeoutSeconds 300
}
#endregion
#endregion
