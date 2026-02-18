#region Event Viewer Panel Functions

# Shared panel state (shell scaffolding for EVT-01)
$script:EventViewerQueryState = @{
    StartTime   = $null
    EndTime     = $null
    MaxEvents   = 500
    TargetScope = 'Local'
    RemoteHosts = ''
}

$script:EventViewerResults = @()
$script:EventViewerHostStatus = @()

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
        $btnRunQuery.IsEnabled = $false
        $btnRunQuery.ToolTip = 'EVT-02 wires bounded retrieval execution.'
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
