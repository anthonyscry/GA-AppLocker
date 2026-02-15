#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:ScannerPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Scanner.ps1'
    . $script:ScannerPath

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')

    $script:MainWindowXamlPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml'
}

Describe 'Get-ScanEventMetrics' {
    It 'Groups by machine, path, and event type and reports blocked/audit totals' {
        $now = Get-Date

        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now.AddMinutes(-10) },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true;  TimeCreated = $now }
        )

        $result = Get-ScanEventMetrics -Events $events -Mode 'All' -TopN 10

        $result.Count | Should -Be 2
        $blockedRow = $result | Where-Object { $_.EventType -eq 'EXE/DLL Blocked' }
        $auditRow = $result | Where-Object { $_.EventType -like '*Would Block*' }

        @($blockedRow).Count | Should -Be 1
        $blockedRow[0].FilePath | Should -Be 'C:\app\\x.exe'
        $blockedRow[0].BlockedCount | Should -Be 2
        $blockedRow[0].AuditCount | Should -Be 0
        $blockedRow[0].Count | Should -Be 2

        @($auditRow).Count | Should -Be 1
        $auditRow[0].AuditCount | Should -Be 1
        $auditRow[0].BlockedCount | Should -Be 0
        $auditRow[0].Count | Should -Be 1
    }

    It 'Filters to blocked or audit modes before grouping' {
        $now = Get-Date

        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\y.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true;  TimeCreated = $now }
        )

        (Get-ScanEventMetrics -Events $events -Mode 'Blocked' -TopN 20).Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Blocked' -TopN 20)[0].FilePath | Should -Be 'C:\app\\x.exe'
        (Get-ScanEventMetrics -Events $events -Mode 'Audit' -TopN 20).Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Audit' -TopN 20)[0].FilePath | Should -Be 'C:\app\\y.exe'
    }

    It 'Applies machine and path filters and top-N limit' {
        $now = Get-Date

        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS2'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\y.exe'; ComputerName = 'WKS1'; EventType = 'Script Audit';      IsBlocked = $false; IsAudit = $true;  TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'Script Audit';      IsBlocked = $false; IsAudit = $true;  TimeCreated = $now }
        )

        (Get-ScanEventMetrics -Events $events -Mode 'All' -Machine 'WKS1' -TopN 2).Count | Should -Be 2
        (Get-ScanEventMetrics -Events $events -Mode 'Blocked' -Machine 'WKS1').Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Audit' -Machine 'WKS1' -PathFilter 'y.exe')[0].Count | Should -Be 1
    }
}

Describe 'Update-EventMetricsUI filter behavior' {
    AfterEach {
        if ($script:CurrentEventMetricsFilter) { $script:CurrentEventMetricsFilter = $null }
        if ($script:CurrentScanEventLogs) { $script:CurrentScanEventLogs = @() }
    }

    It 'Updates the grid rows when mode, machine, path, and top-N change' {
        $now = Get-Date
        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\blocked-1.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\blocked-2.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\audit-1.exe';   ComputerName = 'WKS1'; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true;  TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\wks2.exe';     ComputerName = 'WKS2'; EventType = 'Script Audit';             IsBlocked = $false; IsAudit = $true;  TimeCreated = $now }
        )

        $eventGrid = New-MockDataGrid
        $emptyLabel = New-MockTextBlock -Visibility 'Visible'
        $script:CurrentScanEventLogs = @($events)
        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
            TxtEventMetricsEmpty = $emptyLabel
            CboEventMode = New-MockComboBox -Items @('All', 'Blocked', 'Audit') -SelectedIndex 0
            CboEventMachine = New-MockComboBox -Items @('All') -SelectedIndex 0
            TxtEventPathFilter = New-MockTextBox -Text ''
            TxtEventTopN = New-MockTextBox -Text '20'
            TxtEventTotalCount = New-MockTextBlock
            TxtEventBlockedCount = New-MockTextBlock
            TxtEventAuditCount = New-MockTextBlock
        }

        Initialize-ScanEventMetricsState -Window $win

        # Baseline: Initialize call should populate all rows in All mode
        $total = [int]($win.FindName('TxtEventTotalCount').Text)
        $total | Should -Be 4

        @($eventGrid.ItemsSource).Count | Should -Be 4

        Set-EventMetricsFilterState -Mode 'Blocked' -Machine 'WKS1' -TopN 1
        Update-EventMetricsUI -Window $win

        @($eventGrid.ItemsSource).Count | Should -Be 1
        $eventGrid.ItemsSource[0].Count | Should -Be 1

        Set-EventMetricsFilterState -Mode 'Audit' -Machine 'All' -PathFilter 'wks2' -TopN 20
        Update-EventMetricsUI -Window $win

        @($eventGrid.ItemsSource).Count | Should -Be 1
        $eventGrid.ItemsSource[0].Machine | Should -Be 'WKS2'
        $eventGrid.ItemsSource[0].EventType | Should -Be 'Script Audit'
        $emptyLabel.Visibility | Should -Be 'Collapsed'
    }

    It 'Resets metrics when scan event logs are cleared' {
        $eventGrid = New-MockDataGrid
        $emptyLabel = New-MockTextBlock -Visibility 'Collapsed'
        $script:CurrentScanEventLogs = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true; IsAudit = $false; TimeCreated = Get-Date }
        )

        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
            TxtEventMetricsEmpty = $emptyLabel
            CboEventMode = New-MockComboBox -Items @('All', 'Blocked', 'Audit') -SelectedIndex 0
            CboEventMachine = New-MockComboBox -Items @('All', 'WKS1') -SelectedIndex 1
            TxtEventPathFilter = New-MockTextBox -Text ''
            TxtEventTopN = New-MockTextBox -Text '20'
            TxtEventTotalCount = New-MockTextBlock
            TxtEventBlockedCount = New-MockTextBlock
            TxtEventAuditCount = New-MockTextBlock
        }

        Initialize-ScanEventMetricsState -Window $win

        Set-EventMetricsFilterDefaults -Window $win

        @($eventGrid.ItemsSource) | Should -BeNullOrEmpty
        $win.FindName('TxtEventMetricsEmpty').Visibility | Should -Be 'Visible'
        [int]($win.FindName('TxtEventTotalCount').Text) | Should -Be 0
        [int]($win.FindName('TxtEventBlockedCount').Text) | Should -Be 0
        [int]($win.FindName('TxtEventAuditCount').Text) | Should -Be 0
    }
}

Describe 'MainWindow event metrics XAML controls' {
    It 'Contains event-metrics counter, filter, and results controls' {
        $mainWindowXaml = Get-Content -Path $script:MainWindowXamlPath -Raw

        $mainWindowXaml | Should -Match 'x:Name="TxtEventTotalCount"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventBlockedCount"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventAuditCount"'
        $mainWindowXaml | Should -Match 'x:Name="CboEventMode"'
        $mainWindowXaml | Should -Match 'x:Name="CboEventMachine"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventPathFilter"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventTopN"'
        $mainWindowXaml | Should -Match 'x:Name="EventMetricsDataGrid"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventMetricsEmpty"'
    }
}
