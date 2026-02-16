#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:ScannerPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Scanner.ps1'
    . $script:ScannerPath

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')

    $script:MainWindowXamlPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\MainWindow.xaml'

    if (-not (Get-Command -Name 'Show-Toast' -ErrorAction SilentlyContinue)) {
        function global:Show-Toast {
            param(
                [string]$Message,
                [string]$Type
            )
        }
    }
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

    It 'Filters to blocked, audit, or allowed modes before grouping' {
        $now = Get-Date

        $events = @(
            [PSCustomObject]@{ FilePath = 'C:\app\\x.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Blocked'; IsBlocked = $true;  IsAudit = $false; TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\y.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Would Block (Audit)'; IsBlocked = $false; IsAudit = $true;  TimeCreated = $now },
            [PSCustomObject]@{ FilePath = 'C:\app\\z.exe'; ComputerName = 'WKS1'; EventType = 'EXE/DLL Allowed'; IsBlocked = $false; IsAudit = $false; TimeCreated = $now }
        )

        (Get-ScanEventMetrics -Events $events -Mode 'Blocked' -TopN 20).Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Blocked' -TopN 20)[0].FilePath | Should -Be 'C:\app\\x.exe'
        (Get-ScanEventMetrics -Events $events -Mode 'Audit' -TopN 20).Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Audit' -TopN 20)[0].FilePath | Should -Be 'C:\app\\y.exe'
        (Get-ScanEventMetrics -Events $events -Mode 'Allowed' -TopN 20).Count | Should -Be 1
        (Get-ScanEventMetrics -Events $events -Mode 'Allowed' -TopN 20)[0].FilePath | Should -Be 'C:\app\\z.exe'
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

    It 'Seeds event metrics path filter from shared artifact filter box' {
        $win = New-MockWpfWindow -Elements @{
            ArtifactFilterBox = New-MockTextBox -Text 'C:\app\\shared.exe'
            EventMetricsDataGrid = New-MockDataGrid
            TxtEventMetricsEmpty = New-MockTextBlock -Visibility 'Visible'
            CboEventMode = New-MockComboBox -Items @('All') -SelectedIndex 0
            CboEventMachine = New-MockComboBox -Items @('All') -SelectedIndex 0
            TxtEventTotalCount = New-MockTextBlock
            TxtEventBlockedCount = New-MockTextBlock
            TxtEventAuditCount = New-MockTextBlock
        }

        Initialize-ScanEventMetricsState -Window $win

        $script:CurrentEventMetricsFilter.PathFilter | Should -Be 'C:\app\\shared.exe'
        @($script:CurrentEventMetricsFilter.Values).Count | Should -Be 4
    }

    It 'Seeds path filter from event tab search box when shared box is unavailable' {
        $win = New-MockWpfWindow -Elements @{
            EventArtifactFilterBox = New-MockTextBox -Text 'C:\logs\\blocked.exe'
            EventMetricsDataGrid = New-MockDataGrid
            TxtEventMetricsEmpty = New-MockTextBlock -Visibility 'Visible'
            TxtEventTotalCount = New-MockTextBlock
            TxtEventBlockedCount = New-MockTextBlock
            TxtEventAuditCount = New-MockTextBlock
        }

        Initialize-ScanEventMetricsState -Window $win

        $script:CurrentEventMetricsFilter.PathFilter | Should -Be 'C:\logs\\blocked.exe'
    }
}

Describe 'Invoke-ScannerSharedSearchRefresh' {
    AfterEach {
        if ($script:CurrentEventMetricsFilter) { $script:CurrentEventMetricsFilter = $null }
    }

    It 'Refreshes artifacts and syncs event filter state when Collected Artifacts tab is active' {
        $win = New-MockWpfWindow -Elements @{
            ScannerResultsTabControl = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Header = 'Collected Artifacts' }
            }
            ArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\shared.exe'
            EventArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\shared.exe'
        }

        $script:CurrentEventMetricsFilter = @{
            Mode = 'All'
            Machine = 'All'
            PathFilter = 'C:\apps\\stale.exe'
            TopN = 20
        }

        Mock Update-ArtifactDataGrid { }
        Mock Set-EventMetricsFilterState { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win

        Should -Invoke Update-ArtifactDataGrid -Times 1 -Exactly -ParameterFilter { $Window -eq $win }
        Should -Invoke Set-EventMetricsFilterState -Times 1 -Exactly -ParameterFilter {
            [string]$PathFilter -eq 'C:\apps\\shared.exe'
        }
        Should -Invoke Update-EventMetricsUI -Times 0
    }

    It 'Refreshes only event metrics when Event Metrics tab is active' {
        $win = New-MockWpfWindow -Elements @{
            ScannerResultsTabControl = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Header = 'Event Metrics' }
            }
            ArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\event.exe'
            EventArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\event.exe'
        }

        $script:CurrentEventMetricsFilter = $null

        Mock Update-ArtifactDataGrid { }
        Mock Set-EventMetricsFilterState { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win

        Should -Invoke Update-ArtifactDataGrid -Times 0
        Should -Invoke Set-EventMetricsFilterState -Times 1 -Exactly -ParameterFilter {
            [string]$PathFilter -eq 'C:\apps\\event.exe'
        }
        Should -Invoke Update-EventMetricsUI -Times 1 -Exactly -ParameterFilter { $Window -eq $win }
    }

    It 'Routes to event metrics tab via stable Tag identity even when header differs' {
        $win = New-MockWpfWindow -Elements @{
            ScannerResultsTabControl = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Tag = 'ScannerResults_EventMetrics'; Header = 'Scanner Event Logs' }
            }
            ArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\tag-match.exe'
            EventArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\tag-match.exe'
        }

        $script:CurrentEventMetricsFilter = $null

        Mock Update-ArtifactDataGrid { }
        Mock Set-EventMetricsFilterState { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win

        Should -Invoke Update-ArtifactDataGrid -Times 0
        Should -Invoke Set-EventMetricsFilterState -Times 1 -Exactly -ParameterFilter {
            [string]$PathFilter -eq 'C:\apps\\tag-match.exe'
        }
        Should -Invoke Update-EventMetricsUI -Times 1 -Exactly -ParameterFilter { $Window -eq $win }
    }

    It 'Routes to event metrics tab via stable Name identity even when header differs' {
        $win = New-MockWpfWindow -Elements @{
            ScannerResultsTabControl = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Name = 'ScannerResultsEventMetricsTab'; Header = 'Metrics View' }
            }
            ArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\name-match.exe'
            EventArtifactFilterBox = New-MockTextBox -Text 'C:\apps\\name-match.exe'
        }

        $script:CurrentEventMetricsFilter = $null

        Mock Update-ArtifactDataGrid { }
        Mock Set-EventMetricsFilterState { }
        Mock Update-EventMetricsUI { }

        Invoke-ScannerSharedSearchRefresh -Window $win

        Should -Invoke Update-ArtifactDataGrid -Times 0
        Should -Invoke Set-EventMetricsFilterState -Times 1 -Exactly -ParameterFilter {
            [string]$PathFilter -eq 'C:\apps\\name-match.exe'
        }
        Should -Invoke Update-EventMetricsUI -Times 1 -Exactly -ParameterFilter { $Window -eq $win }
    }
}

Describe 'Invoke-GenerateRuleFromSelectedEvent' {
    BeforeEach {
        $script:CurrentScanArtifacts = @()
    }

    It 'Generates rules from matching scanned artifact metadata' {
        $selectedEvent = [PSCustomObject]@{
            FilePath = 'C:\apps\\blocked.exe'
            Machine = 'WKS1'
            EventType = 'EXE/DLL Blocked'
        }

        $eventGrid = New-MockDataGrid -Data @($selectedEvent) -SelectedItem $selectedEvent
        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
            RbRuleAllow = [PSCustomObject]@{ IsChecked = $true }
            CboPublisherLevel = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'PublisherProductFile' } }
            CboRuleTargetGroup = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'S-1-5-11' } }
            CboUnsignedMode = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Hash' } }
        }

        $script:CurrentScanArtifacts = @(
            [PSCustomObject]@{
                FilePath = 'C:\apps\\blocked.exe'
                ComputerName = 'WKS1'
                FileName = 'blocked.exe'
                SHA256Hash = 'abc123'
                IsSigned = $true
                SignerCertificate = 'CN=Contoso'
                CollectionType = 'Exe'
            }
        )

        Mock Invoke-DirectRuleGenerationWithSettings { }
        Mock Show-Toast { }

        Invoke-GenerateRuleFromSelectedEvent -Window $win

        Should -Invoke Invoke-DirectRuleGenerationWithSettings -Times 1 -ParameterFilter {
            @($Artifacts).Count -eq 1 -and
            [string]$Artifacts[0].FilePath -eq 'C:\apps\\blocked.exe' -and
            [string]$Settings.Action -eq 'Allow' -and
            [string]$Settings.PublisherLevel -eq 'PublisherProductFile' -and
            [string]$Settings.UnsignedMode -eq 'Hash'
        }
    }

    It 'Shows warning when selected event has no matching scanned artifact metadata' {
        $selectedEvent = [PSCustomObject]@{
            FilePath = 'C:\apps\\missing.exe'
            Machine = 'WKS1'
            EventType = 'EXE/DLL Blocked'
        }

        $eventGrid = New-MockDataGrid -Data @($selectedEvent) -SelectedItem $selectedEvent
        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
            RbRuleAllow = [PSCustomObject]@{ IsChecked = $true }
            CboPublisherLevel = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'PublisherProduct' } }
            CboRuleTargetGroup = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'S-1-5-11' } }
            CboUnsignedMode = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Hash' } }
        }

        $script:CurrentScanArtifacts = @(
            [PSCustomObject]@{ FilePath = 'C:\apps\\other.exe'; ComputerName = 'WKS1'; FileName = 'other.exe'; SHA256Hash = 'def456'; IsSigned = $false; CollectionType = 'Exe' }
        )

        Mock Invoke-DirectRuleGenerationWithSettings { }
        Mock Show-Toast { }

        Invoke-GenerateRuleFromSelectedEvent -Window $win

        Should -Invoke Invoke-DirectRuleGenerationWithSettings -Times 0
        Should -Invoke Show-Toast -Times 1 -ParameterFilter {
            $Type -eq 'Warning' -and $Message -like '*No scanned artifact metadata*'
        }
    }
}

Describe 'Invoke-GenerateRuleFromEventTrigger' {
    AfterEach {
        $global:GA_RuleGen_Window = $null
    }

    It 'Invokes selected-event rule generation once when idle' {
        $win = New-MockWpfWindow -Elements @{}
        $global:GA_RuleGen_Window = $null

        Mock Invoke-GenerateRuleFromSelectedEvent { }

        Invoke-GenerateRuleFromEventTrigger -Window $win

        Should -Invoke Invoke-GenerateRuleFromSelectedEvent -Times 1 -Exactly -ParameterFilter {
            $Window -eq $win
        }
    }

    It 'Ignores trigger when event rule generation is already in progress' {
        $win = New-MockWpfWindow -Elements @{}
        $global:GA_RuleGen_Window = [PSCustomObject]@{ Title = 'Busy' }

        Mock Invoke-GenerateRuleFromSelectedEvent { }

        Invoke-GenerateRuleFromEventTrigger -Window $win

        Should -Invoke Invoke-GenerateRuleFromSelectedEvent -Times 0
    }
}

Describe 'Initialize-ScannerPanel button wiring' {
    It 'Wires BtnGenerateRuleFromEvent click to unified event-rule trigger helper' {
        $btnGenerateRuleFromEvent = [PSCustomObject]@{
            _clickHandlers = [System.Collections.ArrayList]::new()
        }

        $btnGenerateRuleFromEvent | Add-Member -MemberType ScriptMethod -Name Add_Click -Value {
            param($handler)
            [void]$this._clickHandlers.Add($handler)
        }

        $btnGenerateRuleFromEvent | Add-Member -MemberType ScriptMethod -Name InvokeClick -Value {
            foreach ($handler in @($this._clickHandlers)) {
                & $handler
            }
        }

        $win = New-MockWpfWindow -Elements @{
            BtnGenerateRuleFromEvent = $btnGenerateRuleFromEvent
        }

        $previousMainWindow = $global:GA_MainWindow
        try {
            $global:GA_MainWindow = $win

            Mock Set-EventMetricsFilterDefaults { }
            Mock Update-SavedScansList { }
            Mock Initialize-ScheduledScansList { }
            Mock Invoke-GenerateRuleFromEventTrigger { }

            Initialize-ScannerPanel -Window $win
            $btnGenerateRuleFromEvent.InvokeClick()

            Should -Invoke Invoke-GenerateRuleFromEventTrigger -Times 1 -Exactly
        }
        finally {
            $global:GA_MainWindow = $previousMainWindow
        }
    }

    It 'Wires EventMetricsDataGrid double-click to unified event-rule trigger helper' {
        $eventGrid = New-MockDataGrid
        $eventGrid | Add-Member -MemberType NoteProperty -Name _doubleClickHandlers -Value ([System.Collections.ArrayList]::new()) -Force

        $eventGrid | Add-Member -MemberType ScriptMethod -Name Add_MouseDoubleClick -Value {
            param($handler)
            [void]$this._doubleClickHandlers.Add($handler)
        } -Force

        $eventGrid | Add-Member -MemberType ScriptMethod -Name InvokeMouseDoubleClick -Value {
            foreach ($handler in @($this._doubleClickHandlers)) {
                & $handler $this $null
            }
        } -Force

        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
        }

        $previousMainWindow = $global:GA_MainWindow
        try {
            $global:GA_MainWindow = $win

            Mock Set-EventMetricsFilterDefaults { }
            Mock Update-SavedScansList { }
            Mock Initialize-ScheduledScansList { }
            Mock Invoke-GenerateRuleFromEventTrigger { }

            Initialize-ScannerPanel -Window $win
            $eventGrid.InvokeMouseDoubleClick()

            Should -Invoke Invoke-GenerateRuleFromEventTrigger -Times 1 -Exactly
        }
        finally {
            $global:GA_MainWindow = $previousMainWindow
        }
    }

    It 'Routes EventMetricsDataGrid Enter key through unified event-rule trigger helper' {
        $eventGrid = New-MockDataGrid
        $eventGrid | Add-Member -MemberType NoteProperty -Name _keyDownHandlers -Value ([System.Collections.ArrayList]::new()) -Force

        $eventGrid | Add-Member -MemberType ScriptMethod -Name Add_KeyDown -Value {
            param($handler)
            [void]$this._keyDownHandlers.Add($handler)
        } -Force

        $eventGrid | Add-Member -MemberType ScriptMethod -Name InvokeKeyDown -Value {
            param([string]$Key)

            $eventArgs = [PSCustomObject]@{
                Key = $Key
                Handled = $false
            }

            foreach ($handler in @($this._keyDownHandlers)) {
                & $handler $this $eventArgs
            }

            return $eventArgs
        } -Force

        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
        }

        $previousMainWindow = $global:GA_MainWindow
        try {
            $global:GA_MainWindow = $win

            Mock Set-EventMetricsFilterDefaults { }
            Mock Update-SavedScansList { }
            Mock Initialize-ScheduledScansList { }
            Mock Invoke-GenerateRuleFromEventTrigger { }

            Initialize-ScannerPanel -Window $win
            $eventArgs = $eventGrid.InvokeKeyDown('Enter')

            Should -Invoke Invoke-GenerateRuleFromEventTrigger -Times 1 -Exactly -ParameterFilter {
                $Window -eq $global:GA_MainWindow
            }
            $eventArgs.Handled | Should -BeTrue
        }
        finally {
            $global:GA_MainWindow = $previousMainWindow
        }
    }

    It 'Routes context-menu GenerateRuleFromEvent click through unified event-rule trigger helper' {
        $menuItem = [PSCustomObject]@{
            Tag = 'GenerateRuleFromEvent'
            _clickHandlers = [System.Collections.ArrayList]::new()
        }

        $menuItem | Add-Member -MemberType ScriptMethod -Name Add_Click -Value {
            param($handler)
            [void]$this._clickHandlers.Add($handler)
        } -Force

        $menuItem | Add-Member -MemberType ScriptMethod -Name InvokeClick -Value {
            foreach ($handler in @($this._clickHandlers)) {
                & $handler $this $null
            }
        } -Force

        $contextMenu = [PSCustomObject]@{
            Items = [System.Collections.ArrayList]::new()
        }
        [void]$contextMenu.Items.Add($menuItem)

        $eventGrid = New-MockDataGrid
        $eventGrid.ContextMenu = $contextMenu

        $win = New-MockWpfWindow -Elements @{
            EventMetricsDataGrid = $eventGrid
        }

        $previousMainWindow = $global:GA_MainWindow
        try {
            $global:GA_MainWindow = $win

            Mock Set-EventMetricsFilterDefaults { }
            Mock Update-SavedScansList { }
            Mock Initialize-ScheduledScansList { }
            Mock Invoke-GenerateRuleFromEventTrigger { }

            Initialize-ScannerPanel -Window $win
            $menuItem._clickHandlers.Count | Should -Be 1
            & $menuItem._clickHandlers[0]

            Should -Invoke Invoke-GenerateRuleFromEventTrigger -Times 1 -Exactly
        }
        finally {
            $global:GA_MainWindow = $previousMainWindow
        }
    }
}

Describe 'Select-EventMetricsRowFromSource' {
    It 'Selects the row item resolved from source chain' {
        $rowItem = [PSCustomObject]@{ FilePath = 'C:\apps\\hit.exe'; Machine = 'WKS1' }
        $rowNode = [PSCustomObject]@{ RowItem = $rowItem; Parent = $null }
        $sourceNode = [PSCustomObject]@{ Parent = $rowNode }

        $grid = New-MockDataGrid -Data @($rowItem)
        $grid.SelectedItem = $null
        $grid.SelectedItems.Clear()

        $selected = Select-EventMetricsRowFromSource -DataGrid $grid -Source $sourceNode

        $selected | Should -BeTrue
        $grid.SelectedItem | Should -Be $rowItem
        $grid.SelectedItems.Count | Should -Be 1
        $grid.SelectedItems[0] | Should -Be $rowItem
    }

    It 'Returns false when no row item can be resolved' {
        $rowItem = [PSCustomObject]@{ FilePath = 'C:\apps\\keep.exe'; Machine = 'WKS1' }
        $sourceNode = [PSCustomObject]@{ Parent = $null }

        $grid = New-MockDataGrid -Data @($rowItem)
        $grid.SelectedItem = $rowItem
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowItem)

        $selected = Select-EventMetricsRowFromSource -DataGrid $grid -Source $sourceNode

        $selected | Should -BeFalse
        $grid.SelectedItem | Should -Be $rowItem
        $grid.SelectedItems.Count | Should -Be 1
    }
}

Describe 'MainWindow event metrics XAML controls' {
    It 'Contains Scanner results subtabs and shared event metrics controls' {
        $mainWindowXaml = Get-Content -Path $script:MainWindowXamlPath -Raw

        $mainWindowXaml | Should -Match 'x:Name="ArtifactFilterBox"'
        $mainWindowXaml | Should -Match 'x:Name="EventArtifactFilterBox"'
        $mainWindowXaml | Should -Match 'x:Name="ArtifactFilterBox"[^>]*(?<!Min)Width="220"'
        $mainWindowXaml | Should -Match 'x:Name="EventArtifactFilterBox"[^>]*(?<!Min)Width="220"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventTotalCount"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventBlockedCount"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventAuditCount"'
        $mainWindowXaml | Should -Match 'x:Name="BtnEventModeAll"'
        $mainWindowXaml | Should -Match 'x:Name="BtnEventModeBlocked"'
        $mainWindowXaml | Should -Match 'x:Name="BtnEventModeAudit"'
        $mainWindowXaml | Should -Match 'x:Name="BtnEventModeAllowed"'
        $mainWindowXaml | Should -Match 'x:Name="BtnGenerateRuleFromEvent"'
        $mainWindowXaml | Should -Match 'x:Name="BtnGenerateRuleFromEvent"[^>]*Content="Generate Rule"'
        $mainWindowXaml | Should -Match 'x:Name="EventMetricsDataGrid"'
        $mainWindowXaml | Should -Match 'Header="Generate Rule \(Publisher then Hash\)"'
        $mainWindowXaml | Should -Match 'x:Name="TxtEventMetricsEmpty"'

        # Subtab layout is expected for scanner results region
        $mainWindowXaml | Should -Match 'Header="Collected Artifacts"'
        $mainWindowXaml | Should -Match 'Header="Event Metrics"'
        $mainWindowXaml | Should -Match 'x:Name="ScannerResultsArtifactsTab"'
        $mainWindowXaml | Should -Match 'x:Name="ScannerResultsEventMetricsTab"'
        $mainWindowXaml | Should -Match 'x:Name="ScannerResultsArtifactsTab"[^>]*Tag="ScannerResults_Artifacts"'
        $mainWindowXaml | Should -Match 'x:Name="ScannerResultsEventMetricsTab"[^>]*Tag="ScannerResults_EventMetrics"'

        # Path filter now reuses artifact search box for both artifact and event filtering
        $mainWindowXaml | Should -Not -Match 'x:Name="TxtEventPathFilter"'
        $mainWindowXaml | Should -Not -Match 'x:Name="TxtEventTopN"'
        $mainWindowXaml | Should -Not -Match 'x:Name="CboEventMode"'
        $mainWindowXaml | Should -Not -Match 'x:Name="CboEventMachine"'
        $mainWindowXaml | Should -Not -Match 'Text="EVENT METRICS"'
        $mainWindowXaml | Should -Not -Match 'Text="COLLECTED ARTIFACTS"'
    }
}
