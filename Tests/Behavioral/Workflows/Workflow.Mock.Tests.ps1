#Requires -Version 5.1

BeforeAll {
    $ErrorActionPreference = 'Stop'

    if (-not $env:LOCALAPPDATA) {
        $env:LOCALAPPDATA = '/tmp'
    }

    Import-Module (Join-Path $PSScriptRoot '..\MockData\New-MockTestData.psm1') -Force -ErrorAction Stop

    function Invoke-AppLockerWorkflowMock {
        param(
            [ValidateSet('HappyPath', 'PartialScanFailure', 'DeployPrecheckFailure')]
            [string]$Scenario = 'HappyPath'
        )

        $fixture = New-MockWorkflowStageFixtures -Scenario $Scenario

        $stageSummary = [ordered]@{
            Discovery = [PSCustomObject]@{
                Checkpoint = 'Discovery'
                Success = $fixture.Discovery.Success
                SelectedMachines = $fixture.Discovery.SelectedCount
            }
            Scan = [PSCustomObject]@{
                Checkpoint = 'Scan'
                Success = $fixture.Scan.Success
                ArtifactCount = $fixture.Scan.ArtifactCount
                FailedMachines = @($fixture.Scan.FailedMachines)
            }
            Rules = [PSCustomObject]@{
                Checkpoint = 'Rules'
                Success = $fixture.Rules.Success
                ApprovedCount = $fixture.Rules.ApprovedCount
                PendingCount = $fixture.Rules.PendingCount
            }
            Policy = [PSCustomObject]@{
                Checkpoint = 'Policy'
                Success = $fixture.Policy.Success
                PolicyId = $fixture.Policy.Data.PolicyId
                RuleCount = @($fixture.Policy.Data.RuleIds).Count
            }
            Deploy = [PSCustomObject]@{
                Checkpoint = 'Deploy'
                Success = $fixture.Deploy.Success
                PrecheckPassed = $fixture.Deploy.PrecheckPassed
                Status = $fixture.Deploy.Data.Status
                Error = $fixture.Deploy.Error
            }
        }

        return [PSCustomObject]@{
            Success = ($fixture.Discovery.Success -and $fixture.Scan.Success -and $fixture.Rules.Success -and $fixture.Policy.Success -and $fixture.Deploy.Success)
            Scenario = $Scenario
            Stages = [PSCustomObject]$stageSummary
            Fixture = $fixture
        }
    }
}

Describe 'Workflow mock contract coverage' -Tag @('Behavioral', 'Workflow', 'Phase13') {
    It 'provides deterministic happy-path stage contracts' {
        $result = Invoke-AppLockerWorkflowMock -Scenario HappyPath

        $result.Success | Should -BeTrue
        $result.Stages.Discovery.SelectedMachines | Should -BeGreaterThan 0
        $result.Stages.Scan.ArtifactCount | Should -BeGreaterThan 0
        $result.Stages.Rules.ApprovedCount | Should -BeGreaterThan 0
        $result.Stages.Deploy.Status | Should -Be 'Completed'
    }

    It 'supports partial scan failures while preserving downstream progression' {
        $result = Invoke-AppLockerWorkflowMock -Scenario PartialScanFailure

        $result.Success | Should -BeTrue
        @($result.Stages.Scan.FailedMachines).Count | Should -BeGreaterThan 0
        $result.Stages.Rules.Success | Should -BeTrue
        $result.Stages.Policy.Success | Should -BeTrue
        $result.Stages.Deploy.Status | Should -Be 'Completed'
    }

    It 'supports deterministic deploy precheck failure contracts' {
        $result = Invoke-AppLockerWorkflowMock -Scenario DeployPrecheckFailure

        $result.Success | Should -BeFalse
        $result.Stages.Discovery.Success | Should -BeTrue
        $result.Stages.Scan.Success | Should -BeTrue
        $result.Stages.Policy.Success | Should -BeTrue
        $result.Stages.Deploy.PrecheckPassed | Should -BeFalse
        $result.Stages.Deploy.Status | Should -Be 'Blocked'
        $result.Stages.Deploy.Error | Should -Match 'Target GPO'
    }

    It 'produces balanced signed and unsigned artifacts across tiered hosts' {
        $fixture = New-MockWorkflowStageFixtures -Scenario HappyPath
        $artifacts = @($fixture.Scan.Artifacts)

        $signed = @($artifacts | Where-Object { $_.IsSigned -eq $true }).Count
        $unsigned = @($artifacts | Where-Object { $_.IsSigned -ne $true }).Count
        $tiers = @($artifacts | ForEach-Object { $_.Tier } | Sort-Object -Unique)

        $signed | Should -BeGreaterThan 0
        $unsigned | Should -BeGreaterThan 0
        $tiers | Should -Contain 'T0'
        $tiers | Should -Contain 'T1'
        $tiers | Should -Contain 'T2'
    }
}
