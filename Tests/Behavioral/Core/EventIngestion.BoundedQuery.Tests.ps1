#Requires -Modules Pester

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\Get-AppLockerEventLogs.ps1'
    . $scriptPath

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
