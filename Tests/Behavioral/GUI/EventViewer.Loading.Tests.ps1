#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:EventViewerPanelPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\EventViewer.ps1'

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . $script:EventViewerPanelPath
}

Describe 'Event Viewer bounded query validation' {
    BeforeEach {
        $script:ToastMessages = [System.Collections.Generic.List[PSCustomObject]]::new()

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

        $script:EventViewerQueryState.EventIds = @(8002, 8003)
    }

    It 'Returns bounded contract for valid local inputs' {
        $window = New-MockWpfWindow -Elements @{
            DpEventViewerStartTime    = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-15T00:00:00Z' }
            DpEventViewerEndTime      = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-16T00:00:00Z' }
            TxtEventViewerMaxEvents   = New-MockTextBox -Text '500'
            CboEventViewerTargetScope = New-MockComboBox -Items @('Local Machine', 'Remote Machines') -SelectedIndex 0
            TxtEventViewerRemoteHosts = New-MockTextBox -Text ''
        }

        $result = Test-EventViewerQueryInputs -Window $window

        $result.Success | Should -BeTrue
        $result.Data.MaxEvents | Should -Be 500
        $result.Data.TargetScope | Should -Be 'Local'
        @($result.Data.Targets).Count | Should -Be 1
        @($result.Data.EventIds) | Should -Be @(8002, 8003)
    }

    It 'Rejects invalid bounds when end is before start' {
        $window = New-MockWpfWindow -Elements @{
            DpEventViewerStartTime    = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-16T00:00:00Z' }
            DpEventViewerEndTime      = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-15T00:00:00Z' }
            TxtEventViewerMaxEvents   = New-MockTextBox -Text '500'
            CboEventViewerTargetScope = New-MockComboBox -Items @('Local Machine', 'Remote Machines') -SelectedIndex 0
            TxtEventViewerRemoteHosts = New-MockTextBox -Text ''
        }

        $result = Test-EventViewerQueryInputs -Window $window

        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'End time must be greater than or equal to Start time'
        $script:ToastMessages.Count | Should -Be 1
        $script:ToastMessages[0].Type | Should -Be 'Warning'
    }

    It 'Rejects remote execution when no hosts are selected' {
        $window = New-MockWpfWindow -Elements @{
            DpEventViewerStartTime    = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-15T00:00:00Z' }
            DpEventViewerEndTime      = [PSCustomObject]@{ SelectedDate = [datetime]'2026-02-16T00:00:00Z' }
            TxtEventViewerMaxEvents   = New-MockTextBox -Text '500'
            CboEventViewerTargetScope = New-MockComboBox -Items @('Local Machine', 'Remote Machines') -SelectedIndex 1
            TxtEventViewerRemoteHosts = New-MockTextBox -Text ' '
        }

        $result = Test-EventViewerQueryInputs -Window $window

        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'Select one or more remote hosts'
        $script:ToastMessages.Count | Should -Be 1
    }
}
