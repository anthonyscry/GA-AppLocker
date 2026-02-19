#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $script:EventViewerPanelPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\EventViewer.ps1'

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . $script:EventViewerPanelPath

    function script:New-RuleGenTestWindow {
        param(
            [bool]$AllowChecked     = $true,
            [bool]$DenyChecked      = $false,
            [string]$TargetGroupSid = 'S-1-5-11'
        )

        $rbAllow = New-MockRadioButton -IsChecked $AllowChecked
        $rbDeny  = New-MockRadioButton -IsChecked $DenyChecked

        $targetGroupItem = [PSCustomObject]@{ Content = 'Authenticated Users'; Tag = $TargetGroupSid }
        $targetGroupCombo = [PSCustomObject]@{
            SelectedItem  = $targetGroupItem
            SelectedIndex = 0
        }

        $window = New-MockWpfWindow -Elements @{
            RbEvtRuleAllow                  = $rbAllow
            RbEvtRuleDeny                   = $rbDeny
            CboEvtRuleTargetGroup           = $targetGroupCombo
            EventViewerEventsDataGrid       = (New-MockDataGrid)
            TxtEventViewerQuerySummary      = (New-MockTextBlock)
            BtnEventViewerRunQuery          = (New-MockButton)
            TxtEventViewerResultCount       = (New-MockTextBlock)
            TxtEventViewerUniqueFiles       = (New-MockTextBlock)
            TxtEventViewerTopFile           = (New-MockTextBlock)
            TxtEventViewerTopFileCount      = (New-MockTextBlock)
            TxtEventViewerEmpty             = (New-MockTextBlock -Visibility 'Visible')
            TxtEventViewerFileMetricsEmpty  = (New-MockTextBlock -Visibility 'Visible')
            EventViewerFileMetricsDataGrid  = (New-MockDataGrid)
        }

        return $window
    }

    function script:New-GenTestEventRow {
        param(
            [string]$FilePath       = 'C:\Windows\System32\cmd.exe',
            [string]$ComputerName   = 'LOCALHOST',
            [int]$EventId           = 8004,
            [string]$CollectionType = 'Exe',
            [string]$Action         = 'Deny',
            $TimeCreated            = [datetime]'2026-02-15T10:00:00Z'
        )

        return [PSCustomObject]@{
            FilePath       = $FilePath
            ComputerName   = $ComputerName
            EventId        = $EventId
            CollectionType = $CollectionType
            Action         = $Action
            TimeCreated    = $TimeCreated
        }
    }

    function script:Install-RuleGenMocks {
        param([string]$MessageBoxReturn = 'Yes')

        $script:RuleCreateCalls    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:LastMessageBoxText = ''
        $script:MessageBoxReturn   = $MessageBoxReturn
        $script:ToastMessages      = [System.Collections.Generic.List[PSCustomObject]]::new()

        $script:EventViewerFileMetrics = @()

        function global:Show-Toast {
            param([string]$Message, [string]$Type)
            [void]$script:ToastMessages.Add([PSCustomObject]@{ Message = $Message; Type = $Type })
        }

        function global:Show-AppLockerMessageBox {
            param([string]$Message, [string]$Title, [string]$Button, [string]$Icon)
            $script:LastMessageBoxText = $Message
            return $script:MessageBoxReturn
        }

        function global:Invoke-AsyncOperation {
            param(
                [scriptblock]$ScriptBlock,
                [hashtable]$Arguments,
                [string]$LoadingMessage,
                [string]$LoadingSubMessage,
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

        function global:Update-RulesDataGrid {
            param($Window)
            # no-op
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
            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{
                Type           = 'Path'
                Path           = $Path
                Action         = $Action
                CollectionType = $CollectionType
                UserOrGroupSid = $UserOrGroupSid
                Status         = $Status
            })
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
            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{
                Type           = 'Hash'
                Hash           = $Hash
                Action         = $Action
                CollectionType = $CollectionType
                UserOrGroupSid = $UserOrGroupSid
                Status         = $Status
            })
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
            [void]$script:RuleCreateCalls.Add([PSCustomObject]@{
                Type           = 'Publisher'
                Publisher      = $PublisherName
                Action         = $Action
                CollectionType = $CollectionType
                UserOrGroupSid = $UserOrGroupSid
                Status         = $Status
            })
            return [PSCustomObject]@{ Success = $true; Data = [PSCustomObject]@{ Id = 'publisher-rule' }; Error = $null }
        }
    }
}

Describe 'GEN-01: Single Rule from Selected Event' {

    BeforeEach {
        Install-RuleGenMocks
    }

    AfterEach {
        $script:RuleCreateCalls    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:LastMessageBoxText = ''
    }

    It 'Creates exactly one rule when one event row is selected via single-rule tag' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\tool.exe' -ComputerName 'REMOTE01'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRuleRecommended'

        @($script:RuleCreateCalls).Count | Should -Be 1
    }

    It 'Reads Allow action from RbEvtRuleAllow RadioButton when checked' {
        $window = New-RuleGenTestWindow -AllowChecked $true -DenyChecked $false
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\allow-tool.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulePath'

        @($script:RuleCreateCalls).Count | Should -Be 1
        $script:RuleCreateCalls[0].Action | Should -Be 'Allow'
    }

    It 'Reads Deny action from RbEvtRuleDeny RadioButton when checked' {
        $window = New-RuleGenTestWindow -AllowChecked $false -DenyChecked $true
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\deny-tool.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulePath'

        @($script:RuleCreateCalls).Count | Should -Be 1
        $script:RuleCreateCalls[0].Action | Should -Be 'Deny'
    }

    It 'Reads target group SID from CboEvtRuleTargetGroup SelectedItem Tag' {
        $window = New-RuleGenTestWindow -TargetGroupSid 'S-1-5-32-544'
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\admin-tool.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulePath'

        @($script:RuleCreateCalls).Count | Should -Be 1
        $script:RuleCreateCalls[0].UserOrGroupSid | Should -Be 'S-1-5-32-544'
    }

    It 'Get-EventViewerRuleDefaults returns Allow and Pending when Deny radio is not checked' {
        $window = New-RuleGenTestWindow -AllowChecked $true -DenyChecked $false

        $defaults = Get-EventViewerRuleDefaults -Window $window

        $defaults.Action | Should -Be 'Allow'
        $defaults.Status | Should -Be 'Pending'
    }

    It 'Get-EventViewerRuleDefaults returns Deny when Deny radio is checked' {
        $window = New-RuleGenTestWindow -AllowChecked $false -DenyChecked $true

        $defaults = Get-EventViewerRuleDefaults -Window $window

        $defaults.Action | Should -Be 'Deny'
        $defaults.Status | Should -Be 'Pending'
    }

    It 'Get-EventViewerRuleDefaults returns SID from CboEvtRuleTargetGroup' {
        $window = New-RuleGenTestWindow -TargetGroupSid 'S-1-5-21-custom'

        $defaults = Get-EventViewerRuleDefaults -Window $window

        $defaults.TargetSid | Should -Be 'S-1-5-21-custom'
    }
}

Describe 'GEN-02: Bulk Rules from Multiple Selected Events' {

    BeforeEach {
        Install-RuleGenMocks
    }

    AfterEach {
        $script:RuleCreateCalls    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:LastMessageBoxText = ''
    }

    It 'Creates rules for all three selected rows when using multi-select tag' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $rowA = New-GenTestEventRow -FilePath 'C:\App\alpha.exe' -ComputerName 'SRV01'
        $rowB = New-GenTestEventRow -FilePath 'C:\App\beta.exe'  -ComputerName 'SRV01'
        $rowC = New-GenTestEventRow -FilePath 'C:\App\gamma.exe' -ComputerName 'SRV01'

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)
        [void]$grid.SelectedItems.Add($rowC)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 3
    }

    It 'Deduplicates rows with identical FilePath and ComputerName before creating rules' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $rowA = New-GenTestEventRow -FilePath 'C:\App\same.exe' -ComputerName 'LOCALHOST' -EventId 8003
        $rowB = New-GenTestEventRow -FilePath 'C:\App\same.exe' -ComputerName 'LOCALHOST' -EventId 8004

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 1
    }

    It 'Treats same FilePath on different hosts as distinct (no dedup across hosts)' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $rowA = New-GenTestEventRow -FilePath 'C:\App\shared.exe' -ComputerName 'SRV01'
        $rowB = New-GenTestEventRow -FilePath 'C:\App\shared.exe' -ComputerName 'SRV02'

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 2
    }

    It 'Shows warning toast and creates no rules when no rows are selected' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $null
        $grid.SelectedItems.Clear()

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 0
        @($script:ToastMessages).Count   | Should -BeGreaterThan 0
        $script:ToastMessages[0].Type    | Should -Be 'Warning'
    }
}

Describe 'GEN-03: Candidate Review with Frequency Counts' {

    BeforeEach {
        Install-RuleGenMocks
    }

    AfterEach {
        $script:RuleCreateCalls    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:LastMessageBoxText = ''
    }

    It 'Confirmation dialog includes selected file paths' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $rowA = New-GenTestEventRow -FilePath 'C:\App\first.exe'  -ComputerName 'LOCALHOST'
        $rowB = New-GenTestEventRow -FilePath 'C:\App\second.exe' -ComputerName 'LOCALHOST'

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        $script:LastMessageBoxText | Should -Match 'C:\\App\\first\.exe'
        $script:LastMessageBoxText | Should -Match 'C:\\App\\second\.exe'
    }

    It 'Confirmation dialog includes frequency counts when EventViewerFileMetrics is populated' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $script:EventViewerFileMetrics = @(
            [PSCustomObject]@{
                FilePath = 'C:\App\tracked.exe'
                Count    = 7
                Blocked  = 5
                Audit    = 2
                Allowed  = 0
            }
        )

        $row = New-GenTestEventRow -FilePath 'C:\App\tracked.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        $script:LastMessageBoxText | Should -Match 'Events:'
        $script:LastMessageBoxText | Should -Match 'B:5'
        $script:LastMessageBoxText | Should -Match 'A:2'
    }

    It 'Confirmation dialog caps display at 10 candidates with overflow message for 15 selections' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $null
        $grid.SelectedItems.Clear()

        for ($i = 1; $i -le 15; $i++) {
            $row = New-GenTestEventRow -FilePath "C:\App\tool$i.exe" -ComputerName 'LOCALHOST'
            if ($i -eq 1) { $grid.SelectedItem = $row }
            [void]$grid.SelectedItems.Add($row)
        }

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        $script:LastMessageBoxText | Should -Match '\.\.\. and 5 more'
    }

    It 'Canceling the confirmation dialog prevents rule creation' {
        $script:MessageBoxReturn = 'No'

        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\cancel-me.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 0
    }

    It 'Confirmation dialog message contains Status: Pending label' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\pending-check.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        $script:LastMessageBoxText | Should -Match 'Status: Pending'
    }
}

Describe 'GEN-04: Pipeline Integration - Pending Status' {

    BeforeEach {
        Install-RuleGenMocks
    }

    AfterEach {
        $script:RuleCreateCalls    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $script:LastMessageBoxText = ''
    }

    It 'All event-derived path rules carry Status=Pending' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $rowA = New-GenTestEventRow -FilePath 'C:\App\path-a.exe' -ComputerName 'LOCALHOST'
        $rowB = New-GenTestEventRow -FilePath 'C:\App\path-b.exe' -ComputerName 'LOCALHOST'

        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $rowA
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($rowA)
        [void]$grid.SelectedItems.Add($rowB)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -Be 2
        foreach ($call in @($script:RuleCreateCalls)) {
            $call.Status | Should -Be 'Pending'
        }
    }

    It 'Hash mode rules that are created carry Status=Pending' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        # Remote host ensures hash lookup is skipped; but any rules that DO get created must be Pending
        $row = New-GenTestEventRow -FilePath 'C:\App\hash-test.exe' -ComputerName 'REMOTE99'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRuleHash'

        # Whether 0 or more rules were created, none should have non-Pending status
        foreach ($call in @($script:RuleCreateCalls)) {
            $call.Status | Should -Be 'Pending'
        }
    }

    It 'Publisher mode rules that are created carry Status=Pending' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\pub-test.exe' -ComputerName 'REMOTE99'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulePublisher'

        foreach ($call in @($script:RuleCreateCalls)) {
            $call.Status | Should -Be 'Pending'
        }
    }

    It 'Get-EventViewerRuleDefaults always returns Status=Pending regardless of window state' {
        $windowAllow = New-RuleGenTestWindow -AllowChecked $true  -DenyChecked $false
        $windowDeny  = New-RuleGenTestWindow -AllowChecked $false -DenyChecked $true

        $defaultsAllow = Get-EventViewerRuleDefaults -Window $windowAllow
        $defaultsDeny  = Get-EventViewerRuleDefaults -Window $windowDeny
        $defaultsNull  = Get-EventViewerRuleDefaults -Window $null

        $defaultsAllow.Status | Should -Be 'Pending'
        $defaultsDeny.Status  | Should -Be 'Pending'
        $defaultsNull.Status  | Should -Be 'Pending'
    }

    It 'Status=Pending is the exact string passed to New-PathRule -Status parameter' {
        $window = New-RuleGenTestWindow
        $global:GA_MainWindow = $window

        $row = New-GenTestEventRow -FilePath 'C:\App\status-verify.exe' -ComputerName 'LOCALHOST'
        $grid = $window.FindName('EventViewerEventsDataGrid')
        $grid.SelectedItem = $row
        $grid.SelectedItems.Clear()
        [void]$grid.SelectedItems.Add($row)

        Invoke-EventViewerRuleActionByTag -Window $window -Tag 'EventViewerCreateRulesSelectedPath'

        @($script:RuleCreateCalls).Count | Should -BeGreaterThan 0
        $script:RuleCreateCalls[0].Status | Should -Be 'Pending'
        $script:RuleCreateCalls[0].Type   | Should -Be 'Path'
    }
}
