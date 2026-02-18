#Requires -Modules Pester

BeforeAll {
    $getEventsPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Get-AppLockerEventLogs.ps1'
    $invokeQueryPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Invoke-AppLockerEventQuery.ps1'
    . $getEventsPath
    . $invokeQueryPath

    if (-not (Get-Command -Name 'Write-ScanLog' -ErrorAction SilentlyContinue)) {
        function global:Write-ScanLog {
            param([string]$Message, [string]$Level = 'Info')
        }
    }

    if (-not (Get-Command -Name 'Get-WinEvent' -ErrorAction SilentlyContinue)) {
        function global:Get-WinEvent {
            param()
            throw 'Get-WinEvent should be mocked in tests.'
        }
    }
}

Describe 'Behavioral Event Ingestion: bounded query contract' -Tag @('Behavioral', 'Core') {
    It 'Rejects missing StartTime' {
        $result = Get-AppLockerEventLogs -EndTime (Get-Date) -MaxEvents 100 -EventIds @(8002)

        $result.Success | Should -BeFalse
        $result.Error | Should -Be 'Bounded query requires StartTime.'
    }

    It 'Rejects inverted time window' {
        $start = Get-Date
        $result = Get-AppLockerEventLogs -StartTime $start -EndTime $start.AddMinutes(-5) -MaxEvents 100 -EventIds @(8002)

        $result.Success | Should -BeFalse
        $result.Error | Should -Be 'EndTime must be greater than StartTime.'
    }

    It 'Rejects invalid max-event cap' {
        $start = (Get-Date).AddHours(-1)
        $end = Get-Date
        $result = Get-AppLockerEventLogs -StartTime $start -EndTime $end -MaxEvents 0 -EventIds @(8002)

        $result.Success | Should -BeFalse
        $result.Error | Should -Be 'Bounded query requires MaxEvents greater than zero.'
    }

    It 'Returns bounded local events with summary counts' {
        $start = (Get-Date).AddHours(-1)
        $end = Get-Date

        Mock Get-WinEvent {
            @(
                [PSCustomObject]@{ Id = 8002; LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'; TimeCreated = (Get-Date).AddMinutes(-10); Message = 'Blocked C:\Temp\bad.exe'; UserId = 'S-1-5-21-1'; LevelDisplayName = 'Information' },
                [PSCustomObject]@{ Id = 8001; LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'; TimeCreated = (Get-Date).AddMinutes(-9); Message = 'Allowed C:\Windows\System32\good.exe'; UserId = 'S-1-5-21-1'; LevelDisplayName = 'Information' }
            )
        }

        $result = Get-AppLockerEventLogs -StartTime $start -EndTime $end -MaxEvents 2 -EventIds @(8001, 8002)

        $result.Success | Should -BeTrue
        $result.Data.Count | Should -Be 2
        $result.Summary.TotalEvents | Should -Be 2
        $result.Summary.BlockedEvents | Should -Be 1
        $result.Summary.AllowedEvents | Should -Be 1
        $result.Summary.MaxEvents | Should -Be 2

        $result.Summary.LogScope.Count | Should -Be 4
    }

    It 'Maps AppLocker event semantics to block versus audit correctly' {
        $start = (Get-Date).AddHours(-1)
        $end = Get-Date

        Mock Get-WinEvent {
            @(
                [PSCustomObject]@{ Id = 8002; LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'; TimeCreated = (Get-Date).AddMinutes(-10); Message = 'Blocked C:\Temp\blocked.exe'; UserId = 'S-1-5-21-1'; LevelDisplayName = 'Information' },
                [PSCustomObject]@{ Id = 8003; LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'; TimeCreated = (Get-Date).AddMinutes(-9); Message = 'Would block C:\Temp\audit.exe'; UserId = 'S-1-5-21-1'; LevelDisplayName = 'Information' }
            )
        }

        $result = Get-AppLockerEventLogs -StartTime $start -EndTime $end -MaxEvents 50 -EventIds @(8002, 8003)

        $blocked = @($result.Data | Where-Object { $_.EventId -eq 8002 })[0]
        $audit = @($result.Data | Where-Object { $_.EventId -eq 8003 })[0]

        $blocked.IsBlocked | Should -BeTrue
        $blocked.IsAudit | Should -BeFalse
        $blocked.EventType | Should -Be 'EXE/DLL Blocked'

        $audit.IsBlocked | Should -BeFalse
        $audit.IsAudit | Should -BeTrue
        $audit.EventType | Should -Be 'EXE/DLL Would Block (Audit)'
    }
}

Describe 'Behavioral Event Ingestion: remote host envelopes' -Tag @('Behavioral', 'Core') {
    It 'Returns one envelope per host and preserves explicit failures' {
        $start = (Get-Date).AddHours(-1)
        $end = Get-Date

        Mock Get-AppLockerEventLogs {
            [PSCustomObject]@{
                Success = $true
                Data    = @(
                    [PSCustomObject]@{ EventId = 8001 },
                    [PSCustomObject]@{ EventId = 8002 }
                )
                Error   = $null
                Summary = [PSCustomObject]@{ TotalEvents = 2 }
            }
        } -ParameterFilter { $ComputerName -eq 'host-a' }

        Mock Get-AppLockerEventLogs {
            [PSCustomObject]@{
                Success = $false
                Data    = @()
                Error   = 'Access is denied'
                Summary = $null
            }
        } -ParameterFilter { $ComputerName -eq 'host-b' }

        $result = Invoke-AppLockerEventQuery -ComputerName @('host-a', 'host-b') -StartTime $start -EndTime $end -MaxEvents 250 -EventIds @(8001, 8002)

        $result.Count | Should -Be 2

        $hostA = @($result | Where-Object { $_.Host -eq 'host-a' })[0]
        $hostB = @($result | Where-Object { $_.Host -eq 'host-b' })[0]

        $hostA.Success | Should -BeTrue
        $hostA.Count | Should -Be 2
        $hostA.ErrorCategory | Should -BeNullOrEmpty
        $hostA.Data.Count | Should -Be 2

        $hostB.Success | Should -BeFalse
        $hostB.Count | Should -Be 0
        $hostB.ErrorCategory | Should -Be 'auth'
        $hostB.Error | Should -Be 'Access is denied'
    }

    It 'Classifies timeout and channel failures with explicit taxonomy' {
        $start = (Get-Date).AddHours(-1)
        $end = Get-Date

        Mock Get-AppLockerEventLogs {
            if ($ComputerName -eq 'timeout-host') {
                throw 'The operation timed out while querying events'
            }

            [PSCustomObject]@{
                Success = $false
                Data    = @()
                Error   = 'The specified channel could not be found'
                Summary = $null
            }
        }

        $result = Invoke-AppLockerEventQuery -ComputerName @('timeout-host', 'channel-host') -StartTime $start -EndTime $end -MaxEvents 10 -EventIds @(8001)

        $timeout = @($result | Where-Object { $_.Host -eq 'timeout-host' })[0]
        $channel = @($result | Where-Object { $_.Host -eq 'channel-host' })[0]

        $timeout.Success | Should -BeFalse
        $timeout.ErrorCategory | Should -Be 'timeout'

        $channel.Success | Should -BeFalse
        $channel.ErrorCategory | Should -Be 'channel'
    }
}
