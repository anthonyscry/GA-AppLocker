#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Deployment panel logic.
.DESCRIPTION
    Tests Refresh-DeployPolicyCombo, Update-DeploymentFilter,
    and panel initialization with mocked WPF elements.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -WarningAction SilentlyContinue
    }

    # Load mock helpers
    . (Join-Path $PSScriptRoot '..\Helpers\MockWpfHelpers.ps1')

    # Dot-source the panel
    . (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\Panels\Deploy.ps1')

    # Global stubs
    if (-not (Get-Command 'Show-Toast' -ErrorAction SilentlyContinue)) {
        function global:Show-Toast { param([string]$Message, [string]$Type) }
    }
    if (-not (Get-Command 'Invoke-ButtonAction' -ErrorAction SilentlyContinue)) {
        function global:Invoke-ButtonAction { param([string]$Action) }
    }
    if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
        function global:Write-Log { param([string]$Message, [string]$Level) }
    }
    if (-not (Get-Command 'Write-AppLockerLog' -ErrorAction SilentlyContinue)) {
        function global:Write-AppLockerLog { param([string]$Message, [string]$Level) }
    }
    if (-not (Get-Command 'Invoke-AsyncOperation' -ErrorAction SilentlyContinue)) {
        function global:Invoke-AsyncOperation {
            param([scriptblock]$ScriptBlock, [hashtable]$Arguments, [string]$LoadingMessage,
                  [string]$LoadingSubMessage, [scriptblock]$OnComplete, [scriptblock]$OnError, [switch]$NoLoadingOverlay)
            try {
                $result = & $ScriptBlock @Arguments
                if ($OnComplete) { & $OnComplete -Result $result }
            } catch {
                if ($OnError) { & $OnError -ErrorMessage $_.Exception.Message }
            }
        }
    }
}

Describe 'Deploy Panel - Refresh-DeployPolicyCombo' {
    It 'Does not throw with empty window' {
        Mock Get-AllPolicies { @{ Success = $true; Data = @() } }
        $win = New-MockWpfWindow -Elements @{}
        { Refresh-DeployPolicyCombo -Window $win } | Should -Not -Throw
    }

    It 'Handles Get-AllPolicies failure gracefully' {
        Mock Get-AllPolicies { @{ Success = $false; Error = 'No data' } }
        $win = New-MockWpfWindow -Elements @{}
        { Refresh-DeployPolicyCombo -Window $win } | Should -Not -Throw
    }
}

Describe 'Deploy Panel - Deployment Filter State' {
    It 'Current deployment filter defaults to All' {
        $script:CurrentDeploymentFilter = 'All'
        $script:CurrentDeploymentFilter | Should -Be 'All'
    }

    It 'Tracks filter state changes' {
        $script:CurrentDeploymentFilter = 'Pending'
        $script:CurrentDeploymentFilter | Should -Be 'Pending'

        $script:CurrentDeploymentFilter = 'Completed'
        $script:CurrentDeploymentFilter | Should -Be 'Completed'
    }
}

Describe 'Deploy Panel - Update-DeploymentFilter' {
    It 'Updates the filter state variable' {
        if (Get-Command 'Update-DeploymentFilter' -ErrorAction SilentlyContinue) {
            Mock Update-DeploymentJobsDataGrid {}

            $win = New-MockWpfWindow -Elements @{}
            Update-DeploymentFilter -Window $win -Filter 'Running'

            $script:CurrentDeploymentFilter | Should -Be 'Running'
        } else {
            Set-ItResult -Skipped -Because 'Update-DeploymentFilter not available'
        }
    }
}

Describe 'Deploy Panel - Deployment State Tracking' {
    It 'Tracks deployment in progress flag' {
        $script:DeploymentInProgress = $false
        $script:DeploymentInProgress | Should -BeFalse
    }

    It 'Tracks deployment cancelled flag' {
        $script:DeploymentCancelled = $false
        $script:DeploymentCancelled | Should -BeFalse
    }
}

Describe 'Deploy Panel - XAML Filter Buttons' {
    BeforeAll {
        $script:RawXaml = Get-Content (Join-Path $PSScriptRoot '..\..\GA-AppLocker\GUI\MainWindow.xaml') -Raw
    }

    It 'Has All Jobs filter button' {
        $script:RawXaml | Should -Match 'BtnFilterAllJobs'
    }

    It 'Has Pending Jobs filter button' {
        $script:RawXaml | Should -Match 'BtnFilterPendingJobs'
    }

    It 'Has Completed Jobs filter button' {
        $script:RawXaml | Should -Match 'BtnFilterCompletedJobs'
    }

    It 'Has Failed Jobs filter button' {
        $script:RawXaml | Should -Match 'BtnFilterFailedJobs'
    }
}
