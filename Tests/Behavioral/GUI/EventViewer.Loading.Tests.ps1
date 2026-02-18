#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:EventViewerPanelPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\EventViewer.ps1'

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . $script:EventViewerPanelPath

    function script:New-EventViewerTestWindow {
        param(
            [datetime]$Start = [datetime]'2026-02-15T00:00:00Z',
            [datetime]$End = [datetime]'2026-02-16T00:00:00Z',
            [string]$MaxEvents = '500',
            [int]$TargetScopeIndex = 0,
            [string]$RemoteHosts = ''
        )

        $window = New-MockWpfWindow -Elements @{
            DpEventViewerStartTime        = [PSCustomObject]@{ SelectedDate = $Start }
            DpEventViewerEndTime          = [PSCustomObject]@{ SelectedDate = $End }
            TxtEventViewerMaxEvents       = New-MockTextBox -Text $MaxEvents
            CboEventViewerTargetScope     = New-MockComboBox -Items @('Local Machine', 'Remote Machines') -SelectedIndex $TargetScopeIndex
            TxtEventViewerRemoteHosts     = New-MockTextBox -Text $RemoteHosts
            TxtEventViewerSearch          = New-MockTextBox -Text ''
            CboEventViewerRuleMode        = New-MockComboBox -Items @('Recommended', 'Publisher', 'Hash', 'Path') -SelectedIndex 0
            TxtEventViewerQuerySummary    = New-MockTextBlock
            TxtEventViewerResultCount     = New-MockTextBlock
            TxtEventViewerUniqueFiles     = New-MockTextBlock
            TxtEventViewerTopFile         = New-MockTextBlock
            TxtEventViewerTopFileCount    = New-MockTextBlock
            TxtEventViewerEmpty           = New-MockTextBlock -Visibility 'Visible'
            TxtEventViewerFileMetricsEmpty = New-MockTextBlock -Visibility 'Visible'
            BtnEventViewerRunQuery        = New-MockButton -Content 'Run Query'
            BtnEventViewerCreateRule      = New-MockButton -Content 'Create Rule'
            BtnEventViewerCreateRulesSelected = New-MockButton -Content 'Create Rules from Selected'
            EventViewerHostStatusDataGrid = New-MockDataGrid
            EventViewerEventsDataGrid     = New-MockDataGrid
            EventViewerFileMetricsDataGrid = New-MockDataGrid
        }

        return $window
    }
}

Describe 'Event Viewer loading and bounded query behavior' {
    BeforeEach {
        $script:ToastMessages = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:CapturedQuery = $null
        $script:QueryCallCount = 0
        $script:MockEnvelopes = @()
        $script:RuleCreateCalls = [System.Collections.Generic.List[PSCustomObject]]::new()

        function global:Show-Toast {
            param(
                [string]$Message,
                [string]$Type
            )

            [void]$script:ToastMessages.Add([PSCustomObject]@{
                    Message = $Message
                    Type    = $Type
                })
        }

        function global:Invoke-AsyncOperation {
            param(
                [scriptblock]$ScriptBlock,
                [hashtable]$Arguments,
                [string]$LoadingMessage,
                [scriptblock]$OnComplete,
                [scriptblock]$OnError
            )

            try {
                $result = if ($Arguments) { & $ScriptBlock @Arguments } else { & $ScriptBlock }
                if ($OnComplete) {
                    & $OnComplete -Result $result
                }
            }
            catch {
                if ($OnError) {
                    & $OnError -ErrorMessage $_.Exception.Message
                }
                else {
                    throw
                }
            }
        }

        function global:Invoke-AppLockerEventQuery {
            param(
                [string[]]$ComputerName,
                [datetime]$StartTime,
                [datetime]$EndTime,
                [int]$MaxEvents,
                [int[]]$EventIds
            )

            $script:QueryCallCount++
            $script:CapturedQuery = [PSCustomObject]@{
                ComputerName = @($ComputerName)
                StartTime    = $StartTime
                EndTime      = $EndTime
                MaxEvents    = $MaxEvents
                EventIds     = @($EventIds)
            }

            return @($script:MockEnvelopes)
        }

        function global:New-PathRule {
            param(
                [string]$Path,
                [string]$Action,
                [string]$CollectionType,
                [string]$Description,
                [string]$UserOrGroupSid,
                [string]$Status,
                [switch]$Save
            )

            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{ Type = 'Path'; Path = $Path; CollectionType = $CollectionType })
            return [PSCustomObject]@{ Success = $true; Data = [PSCustomObject]@{ Id = 'path-rule' }; Error = $null }
        }

        function global:New-HashRule {
            param(
                [string]$Hash,
                [string]$SourceFileName,
                [int64]$SourceFileLength,
                [string]$Action,
                [string]$CollectionType,
                [string]$Description,
                [string]$UserOrGroupSid,
                [string]$Status,
                [switch]$Save
            )

            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{ Type = 'Hash'; Hash = $Hash; CollectionType = $CollectionType })
            return [PSCustomObject]@{ Success = $true; Data = [PSCustomObject]@{ Id = 'hash-rule' }; Error = $null }
        }

        function global:New-PublisherRule {
            param(
                [string]$PublisherName,
                [string]$ProductName,
                [string]$BinaryName,
                [string]$Action,
                [string]$CollectionType,
                [string]$Description,
                [string]$UserOrGroupSid,
                [string]$Status,
                [switch]$Save
            )

            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{ Type = 'Publisher'; Publisher = $PublisherName; CollectionType = $CollectionType })
            return [PSCustomObject]@{ Success = $true; Data = [PSCustomObject]@{ Id = 'publisher-rule' }; Error = $null }
        }

        $script:EventViewerQueryState.EventIds = @(8002, 8003)
    }

    It 'Returns bounded contract for valid local inputs' {
        $window = New-EventViewerTestWindow

        $result = Test-EventViewerQueryInputs -Window $window

        $result.Success | Should -BeTrue
        $result.Data.MaxEvents | Should -Be 500
        $result.Data.TargetScope | Should -Be 'Local'
        @($result.Data.Targets).Count | Should -Be 1
        @($result.Data.EventIds) | Should -Be @(8002, 8003)
    }

    It 'Binds local load results to event and host status grids' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $script:MockEnvelopes = @(
            [PSCustomObject]@{
                Host          = 'LOCALHOST'
                Success       = $true
                Count         = 1
                DurationMs    = 15
                ErrorCategory = $null
                Error         = $null
                Data          = @(
                    [PSCustomObject]@{
                        TimeCreated    = [datetime]'2026-02-15T10:00:00Z'
                        ComputerName   = 'LOCALHOST'
                        EventId        = 8003
                        CollectionType = 'Exe'
                        FilePath       = 'C:\Windows\notepad.exe'
                        Action         = 'Audit'
                    }
                )
            }
        )

        Invoke-LoadEventViewerData -Window $window

        @($window.FindName('EventViewerHostStatusDataGrid').ItemsSource).Count | Should -Be 1
        @($window.FindName('EventViewerEventsDataGrid').ItemsSource).Count | Should -Be 1
        $window.FindName('TxtEventViewerResultCount').Text | Should -Be '1 events'
        $window.FindName('TxtEventViewerEmpty').Visibility | Should -Be 'Collapsed'
        $script:CapturedQuery.MaxEvents | Should -Be 500
        @($script:CapturedQuery.EventIds) | Should -Be @(8002, 8003)
    }

    It 'Shows remote host success and failure rows with aggregate counts' {
        $window = New-EventViewerTestWindow -TargetScopeIndex 1 -RemoteHosts 'srv-a, srv-b'
        $global:GA_MainWindow = $window

        $script:MockEnvelopes = @(
            [PSCustomObject]@{
                Host          = 'srv-a'
                Success       = $true
                Count         = 2
                DurationMs    = 20
                ErrorCategory = $null
                Error         = $null
                Data          = @(
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T10:00:00Z'; ComputerName = 'srv-a'; EventId = 8003; CollectionType = 'Exe'; FilePath = 'C:\A.exe'; Action = 'Audit' },
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T11:00:00Z'; ComputerName = 'srv-a'; EventId = 8004; CollectionType = 'Exe'; FilePath = 'C:\B.exe'; Action = 'Blocked' }
                )
            },
            [PSCustomObject]@{
                Host          = 'srv-b'
                Success       = $false
                Count         = 0
                DurationMs    = 35
                ErrorCategory = 'auth'
                Error         = 'Access is denied.'
                Data          = @()
            }
        )

        Invoke-LoadEventViewerData -Window $window

        $hostRows = @($window.FindName('EventViewerHostStatusDataGrid').ItemsSource)
        $eventRows = @($window.FindName('EventViewerEventsDataGrid').ItemsSource)

        $hostRows.Count | Should -Be 2
        $eventRows.Count | Should -Be 2
        ($hostRows | Where-Object { $_.Host -eq 'srv-b' }).Status | Should -Be 'Failed'
        ($hostRows | Where-Object { $_.Host -eq 'srv-b' }).ErrorCategory | Should -Be 'auth'
        $window.FindName('TxtEventViewerQuerySummary').Text | Should -Match 'Hosts requested: 2 \(success: 1, failed: 1\)'
    }

    It 'Replaces prior results on rerun instead of stacking stale rows' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $script:MockEnvelopes = @(
            [PSCustomObject]@{
                Host          = 'LOCALHOST'
                Success       = $true
                Count         = 1
                DurationMs    = 10
                ErrorCategory = $null
                Error         = $null
                Data          = @(
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T10:00:00Z'; ComputerName = 'LOCALHOST'; EventId = 8003; CollectionType = 'Exe'; FilePath = 'C:\old.exe'; Action = 'Audit' }
                )
            }
        )

        Invoke-LoadEventViewerData -Window $window
        @($window.FindName('EventViewerEventsDataGrid').ItemsSource).Count | Should -Be 1

        $script:MockEnvelopes = @(
            [PSCustomObject]@{
                Host          = 'LOCALHOST'
                Success       = $true
                Count         = 2
                DurationMs    = 14
                ErrorCategory = $null
                Error         = $null
                Data          = @(
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T12:00:00Z'; ComputerName = 'LOCALHOST'; EventId = 8004; CollectionType = 'Exe'; FilePath = 'C:\new-a.exe'; Action = 'Blocked' },
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T12:01:00Z'; ComputerName = 'LOCALHOST'; EventId = 8005; CollectionType = 'Exe'; FilePath = 'C:\new-b.exe'; Action = 'Audit' }
                )
            }
        )

        Invoke-LoadEventViewerData -Window $window

        @($window.FindName('EventViewerEventsDataGrid').ItemsSource).Count | Should -Be 2
        @($window.FindName('EventViewerHostStatusDataGrid').ItemsSource).Count | Should -Be 1
        $window.FindName('TxtEventViewerResultCount').Text | Should -Be '2 events'
    }

    It 'Aggregates top flagged file metrics with action buckets' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $script:MockEnvelopes = @(
            [PSCustomObject]@{
                Host          = 'LOCALHOST'
                Success       = $true
                Count         = 3
                DurationMs    = 11
                ErrorCategory = $null
                Error         = $null
                Data          = @(
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T10:00:00Z'; ComputerName = 'LOCALHOST'; EventId = 8003; CollectionType = 'Exe'; FilePath = 'C:\Temp\app.exe'; Action = 'Deny' },
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T11:00:00Z'; ComputerName = 'LOCALHOST'; EventId = 8004; CollectionType = 'Exe'; FilePath = 'C:\Temp\app.exe'; Action = 'Deny' },
                    [PSCustomObject]@{ TimeCreated = [datetime]'2026-02-15T12:00:00Z'; ComputerName = 'LOCALHOST'; EventId = 8005; CollectionType = 'Exe'; FilePath = 'C:\Temp\other.exe'; Action = 'Allowed' }
                )
            }
        )

        Invoke-LoadEventViewerData -Window $window

        $metricRows = @($window.FindName('EventViewerFileMetricsDataGrid').ItemsSource)
        $metricRows.Count | Should -Be 2
        $appRow = @($metricRows | Where-Object { $_.FilePath -eq 'C:\Temp\app.exe' })[0]
        $otherRow = @($metricRows | Where-Object { $_.FilePath -eq 'C:\Temp\other.exe' })[0]

        $appRow.Count | Should -Be 2
        $appRow.Audit | Should -Be 1
        $appRow.Blocked | Should -Be 1
        $otherRow.Allowed | Should -Be 1
        $window.FindName('TxtEventViewerUniqueFiles').Text | Should -Be '2'
        $window.FindName('TxtEventViewerTopFileCount').Text | Should -Be '2'
    }

    It 'Creates one recommended rule from selected event row' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $row = [PSCustomObject]@{
            FilePath       = 'C:\Temp\sample.exe'
            ComputerName   = 'LOCALHOST'
            EventId        = 8004
            CollectionType = 'Exe'
            Action         = 'Deny'
            TimeCreated    = [datetime]'2026-02-15T11:00:00Z'
        }

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRuleRecommended'

        $script:RuleCreateCalls.Count | Should -Be 1
        $script:RuleCreateCalls[0].Type | Should -Be 'Path'
    }

    It 'Creates deduplicated path rules from selected rows' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $rowA = [PSCustomObject]@{ FilePath = 'C:\Temp\same.exe'; ComputerName = 'LOCALHOST'; EventId = 8004; CollectionType = 'Exe'; Action = 'Deny'; TimeCreated = [datetime]'2026-02-15T11:00:00Z' }
        $rowB = [PSCustomObject]@{ FilePath = 'C:\Temp\same.exe'; ComputerName = 'LOCALHOST'; EventId = 8003; CollectionType = 'Exe'; Action = 'Deny'; TimeCreated = [datetime]'2026-02-15T12:00:00Z' }

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        $script:RuleCreateCalls.Count | Should -Be 1
        $script:RuleCreateCalls[0].Type | Should -Be 'Path'
    }

    It 'Skips hash action when selected rows do not include hash metadata' {
        $window = New-EventViewerTestWindow
        $global:GA_MainWindow = $window

        $row = [PSCustomObject]@{ FilePath = 'C:\Temp\sample.exe'; ComputerName = 'REMOTE01'; EventId = 8004; CollectionType = 'Exe'; Action = 'Deny'; TimeCreated = [datetime]'2026-02-15T11:00:00Z' }
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRuleHash'

        $script:RuleCreateCalls.Count | Should -Be 0
        $script:ToastMessages.Count | Should -BeGreaterThan 0
        $script:ToastMessages[$script:ToastMessages.Count - 1].Message | Should -Match 'Skipped'
    }

    It 'Blocks invalid bounds before invoking backend query' {
        $window = New-EventViewerTestWindow -Start ([datetime]'2026-02-16T00:00:00Z') -End ([datetime]'2026-02-15T00:00:00Z')
        $global:GA_MainWindow = $window

        Invoke-LoadEventViewerData -Window $window

        $script:QueryCallCount | Should -Be 0
        $script:ToastMessages.Count | Should -BeGreaterThan 0
        $script:ToastMessages[0].Type | Should -Be 'Warning'
    }

    It 'Rejects remote execution when no hosts are selected' {
        $window = New-EventViewerTestWindow -TargetScopeIndex 1 -RemoteHosts ' '

        $result = Test-EventViewerQueryInputs -Window $window

        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'Select one or more remote hosts'
    }
}
