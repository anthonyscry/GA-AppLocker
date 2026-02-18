#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:EventViewerPanelPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\EventViewer.ps1'

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . $script:EventViewerPanelPath

    function script:New-TriageTestWindow {
        param(
            [string]$EventCodeFilterTag = 'All',
            [string]$ActionFilterTag    = '',
            [string]$HostFilterText     = '',
            [string]$UserFilterText     = ''
        )

        $eventCodeItem  = New-MockComboBoxItem -Content 'All Events' -Tag $EventCodeFilterTag
        $actionItem     = New-MockComboBoxItem -Content 'All'        -Tag $ActionFilterTag

        $window = New-MockWpfWindow -Elements @{
            CboEventViewerEventCodeFilter = (New-MockComboBoxWithItem -Item $eventCodeItem)
            CboEventViewerActionFilter    = (New-MockComboBoxWithItem -Item $actionItem)
            TxtEventViewerHostFilter      = (New-MockTextBox -Text $HostFilterText)
            TxtEventViewerUserFilter      = (New-MockTextBox -Text $UserFilterText)
            TxtEventViewerSearch          = (New-MockTextBox -Text '')
            TxtEventViewerResultCount     = (New-MockTextBlock)
            TxtEventViewerUniqueFiles     = (New-MockTextBlock)
            TxtEventViewerTopFile         = (New-MockTextBlock)
            TxtEventViewerTopFileCount    = (New-MockTextBlock)
            TxtEventViewerEmpty           = (New-MockTextBlock -Visibility 'Visible')
            TxtEventViewerFileMetricsEmpty = (New-MockTextBlock -Visibility 'Visible')
            EventViewerEventsDataGrid     = (New-MockDataGrid)
            EventViewerFileMetricsDataGrid = (New-MockDataGrid)
        }

        return $window
    }

    function script:New-MockComboBoxWithItem {
        param($Item)

        $list = [System.Collections.ArrayList]::new()
        [void]$list.Add($Item)

        $mock = [PSCustomObject]@{
            Items         = $list
            SelectedIndex = 0
            SelectedItem  = $Item
            Visibility    = 'Visible'
        }
        return (Add-MockEventMethods $mock)
    }

    function script:New-TestEventRow {
        param(
            [int]$EventId          = 8003,
            [string]$FilePath      = 'C:\Windows\notepad.exe',
            [string]$ComputerName  = 'LOCALHOST',
            [string]$Action        = 'Audit',
            [string]$CollectionType = 'Exe',
            [string]$UserSid       = 'S-1-5-21-1234',
            [string]$EventType     = 'AppLocker',
            [string]$EnforcementMode = 'AuditOnly',
            [string]$Message       = 'Test message for event',
            [string]$RawXml        = '<Event><System></System></Event>',
            $TimeCreated           = [datetime]'2026-02-15T10:00:00Z'
        )

        return [PSCustomObject]@{
            EventId         = $EventId
            FilePath        = $FilePath
            ComputerName    = $ComputerName
            Action          = $Action
            CollectionType  = $CollectionType
            UserSid         = $UserSid
            EventType       = $EventType
            EnforcementMode = $EnforcementMode
            Message         = $Message
            RawXml          = $RawXml
            TimeCreated     = $TimeCreated
        }
    }

    function script:New-TriageDetailWindow {
        param(
            [string]$DetailVisibility = 'Collapsed'
        )

        $detailPane = [PSCustomObject]@{ Visibility = $DetailVisibility }

        return New-MockWpfWindow -Elements @{
            PnlEventViewerDetail = $detailPane
            TxtDetailFilePath    = (New-MockTextBlock)
            TxtDetailEventType   = (New-MockTextBlock)
            TxtDetailCollection  = (New-MockTextBlock)
            TxtDetailUser        = (New-MockTextBlock)
            TxtDetailHost        = (New-MockTextBlock)
            TxtDetailAction      = (New-MockTextBlock)
            TxtDetailEnforcement = (New-MockTextBlock)
            TxtDetailTime        = (New-MockTextBlock)
            TxtDetailMessage     = (New-MockTextBox)
            TxtDetailRawXml      = (New-MockTextBox)
        }
    }
}

Describe 'FLT-01: Event-code group filter narrows grid results' {

    It 'Returns all rows when EventIdFilter is empty' {
        $rows = @(
            New-TestEventRow -EventId 8003
            New-TestEventRow -EventId 8004 -FilePath 'C:\app.exe' -Action 'Blocked'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -EventIdFilter @()

        @($result).Count | Should -Be 2
    }

    It 'Narrows to matching event IDs when EventIdFilter is provided' {
        $rows = @(
            New-TestEventRow -EventId 8003
            New-TestEventRow -EventId 8004 -FilePath 'C:\app.exe' -Action 'Blocked'
            New-TestEventRow -EventId 8021 -FilePath 'C:\other.exe' -Action 'Blocked'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -EventIdFilter @(8003)

        @($result).Count | Should -Be 1
        @($result)[0].EventId | Should -Be 8003
    }

    It 'Returns zero rows when no events match the EventIdFilter' {
        $rows = @(
            New-TestEventRow -EventId 8003
            New-TestEventRow -EventId 8005 -FilePath 'C:\app.exe'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -EventIdFilter @(8020, 8021)

        @($result).Count | Should -Be 0
    }

    It 'Reads event code filter from window CboEventViewerEventCodeFilter Tag' {
        $eventCodeItem = New-MockComboBoxItem -Content 'Blocked' -Tag '8002,8004,8006,8021,8024'
        $combo = [PSCustomObject]@{ SelectedItem = $eventCodeItem }
        $window = New-MockWpfWindow -Elements @{ CboEventViewerEventCodeFilter = $combo }

        $result = Get-EventViewerActiveEventIdFilter -Window $window

        @($result) | Should -Contain 8002
        @($result) | Should -Contain 8004
        @($result) | Should -Contain 8006
        @($result).Count | Should -Be 5
    }

    It 'Returns empty array for All Events tag' {
        $eventCodeItem = New-MockComboBoxItem -Content 'All Events' -Tag 'All'
        $combo = [PSCustomObject]@{ SelectedItem = $eventCodeItem }
        $window = New-MockWpfWindow -Elements @{ CboEventViewerEventCodeFilter = $combo }

        $result = Get-EventViewerActiveEventIdFilter -Window $window

        @($result).Count | Should -Be 0
    }
}

Describe 'FLT-02: Action, host, and user filters narrow grid results' {

    It 'Narrows to Allowed rows when ActionFilter is Allowed' {
        $rows = @(
            New-TestEventRow -EventId 8001 -Action 'Allow'
            New-TestEventRow -EventId 8004 -FilePath 'C:\b.exe' -Action 'Deny'
            New-TestEventRow -EventId 8003 -FilePath 'C:\c.exe' -Action 'Deny'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -ActionFilter 'Allowed'

        @($result).Count | Should -Be 1
        @($result)[0].EventId | Should -Be 8001
    }

    It 'Narrows to Blocked rows when ActionFilter is Blocked' {
        $rows = @(
            New-TestEventRow -EventId 8001 -Action 'Allow'
            New-TestEventRow -EventId 8004 -FilePath 'C:\b.exe' -Action 'Deny'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -ActionFilter 'Blocked'

        @($result).Count | Should -Be 1
        @($result)[0].EventId | Should -Be 8004
    }

    It 'Narrows by host substring match (case-insensitive)' {
        $rows = @(
            New-TestEventRow -ComputerName 'SRV-PROD-01'
            New-TestEventRow -EventId 8004 -FilePath 'C:\b.exe' -ComputerName 'WKS-DEV-02'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -HostFilter 'SRV'

        @($result).Count | Should -Be 1
        @($result)[0].ComputerName | Should -Be 'SRV-PROD-01'
    }

    It 'Narrows by user SID substring match (case-insensitive)' {
        $rows = @(
            New-TestEventRow -UserSid 'S-1-5-21-1234-5678'
            New-TestEventRow -EventId 8004 -FilePath 'C:\b.exe' -UserSid 'S-1-5-18'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText '' -UserFilter '1234'

        @($result).Count | Should -Be 1
        @($result)[0].UserSid | Should -Be 'S-1-5-21-1234-5678'
    }

    It 'Returns empty string for action filter when All tag is selected' {
        $actionItem = New-MockComboBoxItem -Content 'All' -Tag ''
        $combo = [PSCustomObject]@{ SelectedItem = $actionItem }
        $window = New-MockWpfWindow -Elements @{ CboEventViewerActionFilter = $combo }

        $result = Get-EventViewerActiveActionFilter -Window $window

        $result | Should -Be ''
    }
}

Describe 'FLT-03: Search text matches Message and UserSid fields' {

    It 'SearchText matches Message field' {
        $rows = @(
            New-TestEventRow -Message 'blocked by rule ABC'
            New-TestEventRow -EventId 8004 -FilePath 'C:\other.exe' -Message 'allowed by rule XYZ'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText 'blocked'

        @($result).Count | Should -Be 1
        @($result)[0].Message | Should -Match 'blocked'
    }

    It 'SearchText matches UserSid field' {
        $rows = @(
            New-TestEventRow -UserSid 'S-1-5-21-SPECIFIC-9999'
            New-TestEventRow -EventId 8004 -FilePath 'C:\other.exe' -UserSid 'S-1-5-18'
        )

        $result = Get-FilteredEventViewerRows -Rows $rows -SearchText 'SPECIFIC'

        @($result).Count | Should -Be 1
        @($result)[0].UserSid | Should -Be 'S-1-5-21-SPECIFIC-9999'
    }
}

Describe 'DET-01: Update-EventViewerDetailPane populates normalized fields' {

    It 'Populates all named TextBlock values from the selected row' {
        $window = New-TriageDetailWindow
        $row = New-TestEventRow `
            -FilePath 'C:\Windows\system32\cmd.exe' `
            -EventType 'AppLocker' `
            -CollectionType 'Exe' `
            -UserSid 'S-1-5-21-000' `
            -ComputerName 'DC01' `
            -Action 'Allow' `
            -EnforcementMode 'Enabled' `
            -TimeCreated ([datetime]'2026-02-15T14:30:00Z') `
            -Message 'Application allowed'

        Update-EventViewerDetailPane -Window $window -Row $row

        $window.FindName('PnlEventViewerDetail').Visibility | Should -Be 'Visible'
        $window.FindName('TxtDetailFilePath').Text   | Should -Be 'C:\Windows\system32\cmd.exe'
        $window.FindName('TxtDetailEventType').Text  | Should -Be 'AppLocker'
        $window.FindName('TxtDetailCollection').Text | Should -Be 'Exe'
        $window.FindName('TxtDetailUser').Text       | Should -Be 'S-1-5-21-000'
        $window.FindName('TxtDetailHost').Text       | Should -Be 'DC01'
        $window.FindName('TxtDetailAction').Text     | Should -Be 'Allow'
        $window.FindName('TxtDetailEnforcement').Text | Should -Be 'Enabled'
        $window.FindName('TxtDetailTime').Text       | Should -Match '2026-02-15'
        $window.FindName('TxtDetailMessage').Text    | Should -Be 'Application allowed'
    }

    It 'Collapses the detail pane when row is null' {
        $window = New-TriageDetailWindow -DetailVisibility 'Visible'

        Update-EventViewerDetailPane -Window $window -Row $null

        $window.FindName('PnlEventViewerDetail').Visibility | Should -Be 'Collapsed'
    }

    It 'Formats TimeCreated as yyyy-MM-dd HH:mm:ss' {
        $window = New-TriageDetailWindow
        $row = New-TestEventRow -TimeCreated ([datetime]'2026-02-15T14:30:45Z')

        Update-EventViewerDetailPane -Window $window -Row $row

        $window.FindName('TxtDetailTime').Text | Should -Match '2026-02-15 \d\d:\d\d:\d\d'
    }
}

Describe 'DET-02: Update-EventViewerDetailPane shows RawXml content' {

    It 'Populates TxtDetailRawXml with event XML content' {
        $window = New-TriageDetailWindow
        $row = New-TestEventRow -RawXml '<Event><System><EventID>8004</EventID></System></Event>'

        Update-EventViewerDetailPane -Window $window -Row $row

        $window.FindName('TxtDetailRawXml').Text | Should -Match 'EventID'
    }

    It 'Shows not-available message for empty RawXml' {
        $window = New-TriageDetailWindow
        $row = New-TestEventRow -RawXml ''

        Update-EventViewerDetailPane -Window $window -Row $row

        $window.FindName('TxtDetailRawXml').Text | Should -Be '(not available for remote events)'
    }

    It 'Shows not-available message when row has no RawXml property' {
        $window = New-TriageDetailWindow
        $row = [PSCustomObject]@{
            EventId    = 8004
            FilePath   = 'C:\test.exe'
            Action     = 'Deny'
        }

        Update-EventViewerDetailPane -Window $window -Row $row

        $window.FindName('TxtDetailRawXml').Text | Should -Be '(not available for remote events)'
    }
}
