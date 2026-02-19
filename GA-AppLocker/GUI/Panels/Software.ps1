#region Software Inventory Panel Functions
# Software.ps1 - Installed software scanning, CSV export/import, and cross-system comparison

# Script-level state for this panel
$script:SoftwareInventory = @()       # Current scan/imported data shown in DataGrid
$script:SoftwareImportedData = @()    # Imported CSV data for comparison
$script:SoftwareImportedFile = ''     # Name of imported file
$script:CurrentSoftwareSourceFilter = 'All'  # Source filter for comparison results

function Initialize-SoftwarePanel {
    param($Window)

    # Wire up sidebar buttons via Tag -> Invoke-ButtonAction
    $buttons = @(
        'BtnScanLocalSoftware', 'BtnScanRemoteSoftware',
        'BtnExportSoftwareCsv',
        'BtnImportBaseline', 'BtnImportComparison',
        'BtnCompareSoftware', 'BtnClearComparison',
        'BtnExportComparisonCsv'
    )
    foreach ($btnName in $buttons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $tagValue = $btn.Tag.ToString()
            $btn.Add_Click({ Invoke-ButtonAction -Action $tagValue }.GetNewClosure())
        }
    }

    # Wire up source filter buttons
    $sourceFilterButtons = @(
        'BtnFilterSoftwareAll', 'BtnFilterSoftwareMatch', 'BtnFilterSoftwareVersionDiff',
        'BtnFilterSoftwareOnlyScan', 'BtnFilterSoftwareOnlyImport'
    )
    foreach ($btnName in $sourceFilterButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            $btn.Add_Click({
                param($sender, $e)
                $tag = $sender.Tag
                if ($tag -match 'FilterSoftware(.+)') {
                    $filter = $Matches[1]
                    Update-SoftwareSourceFilter -Window $global:GA_MainWindow -Filter $filter
                }
            }.GetNewClosure())
        }
    }

    # Wire up text filter with debounce
    $filterBox = $Window.FindName('TxtSoftwareFilter')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
            Update-SoftwareDataGrid -Window $global:GA_MainWindow
        })
    }

    # Wire up remote machine textbox to show live count
    $remoteMachineBox = $Window.FindName('TxtSoftwareRemoteMachines')
    if ($remoteMachineBox) {
        $remoteMachineBox.Add_TextChanged({
            $machineBox = $global:GA_MainWindow.FindName('TxtSoftwareRemoteMachines')
            $hint = $global:GA_MainWindow.FindName('TxtSoftwareMachineHint')
            if ($machineBox -and $hint) {
                $parsed = @(Get-SoftwareRemoteMachineList -Window $global:GA_MainWindow)
                if ($parsed.Count -gt 0) {
                    $hint.Text = "$($parsed.Count) machine(s): $($parsed[0..2] -join ', ')$(if ($parsed.Count -gt 3) { '...' })"
                } else {
                    $scanCount = @($script:SelectedScanMachines).Count
                    if ($scanCount -gt 0) {
                        $hint.Text = "Empty -- will use Scanner list ($scanCount machines)"
                    } else {
                        $hint.Text = '0 machines'
                    }
                }
            }
        })
    }
}

#region ===== SCAN FUNCTIONS =====

function script:Get-SoftwareRemoteMachineList {
    <#
    .SYNOPSIS
        Parses the remote machine textbox into a list of hostnames.
        Falls back to $script:SelectedScanMachines (Scanner panel list) if textbox is empty.
    #>
    param($Window)

    $machineBox = $Window.FindName('TxtSoftwareRemoteMachines')
    $rawText = if ($machineBox) { $machineBox.Text } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($rawText)) {
        # Parse: split by newlines, commas, semicolons, then trim and deduplicate
        $parsed = @($rawText -split '[,;\r\n]+' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Sort-Object -Unique)
        return $parsed
    }

    # Fallback: Scanner panel machine list
    $scanMachines = @($script:SelectedScanMachines)
    if ($scanMachines.Count -gt 0) {
        $hostnames = @($scanMachines | ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.Hostname }
        })
        return $hostnames
    }

    return @()
}

function global:Invoke-ScanLocalSoftware {
    <#
    .SYNOPSIS
        Scans installed software on the local machine via registry.
    #>
    param($Window)

    if ($script:SoftwareLocalScanInProgress) {
        Show-Toast -Message 'A local software scan is already in progress.' -Type 'Warning'
        return
    }

    $script:SoftwareLocalScanInProgress = $true
    Show-LoadingOverlay -Message 'Scanning installed software...' -SubMessage $env:COMPUTERNAME
    try { Request-UiRender -Window $Window } catch { Write-AppLockerLog -Message "[Software] Failed to request UI render before local software scan: $_" -Level DEBUG }

    $script:SoftwareLocalSyncHash = [hashtable]::Synchronized(@{
            Window     = $Window
            Hostname   = $env:COMPUTERNAME
            Result     = $null
            Error      = $null
            IsComplete = $false
            StatusText = 'Reading installed software...'
        })

    $script:SoftwareLocalRunspace = [runspacefactory]::CreateRunspace()
    $script:SoftwareLocalRunspace.ApartmentState = 'STA'
    $script:SoftwareLocalRunspace.ThreadOptions = 'ReuseThread'
    $script:SoftwareLocalRunspace.Open()

    $script:SoftwareLocalPowerShell = [powershell]::Create()
    $script:SoftwareLocalPowerShell.Runspace = $script:SoftwareLocalRunspace

    [void]$script:SoftwareLocalPowerShell.AddScript({
        param($SyncHash)

        try {
            $machineName = $SyncHash.Hostname
            $SyncHash.StatusText = "Reading uninstall registry on $machineName..."

            $paths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            $results = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($item in (Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' })) {
                [void]$results.Add([PSCustomObject]@{
                    Machine         = $machineName
                    DisplayName     = $item.DisplayName
                    DisplayVersion  = if ($item.DisplayVersion) { $item.DisplayVersion } else { '' }
                    Publisher       = if ($item.Publisher) { $item.Publisher } else { '' }
                    InstallDate     = if ($item.InstallDate) { $item.InstallDate } else { '' }
                    InstallLocation = if ($item.InstallLocation) { $item.InstallLocation } else { '' }
                    Architecture    = if ($item.PSPath -like '*WOW6432*') { 'x86' } else { 'x64' }
                    Source          = 'Local'
                })
            }

            $SyncHash.StatusText = 'Reading installed roles/features...'
            try {
                if (Get-Command 'Get-WindowsFeature' -ErrorAction SilentlyContinue) {
                    $features = @(Get-WindowsFeature -ErrorAction SilentlyContinue | Where-Object { $_.Installed })
                    foreach ($feat in $features) {
                        [void]$results.Add([PSCustomObject]@{
                            Machine         = $machineName
                            DisplayName     = "[Role/Feature] $($feat.DisplayName)"
                            DisplayVersion  = ''
                            Publisher       = 'Microsoft'
                            InstallDate     = ''
                            InstallLocation = ''
                            Architecture    = if ($feat.FeatureType -eq 'Role') { 'Role' } else { 'Feature' }
                            Source          = 'Local'
                        })
                    }
                }
            }
            catch { Write-AppLockerLog -Message "[Software] Failed to enumerate installed Windows roles/features: $_" -Level DEBUG }

            $sorted = @($results | Sort-Object DisplayName)
            $SyncHash.Result = $sorted
            $SyncHash.StatusText = "Found $($sorted.Count) programs"
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
        }
    })

    [void]$script:SoftwareLocalPowerShell.AddArgument($script:SoftwareLocalSyncHash)
    $script:SoftwareLocalAsyncResult = $script:SoftwareLocalPowerShell.BeginInvoke()

    $script:SoftwareLocalTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SoftwareLocalTimer.Interval = [TimeSpan]::FromMilliseconds(250)

    $script:SoftwareLocalTimer.Add_Tick({
        $syncHash = $script:SoftwareLocalSyncHash
        $win = $syncHash.Window

        Show-LoadingOverlay -Message 'Scanning installed software...' -SubMessage $syncHash.StatusText

        if ($syncHash.IsComplete) {
            $script:SoftwareLocalTimer.Stop()

            try { $script:SoftwareLocalPowerShell.EndInvoke($script:SoftwareLocalAsyncResult) } catch { Write-AppLockerLog -Message "Software local EndInvoke cleanup: $($_.Exception.Message)" -Level 'DEBUG' }
            if ($script:SoftwareLocalPowerShell) { $script:SoftwareLocalPowerShell.Dispose() }
            if ($script:SoftwareLocalRunspace) {
                $script:SoftwareLocalRunspace.Close()
                $script:SoftwareLocalRunspace.Dispose()
            }

            Hide-LoadingOverlay
            $script:SoftwareLocalScanInProgress = $false

            if ($syncHash.Error) {
                Write-AppLockerLog -Message "Local software scan failed: $($syncHash.Error)" -Level 'ERROR'
                Show-Toast -Message "Scan failed: $($syncHash.Error)" -Type 'Error'
                return
            }

            $results = @($syncHash.Result)
            $script:SoftwareInventory = $results

            Update-SoftwareDataGrid -Window $win
            Update-SoftwareStats -Window $win

            $statusText = $win.FindName('TxtSoftwareStatus')
            if ($statusText) { $statusText.Text = "Scanned $($results.Count) programs on $($syncHash.Hostname)" }

            $lastScan = $win.FindName('TxtSoftwareLastScan')
            if ($lastScan) { $lastScan.Text = "$($syncHash.Hostname) - $(Get-Date -Format 'MM/dd HH:mm')" }

            $baselineFile = $win.FindName('TxtSoftwareBaselineFile')
            if ($baselineFile) { $baselineFile.Text = "Scan: $($syncHash.Hostname) ($($results.Count) items)" }

            try {
                $appDataPath = Get-AppLockerDataPath
                $scansFolder = [System.IO.Path]::Combine($appDataPath, 'Scans')
                if (-not [System.IO.Directory]::Exists($scansFolder)) {
                    [System.IO.Directory]::CreateDirectory($scansFolder) | Out-Null
                }
                $dateSuffix = (Get-Date).ToString('ddMMMyy').ToUpper()
                $csvName = "$($syncHash.Hostname)_softwarelist_${dateSuffix}.csv"
                $csvPath = [System.IO.Path]::Combine($scansFolder, $csvName)
                $results |
                    Select-Object Machine, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, Architecture, Source |
                    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                Write-AppLockerLog -Message "Auto-saved software list: $csvName" -Level 'INFO'
            }
            catch {
                Write-AppLockerLog -Message "Failed to auto-save local CSV: $($_.Exception.Message)" -Level 'ERROR'
            }

            Show-Toast -Message "Found $($results.Count) installed programs on local machine. CSV saved to Scans folder." -Type 'Success'
        }
    })

    $script:SoftwareLocalTimer.Start()
}

function global:Invoke-ScanRemoteSoftware {
    <#
    .SYNOPSIS
        Scans installed software on remote machines via WinRM (background runspace).
    #>
    param($Window)

    $hostnames = @(Get-SoftwareRemoteMachineList -Window $Window)
    if ($hostnames.Count -eq 0) {
        Show-Toast -Message "No remote machines specified. Add machines from AD Discovery or type hostnames in Remote Machines." -Type 'Warning'
        return
    }

    Show-LoadingOverlay -Message "Scanning software on $($hostnames.Count) machine(s)..." -SubMessage ($hostnames[0..2] -join ', ')

    # Get credential on UI thread (needs access to DPAPI)
    $cred = $null
    foreach ($tryTier in @(2, 1, 0)) {
        try {
            $credResult = Get-CredentialForTier -Tier $tryTier
            if ($credResult.Success -and $credResult.Data) {
                $cred = $credResult.Data
                break
            }
        } catch { Write-AppLockerLog -Message "Failed to get credential for tier $tryTier`: $($_.Exception.Message)" -Level 'DEBUG' }
    }

    # Build synchronized hashtable for cross-thread communication
    $script:SoftwareSyncHash = [hashtable]::Synchronized(@{
        Window     = $Window
        Hostnames  = $hostnames
        Credential = $cred
        Result     = $null
        Error      = $null
        IsComplete = $false
        StatusText = 'Initializing...'
    })

    # Create background runspace
    $script:SoftwareRunspace = [runspacefactory]::CreateRunspace()
    $script:SoftwareRunspace.ApartmentState = 'STA'
    $script:SoftwareRunspace.ThreadOptions = 'ReuseThread'
    $script:SoftwareRunspace.Open()
    $script:SoftwareRunspace.SessionStateProxy.SetVariable('SyncHash', $script:SoftwareSyncHash)

    $modulePath = (Get-Module GA-AppLocker).ModuleBase
    $script:SoftwareRunspace.SessionStateProxy.SetVariable('ModulePath', $modulePath)

    $script:SoftwarePowerShell = [powershell]::Create()
    $script:SoftwarePowerShell.Runspace = $script:SoftwareRunspace

    [void]$script:SoftwarePowerShell.AddScript({
        param($SyncHash, $ModulePath)

        try {
            # Import module in this runspace
            $manifestPath = Join-Path $ModulePath 'GA-AppLocker.psd1'
            if (Test-Path $manifestPath) {
                Import-Module $manifestPath -Force -ErrorAction Stop
            }

            $hostnames = $SyncHash.Hostnames
            $cred = $SyncHash.Credential
            $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            $failedHosts = [System.Collections.Generic.List[string]]::new()

            # Ensure Scans folder exists
            $scansFolder = $null
            try {
                $appDataPath = Get-AppLockerDataPath
                $scansFolder = [System.IO.Path]::Combine($appDataPath, 'Scans')
                if (-not [System.IO.Directory]::Exists($scansFolder)) {
                    [System.IO.Directory]::CreateDirectory($scansFolder) | Out-Null
                }
            } catch { Write-AppLockerLog -Message "[Software] Failed to create scans folder for remote software CSV export: $_" -Level WARN }

            $dateSuffix = (Get-Date).ToString('ddMMMyy').ToUpper()
            $hostIndex = 0

            foreach ($hostname in $hostnames) {
                $hostIndex++
                $SyncHash.StatusText = "Scanning $hostname ($hostIndex/$($hostnames.Count))..."

                try {
                    $invokeParams = @{
                        ComputerName = $hostname
                        ScriptBlock  = {
                            $items = [System.Collections.Generic.List[PSCustomObject]]::new()

                            # Registry-based installed software
                            $paths = @(
                                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                            )
                            foreach ($p in (Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                                    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' })) {
                                [void]$items.Add([PSCustomObject]@{
                                    DisplayName     = $p.DisplayName
                                    DisplayVersion  = $p.DisplayVersion
                                    Publisher        = $p.Publisher
                                    InstallDate      = $p.InstallDate
                                    InstallLocation  = $p.InstallLocation
                                    Architecture     = if ($p.PSPath -like '*WOW6432*') { 'x86' } else { 'x64' }
                                })
                            }

                            # Server Roles & Features (only available on Server OS)
                            try {
                                if (Get-Command 'Get-WindowsFeature' -ErrorAction SilentlyContinue) {
                                    foreach ($feat in (Get-WindowsFeature -ErrorAction SilentlyContinue | Where-Object { $_.Installed })) {
                                        [void]$items.Add([PSCustomObject]@{
                                            DisplayName     = "[Role/Feature] $($feat.DisplayName)"
                                            DisplayVersion  = ''
                                            Publisher        = 'Microsoft'
                                            InstallDate      = ''
                                            InstallLocation  = ''
                                            Architecture     = if ($feat.FeatureType -eq 'Role') { 'Role' } else { 'Feature' }
                                        })
                                    }
                                }
                            } catch { Write-Warning "[Software] Failed to enumerate remote Windows roles/features: $_" }

                            $items
                        }
                        ErrorAction = 'Stop'
                    }
                    if ($cred) { $invokeParams['Credential'] = $cred }

                    $remoteResults = @(Invoke-Command @invokeParams)
                    $hostResults = [System.Collections.Generic.List[PSCustomObject]]::new()
                    foreach ($item in $remoteResults) {
                        $obj = [PSCustomObject]@{
                            Machine         = $hostname
                            DisplayName     = $item.DisplayName
                            DisplayVersion  = $item.DisplayVersion
                            Publisher        = $item.Publisher
                            InstallDate      = $item.InstallDate
                            InstallLocation  = $item.InstallLocation
                            Architecture     = $item.Architecture
                            Source           = 'Remote'
                        }
                        [void]$allResults.Add($obj)
                        [void]$hostResults.Add($obj)
                    }

                    # Auto-save per-hostname CSV
                    if ($scansFolder -and $hostResults.Count -gt 0) {
                        try {
                            $csvName = "${hostname}_softwarelist_${dateSuffix}.csv"
                            $csvPath = [System.IO.Path]::Combine($scansFolder, $csvName)
                            $hostResults |
                                Select-Object Machine, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, Architecture, Source |
                                Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                        } catch { Write-AppLockerLog -Message "[Software] Failed to export software CSV for host '$hostname': $_" -Level WARN }
                    }
                }
                catch {
                    [void]$failedHosts.Add("${hostname}: $($_.Exception.Message)")
                }
            }

            $SyncHash.StatusText = 'Processing results...'
            $SyncHash.Result = @{
                AllResults  = @($allResults)
                FailedHosts = @($failedHosts)
                HostCount   = $hostnames.Count
                ScansFolder = $scansFolder
            }
        }
        catch {
            $SyncHash.Error = $_.Exception.Message
        }
        finally {
            $SyncHash.IsComplete = $true
        }
    })

    [void]$script:SoftwarePowerShell.AddArgument($script:SoftwareSyncHash)
    [void]$script:SoftwarePowerShell.AddArgument($modulePath)

    # Start async
    $script:SoftwareAsyncResult = $script:SoftwarePowerShell.BeginInvoke()

    # Poll for completion via DispatcherTimer
    $script:SoftwareTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SoftwareTimer.Interval = [TimeSpan]::FromMilliseconds(300)

    $script:SoftwareTimer.Add_Tick({
        $syncHash = $script:SoftwareSyncHash
        $win = $syncHash.Window

        # Update overlay text
        Show-LoadingOverlay -Message $syncHash.StatusText

        if ($syncHash.IsComplete) {
            $script:SoftwareTimer.Stop()

            try { $script:SoftwarePowerShell.EndInvoke($script:SoftwareAsyncResult) } catch { Write-AppLockerLog -Message "Software EndInvoke cleanup: $($_.Exception.Message)" -Level 'DEBUG' }
            if ($script:SoftwarePowerShell) { $script:SoftwarePowerShell.Dispose() }
            if ($script:SoftwareRunspace) {
                $script:SoftwareRunspace.Close()
                $script:SoftwareRunspace.Dispose()
            }

            Hide-LoadingOverlay

            if ($syncHash.Error) {
                Show-Toast -Message "Remote scan failed: $($syncHash.Error)" -Type 'Error'
                return
            }

            $r = $syncHash.Result
            $script:SoftwareInventory = $r.AllResults
            Update-SoftwareDataGrid -Window $win
            Update-SoftwareStats -Window $win

            $statusText = $win.FindName('TxtSoftwareStatus')
            if ($statusText) { $statusText.Text = "Scanned $($r.AllResults.Count) programs across $($r.HostCount) machine(s)" }

            $lastScan = $win.FindName('TxtSoftwareLastScan')
            if ($lastScan) { $lastScan.Text = "$($r.HostCount) machines - $(Get-Date -Format 'MM/dd HH:mm')" }

            # Update baseline info on Compare tab
            $baselineFile = $win.FindName('TxtSoftwareBaselineFile')
            if ($baselineFile) { $baselineFile.Text = "Scan: $($r.HostCount) machine(s) ($($r.AllResults.Count) items)" }

            if ($r.FailedHosts.Count -gt 0) {
                $failDetails = $r.FailedHosts -join "`n"
                Write-AppLockerLog -Message "Software scan partial: $($r.FailedHosts.Count) machine(s) failed.`n$failDetails" -Level 'WARN'
            }

            $toastMsg = "Found $($r.AllResults.Count) installed programs across $($r.HostCount) machine(s)."
            if ($r.ScansFolder) { $toastMsg += " CSVs saved to Scans folder." }
            $toastType = if ($r.FailedHosts.Count -gt 0) { 'Warning' } else { 'Success' }
            if ($r.FailedHosts.Count -gt 0) { $toastMsg += " Failed: $($r.FailedHosts.Count) machine(s)." }
            Show-Toast -Message $toastMsg -Type $toastType
        }
    })

    $script:SoftwareTimer.Start()
}

function script:Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Enumerates installed software from the registry (local machine).
        On Server OS, also includes installed Roles and Features.
    #>
    param([string]$MachineName = $env:COMPUTERNAME)

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in (Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' })) {
        [void]$results.Add([PSCustomObject]@{
            Machine         = $MachineName
            DisplayName     = $item.DisplayName
            DisplayVersion  = if ($item.DisplayVersion) { $item.DisplayVersion } else { '' }
            Publisher        = if ($item.Publisher) { $item.Publisher } else { '' }
            InstallDate      = if ($item.InstallDate) { $item.InstallDate } else { '' }
            InstallLocation  = if ($item.InstallLocation) { $item.InstallLocation } else { '' }
            Architecture     = if ($item.PSPath -like '*WOW6432*') { 'x86' } else { 'x64' }
            Source           = 'Local'
        })
    }

    # On Server OS, also enumerate installed Roles & Features
    try {
        if (Get-Command 'Get-WindowsFeature' -ErrorAction SilentlyContinue) {
            $features = @(Get-WindowsFeature -ErrorAction SilentlyContinue | Where-Object { $_.Installed })
            foreach ($feat in $features) {
                [void]$results.Add([PSCustomObject]@{
                    Machine         = $MachineName
                    DisplayName     = "[Role/Feature] $($feat.DisplayName)"
                    DisplayVersion  = ''
                    Publisher        = 'Microsoft'
                    InstallDate      = ''
                    InstallLocation  = ''
                    Architecture     = if ($feat.FeatureType -eq 'Role') { 'Role' } else { 'Feature' }
                    Source           = 'Local'
                })
            }
        }
    } catch { Write-AppLockerLog -Message "[Software] Failed to enumerate local Windows roles/features: $_" -Level DEBUG }

    return @($results | Sort-Object DisplayName)
}

#endregion

#region ===== CSV EXPORT / IMPORT =====

function global:Invoke-ExportSoftwareCsv {
    <#
    .SYNOPSIS
        Exports the current software inventory DataGrid to a CSV file.
    #>
    param($Window)

    if ($script:SoftwareInventory.Count -eq 0) {
        Show-Toast -Message 'No software data to export. Run a scan first.' -Type 'Warning'
        return
    }

    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Title = 'Export Software Inventory'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $dialog.DefaultExt = '.csv'

    # Default filename with machine name and date
    $machines = @($script:SoftwareInventory | ForEach-Object { $_.Machine } | Sort-Object -Unique)
    $machineLabel = if ($machines.Count -eq 1) { $machines[0] } else { "$($machines.Count)-machines" }
    $dialog.FileName = "SoftwareInventory_${machineLabel}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

    $result = $dialog.ShowDialog($Window)
    if (-not $result) { return }

    try {
        $script:SoftwareInventory |
            Select-Object Machine, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, Architecture, Source |
            Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8

        Show-Toast -Message "Exported $($script:SoftwareInventory.Count) items to CSV." -Type 'Success'
        Write-AppLockerLog -Message "Exported software inventory to: $($dialog.FileName)" -Level 'INFO'
    }
    catch {
        Write-AppLockerLog -Message "CSV export failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
    }
}

function script:Import-SoftwareCsvFile {
    <#
    .SYNOPSIS
        Shared helper: opens a CSV file dialog, validates, normalizes rows.
        Returns $null on cancel/error, or a hashtable with FileName and Data.
    #>
    param(
        $Window,
        [string]$Title = 'Import Software Inventory CSV'
    )

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = $Title
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'

    $result = $dialog.ShowDialog($Window)
    if (-not $result) { return $null }

    try {
        $imported = @(Import-Csv -Path $dialog.FileName -Encoding UTF8)

        if ($imported.Count -eq 0) {
            Show-Toast -Message 'CSV file is empty.' -Type 'Warning'
            return $null
        }

        $firstRow = $imported[0]
        if ($null -eq $firstRow.PSObject.Properties['DisplayName']) {
            Show-Toast -Message 'CSV missing required "DisplayName" column. Expected columns: Machine, DisplayName, DisplayVersion, Publisher, InstallDate, Architecture.' -Type 'Error'
            return $null
        }

        $normalized = @($imported | ForEach-Object {
            [PSCustomObject]@{
                Machine         = if ($_.Machine) { $_.Machine } else { 'Imported' }
                DisplayName     = $_.DisplayName
                DisplayVersion  = if ($_.DisplayVersion) { $_.DisplayVersion } else { '' }
                Publisher       = if ($_.Publisher) { $_.Publisher } else { '' }
                InstallDate     = if ($_.InstallDate) { $_.InstallDate } else { '' }
                InstallLocation = if ($_.InstallLocation) { $_.InstallLocation } else { '' }
                Architecture    = if ($_.Architecture) { $_.Architecture } else { '' }
                Source          = 'Imported'
            }
        })

        return @{
            FileName = [System.IO.Path]::GetFileName($dialog.FileName)
            FullPath = $dialog.FileName
            Data     = $normalized
        }
    }
    catch {
        Write-AppLockerLog -Message "CSV import failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Import failed: $($_.Exception.Message)" -Type 'Error'
        return $null
    }
}

function global:Invoke-ImportBaselineCsv {
    <#
    .SYNOPSIS
        Imports a CSV as the baseline (left side of comparison).
        Replaces any existing scan/baseline data.
    #>
    param($Window)

    $csv = Import-SoftwareCsvFile -Window $Window -Title 'Import Baseline CSV'
    if (-not $csv) { return }

    $baselineData = @($csv.Data | ForEach-Object {
        [PSCustomObject]@{
            Machine         = $_.Machine
            DisplayName     = $_.DisplayName
            DisplayVersion  = $_.DisplayVersion
            Publisher       = $_.Publisher
            InstallDate     = $_.InstallDate
            InstallLocation = $_.InstallLocation
            Architecture    = $_.Architecture
            Source          = 'CSV'
        }
    })

    $script:SoftwareInventory = $baselineData
    $script:SoftwareImportedData = @()
    $script:SoftwareImportedFile = ''

    Update-SoftwareDataGrid -Window $Window
    Update-SoftwareStats -Window $Window

    $statusText = $Window.FindName('TxtSoftwareStatus')
    if ($statusText) { $statusText.Text = "Baseline: $($baselineData.Count) items from $($csv.FileName)" }

    $lastScan = $Window.FindName('TxtSoftwareLastScan')
    if ($lastScan) { $lastScan.Text = "CSV: $($csv.FileName)" }

    # Update baseline info on Compare tab
    $baselineFile = $Window.FindName('TxtSoftwareBaselineFile')
    if ($baselineFile) { $baselineFile.Text = "$($csv.FileName) ($($baselineData.Count) items)" }

    Show-Toast -Message "Loaded $($baselineData.Count) items as baseline from $($csv.FileName)" -Type 'Success'
    Write-AppLockerLog -Message "Imported software CSV as baseline: $($csv.FullPath) ($($baselineData.Count) items)" -Level 'INFO'
}

function global:Invoke-ImportComparisonCsv {
    <#
    .SYNOPSIS
        Imports a CSV into the comparison slot (right side of comparison).
        Requires a baseline (scan data or prior baseline import) to exist.
    #>
    param($Window)

    # Check baseline exists
    $hasBaseline = @($script:SoftwareInventory | Where-Object { $_.Source -ne 'Imported' -and $_.Source -ne 'Compare' }).Count -gt 0
    if (-not $hasBaseline) {
        Show-Toast -Message 'No baseline data. Run a scan or import a baseline CSV first.' -Type 'Warning'
        return
    }

    $csv = Import-SoftwareCsvFile -Window $Window -Title 'Import Comparison CSV'
    if (-not $csv) { return }

    $script:SoftwareImportedData = $csv.Data
    $script:SoftwareImportedFile = $csv.FileName

    $importedFileText = $Window.FindName('TxtSoftwareImportedFile')
    if ($importedFileText) { $importedFileText.Text = "$($csv.FileName) ($($csv.Data.Count) items)" }

    $statusText = $Window.FindName('TxtSoftwareStatus')
    if ($statusText) { $statusText.Text = "Comparison ready: $($csv.Data.Count) items from $($csv.FileName). Click Compare Inventories." }

    Show-Toast -Message "Loaded $($csv.Data.Count) items for comparison from $($csv.FileName)" -Type 'Success'
    Write-AppLockerLog -Message "Imported software CSV for comparison: $($csv.FullPath) ($($csv.Data.Count) items)" -Level 'INFO'
}

# Legacy function removed - use Invoke-ImportBaselineCsv or Invoke-ImportComparisonCsv
# Was: Invoke-ImportSoftwareCsv

#endregion

#region ===== COMPARISON =====

function global:Invoke-CompareSoftware {
    <#
    .SYNOPSIS
        Compares baseline data (scan or first CSV) against imported CSV data.
        Shows four categories: Match, Version Diff, Only in Baseline, Only in Import.
    #>
    param($Window)

    # Need both a baseline and an import to compare
    if ($script:SoftwareImportedData.Count -eq 0) {
        Show-Toast -Message 'No imported data to compare against. Import a second CSV first.' -Type 'Warning'
        return
    }

    # Get baseline data (scan results or first-imported CSV, not the comparison-imported entries)
    $scanData = @($script:SoftwareInventory | Where-Object { $_.Source -ne 'Imported' -and $_.Source -ne 'Compare' })
    if ($scanData.Count -eq 0) {
        Show-Toast -Message 'No baseline data to compare. Run a scan or import a CSV first, then import a second CSV.' -Type 'Warning'
        return
    }

    Show-LoadingOverlay -Message 'Comparing software inventories...'

    try {
        $comparisonResults = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Build lookup by DisplayName (case-insensitive)
        $scanLookup = @{}
        foreach ($item in $scanData) {
            $key = $item.DisplayName.ToLower().Trim()
            if (-not $scanLookup.ContainsKey($key)) {
                $scanLookup[$key] = $item
            }
        }

        $importLookup = @{}
        foreach ($item in $script:SoftwareImportedData) {
            $key = $item.DisplayName.ToLower().Trim()
            if (-not $importLookup.ContainsKey($key)) {
                $importLookup[$key] = $item
            }
        }

        # Only in scan (not in imported)
        foreach ($key in $scanLookup.Keys) {
            if (-not $importLookup.ContainsKey($key)) {
                $s = $scanLookup[$key]
                [void]$comparisonResults.Add([PSCustomObject]@{
                    Machine        = $s.Machine
                    DisplayName    = $s.DisplayName
                    DisplayVersion = $s.DisplayVersion
                    Publisher      = $s.Publisher
                    InstallDate    = $s.InstallDate
                    InstallLocation = $s.InstallLocation
                    Architecture   = $s.Architecture
                    Source         = 'Only in Scan'
                })
            }
        }

        # Only in imported (not in scan)
        foreach ($key in $importLookup.Keys) {
            if (-not $scanLookup.ContainsKey($key)) {
                $i = $importLookup[$key]
                [void]$comparisonResults.Add([PSCustomObject]@{
                    Machine        = $i.Machine
                    DisplayName    = $i.DisplayName
                    DisplayVersion = $i.DisplayVersion
                    Publisher      = $i.Publisher
                    InstallDate    = $i.InstallDate
                    InstallLocation = $i.InstallLocation
                    Architecture   = $i.Architecture
                    Source         = 'Only in Import'
                })
            }
        }

        # Version differences and matches (same name in both)
        foreach ($key in $scanLookup.Keys) {
            if ($importLookup.ContainsKey($key)) {
                $s = $scanLookup[$key]
                $i = $importLookup[$key]
                $scanVer = if ($s.DisplayVersion) { $s.DisplayVersion.Trim() } else { '' }
                $importVer = if ($i.DisplayVersion) { $i.DisplayVersion.Trim() } else { '' }

                if ($scanVer -ne $importVer) {
                    [void]$comparisonResults.Add([PSCustomObject]@{
                        Machine        = "$($s.Machine) vs $($i.Machine)"
                        DisplayName    = $s.DisplayName
                        DisplayVersion = "$scanVer -> $importVer"
                        Publisher      = $s.Publisher
                        InstallDate    = ''
                        InstallLocation = ''
                        Architecture   = $s.Architecture
                        Source         = 'Version Diff'
                    })
                }
                else {
                    [void]$comparisonResults.Add([PSCustomObject]@{
                        Machine        = $s.Machine
                        DisplayName    = $s.DisplayName
                        DisplayVersion = $s.DisplayVersion
                        Publisher      = $s.Publisher
                        InstallDate    = $s.InstallDate
                        InstallLocation = $s.InstallLocation
                        Architecture   = $s.Architecture
                        Source         = 'Match'
                    })
                }
            }
        }

        # Sort: diffs first, then only-in-scan, then only-in-import, then matches
        $sorted = @($comparisonResults | Sort-Object @{Expression = {
            switch ($_.Source) {
                'Version Diff'   { 0 }
                'Only in Scan'   { 1 }
                'Only in Import' { 2 }
                'Match'          { 3 }
                default          { 4 }
            }
        }}, DisplayName)

        $script:SoftwareInventory = $sorted
        Update-SoftwareDataGrid -Window $Window
        Update-SoftwareStats -Window $Window

        # Summary
        $onlyScan = @($sorted | Where-Object { $_.Source -eq 'Only in Scan' }).Count
        $onlyImport = @($sorted | Where-Object { $_.Source -eq 'Only in Import' }).Count
        $versionDiff = @($sorted | Where-Object { $_.Source -eq 'Version Diff' }).Count
        $matchCount = @($sorted | Where-Object { $_.Source -eq 'Match' }).Count

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) {
            $statusText.Text = "Comparison: $versionDiff version diff(s), $onlyScan only in scan, $onlyImport only in import, $matchCount match"
        }

        Show-Toast -Message "Comparison complete: $matchCount match, $versionDiff version diff(s), $onlyScan scan-only, $onlyImport import-only." -Type 'Success'
    }
    catch {
        Write-AppLockerLog -Message "Software comparison failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Comparison failed: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
}

function global:Invoke-ExportComparisonCsv {
    <#
    .SYNOPSIS
        Exports the current comparison results to a CSV file.
        Includes the Source column (Match, Version Diff, Only in Scan, Only in Import).
    #>
    param($Window)

    if ($script:SoftwareInventory.Count -eq 0) {
        Show-Toast -Message 'No comparison data to export. Run a comparison first.' -Type 'Warning'
        return
    }

    # Check if this is actually comparison data (has Source values like Match/Version Diff)
    $hasComparisonData = @($script:SoftwareInventory | Where-Object {
        $_.Source -eq 'Match' -or $_.Source -eq 'Version Diff' -or $_.Source -eq 'Only in Scan' -or $_.Source -eq 'Only in Import'
    }).Count -gt 0

    if (-not $hasComparisonData) {
        Show-Toast -Message 'No comparison results found. Import two CSVs and click Compare first.' -Type 'Warning'
        return
    }

    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Title = 'Export Comparison Results'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $dialog.DefaultExt = '.csv'
    $dialog.FileName = "SoftwareComparison_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

    $result = $dialog.ShowDialog($Window)
    if (-not $result) { return }

    try {
        $script:SoftwareInventory |
            Select-Object Source, Machine, DisplayName, DisplayVersion, Publisher, InstallDate, Architecture |
            Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8

        $total = $script:SoftwareInventory.Count
        $diffs = @($script:SoftwareInventory | Where-Object { $_.Source -ne 'Match' }).Count
        Show-Toast -Message "Exported $total items ($diffs differences) to CSV." -Type 'Success'
        Write-AppLockerLog -Message "Exported comparison results to: $($dialog.FileName)" -Level 'INFO'
    }
    catch {
        Write-AppLockerLog -Message "Comparison CSV export failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Export failed: $($_.Exception.Message)" -Type 'Error'
    }
}

function global:Invoke-ClearSoftwareComparison {
    <#
    .SYNOPSIS
        Clears comparison results and imported data.
    #>
    param($Window)

    $script:SoftwareImportedData = @()
    $script:SoftwareImportedFile = ''
    $script:SoftwareInventory = @()
    $script:CurrentSoftwareSourceFilter = 'All'

    # Reset filter button highlights
    Update-SoftwareSourceFilter -Window $Window -Filter 'All'

    Update-SoftwareDataGrid -Window $Window
    Update-SoftwareStats -Window $Window

    if ($Window) {
        $importedFileText = $Window.FindName('TxtSoftwareImportedFile')
        if ($importedFileText) { $importedFileText.Text = 'None' }

        $baselineFile = $Window.FindName('TxtSoftwareBaselineFile')
        if ($baselineFile) { $baselineFile.Text = 'None (scan or import a CSV on Scan tab)' }

        $lastScan = $Window.FindName('TxtSoftwareLastScan')
        if ($lastScan) { $lastScan.Text = 'None' }

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) { $statusText.Text = 'Ready - scan local machine or import a CSV to get started.' }
    }

    Show-Toast -Message 'Cleared all software inventory data.' -Type 'Info'
}

#endregion

#region ===== DATAGRID UPDATE =====

function global:Update-SoftwareSourceFilter {
    <#
    .SYNOPSIS
        Updates the source filter and refreshes the DataGrid + button highlights.
    #>
    param(
        $Window,
        [string]$Filter
    )

    # Map filter tag values to Source column values
    $script:CurrentSoftwareSourceFilter = switch ($Filter) {
        'All'          { 'All' }
        'Match'        { 'Match' }
        'VersionDiff'  { 'Version Diff' }
        'OnlyScan'     { 'Only in Scan' }
        'OnlyImport'   { 'Only in Import' }
        default        { 'All' }
    }

    # Update button highlight states
    $allButtons = @(
        'BtnFilterSoftwareAll', 'BtnFilterSoftwareMatch', 'BtnFilterSoftwareVersionDiff',
        'BtnFilterSoftwareOnlyScan', 'BtnFilterSoftwareOnlyImport'
    )

    # Determine which button matches current filter
    $activeBtn = switch ($Filter) {
        'All'          { 'BtnFilterSoftwareAll' }
        'Match'        { 'BtnFilterSoftwareMatch' }
        'VersionDiff'  { 'BtnFilterSoftwareVersionDiff' }
        'OnlyScan'     { 'BtnFilterSoftwareOnlyScan' }
        'OnlyImport'   { 'BtnFilterSoftwareOnlyImport' }
        default        { 'BtnFilterSoftwareAll' }
    }

    if (-not $Window) {
        Update-SoftwareDataGrid -Window $Window
        return
    }

    foreach ($btnName in $allButtons) {
        $btn = $Window.FindName($btnName)
        if ($btn) {
            if ($btnName -eq $activeBtn) {
                $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3E3E42')
                $btn.Foreground = [System.Windows.Media.Brushes]::White
            } else {
                $btn.Background = [System.Windows.Media.Brushes]::Transparent
                # Restore original foreground color
                $btn.Foreground = switch ($btnName) {
                    'BtnFilterSoftwareAll'          { [System.Windows.Media.Brushes]::White }
                    'BtnFilterSoftwareMatch'        { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1565C0') }
                    'BtnFilterSoftwareVersionDiff'  { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6A100') }
                    'BtnFilterSoftwareOnlyScan'     { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4CAF50') }
                    'BtnFilterSoftwareOnlyImport'   { [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D13438') }
                }
            }
        }
    }

    Update-SoftwareDataGrid -Window $Window
}

function global:Update-SoftwareDataGrid {
    <#
    .SYNOPSIS
        Updates the SoftwareDataGrid with current inventory data, applying text filter.
    #>
    param($Window)

    if (-not $Window) { return }
    $dataGrid = $Window.FindName('SoftwareDataGrid')
    if (-not $dataGrid) { return }

    $data = $script:SoftwareInventory

    # Apply source filter (comparison category)
    if ($script:CurrentSoftwareSourceFilter -and $script:CurrentSoftwareSourceFilter -ne 'All') {
        $sourceFilter = $script:CurrentSoftwareSourceFilter
        $data = @($data | Where-Object { $_.Source -eq $sourceFilter })
    }

    # Apply text filter
    $filterBox = $Window.FindName('TxtSoftwareFilter')
    $textFilter = if ($filterBox) { $filterBox.Text } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($textFilter)) {
        $filterText = $textFilter.ToLower()
        $data = @($data | Where-Object {
            ($_.DisplayName -and $_.DisplayName.ToLower().Contains($filterText)) -or
            ($_.Publisher -and $_.Publisher.ToLower().Contains($filterText)) -or
            ($_.DisplayVersion -and $_.DisplayVersion.ToLower().Contains($filterText)) -or
            ($_.Machine -and $_.Machine.ToLower().Contains($filterText)) -or
            ($_.Source -and $_.Source.ToLower().Contains($filterText))
        })
    }

    $dataGrid.ItemsSource = $null
    $dataGrid.ItemsSource = @($data)

    $filteredCount = $Window.FindName('TxtSoftwareFilteredCount')
    if ($filteredCount) { $filteredCount.Text = @($data).Count.ToString() }
}

function global:Update-SoftwareStats {
    <#
    .SYNOPSIS
        Updates the sidebar stats displays.
    #>
    param($Window)

    if (-not $Window) { return }
    $totalCount = $Window.FindName('TxtSoftwareTotalCount')
    if ($totalCount) { $totalCount.Text = $script:SoftwareInventory.Count.ToString() }

    $machineCount = $Window.FindName('TxtSoftwareMachineCount')
    if ($machineCount) {
        $machines = @($script:SoftwareInventory | ForEach-Object { $_.Machine } | Sort-Object -Unique)
        $machineCount.Text = $machines.Count.ToString()
    }
}

#endregion

#endregion
