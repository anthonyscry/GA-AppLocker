#Requires -Modules Pester

BeforeAll {
    $driftPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Policy\Functions\Get-PolicyDriftReport.ps1'
    $telemetryPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Policy\Functions\Get-PolicyTelemetrySummary.ps1'

    if (Test-Path $driftPath) {
        . $driftPath
    }

    if (Test-Path $telemetryPath) {
        . $telemetryPath
    }

    if (-not (Get-Command -Name 'Write-PolicyLog' -ErrorAction SilentlyContinue)) {
        function global:Write-PolicyLog {
            param([string]$Message, [string]$Level = 'Info')
        }
    }

    if (-not (Get-Command -Name 'Invoke-AppLockerEventCategorization' -ErrorAction SilentlyContinue)) {
        function global:Invoke-AppLockerEventCategorization {
            param()
            throw 'Invoke-AppLockerEventCategorization should be mocked in tests.'
        }
    }

    if (-not (Get-Command -Name 'Get-Policy' -ErrorAction SilentlyContinue)) {
        function global:Get-Policy {
            param()
            throw 'Get-Policy should be mocked in tests.'
        }
    }

    if (-not (Get-Command -Name 'Get-Rule' -ErrorAction SilentlyContinue)) {
        function global:Get-Rule {
            param()
            throw 'Get-Rule should be mocked in tests.'
        }
    }

    if (-not (Get-Command -Name 'Write-AuditLog' -ErrorAction SilentlyContinue)) {
        function global:Write-AuditLog {
            param(
                [string]$Action,
                [string]$Category,
                [string]$Target,
                [string]$TargetId,
                [string]$Details,
                [string]$OldValue,
                [string]$NewValue
            )
            throw 'Write-AuditLog should be mocked in tests.'
        }
    }

    if (-not (Get-Command -Name 'Get-AuditLog' -ErrorAction SilentlyContinue)) {
        function global:Get-AuditLog {
            param()
            throw 'Get-AuditLog should be mocked in tests.'
        }
    }
}

Describe 'Behavioral Bundle C: Policy drift reporting' -Tag @('Behavioral', 'Core') {
    It 'Builds drift summary and uncovered gaps from categorized events' {
        $eventTime = (Get-Date).AddHours(-2)

        Mock Invoke-AppLockerEventCategorization {
            [PSCustomObject]@{
                Success = $true
                Data = [PSCustomObject]@{
                    Events = @(
                        [PSCustomObject]@{ FilePath = 'C:\Windows\System32\cmd.exe'; ComputerName = 'WS01'; EventId = 8002; CoverageStatus = 'Covered'; Category = 'KnownGood'; TimeCreated = $eventTime },
                        [PSCustomObject]@{ FilePath = 'C:\Temp\bad.exe'; ComputerName = 'WS01'; EventId = 8002; CoverageStatus = 'Uncovered'; Category = 'KnownBad'; TimeCreated = $eventTime }
                    )
                    Summary = [PSCustomObject]@{
                        TotalEvents = 2
                        CoveredCount = 1
                        PartialCount = 0
                        UncoveredCount = 1
                        CoveragePercentage = 50
                    }
                }
                Error = $null
            }
        }

        $result = Get-PolicyDriftReport -Events @([PSCustomObject]@{ FilePath = 'C:\Temp\bad.exe' })

        $result.Success | Should -BeTrue
        $result.Data.Summary.GapCount | Should -Be 1
        $result.Data.Summary.CoveragePercentage | Should -Be 50
        $result.Data.Summary.StalenessStatus | Should -Be 'Fresh'
    }

    It 'Loads policy rules when PolicyId is provided and explicit rules are absent' {
        Mock Get-Policy {
            @{ Success = $true; Data = [PSCustomObject]@{ PolicyId = 'policy-1'; Name = 'Policy One'; RuleIds = @('r1', 'r2') } }
        }

        Mock Get-Rule {
            param($Id)
            @{ Success = $true; Data = [PSCustomObject]@{ Id = $Id; RuleType = 'Hash'; Hash = ('A' * 64); Action = 'Allow'; Status = 'Approved' } }
        }

        Mock Invoke-AppLockerEventCategorization {
            [PSCustomObject]@{
                Success = $true
                Data = [PSCustomObject]@{
                    Events = @()
                    Summary = [PSCustomObject]@{ TotalEvents = 0; CoveredCount = 0; PartialCount = 0; UncoveredCount = 0; CoveragePercentage = 0 }
                }
            }
        }

        $result = Get-PolicyDriftReport -PolicyId 'policy-1' -Events @()

        $result.Success | Should -BeTrue
        $result.Data.PolicyRuleCount | Should -Be 2
        Assert-MockCalled Get-Rule -Times 2
    }

    It 'Writes telemetry event when RecordTelemetry is set' {
        Mock Invoke-AppLockerEventCategorization {
            [PSCustomObject]@{
                Success = $true
                Data = [PSCustomObject]@{
                    Events = @()
                    Summary = [PSCustomObject]@{ TotalEvents = 0; CoveredCount = 0; PartialCount = 0; UncoveredCount = 0; CoveragePercentage = 0 }
                }
            }
        }

        Mock Write-AuditLog {
            @{ Success = $true; Data = $null; Error = $null }
        }

        $result = Get-PolicyDriftReport -PolicyId 'policy-telemetry' -Events @() -RecordTelemetry

        $result.Success | Should -BeTrue
        Assert-MockCalled Write-AuditLog -Times 1 -ParameterFilter { $Action -eq 'PolicyDriftCalculated' -and $Category -eq 'Policy' }
    }
}

Describe 'Behavioral Bundle C: Policy telemetry summary' -Tag @('Behavioral', 'Core') {
    It 'Aggregates policy telemetry counts and latest drift metadata' {
        $now = Get-Date
        Mock Get-AuditLog {
            @{ Success = $true; Data = @(
                [PSCustomObject]@{ Timestamp = $now.AddHours(-5).ToString('o'); Action = 'PolicyDriftCalculated'; Category = 'Policy'; TargetId = 'policy-1'; Details = '{"GapCount":2}' },
                [PSCustomObject]@{ Timestamp = $now.AddHours(-4).ToString('o'); Action = 'PolicyDeployed'; Category = 'Policy'; TargetId = 'policy-1'; Details = 'Deploy success' },
                [PSCustomObject]@{ Timestamp = $now.AddHours(-3).ToString('o'); Action = 'PolicyDriftCalculated'; Category = 'Policy'; TargetId = 'policy-1'; Details = '{"GapCount":1}' },
                [PSCustomObject]@{ Timestamp = $now.AddHours(-2).ToString('o'); Action = 'PolicyDriftCalculated'; Category = 'Policy'; TargetId = 'policy-2'; Details = '{"GapCount":9}' }
            ); Error = $null }
        }

        $result = Get-PolicyTelemetrySummary -PolicyId 'policy-1' -Days 30 -Last 200

        $result.Success | Should -BeTrue
        $result.Data.TotalPolicyEvents | Should -Be 3
        $result.Data.DriftChecksCount | Should -Be 2
        $result.Data.LastDriftCheck.TargetId | Should -Be 'policy-1'
    }
}
