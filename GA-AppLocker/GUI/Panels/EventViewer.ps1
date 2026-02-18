#region Event Viewer Panel Functions

# Shared panel state (shell scaffolding for EVT-01)
$script:EventViewerQueryState = @{
    StartTime   = $null
    EndTime     = $null
    MaxEvents   = 500
    EventIds    = @(8002..8025)
    TargetScope = 'Local'
    RemoteHosts = ''
}

$script:EventViewerResults = @()
$script:EventViewerHostStatus = @()
$script:EventViewerFileMetrics = @()

function global:Show-EventViewerToast {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )

    if (Get-Command -Name 'Show-Toast' -ErrorAction SilentlyContinue) {
        Show-Toast -Message $Message -Type $Type
    }
}

function script:Get-EventViewerStateEventIds {
    $ids = @()

    if ($script:EventViewerQueryState.ContainsKey('EventIds')) {
        foreach ($id in @($script:EventViewerQueryState.EventIds)) {
            $parsed = 0
            if ([int]::TryParse([string]$id, [ref]$parsed) -and $parsed -gt 0) {
                $ids += $parsed
            }
        }
    }

    if (@($ids).Count -eq 0) {
        return @(8002..8025)
    }

    return @($ids | Select-Object -Unique | Sort-Object)
}

function script:Get-EventViewerTargetHosts {
    param(
        [Parameter()]
        [string]$TargetScope,

        [Parameter()]
        [string]$RemoteHostsText
    )

    if ($TargetScope -eq 'Remote') {
        $parsedHosts = @()
        foreach ($token in (([string]$RemoteHostsText) -split '[,;\r\n]')) {
            $remoteHost = [string]$token
            if (-not [string]::IsNullOrWhiteSpace($remoteHost)) {
                $parsedHosts += $remoteHost.Trim()
            }
        }

        $uniqueHosts = @($parsedHosts | Select-Object -Unique)
        if ($uniqueHosts.Count -eq 0) {
            return @{
                Success = $false
                Error = 'Select one or more remote hosts before running query.'
                Hosts = @()
            }
        }

        return @{
            Success = $true
            Error = $null
            Hosts = $uniqueHosts
        }
    }

    $localHost = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($localHost)) {
        $localHost = 'localhost'
    }

    return @{
        Success = $true
        Error = $null
        Hosts = @($localHost)
    }
}

function script:Get-EventViewerScope {
    param($TargetScopeControl)

    if (-not $TargetScopeControl) {
        return 'Local'
    }

    $selected = $TargetScopeControl.SelectedItem
    $raw = $null

    if ($selected -is [string]) {
        $raw = $selected
    }
    elseif ($selected -and ($selected.PSObject.Properties.Name -contains 'Content')) {
        $raw = [string]$selected.Content
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ($TargetScopeControl.SelectedIndex -eq 1) {
            return 'Remote'
        }
        return 'Local'
    }

    if ($raw -match 'remote') {
        return 'Remote'
    }

    return 'Local'
}

function script:Get-EventViewerQueryContract {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param($Window)

    if (-not $Window) {
        return @{ Success = $false; Error = 'Event Viewer window reference is not available.'; Data = $null }
    }

    $startPicker = $Window.FindName('DpEventViewerStartTime')
    $endPicker = $Window.FindName('DpEventViewerEndTime')
    $maxEventsControl = $Window.FindName('TxtEventViewerMaxEvents')
    $targetScopeControl = $Window.FindName('CboEventViewerTargetScope')
    $remoteHostsControl = $Window.FindName('TxtEventViewerRemoteHosts')

    $startTime = $null
    $endTime = $null
    $maxEvents = 0

    if ($startPicker) {
        $startTime = $startPicker.SelectedDate
    }
    if ($endPicker) {
        $endTime = $endPicker.SelectedDate
    }

    if (-not $startTime -or -not $endTime) {
        return @{ Success = $false; Error = 'Start and End time are required.'; Data = $null }
    }

    if ($endTime -lt $startTime) {
        return @{ Success = $false; Error = 'End time must be greater than or equal to Start time.'; Data = $null }
    }

    if (-not $maxEventsControl -or -not [int]::TryParse([string]$maxEventsControl.Text, [ref]$maxEvents)) {
        return @{ Success = $false; Error = 'Max events must be a number between 1 and 5000.'; Data = $null }
    }

    if ($maxEvents -lt 1 -or $maxEvents -gt 5000) {
        return @{ Success = $false; Error = 'Max events must be between 1 and 5000.'; Data = $null }
    }

    $eventIds = @(Get-EventViewerStateEventIds)
    if (@($eventIds).Count -eq 0) {
        return @{ Success = $false; Error = 'Select at least one event ID before running query.'; Data = $null }
    }

    $targetScope = Get-EventViewerScope -TargetScopeControl $targetScopeControl
    $remoteHostsText = if ($remoteHostsControl) { [string]$remoteHostsControl.Text } else { '' }
    $targetResult = Get-EventViewerTargetHosts -TargetScope $targetScope -RemoteHostsText $remoteHostsText
    if (-not $targetResult.Success) {
        return @{ Success = $false; Error = $targetResult.Error; Data = $null }
    }

    $contract = [PSCustomObject]@{
        StartTime   = [datetime]$startTime
        EndTime     = [datetime]$endTime
        MaxEvents   = $maxEvents
        EventIds    = @($eventIds)
        TargetScope = $targetScope
        Targets     = @($targetResult.Hosts)
    }

    return @{ Success = $true; Error = $null; Data = $contract }
}

function script:Update-EventViewerQueryState {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$QueryContract
    )

    $script:EventViewerQueryState.StartTime = $QueryContract.StartTime
    $script:EventViewerQueryState.EndTime = $QueryContract.EndTime
    $script:EventViewerQueryState.MaxEvents = $QueryContract.MaxEvents
    $script:EventViewerQueryState.EventIds = @($QueryContract.EventIds)
    $script:EventViewerQueryState.TargetScope = $QueryContract.TargetScope
    $script:EventViewerQueryState.RemoteHosts = @($QueryContract.Targets) -join ', '
}

function script:Test-EventViewerQueryInputs {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param($Window)

    $result = Get-EventViewerQueryContract -Window $Window
    if (-not $result.Success) {
        Show-EventViewerToast -Message $result.Error -Type 'Warning'
        return $result
    }

    Update-EventViewerQueryState -QueryContract $result.Data
    return $result
}

function global:Get-EventViewerHostStatusGrid {
    param($Window)

    if (-not $Window) { return $null }

    $grid = $Window.FindName('EventViewerHostStatusDataGrid')
    if ($grid) { return $grid }

    return $Window.FindName('EventViewerHostStatusGrid')
}

function global:Get-EventViewerEventsGrid {
    param($Window)

    if (-not $Window) { return $null }

    $grid = $Window.FindName('EventViewerEventsDataGrid')
    if ($grid) { return $grid }

    return $Window.FindName('EventViewerResultsGrid')
}

function global:Get-EventViewerMetricsGrid {
    param($Window)

    if (-not $Window) { return $null }

    return $Window.FindName('EventViewerFileMetricsDataGrid')
}

function global:Get-EventViewerRuleMode {
    param($Window)

    if (-not $Window) { return 'Recommended' }

    $modeControl = $Window.FindName('CboEventViewerRuleMode')
    if (-not $modeControl) { return 'Recommended' }

    $selected = $modeControl.SelectedItem
    if ($selected -and ($selected.PSObject.Properties.Name -contains 'Tag') -and -not [string]::IsNullOrWhiteSpace([string]$selected.Tag)) {
        return [string]$selected.Tag
    }

    if ($selected -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$selected)) {
        return [string]$selected
    }

    return 'Recommended'
}

function global:Get-EventViewerSearchText {
    param($Window)

    if (-not $Window) { return '' }

    $searchControl = $Window.FindName('TxtEventViewerSearch')
    if (-not $searchControl) { return '' }

    return [string]$searchControl.Text
}

function global:Get-EventViewerCollectionTypeFromRow {
    param($Row)

    if (-not $Row) { return 'Exe' }

    $collection = if ($Row.PSObject.Properties.Name -contains 'CollectionType') { [string]$Row.CollectionType } else { '' }
    if ($collection -in @('Exe', 'Dll', 'Msi', 'Script', 'Appx')) {
        return $collection
    }

    $path = if ($Row.PSObject.Properties.Name -contains 'FilePath') { [string]$Row.FilePath } else { '' }
    $ext = [System.IO.Path]::GetExtension($path)

    switch -Regex ($ext.ToLowerInvariant()) {
        '^\.dll$' { return 'Dll' }
        '^\.ms(i|p|t)$' { return 'Msi' }
        '^\.(ps1|psm1|psd1|bat|cmd|vbs|js|wsf)$' { return 'Script' }
        '^\.(appx|msix)$' { return 'Appx' }
        default { return 'Exe' }
    }
}

function global:Test-IsEventViewerAuditEvent {
    param(
        [Parameter()]
        [int]$EventId
    )

    return $EventId -in @(8003, 8007, 8022, 8025)
}

function global:Get-EventViewerActionBucket {
    param(
        [Parameter()]
        [int]$EventId,

        [Parameter()]
        [string]$Action
    )

    $normalizedAction = if ($null -eq $Action) { '' } else { $Action.Trim().ToLowerInvariant() }

    if ($normalizedAction -in @('allow', 'allowed')) {
        return 'Allowed'
    }

    if ($normalizedAction -in @('deny', 'denied', 'block', 'blocked')) {
        if (Test-IsEventViewerAuditEvent -EventId $EventId) {
            return 'Audit'
        }
        return 'Blocked'
    }

    if (Test-IsEventViewerAuditEvent -EventId $EventId) {
        return 'Audit'
    }

    if ($EventId -in @(8001, 8005, 8020, 8023)) {
        return 'Allowed'
    }

    if ($EventId -in @(8002, 8004, 8006, 8021, 8024)) {
        return 'Blocked'
    }

    return 'Blocked'
}

function global:Get-FilteredEventViewerRows {
    param(
        [Parameter()]
        [PSCustomObject[]]$Rows,

        [Parameter()]
        [string]$SearchText
    )

    $allRows = @($Rows)
    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        return $allRows
    }

    $needle = $SearchText.Trim().ToLowerInvariant()
    $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($row in $allRows) {
        if (-not $row) { continue }

        $haystack = @(
            if ($row.PSObject.Properties.Name -contains 'FilePath') { [string]$row.FilePath } else { '' }
            if ($row.PSObject.Properties.Name -contains 'ComputerName') { [string]$row.ComputerName } else { '' }
            if ($row.PSObject.Properties.Name -contains 'EventId') { [string]$row.EventId } else { '' }
            if ($row.PSObject.Properties.Name -contains 'CollectionType') { [string]$row.CollectionType } else { '' }
            if ($row.PSObject.Properties.Name -contains 'Action') { [string]$row.Action } else { '' }
        ) -join ' '

        if ($haystack.ToLowerInvariant().Contains($needle)) {
            [void]$filtered.Add($row)
        }
    }

    return @($filtered)
}

function global:ConvertTo-EventViewerFileMetricsRows {
    param(
        [Parameter()]
        [PSCustomObject[]]$EventRows
    )

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $buckets = @{}

    foreach ($row in @($EventRows)) {
        if (-not $row) { continue }

        $rawPath = if ($row.PSObject.Properties.Name -contains 'FilePath') { [string]$row.FilePath } else { '' }
        $filePath = if ([string]::IsNullOrWhiteSpace($rawPath)) { '<unknown path>' } else { $rawPath }
        $key = $filePath.ToLowerInvariant()

        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = [ordered]@{
                FilePath   = $filePath
                Count      = 0
                Blocked    = 0
                Audit      = 0
                Allowed    = 0
                LastSeen   = $null
                TopEvent   = ''
                EventCount = @{}
            }
        }

        $bucket = $buckets[$key]
        $bucket.Count++

        $eventIdValue = 0
        if ($row.PSObject.Properties.Name -contains 'EventId') {
            $parsedId = 0
            if ([int]::TryParse([string]$row.EventId, [ref]$parsedId)) {
                $eventIdValue = $parsedId
            }
        }

        $rowAction = if ($row.PSObject.Properties.Name -contains 'Action') { [string]$row.Action } else { '' }
        $bucketName = Get-EventViewerActionBucket -EventId $eventIdValue -Action $rowAction

        switch ($bucketName) {
            'Allowed' { $bucket.Allowed++ }
            'Audit' { $bucket.Audit++ }
            default { $bucket.Blocked++ }
        }

        $eventKey = [string]$eventIdValue
        if (-not $bucket.EventCount.ContainsKey($eventKey)) {
            $bucket.EventCount[$eventKey] = 0
        }
        $bucket.EventCount[$eventKey] = [int]$bucket.EventCount[$eventKey] + 1

        $timeValue = $null
        if ($row.PSObject.Properties.Name -contains 'TimeCreated' -and $row.TimeCreated) {
            $timeValue = [datetime]$row.TimeCreated
        }
        if ($timeValue -and ($null -eq $bucket.LastSeen -or $timeValue -gt $bucket.LastSeen)) {
            $bucket.LastSeen = $timeValue
        }
    }

    foreach ($bucket in $buckets.Values) {
        $topEvent = ''
        $topEventCount = -1
        foreach ($eventKey in $bucket.EventCount.Keys) {
            $count = [int]$bucket.EventCount[$eventKey]
            if ($count -gt $topEventCount) {
                $topEventCount = $count
                $topEvent = $eventKey
            }
        }

        [void]$rows.Add([PSCustomObject]@{
                FilePath = [string]$bucket.FilePath
                Count    = [int]$bucket.Count
                Blocked  = [int]$bucket.Blocked
                Audit    = [int]$bucket.Audit
                Allowed  = [int]$bucket.Allowed
                TopEvent = $topEvent
                LastSeen = if ($bucket.LastSeen) { ([datetime]$bucket.LastSeen).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
            })
    }

    return @($rows | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'FilePath'; Descending = $false })
}

function global:Update-EventViewerResultBindings {
    param(
        $Window,
        [PSCustomObject[]]$EventRows
    )

    if (-not $Window) { return }

    $eventsGrid = Get-EventViewerEventsGrid -Window $Window
    $metricsGrid = Get-EventViewerMetricsGrid -Window $Window
    $emptyLabel = $Window.FindName('TxtEventViewerEmpty')
    $metricEmptyLabel = $Window.FindName('TxtEventViewerFileMetricsEmpty')
    $resultCount = $Window.FindName('TxtEventViewerResultCount')
    $uniqueFilesControl = $Window.FindName('TxtEventViewerUniqueFiles')
    $topFileControl = $Window.FindName('TxtEventViewerTopFile')
    $topCountControl = $Window.FindName('TxtEventViewerTopFileCount')

    $searchText = Get-EventViewerSearchText -Window $Window
    $filteredRows = Get-FilteredEventViewerRows -Rows @($EventRows) -SearchText $searchText

    if ($eventsGrid) {
        $eventsGrid.ItemsSource = @($filteredRows)
    }

    if ($resultCount) {
        $resultCount.Text = "{0} events" -f @($filteredRows).Count
    }

    if ($emptyLabel) {
        $emptyLabel.Visibility = if (@($filteredRows).Count -gt 0) { 'Collapsed' } else { 'Visible' }
    }

    $metricRows = ConvertTo-EventViewerFileMetricsRows -EventRows @($filteredRows)
    $script:EventViewerFileMetrics = @($metricRows)

    if ($metricsGrid) {
        $metricsGrid.ItemsSource = @($metricRows)
    }

    if ($metricEmptyLabel) {
        $metricEmptyLabel.Visibility = if (@($metricRows).Count -gt 0) { 'Collapsed' } else { 'Visible' }
    }

    if ($uniqueFilesControl) {
        $uniqueFilesControl.Text = [string]@($metricRows).Count
    }

    if ($topCountControl) {
        $topCountControl.Text = if (@($metricRows).Count -gt 0) { [string]$metricRows[0].Count } else { '0' }
    }

    if ($topFileControl) {
        $topFileControl.Text = if (@($metricRows).Count -gt 0) { [string]$metricRows[0].FilePath } else { '-' }
    }
}

function global:Get-EventViewerSelectedRows {
    param(
        $Window,
        [bool]$UseSelection
    )

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $eventsGrid = Get-EventViewerEventsGrid -Window $Window
    if (-not $eventsGrid) {
        return @($rows)
    }

    if ($UseSelection -and $eventsGrid.PSObject.Properties.Name -contains 'SelectedItems' -and $eventsGrid.SelectedItems) {
        foreach ($item in @($eventsGrid.SelectedItems)) {
            if ($item) { [void]$rows.Add($item) }
        }
    }

    if ($rows.Count -eq 0) {
        $selected = $eventsGrid.SelectedItem
        if ($null -eq $selected -and $eventsGrid.PSObject.Properties.Name -contains 'CurrentItem' -and $null -ne $eventsGrid.CurrentItem) {
            $selected = $eventsGrid.CurrentItem
        }
        if ($selected) {
            [void]$rows.Add($selected)
        }
    }

    $uniqueRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($row in @($rows)) {
        $filePath = if ($row.PSObject.Properties.Name -contains 'FilePath') { [string]$row.FilePath } else { '' }
        $hostName = if ($row.PSObject.Properties.Name -contains 'ComputerName') { [string]$row.ComputerName } else { '' }
        $key = "$filePath|$hostName"
        if ($seen.Add($key)) {
            [void]$uniqueRows.Add($row)
        }
    }

    return @($uniqueRows)
}

function global:Test-IsLocalEventViewerHost {
    param(
        [string]$ComputerName
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $true }

    $normalized = $ComputerName.Trim().ToLowerInvariant()
    $localName = ([string]$env:COMPUTERNAME).ToLowerInvariant()

    return $normalized -in @('localhost', '.', '127.0.0.1', $localName)
}

function script:Get-EventViewerRuleDefaults {
    param($Window)

    $action = 'Allow'
    $targetSid = 'S-1-5-11'

    if ($Window) {
        $rbAllow = $Window.FindName('RbRuleAllow')
        if ($rbAllow -and $rbAllow.IsChecked -eq $false) {
            $action = 'Deny'
        }

        $targetCombo = $Window.FindName('CboRuleTargetGroup')
        if ($targetCombo -and $targetCombo.SelectedItem -and $targetCombo.SelectedItem.Tag) {
            $selectedSid = [string]$targetCombo.SelectedItem.Tag
            if (-not [string]::IsNullOrWhiteSpace($selectedSid)) {
                $targetSid = $selectedSid
            }
        }
    }

    return [PSCustomObject]@{
        Action = $action
        TargetSid = $targetSid
        Status = 'Pending'
    }
}

function script:Confirm-EventViewerRuleGeneration {
    param(
        [string]$Mode,
        [int]$Count,
        [string]$Action,
        [string]$TargetSid
    )

    $message = "Create $Count AppLocker rule candidate(s) from Event Viewer selection?`n`nMode: $Mode`nAction: $Action`nTarget: $TargetSid`nStatus: Pending`n`nContinue?"

    if (Get-Command -Name 'Show-AppLockerMessageBox' -ErrorAction SilentlyContinue) {
        return (Show-AppLockerMessageBox $message 'Confirm Event Viewer Rule Creation' 'YesNo' 'Question')
    }

    return 'Yes'
}

function global:Invoke-EventViewerRuleCreationAsync {
    param(
        $Window,
        [PSCustomObject[]]$Rows,
        [string]$Mode,
        [string]$TargetSid,
        [string]$Action,
        [string]$Status
    )

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $sourceRows = @($Rows)
    if ($sourceRows.Count -eq 0) {
        Show-EventViewerToast -Message 'Select one or more event rows first.' -Type 'Warning'
        return
    }

    $summary = $win.FindName('TxtEventViewerQuerySummary')
    if ($summary) {
        $summary.Text = "Creating rules from $($sourceRows.Count) selected event row(s)..."
    }

    Invoke-AsyncOperation -ScriptBlock {
        param($InputRows, $RequestedMode, $RequestedAction, $RequestedTargetSid, $RequestedStatus)

        function Get-CollectionTypeFromRow {
            param($Row)

            $collection = if ($Row.PSObject.Properties.Name -contains 'CollectionType') { [string]$Row.CollectionType } else { '' }
            if ($collection -in @('Exe', 'Dll', 'Msi', 'Script', 'Appx')) {
                return $collection
            }

            $path = if ($Row.PSObject.Properties.Name -contains 'FilePath') { [string]$Row.FilePath } else { '' }
            $ext = [System.IO.Path]::GetExtension($path)

            switch -Regex ($ext.ToLowerInvariant()) {
                '^\.dll$' { return 'Dll' }
                '^\.ms(i|p|t)$' { return 'Msi' }
                '^\.(ps1|psm1|psd1|bat|cmd|vbs|js|wsf)$' { return 'Script' }
                '^\.(appx|msix)$' { return 'Appx' }
                default { return 'Exe' }
            }
        }

        function Test-IsLocalHostName {
            param([string]$ComputerName)

            if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $true }

            $normalized = $ComputerName.Trim().ToLowerInvariant()
            $localName = ([string]$env:COMPUTERNAME).ToLowerInvariant()

            return $normalized -in @('localhost', '.', '127.0.0.1', $localName)
        }

        function Get-RowMetadata {
            param($Row, [string]$Mode)

            $filePath = if ($Row.PSObject.Properties.Name -contains 'FilePath') { [string]$Row.FilePath } else { '' }
            $hostName = if ($Row.PSObject.Properties.Name -contains 'ComputerName') { [string]$Row.ComputerName } else { '' }

            $metadata = [PSCustomObject]@{
                FilePath       = $filePath
                FileName       = if ([string]::IsNullOrWhiteSpace($filePath)) { 'Unknown' } else { [System.IO.Path]::GetFileName($filePath) }
                FileLength     = 0
                CollectionType = Get-CollectionTypeFromRow -Row $Row
                Hash           = $null
                PublisherName  = $null
                ProductName    = '*'
                BinaryName     = '*'
                IsLocal        = Test-IsLocalHostName -ComputerName $hostName
            }

            if (-not $metadata.IsLocal -or [string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath)) {
                return $metadata
            }

            try {
                $fileItem = Get-Item -LiteralPath $filePath -ErrorAction Stop
                if ($fileItem) {
                    $metadata.FileLength = [int64]$fileItem.Length
                    $metadata.FileName = [string]$fileItem.Name
                    if ($fileItem.PSObject.Properties.Name -contains 'VersionInfo' -and $fileItem.VersionInfo -and -not [string]::IsNullOrWhiteSpace([string]$fileItem.VersionInfo.ProductName)) {
                        $metadata.ProductName = [string]$fileItem.VersionInfo.ProductName
                    }
                    $metadata.BinaryName = [string]$fileItem.Name
                }
            }
            catch {
            }

            if ($Mode -in @('Recommended', 'Hash')) {
                try {
                    $fileHash = Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction Stop
                    if ($fileHash -and -not [string]::IsNullOrWhiteSpace([string]$fileHash.Hash)) {
                        $metadata.Hash = [string]$fileHash.Hash
                    }
                }
                catch {
                }
            }

            if ($Mode -in @('Recommended', 'Publisher')) {
                try {
                    $signature = Get-AuthenticodeSignature -FilePath $filePath -ErrorAction Stop
                    if ($signature -and $signature.SignerCertificate -and -not [string]::IsNullOrWhiteSpace([string]$signature.SignerCertificate.Subject)) {
                        $metadata.PublisherName = [string]$signature.SignerCertificate.Subject
                    }
                }
                catch {
                }
            }

            return $metadata
        }

        $resolvedTargetSid = if ($RequestedTargetSid) { [string]$RequestedTargetSid } else { 'S-1-5-11' }
        if ($resolvedTargetSid.StartsWith('RESOLVE:')) {
            try { $resolvedTargetSid = Resolve-GroupSid -GroupName $resolvedTargetSid } catch { }
        }

        $created = 0
        $skipped = 0
        $failed = 0
        $sampleMessages = [System.Collections.Generic.List[string]]::new()

        foreach ($row in @($InputRows)) {
            $metadata = Get-RowMetadata -Row $row -Mode $RequestedMode

            if ([string]::IsNullOrWhiteSpace($metadata.FilePath) -or $metadata.FilePath -eq '<unknown path>') {
                $skipped++
                if ($sampleMessages.Count -lt 3) { [void]$sampleMessages.Add('Skipped: missing file path') }
                continue
            }

            $effectiveMode = $RequestedMode
            if ($RequestedMode -eq 'Recommended') {
                if (-not [string]::IsNullOrWhiteSpace([string]$metadata.PublisherName)) {
                    $effectiveMode = 'Publisher'
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$metadata.Hash)) {
                    $effectiveMode = 'Hash'
                }
                else {
                    $effectiveMode = 'Path'
                }
            }

            try {
                $ruleResult = $null

                switch ($effectiveMode) {
                    'Publisher' {
                        if ([string]::IsNullOrWhiteSpace([string]$metadata.PublisherName)) {
                            $skipped++
                            if ($sampleMessages.Count -lt 3) { [void]$sampleMessages.Add("Skipped publisher: $($metadata.FilePath)") }
                            continue
                        }

                        $ruleResult = New-PublisherRule -PublisherName $metadata.PublisherName -ProductName $metadata.ProductName -BinaryName $metadata.BinaryName -Action $RequestedAction -CollectionType $metadata.CollectionType -Description "Event Viewer generated publisher rule for $($metadata.FilePath)" -UserOrGroupSid $resolvedTargetSid -Status $RequestedStatus -Save
                    }
                    'Hash' {
                        if ([string]::IsNullOrWhiteSpace([string]$metadata.Hash)) {
                            $skipped++
                            if ($sampleMessages.Count -lt 3) { [void]$sampleMessages.Add("Skipped hash: $($metadata.FilePath)") }
                            continue
                        }

                        $ruleResult = New-HashRule -Hash $metadata.Hash -SourceFileName $metadata.FileName -SourceFileLength $metadata.FileLength -Action $RequestedAction -CollectionType $metadata.CollectionType -Description "Event Viewer generated hash rule for $($metadata.FilePath)" -UserOrGroupSid $resolvedTargetSid -Status $RequestedStatus -Save
                    }
                    default {
                        $ruleResult = New-PathRule -Path $metadata.FilePath -Action $RequestedAction -CollectionType $metadata.CollectionType -Description "Event Viewer generated path rule for $($metadata.FilePath)" -UserOrGroupSid $resolvedTargetSid -Status $RequestedStatus -Save
                    }
                }

                if ($ruleResult -and $ruleResult.Success) {
                    $created++
                }
                else {
                    $failed++
                    if ($sampleMessages.Count -lt 3) {
                        $err = if ($ruleResult -and $ruleResult.Error) { [string]$ruleResult.Error } else { 'Unknown create failure' }
                        [void]$sampleMessages.Add("Failed: $err")
                    }
                }
            }
            catch {
                $failed++
                if ($sampleMessages.Count -lt 3) {
                    [void]$sampleMessages.Add("Failed: $($_.Exception.Message)")
                }
            }
        }

        return [PSCustomObject]@{
            Requested = @($InputRows).Count
            Created = $created
            Skipped = $skipped
            Failed = $failed
            Mode = $RequestedMode
            Action = $RequestedAction
            TargetSid = $resolvedTargetSid
            SampleMessages = @($sampleMessages)
        }
    } -Arguments @{
        InputRows = @($sourceRows)
        RequestedMode = $Mode
        RequestedAction = $Action
        RequestedTargetSid = $TargetSid
        RequestedStatus = $Status
    } -LoadingMessage 'Creating Event Viewer rules...' -LoadingSubMessage "Processing $($sourceRows.Count) selected row(s)..." -OnComplete {
        param($Result)

        $activeWindow = if ($Window) { $Window } else { $global:GA_MainWindow }
        if ($activeWindow) {
            $summaryControl = $activeWindow.FindName('TxtEventViewerQuerySummary')
            if ($summaryControl) {
                $summaryControl.Text = 'Rule creation complete. Review counts and continue triage.'
            }
        }

        $message = "Created $($Result.Created) rule(s). Skipped $($Result.Skipped). Failed $($Result.Failed)."
        if (@($Result.SampleMessages).Count -gt 0) {
            $message += ' ' + ((@($Result.SampleMessages) -join ' | '))
        }

        $type = if ($Result.Created -gt 0 -and $Result.Failed -eq 0) { 'Success' } else { 'Warning' }
        Show-EventViewerToast -Message $message -Type $type

        if ($Result.Created -gt 0 -and (Get-Command -Name 'Update-RulesDataGrid' -ErrorAction SilentlyContinue)) {
            try { Update-RulesDataGrid -Window $activeWindow } catch { }
        }
    }.GetNewClosure() -OnError {
        param($ErrorMessage)

        $activeWindow = if ($Window) { $Window } else { $global:GA_MainWindow }
        if ($activeWindow) {
            $summaryControl = $activeWindow.FindName('TxtEventViewerQuerySummary')
            if ($summaryControl) {
                $summaryControl.Text = 'Rule creation failed. Review selection and try again.'
            }
        }

        Show-EventViewerToast -Message "Failed to create Event Viewer rules: $ErrorMessage" -Type 'Error'
    }.GetNewClosure()
}

function global:Invoke-EventViewerRuleActionByTag {
    param(
        $Window,
        [string]$Tag
    )

    $actionMap = @{
        'EventViewerCreateRuleRecommended' = @{ Mode = 'Recommended'; UseSelection = $false }
        'EventViewerCreateRulesSelectedRecommended' = @{ Mode = 'Recommended'; UseSelection = $true }
        'EventViewerCreateRulePublisher' = @{ Mode = 'Publisher'; UseSelection = $false }
        'EventViewerCreateRuleHash' = @{ Mode = 'Hash'; UseSelection = $false }
        'EventViewerCreateRulePath' = @{ Mode = 'Path'; UseSelection = $false }
        'EventViewerCreateRulesSelectedPublisher' = @{ Mode = 'Publisher'; UseSelection = $true }
        'EventViewerCreateRulesSelectedHash' = @{ Mode = 'Hash'; UseSelection = $true }
        'EventViewerCreateRulesSelectedPath' = @{ Mode = 'Path'; UseSelection = $true }
    }

    if (-not $actionMap.ContainsKey($Tag)) {
        return
    }

    $win = if ($Window) { $Window } else { $global:GA_MainWindow }
    if (-not $win) { return }

    $mode = [string]$actionMap[$Tag].Mode
    $useSelection = [bool]$actionMap[$Tag].UseSelection
    $rows = Get-EventViewerSelectedRows -Window $win -UseSelection $useSelection

    if (@($rows).Count -eq 0) {
        Show-EventViewerToast -Message 'Select one or more event rows first.' -Type 'Warning'
        return
    }

    $defaults = Get-EventViewerRuleDefaults -Window $win
    $confirmation = Confirm-EventViewerRuleGeneration -Mode $mode -Count @($rows).Count -Action $defaults.Action -TargetSid $defaults.TargetSid
    if ([string]$confirmation -ne 'Yes') {
        Show-EventViewerToast -Message 'Rule creation canceled.' -Type 'Info'
        return
    }

    Invoke-EventViewerRuleCreationAsync -Window $win -Rows @($rows) -Mode $mode -TargetSid $defaults.TargetSid -Action $defaults.Action -Status $defaults.Status
}

function global:ConvertTo-EventViewerHostStatusRows {
    param(
        [Parameter()]
        [PSCustomObject[]]$Envelopes
    )

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($envelope in @($Envelopes)) {
        if (-not $envelope) { continue }

        $isSuccess = [bool]$envelope.Success
        $status = if ($isSuccess) { 'Success' } else { 'Failed' }
        $count = if ($null -ne $envelope.Count) { [int]$envelope.Count } else { 0 }
        $duration = if ($null -ne $envelope.DurationMs) { [int]$envelope.DurationMs } else { 0 }
        $message = if ($isSuccess) {
            "$count event(s) retrieved"
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$envelope.Error)) {
            [string]$envelope.Error
        }
        else {
            'Event query failed.'
        }

        [void]$rows.Add([PSCustomObject]@{
                Host          = [string]$envelope.Host
                Status        = $status
                Events        = $count
                DurationMs    = $duration
                ErrorCategory = if ($isSuccess) { '' } else { [string]$envelope.ErrorCategory }
                Message       = $message
            })
    }

    return @($rows)
}

function global:ConvertTo-EventViewerRows {
    param(
        [Parameter()]
        [PSCustomObject[]]$Envelopes
    )

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($envelope in @($Envelopes)) {
        if (-not $envelope -or -not $envelope.Success) { continue }

        foreach ($event in @($envelope.Data)) {
            if (-not $event) { continue }

            $timeCreated = $null
            if ($event.PSObject.Properties.Name -contains 'TimeCreated') {
                $timeCreated = $event.TimeCreated
            }
            elseif ($event.PSObject.Properties.Name -contains 'Timestamp') {
                $timeCreated = $event.Timestamp
            }

            $eventId = $null
            if ($event.PSObject.Properties.Name -contains 'EventId') {
                $eventId = $event.EventId
            }
            elseif ($event.PSObject.Properties.Name -contains 'Id') {
                $eventId = $event.Id
            }

            [void]$rows.Add([PSCustomObject]@{
                    TimeCreated     = $timeCreated
                    ComputerName    = if ($event.PSObject.Properties.Name -contains 'ComputerName' -and -not [string]::IsNullOrWhiteSpace([string]$event.ComputerName)) { [string]$event.ComputerName } else { [string]$envelope.Host }
                    EventId         = $eventId
                    CollectionType  = if ($event.PSObject.Properties.Name -contains 'CollectionType') { [string]$event.CollectionType } else { '' }
                    FilePath        = if ($event.PSObject.Properties.Name -contains 'FilePath') { [string]$event.FilePath } else { '' }
                    Action          = if ($event.PSObject.Properties.Name -contains 'Action') { [string]$event.Action } else { '' }
                    UserSid         = if ($event.PSObject.Properties.Name -contains 'UserSid') { [string]$event.UserSid } else { '' }
                    EventType       = if ($event.PSObject.Properties.Name -contains 'EventType') { [string]$event.EventType } else { '' }
                    EnforcementMode = if ($event.PSObject.Properties.Name -contains 'EnforcementMode') { [string]$event.EnforcementMode } else { '' }
                    IsBlocked       = if ($event.PSObject.Properties.Name -contains 'IsBlocked') { [bool]$event.IsBlocked } else { $false }
                    IsAudit         = if ($event.PSObject.Properties.Name -contains 'IsAudit') { [bool]$event.IsAudit } else { $false }
                    Message         = if ($event.PSObject.Properties.Name -contains 'Message') { [string]$event.Message } else { '' }
                    RawXml          = if ($event.PSObject.Properties.Name -contains 'RawXml') { [string]$event.RawXml } else { '' }
                })
        }
    }

    $sortedRows = @($rows | Sort-Object -Property TimeCreated -Descending)
    return $sortedRows
}

function global:Set-EventViewerLoadingState {
    param(
        $Window,
        [bool]$IsLoading
    )

    if (-not $Window) { return }

    $runButton = $Window.FindName('BtnEventViewerRunQuery')
    if ($runButton) {
        $runButton.IsEnabled = -not $IsLoading
    }
}

function global:Invoke-LoadEventViewerData {
    param($Window)

    if (-not $Window) {
        $Window = $global:GA_MainWindow
    }

    if (-not $Window) {
        return
    }

    $validation = Test-EventViewerQueryInputs -Window $Window
    if (-not $validation.Success) {
        return
    }

    $queryContract = $validation.Data
    $summary = $Window.FindName('TxtEventViewerQuerySummary')
    $hostGrid = Get-EventViewerHostStatusGrid -Window $Window

    $script:EventViewerResults = @()
    $script:EventViewerHostStatus = @()
    $script:EventViewerFileMetrics = @()

    if ($hostGrid) { $hostGrid.ItemsSource = @() }
    Update-EventViewerResultBindings -Window $Window -EventRows @()
    if ($summary) { $summary.Text = 'Running bounded event query...' }

    Set-EventViewerLoadingState -Window $Window -IsLoading $true

    Invoke-AsyncOperation -ScriptBlock {
        param($Query)

        $envelopes = Invoke-AppLockerEventQuery -ComputerName @($Query.Targets) -StartTime $Query.StartTime -EndTime $Query.EndTime -MaxEvents $Query.MaxEvents -EventIds @($Query.EventIds)

        return [PSCustomObject]@{
            Query     = $Query
            Envelopes = @($envelopes)
        }
    } -Arguments @{ Query = $queryContract } -LoadingMessage 'Loading AppLocker events...' -OnComplete {
        param($Result)

        $activeWindow = if ($Window) { $Window } else { $global:GA_MainWindow }
        if (-not $activeWindow) { return }

        $hostGridControl = Get-EventViewerHostStatusGrid -Window $activeWindow
        $summaryControl = $activeWindow.FindName('TxtEventViewerQuerySummary')

        $query = if ($Result) { $Result.Query } else { $queryContract }
        $envelopes = if ($Result) { @($Result.Envelopes) } else { @() }

        $hostRows = ConvertTo-EventViewerHostStatusRows -Envelopes $envelopes
        $eventRows = ConvertTo-EventViewerRows -Envelopes $envelopes

        $script:EventViewerHostStatus = @($hostRows)
        $script:EventViewerResults = @($eventRows)

        if ($hostGridControl) {
            $hostGridControl.ItemsSource = @($hostRows)
        }
        Update-EventViewerResultBindings -Window $activeWindow -EventRows @($eventRows)

        $requestedHosts = @($envelopes).Count
        $successHosts = @($envelopes | Where-Object { $_.Success }).Count
        $failedHosts = $requestedHosts - $successHosts

        if ($summaryControl) {
            $summaryControl.Text = 'Hosts requested: {0} (success: {1}, failed: {2}) | Events: {3} | Bounds: {4} to {5} | Max {6}' -f $requestedHosts, $successHosts, $failedHosts, @($eventRows).Count, $query.StartTime.ToString('yyyy-MM-dd HH:mm'), $query.EndTime.ToString('yyyy-MM-dd HH:mm'), $query.MaxEvents
        }

        Set-EventViewerLoadingState -Window $activeWindow -IsLoading $false

        Show-EventViewerToast -Message ('Loaded {0} event(s) across {1} requested host(s).' -f @($eventRows).Count, $requestedHosts) -Type 'Success'
    }.GetNewClosure() -OnError {
        param($ErrorMessage)

        $activeWindow = if ($Window) { $Window } else { $global:GA_MainWindow }
        if ($activeWindow) {
            $summaryControl = $activeWindow.FindName('TxtEventViewerQuerySummary')
            if ($summaryControl) {
                $summaryControl.Text = 'Query failed. Update bounds/targets and retry.'
            }
            Set-EventViewerLoadingState -Window $activeWindow -IsLoading $false
        }

        Show-EventViewerToast -Message "Failed to load AppLocker events: $ErrorMessage" -Type 'Error'
    }.GetNewClosure()
}

function Initialize-EventViewerPanel {
    param($Window)

    if (-not $Window) { return }

    $startPicker = $Window.FindName('DpEventViewerStartTime')
    $endPicker = $Window.FindName('DpEventViewerEndTime')
    $maxEvents = $Window.FindName('TxtEventViewerMaxEvents')
    $targetScope = $Window.FindName('CboEventViewerTargetScope')
    $remoteHosts = $Window.FindName('TxtEventViewerRemoteHosts')
    $summary = $Window.FindName('TxtEventViewerQuerySummary')
    $resultCount = $Window.FindName('TxtEventViewerResultCount')
    $uniqueFiles = $Window.FindName('TxtEventViewerUniqueFiles')
    $topFile = $Window.FindName('TxtEventViewerTopFile')
    $topFileCount = $Window.FindName('TxtEventViewerTopFileCount')
    $hostGrid = Get-EventViewerHostStatusGrid -Window $Window
    $resultsGrid = Get-EventViewerEventsGrid -Window $Window
    $metricsGrid = Get-EventViewerMetricsGrid -Window $Window
    $emptyLabel = $Window.FindName('TxtEventViewerEmpty')
    $metricEmptyLabel = $Window.FindName('TxtEventViewerFileMetricsEmpty')
    $searchBox = $Window.FindName('TxtEventViewerSearch')
    $btnRunQuery = $Window.FindName('BtnEventViewerRunQuery')
    $btnClear = $Window.FindName('BtnEventViewerClearResults')
    $btnCreateRule = $Window.FindName('BtnEventViewerCreateRule')
    $btnCreateRulesSelected = $Window.FindName('BtnEventViewerCreateRulesSelected')

    if ($startPicker -and -not $startPicker.SelectedDate) {
        $startPicker.SelectedDate = [DateTime]::Now.AddDays(-7)
    }
    if ($endPicker -and -not $endPicker.SelectedDate) {
        $endPicker.SelectedDate = [DateTime]::Now
    }

    # Force calendar popup readable on dark theme.
    # WPF Calendar template parts use hardcoded colors that ignore style overrides.
    # We walk the visual tree on CalendarOpened to fix Background/Foreground on the
    # Calendar itself plus all TextBlock children (month/year header, day-of-week labels).
    $calendarFixScript = {
        param($sender, $e)
        try {
            $dp = $sender
            $whiteBrush = [System.Windows.Media.Brushes]::White
            $darkBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x2D, 0x2D, 0x30))

            # Try reflection first (most reliable for the Calendar control itself)
            $cal = $null
            $calProp = $dp.GetType().GetProperty('Calendar', [System.Reflection.BindingFlags]'Instance,NonPublic,Public')
            if ($calProp) { $cal = $calProp.GetValue($dp) }

            if ($cal) {
                $cal.Background = $darkBg
                $cal.Foreground = $whiteBrush

                # Walk visual tree to fix template TextBlocks (header, day labels)
                $cal.UpdateLayout()
                $stack = [System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new()
                $stack.Push($cal)
                while ($stack.Count -gt 0) {
                    $parent = $stack.Pop()
                    $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($parent)
                    for ($i = 0; $i -lt $childCount; $i++) {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($parent, $i)
                        if ($child -is [System.Windows.Controls.TextBlock]) {
                            $child.Foreground = $whiteBrush
                        }
                        elseif ($child -is [System.Windows.Controls.Control]) {
                            $child.Foreground = $whiteBrush
                            $child.Background = $darkBg
                        }
                        $stack.Push($child)
                    }
                }
            }
        } catch { }
    }
    if ($startPicker -and $startPicker.PSObject.Methods['Add_CalendarOpened']) {
        $startPicker.Add_CalendarOpened($calendarFixScript)
    }
    if ($endPicker -and $endPicker.PSObject.Methods['Add_CalendarOpened']) {
        $endPicker.Add_CalendarOpened($calendarFixScript)
    }
    if ($maxEvents -and [string]::IsNullOrWhiteSpace([string]$maxEvents.Text)) {
        $maxEvents.Text = '500'
    }
    if ($targetScope -and $targetScope.SelectedIndex -lt 0) {
        $targetScope.SelectedIndex = 0
    }
    if ($remoteHosts -and $null -eq $remoteHosts.Text) {
        $remoteHosts.Text = ''
    }
    if ($searchBox -and $null -eq $searchBox.Text) {
        $searchBox.Text = ''
    }

    $script:EventViewerResults = @()
    $script:EventViewerHostStatus = @()
    $script:EventViewerFileMetrics = @()

    if ($hostGrid) {
        $hostGrid.ItemsSource = @()
    }
    if ($resultsGrid) {
        $resultsGrid.ItemsSource = @()
    }
    if ($metricsGrid) {
        $metricsGrid.ItemsSource = @()
    }
    if ($emptyLabel) {
        $emptyLabel.Visibility = 'Visible'
    }
    if ($metricEmptyLabel) {
        $metricEmptyLabel.Visibility = 'Visible'
    }
    if ($resultCount) {
        $resultCount.Text = '0 events'
    }
    if ($uniqueFiles) {
        $uniqueFiles.Text = '0'
    }
    if ($topFile) {
        $topFile.Text = '-'
    }
    if ($topFileCount) {
        $topFileCount.Text = '0'
    }
    if ($summary) {
        $summary.Text = 'Query window pending. Set start/end and run retrieval.'
    }

    if ($btnRunQuery) {
        $btnRunQuery.IsEnabled = $true
        $btnRunQuery.ToolTip = 'Run bounded AppLocker event retrieval for local or selected remote hosts.'
        $btnRunQuery.Add_Click({
                Invoke-LoadEventViewerData -Window $global:GA_MainWindow
            })
    }

    if ($btnCreateRule) {
        $btnCreateRule.Add_Click({
                $win = if ($global:GA_MainWindow) { $global:GA_MainWindow } else { $Window }
                if (-not $win) { return }

                $selectedMode = Get-EventViewerRuleMode -Window $win
                switch ($selectedMode) {
                    'Publisher' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulePublisher' }
                    'Hash' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRuleHash' }
                    'Path' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulePath' }
                    default { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRuleRecommended' }
                }
            })
    }

    if ($btnCreateRulesSelected) {
        $btnCreateRulesSelected.Add_Click({
                $win = if ($global:GA_MainWindow) { $global:GA_MainWindow } else { $Window }
                if (-not $win) { return }

                $selectedMode = Get-EventViewerRuleMode -Window $win
                switch ($selectedMode) {
                    'Publisher' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulesSelectedPublisher' }
                    'Hash' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulesSelectedHash' }
                    'Path' { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulesSelectedPath' }
                    default { Invoke-EventViewerRuleActionByTag -Window $win -Tag 'EventViewerCreateRulesSelectedRecommended' }
                }
            })
    }

    if ($searchBox) {
        $searchBox.Add_TextChanged({
                $win = if ($global:GA_MainWindow) { $global:GA_MainWindow } else { $Window }
                if (-not $win) { return }
                Update-EventViewerResultBindings -Window $win -EventRows @($script:EventViewerResults)
            })
    }

    if ($resultsGrid -and $resultsGrid.ContextMenu -and $resultsGrid.ContextMenu.Items) {
        foreach ($menuItem in @($resultsGrid.ContextMenu.Items)) {
            if (-not $menuItem) { continue }

            if ($menuItem.PSObject.Properties.Name -contains 'Tag' -and -not [string]::IsNullOrWhiteSpace([string]$menuItem.Tag)) {
                $menuItem.Add_Click({
                        $item = $this
                        $win = if ($global:GA_MainWindow) { $global:GA_MainWindow } else { $Window }
                        if (-not $win) { return }
                        Invoke-EventViewerRuleActionByTag -Window $win -Tag ([string]$item.Tag)
                    })
            }

            if ($menuItem.PSObject.Properties.Name -contains 'Items' -and $menuItem.Items) {
                foreach ($child in @($menuItem.Items)) {
                    if (-not $child) { continue }
                    if ($child.PSObject.Properties.Name -contains 'Tag' -and -not [string]::IsNullOrWhiteSpace([string]$child.Tag)) {
                        $child.Add_Click({
                                $item = $this
                                $win = if ($global:GA_MainWindow) { $global:GA_MainWindow } else { $Window }
                                if (-not $win) { return }
                                Invoke-EventViewerRuleActionByTag -Window $win -Tag ([string]$item.Tag)
                            })
                    }
                }
            }
        }
    }

    if ($btnClear) {
        $btnClear.Add_Click({
                $win = $global:GA_MainWindow
                if (-not $win) { return }

                $hostGridLocal = Get-EventViewerHostStatusGrid -Window $win
                $resultsGridLocal = Get-EventViewerEventsGrid -Window $win
                $metricsGridLocal = Get-EventViewerMetricsGrid -Window $win
                $emptyLocal = $win.FindName('TxtEventViewerEmpty')
                $metricEmptyLocal = $win.FindName('TxtEventViewerFileMetricsEmpty')
                $countLocal = $win.FindName('TxtEventViewerResultCount')
                $uniqueLocal = $win.FindName('TxtEventViewerUniqueFiles')
                $topFileLocal = $win.FindName('TxtEventViewerTopFile')
                $topCountLocal = $win.FindName('TxtEventViewerTopFileCount')
                $searchLocal = $win.FindName('TxtEventViewerSearch')
                $summaryLocal = $win.FindName('TxtEventViewerQuerySummary')

                $script:EventViewerResults = @()
                $script:EventViewerHostStatus = @()
                $script:EventViewerFileMetrics = @()

                if ($hostGridLocal) { $hostGridLocal.ItemsSource = @() }
                if ($resultsGridLocal) { $resultsGridLocal.ItemsSource = @() }
                if ($metricsGridLocal) { $metricsGridLocal.ItemsSource = @() }
                if ($emptyLocal) { $emptyLocal.Visibility = 'Visible' }
                if ($metricEmptyLocal) { $metricEmptyLocal.Visibility = 'Visible' }
                if ($countLocal) { $countLocal.Text = '0 events' }
                if ($uniqueLocal) { $uniqueLocal.Text = '0' }
                if ($topFileLocal) { $topFileLocal.Text = '-' }
                if ($topCountLocal) { $topCountLocal.Text = '0' }
                if ($searchLocal) { $searchLocal.Text = '' }
                if ($summaryLocal) { $summaryLocal.Text = 'Results cleared. Configure bounds and run retrieval.' }
            })
    }
}

#endregion
