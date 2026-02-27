#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    try {
        Add-Type -TypeDefinition @'
namespace System.Windows.Media {
    public class BrushConverter {
        public object ConvertFromString(string value) { return new object(); }
    }
    public static class Brushes {
        public static readonly object Transparent = new object();
        public static readonly object White = new object();
    }
}
'@ -ErrorAction Stop
    }
    catch {
        # Types may already exist.
    }

    . (Join-Path $PSScriptRoot '..\..\Helpers\MockWpfHelpers.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\GUI\Panels\Policy.ps1')

    function global:Write-Log {
        param([string]$Message, [string]$Level = 'Info')
    }

    function global:Show-Toast {
        param([string]$Message, [string]$Type = 'Info')
    }

    function global:Show-AppLockerMessageBox {
        param($Message, $Title, $Button, $Icon)
        return 'Yes'
    }

    function global:Invoke-BackgroundWork {
        param([scriptblock]$ScriptBlock, [object[]]$ArgumentList, [scriptblock]$OnComplete, [scriptblock]$OnTimeout)
        $result = & $ScriptBlock @($ArgumentList)
        if ($OnComplete) { & $OnComplete $result }
    }

    function global:Get-AllPolicies {
        @{ Success = $true; Data = @(); Error = $null }
    }

    function global:New-Policy {
        @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'stub-policy' }; Error = $null }
    }

    function global:Update-Policy {
        @{ Success = $true; Data = $null; Error = $null }
    }

    function global:Remove-Policy {
        @{ Success = $true; Data = $null; Error = $null }
    }

    function global:Get-Policy {
        @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'stub-policy'; Name = 'Stub'; TargetGPO = 'AppLocker-Servers'; RuleIds = @('r1'); Phase = 1 }; Error = $null }
    }

    function global:Invoke-AsyncOperation {
        param($ScriptBlock, $Arguments, $LoadingMessage, $OnComplete, $OnError, [switch]$NoLoadingOverlay)
        $result = if ($Arguments) { & $ScriptBlock $Arguments.Policies } else { & $ScriptBlock }
        if ($OnComplete) { & $OnComplete $result }
    }

    function global:Select-PolicyInGrid {
        param($Window, [string]$PolicyId)
    }

    function global:Update-WorkflowBreadcrumb {
        param($Window)
    }

    function global:Set-ActivePanel {
        param([string]$PanelName)
    }
}

Describe 'Policy panel workflow matrix' -Tag @('Behavioral', 'GUI', 'Policy') {
    BeforeEach {
        $script:SelectedPolicyId = $null
        $global:GA_SelectedPolicyId = $null
        $script:CurrentPoliciesFilter = 'All'
        $script:PolicyCacheResult = $null
        $script:PolicyCacheTimestamp = $null
    }

    It 'loads policy data into grid and updates selection details' {
        $rows = @(
            [PSCustomObject]@{ PolicyId = 'p-1'; Name = 'Policy One'; Description = 'Primary'; EnforcementMode = 'AuditOnly'; Phase = 2; Status = 'Draft'; RuleIds = @('r1', 'r2'); TargetOUs = @(); TargetGPO = ''; CreatedAt = (Get-Date).ToString('o'); ModifiedAt = (Get-Date).ToString('o'); Version = 1 },
            [PSCustomObject]@{ PolicyId = 'p-2'; Name = 'Policy Two'; Description = 'Secondary'; EnforcementMode = 'Enabled'; Phase = 5; Status = 'Active'; RuleIds = @('r3'); TargetOUs = @(); TargetGPO = 'AppLocker-Servers'; CreatedAt = (Get-Date).ToString('o'); ModifiedAt = (Get-Date).ToString('o'); Version = 2 }
        )

        $grid = New-MockDataGrid -Data @() -SelectedItem $null
        $win = New-MockWpfWindow -Elements @{
            PoliciesDataGrid = $grid
            TxtPolicyFilter = New-MockTextBox -Text ''
            TxtPolicyTotalCount = New-MockTextBlock
            TxtPolicyDraftCount = New-MockTextBlock
            TxtPolicyActiveCount = New-MockTextBlock
            TxtPolicyDeployedCount = New-MockTextBlock
            TxtPolicySelectedCount = New-MockTextBlock
            TxtPolicyRuleCount = New-MockTextBlock
            TxtSelectedPolicyName = New-MockTextBlock
            TxtPolicyEditHint = New-MockTextBlock
            TxtEditPolicyName = New-MockTextBox
            TxtEditPolicyDescription = New-MockTextBox
            CboEditEnforcement = New-MockComboBox -Items @('Audit', 'Enabled', 'NotConfigured') -SelectedIndex 0
            CboEditPhase = New-MockComboBox -Items @([PSCustomObject]@{ Tag = 1 }, [PSCustomObject]@{ Tag = 2 }) -SelectedIndex 0
            CboEditTargetGPO = New-MockComboBox -Items @([PSCustomObject]@{ Tag = '' }) -SelectedIndex 0
            TxtEditCustomGPO = New-MockTextBox -Text ''
        }

        Mock Get-AllPolicies { @{ Success = $true; Data = $rows; Error = $null } }

        Update-PoliciesDataGrid -Window $win

        @($grid.ItemsSource).Count | Should -Be 2
        $grid.SelectedItem = $grid.ItemsSource[0]
        [void]$grid.SelectedItems.Add($grid.SelectedItem)
        Update-SelectedPolicyInfo -Window $win

        $script:SelectedPolicyId | Should -Be 'p-1'
        $win.FindName('TxtPolicyRuleCount').Text | Should -Be '2 rules'
    }

    It 'creates policy and routes selection to edit tab on success' {
        $tab = [PSCustomObject]@{ SelectedIndex = 0 }
        $win = New-MockWpfWindow -Elements @{
            TxtPolicyName = New-MockTextBox -Text 'New Policy'
            TxtPolicyDescription = New-MockTextBox -Text 'Created from test'
            CboPolicyEnforcement = New-MockComboBox -Items @('AuditOnly', 'Enabled', 'NotConfigured') -SelectedIndex 0
            CboPolicyPhase = New-MockComboBox -Items @([PSCustomObject]@{ Tag = 1 }, [PSCustomObject]@{ Tag = 5 }) -SelectedIndex 1
            CboPolicyTargetGPO = New-MockComboBox -Items @([PSCustomObject]@{ Tag = 'AppLocker-Servers' }) -SelectedIndex 0
            TxtPolicyCustomGPO = New-MockTextBox -Text ''
            PolicyTabControl = $tab
        }

        Mock New-Policy { @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'new-1' }; Error = $null } }
        Mock Update-Policy { @{ Success = $true; Data = $null; Error = $null } }
        Mock Update-PoliciesDataGrid { }
        Mock Select-PolicyInGrid { }
        Mock Update-SelectedPolicyInfo { }
        Mock Update-WorkflowBreadcrumb { }
        Mock Show-Toast { }

        Invoke-CreatePolicy -Window $win

        Assert-MockCalled New-Policy -Times 1 -Exactly
        $tab.SelectedIndex | Should -Be 1
    }

    It 'shows create and save validation errors for missing selection or invalid input' {
        $win = New-MockWpfWindow -Elements @{
            TxtPolicyName = New-MockTextBox -Text ''
            TxtEditPolicyName = New-MockTextBox -Text ''
        }

        Mock Show-Toast { }

        Invoke-CreatePolicy -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Warning' -and $Message -like '*enter a policy name*' }

        $script:SelectedPolicyId = 'p-edit'
        Invoke-SavePolicyChanges -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Warning' -and $Message -like '*name cannot be empty*' }
    }

    It 'handles delete flow in empty and success states through async callback' {
        $grid = New-MockDataGrid -Data @()
        $win = New-MockWpfWindow -Elements @{ PoliciesDataGrid = $grid }

        Mock Show-Toast { }
        Invoke-DeleteSelectedPolicy -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Warning' -and $Message -like '*select one or more policies*' }

        $selected = [PSCustomObject]@{ PolicyId = 'p-del'; Name = 'Delete Me' }
        $grid.SelectedItem = $selected
        [void]$grid.SelectedItems.Add($selected)

        Mock Remove-Policy { @{ Success = $true; Data = $null; Error = $null } }
        Mock Invoke-AsyncOperation {
            param($ScriptBlock, $Arguments, $LoadingMessage, $OnComplete, $OnError)
            $summary = & $ScriptBlock $Arguments.Policies
            & $OnComplete $summary
        }
        Mock Update-PoliciesDataGrid { }
        Mock Update-SelectedPolicyInfo { }

        Invoke-DeleteSelectedPolicy -Window $win
        Assert-MockCalled Remove-Policy -Times 1 -Exactly
    }

    It 'applies status filters and routes deploy handoff preconditions' {
        $win = New-MockWpfWindow -Elements @{
            BtnFilterAllPolicies = New-MockButton
            BtnFilterDraft = New-MockButton
            BtnFilterActive = New-MockButton
            BtnFilterDeployed = New-MockButton
            BtnFilterArchived = New-MockButton
        }

        Mock Update-PoliciesDataGrid { }
        Update-PoliciesFilter -Window $win -Filter 'Draft'
        $script:CurrentPoliciesFilter | Should -Be 'Draft'

        Mock Show-Toast { }
        $script:SelectedPolicyId = $null
        Invoke-DeploySelectedPolicy -Window $win
        Assert-MockCalled Show-Toast -Times 1 -Exactly -ParameterFilter { $Type -eq 'Warning' -and $Message -like '*select a policy to deploy*' }

        $script:SelectedPolicyId = 'p-deploy'
        Mock Get-Policy { @{ Success = $true; Data = [PSCustomObject]@{ Name = 'Deploy Me'; TargetGPO = 'AppLocker-Servers' }; Error = $null } }
        Mock Set-ActivePanel { }

        Invoke-DeploySelectedPolicy -Window $win
        Assert-MockCalled Set-ActivePanel -Times 1 -Exactly -ParameterFilter { $PanelName -eq 'PanelDeploy' }
    }
}
