#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    try {
        Add-Type -TypeDefinition @'
namespace System.Windows.Media {
    public class Color {
        public static Color FromRgb(byte r, byte g, byte b) { return new Color(); }
    }
    public class SolidColorBrush {
        public SolidColorBrush(Color color) { }
    }
    public class BrushConverter {
        public object ConvertFromString(string value) { return new object(); }
    }
    public static class Brushes {
        public static readonly object Transparent = new object();
        public static readonly object White = new object();
    }
}
namespace System.Windows.Controls {
    public class MenuItem {
        public object Tag { get; set; }
    }
}
'@ -ErrorAction Stop
    }
    catch {
        # Types may already exist.
    }

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    Import-Module (Join-Path $PSScriptRoot '..\MockData\New-MockTestData.psm1') -Force
    . (Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Rules.ps1')

    function global:Write-Log {
        param([string]$Message, [string]$Level = 'Info')
    }

    function global:Show-Toast {
        param([string]$Message, [string]$Type = 'Info')
    }

    function global:Write-AppLockerLog {
        param([string]$Message, [string]$Level = 'Info')
    }

    function global:Show-AppLockerMessageBox {
        param($Message, $Title, $Button, $Icon)
        return 'Yes'
    }

    function global:Get-AppLockerDataPath {
        '/tmp/ga-applocker'
    }

    function global:Get-AllRules {
        @{ Success = $true; Data = @(); Error = $null }
    }

    function global:Invoke-BackgroundWork {
        param([scriptblock]$ScriptBlock, [object[]]$ArgumentList, [scriptblock]$OnComplete, [scriptblock]$OnTimeout)
    }
}

Describe 'Rules panel workflow matrix' -Tag @('Behavioral', 'GUI', 'Rules') {
    BeforeEach {
        $script:CurrentRulesFilter = 'All'
        $script:CurrentRulesTypeFilter = 'All'
        $script:SuppressRulesSelectionChanged = $false
        $script:AllRulesSelected = $false
    }

    It 'loads grid counters and selection state from bound rows' {
        $fixtures = New-MockScannerRuleWorkflowFixtures -ComputerCount 2 -ArtifactsPerComputer 6
        $rows = @($fixtures.Rules | Select-Object -First 8)

        $grid = New-MockDataGrid -Data $rows
        [void]$grid.SelectedItems.Add($rows[0])
        [void]$grid.SelectedItems.Add($rows[1])

        $win = New-MockWpfWindow -Elements @{
            RulesDataGrid = $grid
            TxtSelectedRuleCount = New-MockTextBlock
            ChkSelectAllRules = New-MockCheckBox -IsChecked $false
            TxtRuleTotalCount = New-MockTextBlock
            TxtRulePendingCount = New-MockTextBlock
            TxtRuleApprovedCount = New-MockTextBlock
            TxtRuleRejectedCount = New-MockTextBlock
            BtnFilterAllRules = New-MockButton
            BtnFilterPending = New-MockButton
            BtnFilterApproved = New-MockButton
            BtnFilterRejected = New-MockButton
        }

        Update-RuleCounters -Window $win -Rules $rows
        Update-RulesSelectionCount -Window $win

        $win.FindName('TxtRuleTotalCount').Text | Should -Be '8'
        $win.FindName('TxtSelectedRuleCount').Text | Should -Be '2'
    }

    It 'transitions type filters and refreshes the grid' {
        $win = New-MockWpfWindow -Elements @{
            BtnFilterAllRules = New-MockButton
            BtnFilterPublisher = New-MockButton
            BtnFilterHash = New-MockButton
            BtnFilterPath = New-MockButton
            BtnFilterPending = New-MockButton
            BtnFilterApproved = New-MockButton
            BtnFilterRejected = New-MockButton
        }

        Mock Update-RulesDataGrid { }

        Update-RulesFilter -Window $win -Filter 'Publisher'
        $script:CurrentRulesTypeFilter | Should -Be 'Publisher'

        Update-RulesFilter -Window $win -Filter 'All'
        $script:CurrentRulesTypeFilter | Should -Be 'All'

        Assert-MockCalled Update-RulesDataGrid -Times 2 -Exactly
    }

    It 'blocks status updates when no rules are selected' {
        $win = New-MockWpfWindow
        Mock Get-SelectedRules { @() }
        Mock Show-Toast { }

        Set-SelectedRuleStatus -Window $win -Status 'Approved'

        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'Warning' -and $Message -like '*select one or more rules*'
        }
    }

    It 'accepts large selected-rule sets without throwing update errors' {
        $win = New-MockWpfWindow
        $selected = [System.Collections.Generic.List[PSCustomObject]]::new()
        1..60 | ForEach-Object {
            [void]$selected.Add([PSCustomObject]@{ Id = "rule-$($_)" })
        }

        Mock Get-SelectedRules { @($selected.ToArray()) }
        Mock Get-Module { [PSCustomObject]@{ ModuleBase = 'C:\Temp\GA-AppLocker\GA-AppLocker' } } -ParameterFilter { $Name -eq 'GA-AppLocker' }
        Mock Invoke-BackgroundWork { }

        { Set-SelectedRuleStatus -Window $win -Status 'Rejected' } | Should -Not -Throw
    }

    It 'routes context menu actions to bulk operations and single-item details' {
        $item = [PSCustomObject]@{ RuleId = 'r-1'; Id = 'r-1'; Name = 'Rule 1' }
        $grid = New-MockDataGrid -Data @($item) -SelectedItem $item
        [void]$grid.SelectedItems.Add($item)

        $win = New-MockWpfWindow -Elements @{ RulesDataGrid = $grid }

        Mock Set-SelectedRuleStatus { }
        Mock Invoke-AddSelectedRulesToPolicy { }
        Mock Show-RuleDetails { }
        Mock Invoke-DeleteSelectedRules { }

        Invoke-RulesContextAction -Action 'ApproveRule' -Window $win
        Invoke-RulesContextAction -Action 'AddRuleToPolicy' -Window $win
        Invoke-RulesContextAction -Action 'ViewRuleDetails' -Window $win
        Invoke-RulesContextAction -Action 'DeleteRule' -Window $win

        Assert-MockCalled Set-SelectedRuleStatus -Times 1 -Exactly -ParameterFilter { $Status -eq 'Approved' }
        Assert-MockCalled Invoke-AddSelectedRulesToPolicy -Times 1 -Exactly
        Assert-MockCalled Show-RuleDetails -Times 1 -Exactly
        Assert-MockCalled Invoke-DeleteSelectedRules -Times 1 -Exactly
    }

    It 'handles empty result and repository error states while refreshing' {
        $grid = New-MockDataGrid
        $win = New-MockWpfWindow -Elements @{
            RulesDataGrid = $grid
            TxtRuleFilter = New-MockTextBox -Text ''
        }

        Mock Get-AllRules { @{ Success = $true; Data = @(); Error = $null } }
        Update-RulesDataGrid -Window $win
        $grid.ItemsSource | Should -BeNullOrEmpty

        Mock Get-AllRules { @{ Success = $false; Data = $null; Error = 'repo failed' } }
        Update-RulesDataGrid -Window $win
        $grid.ItemsSource | Should -BeNullOrEmpty
    }
}
