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

function script:Show-EventViewerToast {
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
    $hostGrid = $Window.FindName('EventViewerHostStatusGrid')
    $resultsGrid = $Window.FindName('EventViewerResultsGrid')
    $emptyLabel = $Window.FindName('TxtEventViewerEmpty')
    $btnRunQuery = $Window.FindName('BtnEventViewerRunQuery')
    $btnClear = $Window.FindName('BtnEventViewerClearResults')

    if ($startPicker -and -not $startPicker.SelectedDate) {
        $startPicker.SelectedDate = [DateTime]::Now.AddHours(-24)
    }
    if ($endPicker -and -not $endPicker.SelectedDate) {
        $endPicker.SelectedDate = [DateTime]::Now
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

    $script:EventViewerResults = @()
    $script:EventViewerHostStatus = @()

    if ($hostGrid) {
        $hostGrid.ItemsSource = @()
    }
    if ($resultsGrid) {
        $resultsGrid.ItemsSource = @()
    }
    if ($emptyLabel) {
        $emptyLabel.Visibility = 'Visible'
    }
    if ($resultCount) {
        $resultCount.Text = '0 events'
    }
    if ($summary) {
        $summary.Text = 'Query window pending. Set start/end and run retrieval.'
    }

    if ($btnRunQuery) {
        $btnRunQuery.IsEnabled = $true
        $btnRunQuery.ToolTip = 'Run bounded AppLocker event retrieval for local or selected remote hosts.'
    }

    if ($btnClear) {
        $btnClear.Add_Click({
                $win = $global:GA_MainWindow
                if (-not $win) { return }

                $hostGridLocal = $win.FindName('EventViewerHostStatusGrid')
                $resultsGridLocal = $win.FindName('EventViewerResultsGrid')
                $emptyLocal = $win.FindName('TxtEventViewerEmpty')
                $countLocal = $win.FindName('TxtEventViewerResultCount')
                $summaryLocal = $win.FindName('TxtEventViewerQuerySummary')

                $script:EventViewerResults = @()
                $script:EventViewerHostStatus = @()

                if ($hostGridLocal) { $hostGridLocal.ItemsSource = @() }
                if ($resultsGridLocal) { $resultsGridLocal.ItemsSource = @() }
                if ($emptyLocal) { $emptyLocal.Visibility = 'Visible' }
                if ($countLocal) { $countLocal.Text = '0 events' }
                if ($summaryLocal) { $summaryLocal.Text = 'Results cleared. Configure bounds and run retrieval.' }
            })
    }
}

#endregion
