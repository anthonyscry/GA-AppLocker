#Requires -Modules Pester

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = '/tmp'

    $script:ScheduledScansPath = Join-Path $PSScriptRoot '..\..\..\GA-AppLocker\Modules\GA-AppLocker.Scanning\Functions\ScheduledScans.ps1'
    . $script:ScheduledScansPath

    function global:Get-AppLockerDataPath {
        return Join-Path $env:LOCALAPPDATA 'GA-AppLocker'
    }

    function global:Write-AppLockerLog {
        param($Message, $Level, $NoConsole)
    }

    function global:Start-ArtifactScan {
        param(
            $ScanLocal,
            $SaveResults,
            $ScanName,
            $Paths,
            $Machines,
            $SkipDllScanning,
            $SkipWshScanning,
            $SkipShellScanning,
            $IncludeEventLogs
        )

        if ($null -eq $script:StartArtifactScanCallCount) { $script:StartArtifactScanCallCount = 0 }
        $script:StartArtifactScanCallCount += 1
        $script:LastStartArtifactScanParams = [ordered]@{
            ScanLocal = $ScanLocal
            SaveResults = $SaveResults
            ScanName = $ScanName
            Paths = $Paths
            Machines = $Machines
            SkipDllScanning = $SkipDllScanning
            SkipWshScanning = $SkipWshScanning
            SkipShellScanning = $SkipShellScanning
            IncludeEventLogs = $IncludeEventLogs
        }

        return @{ Success = $true; Summary = @{ TotalArtifacts = 0; SignedArtifacts = 0; UnsignedArtifacts = 0 }; Data = @{ EventLogs = @() } }
    }
}

AfterAll {
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
}

Describe 'Scheduled scan event log configuration' -Tag @('Behavioral','Core') {
    BeforeEach {
        $script:ScheduledScanTestPath = Join-Path ([System.IO.Path]::GetTempPath()) "GA-AppLocker-ScheduledScans-$([Guid]::NewGuid())"
        New-Item -Path $script:ScheduledScanTestPath -ItemType Directory -Force | Out-Null
        Mock Get-ScheduledScanStoragePath { return $script:ScheduledScanTestPath }
        Mock Register-ScheduledScanTask { return @{ Success = $true } }
        Mock Write-AppLockerLog { }
        $script:StartArtifactScanCallCount = 0
        $script:LastStartArtifactScanParams = $null
    }

    AfterEach {
        if (Test-Path $script:ScheduledScanTestPath) {
            Remove-Item -Path $script:ScheduledScanTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'persists the include event logs flag when creating a schedule' {
        $result = New-ScheduledScan -Name 'EventLogScan' -ScanPaths @('C:\Windows') -Schedule 'Daily' -Time '03:30' -IncludeEventLogs

        $result.Success | Should -BeTrue
        $filePath = Join-Path $script:ScheduledScanTestPath "$($result.Data.Id).json"
        $scheduled = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        $scheduled.IncludeEventLogs | Should -BeTrue
    }

    It 'passes include event logs to Start-ArtifactScan when running a scheduled scan' {
        $creation = New-ScheduledScan -Name 'EventLogScan' -ScanPaths @('C:\Windows') -Schedule 'Daily' -Time '04:00' -IncludeEventLogs
        $creation.Success | Should -BeTrue

        $runResult = Invoke-ScheduledScan -Id $creation.Data.Id
        $runResult.Success | Should -BeTrue

        $script:StartArtifactScanCallCount | Should -Be 1
        $script:LastStartArtifactScanParams.IncludeEventLogs | Should -BeTrue
    }

    It 'keeps legacy schedules without include event logs compatible' {
        $legacyId = [guid]::NewGuid().ToString()
        $legacySchedule = [PSCustomObject]@{
            Id               = $legacyId
            Name             = 'LegacySchedule'
            ScanPaths        = @('C:\Windows')
            Schedule         = 'Daily'
            Time             = '05:00'
            DaysOfWeek       = @()
            SkipDllScanning  = $false
            TargetMachines   = @()
            Enabled          = $true
            CreatedAt        = (Get-Date).ToString('o')
            LastRunAt        = $null
            NextRunAt        = (Get-Date).AddDays(1).ToString('o')
            LastRunStatus    = $null
        }

        $legacyPath = Join-Path $script:ScheduledScanTestPath "$legacyId.json"
        $legacySchedule | ConvertTo-Json -Depth 5 | Set-Content -Path $legacyPath -Encoding UTF8

        $runResult = Invoke-ScheduledScan -Id $legacyId
        $runResult.Success | Should -BeTrue

        $script:StartArtifactScanCallCount | Should -Be 1
        $script:LastStartArtifactScanParams.IncludeEventLogs | Should -Be $null
        $script:LastStartArtifactScanParams.SkipWshScanning | Should -Be $null
        $script:LastStartArtifactScanParams.SkipShellScanning | Should -Be $null
    }

    It 'persists WSH and Shell skip flags when creating a schedule' {
        $result = New-ScheduledScan -Name 'ScriptParity' -ScanPaths @('C:\Windows') -Schedule 'Daily' -Time '05:30' -SkipWshScanning -SkipShellScanning

        $result.Success | Should -BeTrue
        $filePath = Join-Path $script:ScheduledScanTestPath "$($result.Data.Id).json"
        $scheduled = Get-Content -Path $filePath -Raw | ConvertFrom-Json

        $scheduled.SkipWshScanning | Should -BeTrue
        $scheduled.SkipShellScanning | Should -BeTrue
    }

    It 'passes WSH and Shell skip flags to Start-ArtifactScan when running a scheduled scan' {
        $creation = New-ScheduledScan -Name 'ScriptParityRun' -ScanPaths @('C:\Windows') -Schedule 'Daily' -Time '06:00' -SkipWshScanning -SkipShellScanning
        $creation.Success | Should -BeTrue

        $runResult = Invoke-ScheduledScan -Id $creation.Data.Id
        $runResult.Success | Should -BeTrue

        $script:StartArtifactScanCallCount | Should -Be 1
        $script:LastStartArtifactScanParams.SkipWshScanning | Should -BeTrue
        $script:LastStartArtifactScanParams.SkipShellScanning | Should -BeTrue
    }
}
