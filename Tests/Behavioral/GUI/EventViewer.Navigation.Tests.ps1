#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:MainWindowXamlPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml'
    $script:MainWindowCodeBehindPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml.ps1'
    $script:EventViewerPanelPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\EventViewer.ps1'

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . $script:EventViewerPanelPath
}

Describe 'Event Viewer panel shell in MainWindow XAML' {
    It 'Includes navigation entry and bounded retrieval shell controls' {
        $xaml = Get-Content -Path $script:MainWindowXamlPath -Raw

        $xaml | Should -Match 'x:Name="NavEventViewer"'
        $xaml | Should -Match 'x:Name="NavEventViewerText"[^>]*Text="Event Viewer"'
        $xaml | Should -Match 'x:Name="PanelEventViewer"'
        $xaml | Should -Match 'x:Name="DpEventViewerStartTime"'
        $xaml | Should -Match 'x:Name="DpEventViewerEndTime"'
        $xaml | Should -Match 'x:Name="DpEventViewerStartTime"[^>]*Style="\{StaticResource DatePickerStyle\}"'
        $xaml | Should -Match 'x:Name="DpEventViewerEndTime"[^>]*Style="\{StaticResource DatePickerStyle\}"'
        $xaml | Should -Match 'x:Name="TxtEventViewerMaxEvents"'
        $xaml | Should -Match 'x:Name="CboEventViewerTargetScope"'
        $xaml | Should -Match 'x:Name="TxtEventViewerRemoteHosts"'
        $xaml | Should -Match 'x:Name="TxtEventViewerSearch"'
        $xaml | Should -Match 'x:Name="BtnEventViewerCreateRule"'
        $xaml | Should -Match 'x:Name="BtnEventViewerCreateRulesSelected"'
        $xaml | Should -Match 'x:Name="EventViewerHostStatusDataGrid"'
        $xaml | Should -Match 'x:Name="EventViewerEventsDataGrid"'
        $xaml | Should -Match 'x:Name="EventViewerFileMetricsDataGrid"'
        $xaml | Should -Match 'x:Name="TxtEventViewerUniqueFiles"'
        $xaml | Should -Match 'x:Name="TxtEventViewerTopFileCount"'
        $xaml | Should -Match 'MenuItem Header="Create Rule \(Recommended\)"'
        $xaml | Should -Match 'MenuItem Header="Create Rules from Selected"'
        $xaml | Should -Match 'x:Name="TxtEventViewerEmpty"'
    }
}

Describe 'Event Viewer navigation and initialization wiring in MainWindow code-behind' {
    It 'Routes nav action and panel visibility mapping to PanelEventViewer' {
        $codeBehind = Get-Content -Path $script:MainWindowCodeBehindPath -Raw

        $codeBehind | Should -Match "'NavEventViewer'\s*\{\s*Set-ActivePanel\s*-PanelName\s*'PanelEventViewer'\s*\}"
        $codeBehind | Should -Match "'PanelEventViewer'"
        $codeBehind | Should -Match "'NavEventViewer'\s*=\s*'PanelEventViewer'"
        $codeBehind | Should -Match "FindName\('NavEventViewer'\)"
        $codeBehind | Should -Match "Invoke-ButtonAction\s*-Action\s*'NavEventViewer'"
    }

    It 'Invokes Initialize-EventViewerPanel during main window startup' {
        $codeBehind = Get-Content -Path $script:MainWindowCodeBehindPath -Raw

        $codeBehind | Should -Match 'Initialize-EventViewerPanel\s*-Window\s*\$Window'
        $codeBehind | Should -Match "Event Viewer panel initialized"
    }
}

Describe 'Initialize-EventViewerPanel shell behavior' {
    It 'Seeds default bounded-query values and empty grid placeholders' {
        $startPicker = [PSCustomObject]@{ SelectedDate = $null }
        $endPicker = [PSCustomObject]@{ SelectedDate = $null }
        $maxEvents = New-MockTextBox -Text ''
        $targetScope = New-MockComboBox -Items @('Local Machine', 'Remote Machines') -SelectedIndex 0
        $remoteHosts = New-MockTextBox -Text ''
        $summary = New-MockTextBlock
        $resultCount = New-MockTextBlock
        $hostGrid = New-MockDataGrid -Data @([PSCustomObject]@{ HostName = 'seed' })
        $resultsGrid = New-MockDataGrid -Data @([PSCustomObject]@{ EventId = 1 })
        $empty = New-MockTextBlock -Visibility 'Collapsed'
        $btnRun = New-MockButton -Content 'Run Query'
        $btnClear = New-MockButton -Content 'Clear'
        $btnRun | Add-Member -MemberType NoteProperty -Name ToolTip -Value $null -Force

        $win = New-MockWpfWindow -Elements @{
            DpEventViewerStartTime    = $startPicker
            DpEventViewerEndTime      = $endPicker
            TxtEventViewerMaxEvents   = $maxEvents
            CboEventViewerTargetScope = $targetScope
            TxtEventViewerRemoteHosts = $remoteHosts
            TxtEventViewerQuerySummary = $summary
            TxtEventViewerResultCount = $resultCount
            EventViewerHostStatusGrid = $hostGrid
            EventViewerResultsGrid    = $resultsGrid
            TxtEventViewerEmpty       = $empty
            BtnEventViewerRunQuery    = $btnRun
            BtnEventViewerClearResults = $btnClear
        }

        Initialize-EventViewerPanel -Window $win

        $startPicker.SelectedDate | Should -Not -BeNullOrEmpty
        $endPicker.SelectedDate | Should -Not -BeNullOrEmpty
        $maxEvents.Text | Should -Be '500'
        @($hostGrid.ItemsSource).Count | Should -Be 0
        @($resultsGrid.ItemsSource).Count | Should -Be 0
        $resultCount.Text | Should -Be '0 events'
        $empty.Visibility | Should -Be 'Visible'
        $btnRun.IsEnabled | Should -BeTrue
        $btnRun.ToolTip | Should -Match 'Run bounded AppLocker event retrieval'
    }
}

Describe 'Event Viewer action handler wiring' {
    It 'wires Event Viewer action buttons to callable handlers' {
        $handlers = Get-Command -Name Invoke-EventViewer* -ErrorAction SilentlyContinue
        @($handlers).Count | Should -BeGreaterThan 0
    }
}
