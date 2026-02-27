#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    if (-not $env:LOCALAPPDATA) {
        $env:LOCALAPPDATA = '/tmp'
    }

    Import-Module (Join-Path $PSScriptRoot '..\MockData\New-MockTestData.psm1') -Force -ErrorAction Stop

    function Invoke-E2ECheckpointFlow {
        param(
            [ValidateSet('HappyPath', 'PartialScanFailure', 'DeployPrecheckFailure')]
            [string]$Scenario = 'HappyPath'
        )

        $fixture = New-MockWorkflowStageFixtures -Scenario $Scenario
        $checkpoints = [System.Collections.Generic.List[PSCustomObject]]::new()

        [void]$checkpoints.Add([PSCustomObject]@{
            Stage = 'Discovery'
            Success = $fixture.Discovery.Success
            Evidence = "SelectedMachines=$($fixture.Discovery.SelectedCount)"
        })

        [void]$checkpoints.Add([PSCustomObject]@{
            Stage = 'Scan'
            Success = $fixture.Scan.Success
            Evidence = "Artifacts=$($fixture.Scan.ArtifactCount);FailedMachines=$(@($fixture.Scan.FailedMachines).Count)"
        })

        [void]$checkpoints.Add([PSCustomObject]@{
            Stage = 'Rules'
            Success = $fixture.Rules.Success
            Evidence = "Approved=$($fixture.Rules.ApprovedCount);Pending=$($fixture.Rules.PendingCount)"
        })

        [void]$checkpoints.Add([PSCustomObject]@{
            Stage = 'Policy'
            Success = $fixture.Policy.Success
            Evidence = "PolicyId=$($fixture.Policy.Data.PolicyId);RuleCount=$(@($fixture.Policy.Data.RuleIds).Count)"
        })

        [void]$checkpoints.Add([PSCustomObject]@{
            Stage = 'Deploy'
            Success = $fixture.Deploy.Success
            Evidence = "Status=$($fixture.Deploy.Data.Status);PrecheckPassed=$($fixture.Deploy.PrecheckPassed)"
            Error = $fixture.Deploy.Error
        })

        return [PSCustomObject]@{
            Scenario = $Scenario
            Checkpoints = @($checkpoints)
            Success = (@($checkpoints | Where-Object { $_.Success -eq $false }).Count -eq 0)
            Fixture = $fixture
        }
    }
}

Describe 'Core E2E workflow checkpoints (scan -> rules -> policy -> deploy)' -Tag @('Behavioral', 'E2E', 'Phase13') {
    It 'validates canonical checkpoint chain end-to-end' {
        $result = Invoke-E2ECheckpointFlow -Scenario HappyPath

        $result.Success | Should -BeTrue
        @($result.Checkpoints).Count | Should -Be 5
        @($result.Checkpoints | ForEach-Object { $_.Stage }) | Should -Be @('Discovery', 'Scan', 'Rules', 'Policy', 'Deploy')
        @($result.Checkpoints | Where-Object { $_.Success -eq $false }).Count | Should -Be 0
    }

    It 'keeps downstream checkpoints valid when scan stage has partial failures' {
        $result = Invoke-E2ECheckpointFlow -Scenario PartialScanFailure

        $result.Success | Should -BeTrue
        $scan = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Scan' })[0]
        $policy = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Policy' })[0]
        $deploy = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Deploy' })[0]

        $scan.Success | Should -BeTrue
        $scan.Evidence | Should -Match 'FailedMachines=1'
        $policy.Success | Should -BeTrue
        $deploy.Success | Should -BeTrue
    }

    It 'blocks deploy checkpoint deterministically when precheck fails' {
        $result = Invoke-E2ECheckpointFlow -Scenario DeployPrecheckFailure

        $result.Success | Should -BeFalse
        $discovery = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Discovery' })[0]
        $scan = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Scan' })[0]
        $rules = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Rules' })[0]
        $deploy = @($result.Checkpoints | Where-Object { $_.Stage -eq 'Deploy' })[0]

        $discovery.Success | Should -BeTrue
        $scan.Success | Should -BeTrue
        $rules.Success | Should -BeTrue
        $deploy.Success | Should -BeFalse
        $deploy.Evidence | Should -Match 'PrecheckPassed=False'
        $deploy.Error | Should -Match 'Target GPO'
    }

    It 'asserts stage-level evidence, not final-status-only outputs' {
        $result = Invoke-E2ECheckpointFlow -Scenario HappyPath

        foreach ($checkpoint in @($result.Checkpoints)) {
            $checkpoint.PSObject.Properties.Name | Should -Contain 'Stage'
            $checkpoint.PSObject.Properties.Name | Should -Contain 'Success'
            $checkpoint.PSObject.Properties.Name | Should -Contain 'Evidence'
            [string]::IsNullOrWhiteSpace([string]$checkpoint.Evidence) | Should -BeFalse
        }
    }
}
