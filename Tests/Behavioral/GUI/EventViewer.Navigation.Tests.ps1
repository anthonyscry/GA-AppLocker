#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $script:MainWindowXamlPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml'
}

Describe 'Event Viewer panel shell in MainWindow XAML' {
    It 'Includes navigation entry and bounded retrieval shell controls' {
        $xaml = Get-Content -Path $script:MainWindowXamlPath -Raw

        $xaml | Should -Match 'x:Name="NavEventViewer"'
        $xaml | Should -Match 'x:Name="NavEventViewerText"[^>]*Text="Event Viewer"'
        $xaml | Should -Match 'x:Name="PanelEventViewer"'
        $xaml | Should -Match 'x:Name="DpEventViewerStartTime"'
        $xaml | Should -Match 'x:Name="DpEventViewerEndTime"'
        $xaml | Should -Match 'x:Name="TxtEventViewerMaxEvents"'
        $xaml | Should -Match 'x:Name="CboEventViewerTargetScope"'
        $xaml | Should -Match 'x:Name="TxtEventViewerRemoteHosts"'
        $xaml | Should -Match 'x:Name="EventViewerHostStatusGrid"'
        $xaml | Should -Match 'x:Name="EventViewerResultsGrid"'
        $xaml | Should -Match 'x:Name="TxtEventViewerEmpty"'
    }
}
