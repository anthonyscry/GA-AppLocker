#region Software Inventory Panel Functions
# Software.ps1 - Installed software scanning, CSV export/import, and cross-system comparison

# Script-level state for this panel
$script:SoftwareInventory = @()       # Current scan/imported data shown in DataGrid
$script:SoftwareImportedData = @()    # Imported CSV data for comparison
$script:SoftwareImportedFile = ''     # Name of imported file

function Initialize-SoftwarePanel {
    param([System.Windows.Window]$Window)

    # Wire up sidebar buttons via Tag -> Invoke-ButtonAction
    $buttons = @(
        'BtnScanLocalSoftware', 'BtnScanRemoteSoftware',
        'BtnExportSoftwareCsv', 'BtnImportSoftwareCsv',
        'BtnCompareSoftware', 'BtnClearComparison'
    )
    foreach ($btnName in $buttons) {
        $btn = $Window.FindName($btnName)
        if ($btn -and $btn.Tag) {
            $tagValue = $btn.Tag.ToString()
            $btn.Add_Click({ Invoke-ButtonAction -Action $tagValue }.GetNewClosure())
        }
    }

    # Wire up text filter with debounce
    $filterBox = $Window.FindName('TxtSoftwareFilter')
    if ($filterBox) {
        $filterBox.Add_TextChanged({
            Update-SoftwareDataGrid -Window $global:GA_MainWindow
        })
    }
}

#region ===== SCAN FUNCTIONS =====

function global:Invoke-ScanLocalSoftware {
    <#
    .SYNOPSIS
        Scans installed software on the local machine via registry.
    #>
    param([System.Windows.Window]$Window)

    Show-LoadingOverlay -Message 'Scanning installed software...' -SubMessage $env:COMPUTERNAME

    try {
        $results = Get-InstalledSoftware -MachineName $env:COMPUTERNAME
        $script:SoftwareInventory = $results

        Update-SoftwareDataGrid -Window $Window
        Update-SoftwareStats -Window $Window

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) { $statusText.Text = "Scanned $($results.Count) programs on $env:COMPUTERNAME" }

        $lastScan = $Window.FindName('TxtSoftwareLastScan')
        if ($lastScan) { $lastScan.Text = "$env:COMPUTERNAME - $(Get-Date -Format 'MM/dd HH:mm')" }

        # Auto-save local scan CSV: hostname_softwarelist_ddMMMYY.csv
        try {
            $appDataPath = Get-AppLockerDataPath
            $scansFolder = [System.IO.Path]::Combine($appDataPath, 'Scans')
            if (-not [System.IO.Directory]::Exists($scansFolder)) {
                [System.IO.Directory]::CreateDirectory($scansFolder) | Out-Null
            }
            $dateSuffix = (Get-Date).ToString('ddMMMyy').ToUpper()
            $csvName = "$($env:COMPUTERNAME)_softwarelist_${dateSuffix}.csv"
            $csvPath = [System.IO.Path]::Combine($scansFolder, $csvName)
            $results |
                Select-Object Machine, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, Architecture, Source |
                Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            Write-AppLockerLog -Message "Auto-saved software list: $csvName" -Level 'INFO'
        } catch {
            Write-AppLockerLog -Message "Failed to auto-save local CSV: $($_.Exception.Message)" -Level 'ERROR'
        }

        Show-Toast -Message "Found $($results.Count) installed programs on local machine. CSV saved to Scans folder." -Type 'Success'
    }
    catch {
        Write-AppLockerLog -Message "Local software scan failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Scan failed: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
}

function global:Invoke-ScanRemoteSoftware {
    <#
    .SYNOPSIS
        Scans installed software on remote machines via WinRM.
    #>
    param([System.Windows.Window]$Window)

    $machines = @($script:SelectedScanMachines)
    if ($machines.Count -eq 0) {
        Show-Toast -Message 'No machines selected. Go to AD Discovery to select machines for scanning.' -Type 'Warning'
        return
    }

    # Get hostnames
    $hostnames = @($machines | ForEach-Object {
        if ($_ -is [string]) { $_ } else { $_.Hostname }
    })

    Show-LoadingOverlay -Message "Scanning software on $($hostnames.Count) machine(s)..." -SubMessage ($hostnames[0..2] -join ', ')

    try {
        $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Get credential using the same tier-based fallback chain as the Scanner panel.
        # Try tiers in order T2 (workstations) -> T1 (servers) -> T0 (DCs), then implicit Windows auth.
        $cred = $null
        $credSource = 'implicit Windows auth'
        foreach ($tryTier in @(2, 1, 0)) {
            try {
                $credResult = Get-CredentialForTier -Tier $tryTier
                if ($credResult.Success -and $credResult.Data) {
                    $cred = $credResult.Data
                    $credSource = "Tier $tryTier credential"
                    break
                }
            } catch { }
        }
        Write-AppLockerLog -Message "Software remote scan using: $credSource" -Level 'INFO'

        # Ensure Scans folder exists for auto-save
        $scansFolder = $null
        try {
            $appDataPath = Get-AppLockerDataPath
            $scansFolder = [System.IO.Path]::Combine($appDataPath, 'Scans')
            if (-not [System.IO.Directory]::Exists($scansFolder)) {
                [System.IO.Directory]::CreateDirectory($scansFolder) | Out-Null
            }
        } catch {
            Write-AppLockerLog -Message "Could not create Scans folder: $($_.Exception.Message)" -Level 'ERROR'
        }

        $dateSuffix = (Get-Date).ToString('ddMMMyy').ToUpper()

        foreach ($hostname in $hostnames) {
            try {
                $invokeParams = @{
                    ComputerName = $hostname
                    ScriptBlock  = {
                        $paths = @(
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                        )
                        Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
                            ForEach-Object {
                                [PSCustomObject]@{
                                    DisplayName    = $_.DisplayName
                                    DisplayVersion = $_.DisplayVersion
                                    Publisher      = $_.Publisher
                                    InstallDate    = $_.InstallDate
                                    InstallLocation = $_.InstallLocation
                                    Architecture   = if ($_.PSPath -like '*WOW6432*') { 'x86' } else { 'x64' }
                                }
                            }
                    }
                    ErrorAction = 'Stop'
                }
                if ($cred) { $invokeParams['Credential'] = $cred }

                $remoteResults = @(Invoke-Command @invokeParams)
                $hostResults = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($item in $remoteResults) {
                    $obj = [PSCustomObject]@{
                        Machine        = $hostname
                        DisplayName    = $item.DisplayName
                        DisplayVersion = $item.DisplayVersion
                        Publisher      = $item.Publisher
                        InstallDate    = $item.InstallDate
                        InstallLocation = $item.InstallLocation
                        Architecture   = $item.Architecture
                        Source         = 'Remote'
                    }
                    $allResults.Add($obj)
                    $hostResults.Add($obj)
                }

                Write-AppLockerLog -Message "Scanned $($remoteResults.Count) programs on $hostname" -Level 'INFO'

                # Auto-save per-hostname CSV: hostname_softwarelist_ddMMMYY.csv
                if ($scansFolder -and $hostResults.Count -gt 0) {
                    try {
                        $csvName = "${hostname}_softwarelist_${dateSuffix}.csv"
                        $csvPath = [System.IO.Path]::Combine($scansFolder, $csvName)
                        $hostResults |
                            Select-Object Machine, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, Architecture, Source |
                            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                        Write-AppLockerLog -Message "Auto-saved software list: $csvName" -Level 'INFO'
                    } catch {
                        Write-AppLockerLog -Message "Failed to auto-save CSV for $hostname`: $($_.Exception.Message)" -Level 'ERROR'
                    }
                }
            }
            catch {
                Write-AppLockerLog -Message "Failed to scan software on $hostname`: $($_.Exception.Message)" -Level 'ERROR'
                Show-Toast -Message "Failed to scan $hostname`: $($_.Exception.Message)" -Type 'Warning'
            }
        }

        $script:SoftwareInventory = @($allResults)
        Update-SoftwareDataGrid -Window $Window
        Update-SoftwareStats -Window $Window

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) { $statusText.Text = "Scanned $($allResults.Count) programs across $($hostnames.Count) machine(s)" }

        $lastScan = $Window.FindName('TxtSoftwareLastScan')
        if ($lastScan) { $lastScan.Text = "$($hostnames.Count) machines - $(Get-Date -Format 'MM/dd HH:mm')" }

        # Summary toast with auto-save info
        $savedCount = @($hostnames | Where-Object { $allResults | Where-Object { $_.Machine -eq $_ } }).Count
        $toastMsg = "Found $($allResults.Count) installed programs across $($hostnames.Count) machine(s)."
        if ($scansFolder) { $toastMsg += " CSVs saved to Scans folder." }
        Show-Toast -Message $toastMsg -Type 'Success'
    }
    catch {
        Write-AppLockerLog -Message "Remote software scan failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Remote scan failed: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
}

function script:Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Enumerates installed software from the registry (local machine).
    #>
    param([string]$MachineName = $env:COMPUTERNAME)

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $results = @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
        ForEach-Object {
            [PSCustomObject]@{
                Machine        = $MachineName
                DisplayName    = $_.DisplayName
                DisplayVersion = if ($_.DisplayVersion) { $_.DisplayVersion } else { '' }
                Publisher      = if ($_.Publisher) { $_.Publisher } else { '' }
                InstallDate    = if ($_.InstallDate) { $_.InstallDate } else { '' }
                InstallLocation = if ($_.InstallLocation) { $_.InstallLocation } else { '' }
                Architecture   = if ($_.PSPath -like '*WOW6432*') { 'x86' } else { 'x64' }
                Source         = 'Local'
            }
        } | Sort-Object DisplayName)

    return $results
}

#endregion

#region ===== CSV EXPORT / IMPORT =====

function global:Invoke-ExportSoftwareCsv {
    <#
    .SYNOPSIS
        Exports the current software inventory DataGrid to a CSV file.
    #>
    param([System.Windows.Window]$Window)

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

function global:Invoke-ImportSoftwareCsv {
    <#
    .SYNOPSIS
        Imports a software inventory CSV file for viewing or comparison.
    #>
    param([System.Windows.Window]$Window)

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = 'Import Software Inventory CSV'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'

    $result = $dialog.ShowDialog($Window)
    if (-not $result) { return }

    try {
        $imported = @(Import-Csv -Path $dialog.FileName -Encoding UTF8)

        if ($imported.Count -eq 0) {
            Show-Toast -Message 'CSV file is empty.' -Type 'Warning'
            return
        }

        # Validate expected columns exist
        $firstRow = $imported[0]
        $hasDisplayName = $null -ne $firstRow.PSObject.Properties['DisplayName']
        if (-not $hasDisplayName) {
            Show-Toast -Message 'CSV missing required "DisplayName" column. Expected columns: Machine, DisplayName, DisplayVersion, Publisher, InstallDate, Architecture.' -Type 'Error'
            return
        }

        # Normalize: ensure all expected properties exist
        $normalized = @($imported | ForEach-Object {
            [PSCustomObject]@{
                Machine        = if ($_.Machine) { $_.Machine } else { 'Imported' }
                DisplayName    = $_.DisplayName
                DisplayVersion = if ($_.DisplayVersion) { $_.DisplayVersion } else { '' }
                Publisher      = if ($_.Publisher) { $_.Publisher } else { '' }
                InstallDate    = if ($_.InstallDate) { $_.InstallDate } else { '' }
                InstallLocation = if ($_.InstallLocation) { $_.InstallLocation } else { '' }
                Architecture   = if ($_.Architecture) { $_.Architecture } else { '' }
                Source         = 'Imported'
            }
        })

        # Store as imported data AND show it
        $script:SoftwareImportedData = $normalized
        $script:SoftwareImportedFile = [System.IO.Path]::GetFileName($dialog.FileName)
        $script:SoftwareInventory = $normalized

        Update-SoftwareDataGrid -Window $Window
        Update-SoftwareStats -Window $Window

        $importedFileText = $Window.FindName('TxtSoftwareImportedFile')
        if ($importedFileText) { $importedFileText.Text = "$($script:SoftwareImportedFile) ($($normalized.Count) items)" }

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) { $statusText.Text = "Imported $($normalized.Count) items from $($script:SoftwareImportedFile)" }

        Show-Toast -Message "Imported $($normalized.Count) software items from CSV." -Type 'Success'
        Write-AppLockerLog -Message "Imported software CSV: $($dialog.FileName) ($($normalized.Count) items)" -Level 'INFO'
    }
    catch {
        Write-AppLockerLog -Message "CSV import failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Import failed: $($_.Exception.Message)" -Type 'Error'
    }
}

#endregion

#region ===== COMPARISON =====

function global:Invoke-CompareSoftware {
    <#
    .SYNOPSIS
        Compares current scan data against imported CSV data.
        Shows three categories: Only in Scan, Only in Imported, Version Differences.
    #>
    param([System.Windows.Window]$Window)

    # Need both a scan and an import to compare
    if ($script:SoftwareImportedData.Count -eq 0) {
        Show-Toast -Message 'No imported data to compare against. Import a CSV first.' -Type 'Warning'
        return
    }

    # Get scan data (non-imported entries)
    $scanData = @($script:SoftwareInventory | Where-Object { $_.Source -ne 'Imported' -and $_.Source -ne 'Compare' })
    if ($scanData.Count -eq 0) {
        Show-Toast -Message 'No scan data to compare. Run a local or remote scan first, then import a CSV.' -Type 'Warning'
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
                $comparisonResults.Add([PSCustomObject]@{
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
                $comparisonResults.Add([PSCustomObject]@{
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

        # Version differences (same name, different version)
        foreach ($key in $scanLookup.Keys) {
            if ($importLookup.ContainsKey($key)) {
                $s = $scanLookup[$key]
                $i = $importLookup[$key]
                $scanVer = if ($s.DisplayVersion) { $s.DisplayVersion.Trim() } else { '' }
                $importVer = if ($i.DisplayVersion) { $i.DisplayVersion.Trim() } else { '' }

                if ($scanVer -ne $importVer) {
                    $comparisonResults.Add([PSCustomObject]@{
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
            }
        }

        # Sort: diffs first, then only-in-scan, then only-in-import
        $sorted = @($comparisonResults | Sort-Object @{Expression = {
            switch ($_.Source) {
                'Version Diff'   { 0 }
                'Only in Scan'   { 1 }
                'Only in Import' { 2 }
                default          { 3 }
            }
        }}, DisplayName)

        $script:SoftwareInventory = $sorted
        Update-SoftwareDataGrid -Window $Window
        Update-SoftwareStats -Window $Window

        # Summary
        $onlyScan = @($sorted | Where-Object { $_.Source -eq 'Only in Scan' }).Count
        $onlyImport = @($sorted | Where-Object { $_.Source -eq 'Only in Import' }).Count
        $versionDiff = @($sorted | Where-Object { $_.Source -eq 'Version Diff' }).Count
        $common = $scanLookup.Count - $onlyScan - $versionDiff

        $statusText = $Window.FindName('TxtSoftwareStatus')
        if ($statusText) {
            $statusText.Text = "Comparison: $versionDiff version diff(s), $onlyScan only in scan, $onlyImport only in import, $common identical"
        }

        Show-Toast -Message "Comparison complete: $($sorted.Count) differences found ($versionDiff version, $onlyScan scan-only, $onlyImport import-only)." -Type 'Success'
    }
    catch {
        Write-AppLockerLog -Message "Software comparison failed: $($_.Exception.Message)" -Level 'ERROR'
        Show-Toast -Message "Comparison failed: $($_.Exception.Message)" -Type 'Error'
    }
    finally {
        Hide-LoadingOverlay
    }
}

function global:Invoke-ClearSoftwareComparison {
    <#
    .SYNOPSIS
        Clears comparison results and imported data.
    #>
    param([System.Windows.Window]$Window)

    $script:SoftwareImportedData = @()
    $script:SoftwareImportedFile = ''
    $script:SoftwareInventory = @()

    Update-SoftwareDataGrid -Window $Window
    Update-SoftwareStats -Window $Window

    $importedFileText = $Window.FindName('TxtSoftwareImportedFile')
    if ($importedFileText) { $importedFileText.Text = 'None' }

    $lastScan = $Window.FindName('TxtSoftwareLastScan')
    if ($lastScan) { $lastScan.Text = 'None' }

    $statusText = $Window.FindName('TxtSoftwareStatus')
    if ($statusText) { $statusText.Text = 'Ready - scan local machine or import a CSV to get started.' }

    Show-Toast -Message 'Cleared all software inventory data.' -Type 'Info'
}

#endregion

#region ===== DATAGRID UPDATE =====

function global:Update-SoftwareDataGrid {
    <#
    .SYNOPSIS
        Updates the SoftwareDataGrid with current inventory data, applying text filter.
    #>
    param([System.Windows.Window]$Window)

    $dataGrid = $Window.FindName('SoftwareDataGrid')
    if (-not $dataGrid) { return }

    $data = $script:SoftwareInventory

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

function script:Update-SoftwareStats {
    <#
    .SYNOPSIS
        Updates the sidebar stats displays.
    #>
    param([System.Windows.Window]$Window)

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
