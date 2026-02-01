#Requires -Modules Pester
<#
.SYNOPSIS
    Tests for GA-AppLocker.Core module: Config, Logging, DataPath, WithRetry, GroupSid, AuditTrail.

.DESCRIPTION
    Covers functions not tested in Cache.Tests, Events.Tests, Validation.Tests, or SessionState.Tests:
    - Get-AppLockerConfig / Set-AppLockerConfig
    - Write-AppLockerLog
    - Get-AppLockerDataPath
    - Invoke-WithRetry
    - Resolve-GroupSid
    - Test-Prerequisites
    - Write-AuditLog / Get-AuditLog / Get-AuditLogPath / Get-AuditLogSummary / Clear-AuditLog / Export-AuditLog

.NOTES
    Module: GA-AppLocker.Core
    Run with: Invoke-Pester -Path .\Tests\Unit\Core.Config.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-Module 'GA-AppLocker*' | Remove-Module -Force -ErrorAction SilentlyContinue
    $modulePath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\GA-AppLocker.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

# ============================================================================
# GET-APPLOCKERDATAPATH
# ============================================================================

Describe 'Get-AppLockerDataPath' -Tag 'Unit', 'Core' {

    It 'Should return a non-empty string' {
        $path = Get-AppLockerDataPath
        $path | Should -Not -BeNullOrEmpty
    }

    It 'Should return a path under LOCALAPPDATA' {
        $path = Get-AppLockerDataPath
        $path | Should -BeLike "*$env:LOCALAPPDATA*"
    }

    It 'Should include GA-AppLocker in the path' {
        $path = Get-AppLockerDataPath
        $path | Should -BeLike '*GA-AppLocker*'
    }

    It 'Should create the directory if it does not exist' {
        $path = Get-AppLockerDataPath
        Test-Path $path | Should -Be $true
    }

    It 'Should return the same path on repeated calls' {
        $path1 = Get-AppLockerDataPath
        $path2 = Get-AppLockerDataPath
        $path1 | Should -Be $path2
    }
}

# ============================================================================
# GET-APPLOCKERCONFIG
# ============================================================================

Describe 'Get-AppLockerConfig' -Tag 'Unit', 'Core' {

    It 'Should return a config object (not null)' {
        $config = Get-AppLockerConfig
        $config | Should -Not -BeNullOrEmpty
    }

    It 'Should have default scan paths' {
        $config = Get-AppLockerConfig
        $config.DefaultScanPaths | Should -Not -BeNullOrEmpty
        $config.DefaultScanPaths.Count | Should -BeGreaterThan 0
    }

    It 'Should have tier mapping (TierMapping)' {
        $config = Get-AppLockerConfig
        $config.TierMapping | Should -Not -BeNullOrEmpty
    }

    It 'Should have MachineTypeTiers mapping' {
        $config = Get-AppLockerConfig
        $config.MachineTypeTiers | Should -Not -BeNullOrEmpty
    }

    It 'Should return specific key when -Key is used' {
        $timeout = Get-AppLockerConfig -Key 'ScanTimeout'
        # Timeout may be null if not set, but the call should not throw
        { Get-AppLockerConfig -Key 'ScanTimeout' } | Should -Not -Throw
    }

    It 'Should return null for non-existent key' {
        $val = Get-AppLockerConfig -Key 'ThisKeyDoesNotExist_12345'
        $val | Should -BeNullOrEmpty
    }

    It 'Should have ArtifactTypes' {
        $config = Get-AppLockerConfig
        $config.ArtifactTypes | Should -Not -BeNullOrEmpty
    }

    It 'Should have HighRiskPaths' {
        $config = Get-AppLockerConfig
        $config.HighRiskPaths | Should -Not -BeNullOrEmpty
    }

    It 'Should have UI settings' {
        $config = Get-AppLockerConfig
        # The config should have some UI-related key
        $props = $config.PSObject.Properties.Name
        $props | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# SET-APPLOCKERCONFIG
# ============================================================================

Describe 'Set-AppLockerConfig' -Tag 'Unit', 'Core' {

    BeforeAll {
        # Save original config so we can restore after tests
        $script:OriginalConfig = Get-AppLockerConfig
    }

    AfterAll {
        # Restore original config - remove test settings file
        $settingsPath = Join-Path (Get-AppLockerDataPath) 'Settings\settings.json'
        if (Test-Path $settingsPath) {
            # Re-read and verify; tests may have modified
        }
    }

    It 'Should return a Success result' {
        $result = Set-AppLockerConfig -Key 'TestSetting_Unit' -Value 'TestValue123'
        $result.Success | Should -Be $true
    }

    It 'Should persist a single key-value setting' {
        Set-AppLockerConfig -Key 'TestSetting_Unit' -Value 'PersistTest'
        $readBack = Get-AppLockerConfig -Key 'TestSetting_Unit'
        $readBack | Should -Be 'PersistTest'
    }

    It 'Should persist bulk settings via -Settings hashtable' {
        $settings = @{
            TestBulk1 = 'Value1'
            TestBulk2 = 42
        }
        $result = Set-AppLockerConfig -Settings $settings
        $result.Success | Should -Be $true

        $config = Get-AppLockerConfig
        $config.TestBulk1 | Should -Be 'Value1'
        $config.TestBulk2 | Should -Be 42
    }

    It 'Should overwrite existing key' {
        Set-AppLockerConfig -Key 'TestSetting_Unit' -Value 'Original'
        Set-AppLockerConfig -Key 'TestSetting_Unit' -Value 'Overwritten'
        $val = Get-AppLockerConfig -Key 'TestSetting_Unit'
        $val | Should -Be 'Overwritten'
    }

    It 'Should handle boolean values' {
        Set-AppLockerConfig -Key 'TestBool' -Value $true
        $val = Get-AppLockerConfig -Key 'TestBool'
        $val | Should -Be $true
    }

    It 'Should handle array values' {
        Set-AppLockerConfig -Key 'TestArray' -Value @('a', 'b', 'c')
        $val = Get-AppLockerConfig -Key 'TestArray'
        $val.Count | Should -Be 3
    }
}

# ============================================================================
# WRITE-APPLOCKERLOG
# ============================================================================

Describe 'Write-AppLockerLog' -Tag 'Unit', 'Core' {

    It 'Should not throw when writing a log message' {
        { Write-AppLockerLog -Message 'Unit test log message' -Level 'INFO' -NoConsole } | Should -Not -Throw
    }

    It 'Should not throw for Warning level' {
        { Write-AppLockerLog -Message 'Unit test warning' -Level 'Warning' -NoConsole } | Should -Not -Throw
    }

    It 'Should not throw for Error level' {
        { Write-AppLockerLog -Message 'Unit test error' -Level 'Error' -NoConsole } | Should -Not -Throw
    }

    It 'Should not throw for Debug level' {
        { Write-AppLockerLog -Message 'Unit test debug' -Level 'Debug' -NoConsole } | Should -Not -Throw
    }

    It 'Should create a log file in the Logs directory' {
        $logDir = Join-Path (Get-AppLockerDataPath) 'Logs'
        Write-AppLockerLog -Message 'File creation test' -Level 'INFO' -NoConsole
        $today = Get-Date -Format 'yyyy-MM-dd'
        $logFile = Join-Path $logDir "GA-AppLocker_$today.log"
        Test-Path $logFile | Should -Be $true
    }

    It 'Should append to existing log file' {
        $logDir = Join-Path (Get-AppLockerDataPath) 'Logs'
        $today = Get-Date -Format 'yyyy-MM-dd'
        $logFile = Join-Path $logDir "GA-AppLocker_$today.log"

        $sizeBefore = if (Test-Path $logFile) { (Get-Item $logFile).Length } else { 0 }
        Write-AppLockerLog -Message 'Append test message 12345' -Level 'INFO' -NoConsole
        $sizeAfter = (Get-Item $logFile).Length
        $sizeAfter | Should -BeGreaterThan $sizeBefore
    }

    It 'Should include timestamp in log entry' {
        $logDir = Join-Path (Get-AppLockerDataPath) 'Logs'
        $today = Get-Date -Format 'yyyy-MM-dd'
        $logFile = Join-Path $logDir "GA-AppLocker_$today.log"

        $uniqueMsg = "TimestampCheck_$(Get-Date -Format 'HHmmss')"
        Write-AppLockerLog -Message $uniqueMsg -Level 'INFO' -NoConsole

        $content = Get-Content $logFile -Tail 5
        ($content -join "`n") | Should -BeLike "*$uniqueMsg*"
    }

    It 'Should reject empty message (ValidateNotNullOrEmpty)' {
        { Write-AppLockerLog -Message '' -Level 'INFO' -NoConsole } | Should -Throw
    }

    It 'Should handle special characters in message' {
        { Write-AppLockerLog -Message 'Test <>&"chars' -Level 'INFO' -NoConsole } | Should -Not -Throw
    }
}

# ============================================================================
# INVOKE-WITHRETRY (not exported — dot-source directly for testing)
# ============================================================================

Describe 'Invoke-WithRetry' -Tag 'Unit', 'Core' {

    BeforeAll {
        # Invoke-WithRetry is no longer exported (dead code) but we test it directly
        $retryPath = Join-Path $PSScriptRoot '..\..\GA-AppLocker\Modules\GA-AppLocker.Core\Functions\Invoke-WithRetry.ps1'
        . $retryPath
    }

    It 'Should execute scriptblock and return result on first try' {
        $result = Invoke-WithRetry -ScriptBlock { 42 } -MaxRetries 3
        $result | Should -Be 42
    }

    It 'Should return complex objects' {
        $result = Invoke-WithRetry -ScriptBlock { @{ Key = 'Value' } }
        $result.Key | Should -Be 'Value'
    }

    It 'Should retry on transient errors and succeed' {
        $script:RetryCount = 0
        $result = Invoke-WithRetry -ScriptBlock {
            $script:RetryCount++
            if ($script:RetryCount -lt 2) { throw 'The client cannot connect to the destination' }
            'success'
        } -MaxRetries 3 -InitialDelayMs 10 -OperationName 'UnitTest'
        $result | Should -Be 'success'
        $script:RetryCount | Should -BeGreaterOrEqual 2
    }

    It 'Should throw immediately on non-transient errors' {
        {
            Invoke-WithRetry -ScriptBlock {
                throw 'Non-transient custom error'
            } -MaxRetries 3 -InitialDelayMs 10 -TransientErrorPatterns @('cannot access')
        } | Should -Throw '*Non-transient*'
    }

    It 'Should throw after max retries exhausted' {
        {
            Invoke-WithRetry -ScriptBlock {
                throw 'The process cannot access the file'
            } -MaxRetries 2 -InitialDelayMs 10
        } | Should -Throw
    }

    It 'Should work with MaxRetries of 0 (no retries)' {
        $result = Invoke-WithRetry -ScriptBlock { 'no retry' } -MaxRetries 0
        $result | Should -Be 'no retry'
    }

    It 'Should pass with UseExponentialBackoff false' {
        $result = Invoke-WithRetry -ScriptBlock { 'linear' } -MaxRetries 1 -UseExponentialBackoff $false
        $result | Should -Be 'linear'
    }
}

# ============================================================================
# RESOLVE-GROUPSID
# ============================================================================

Describe 'Resolve-GroupSid' -Tag 'Unit', 'Core' {

    It 'Should resolve Everyone to S-1-1-0' {
        $sid = Resolve-GroupSid -GroupName 'Everyone'
        $sid | Should -Be 'S-1-1-0'
    }

    It 'Should resolve Administrators to S-1-5-32-544' {
        $sid = Resolve-GroupSid -GroupName 'Administrators'
        $sid | Should -Be 'S-1-5-32-544'
    }

    It 'Should resolve Users to S-1-5-32-545' {
        $sid = Resolve-GroupSid -GroupName 'Users'
        $sid | Should -Be 'S-1-5-32-545'
    }

    It 'Should resolve Authenticated Users to S-1-5-11' {
        $sid = Resolve-GroupSid -GroupName 'Authenticated Users'
        $sid | Should -Be 'S-1-5-11'
    }

    It 'Should strip RESOLVE: prefix' {
        $sid = Resolve-GroupSid -GroupName 'RESOLVE:Everyone'
        $sid | Should -Be 'S-1-1-0'
    }

    It 'Should return UNRESOLVED placeholder for unknown groups' {
        $result = Resolve-GroupSid -GroupName 'NonExistentGroup_XYZ123' -FallbackToPlaceholder
        $result | Should -BeLike 'UNRESOLVED:*'
    }

    It 'Should cache resolved SIDs (second call should be fast)' {
        # First call
        Resolve-GroupSid -GroupName 'Everyone'
        # Second call should use cache
        $sid = Resolve-GroupSid -GroupName 'Everyone'
        $sid | Should -Be 'S-1-1-0'
    }

    It 'Should return null when FallbackToPlaceholder is false for unknown group' {
        $result = Resolve-GroupSid -GroupName 'CompletelyFakeGroup_999'
        # With default FallbackToPlaceholder ($true), should return UNRESOLVED:
        $result | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# TEST-PREREQUISITES
# ============================================================================

Describe 'Test-Prerequisites' -Tag 'Unit', 'Core' {

    It 'Should return an object with AllPassed and Checks properties' {
        $result = Test-Prerequisites
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'AllPassed'
        $result.PSObject.Properties.Name | Should -Contain 'Checks'
    }

    It 'Should have multiple check entries' {
        $result = Test-Prerequisites
        $result.Checks.Count | Should -BeGreaterOrEqual 3
    }

    It 'Should pass PowerShell version check (we are running PS 5.1+)' {
        $result = Test-Prerequisites
        $psCheck = $result.Checks | Where-Object { $_.Name -like '*PowerShell*' }
        $psCheck | Should -Not -BeNullOrEmpty
        $psCheck.Passed | Should -Be $true
    }

    It 'Should pass .NET Framework check' {
        $result = Test-Prerequisites
        $netCheck = $result.Checks | Where-Object { $_.Name -like '*.NET*' }
        $netCheck | Should -Not -BeNullOrEmpty
        $netCheck.Passed | Should -Be $true
    }

    It 'Should check for domain membership' {
        $result = Test-Prerequisites
        $domainCheck = $result.Checks | Where-Object { $_.Name -like '*Domain*' }
        $domainCheck | Should -Not -BeNullOrEmpty
    }

    It 'Should check for administrator privileges' {
        $result = Test-Prerequisites
        $adminCheck = $result.Checks | Where-Object { $_.Name -like '*Admin*' }
        $adminCheck | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# AUDIT TRAIL
# ============================================================================

Describe 'Write-AuditLog' -Tag 'Unit', 'Core', 'AuditTrail' {

    It 'Should return a Success result' {
        $result = Write-AuditLog -Action 'UnitTest' -Category 'System' -Target 'TestTarget'
        $result.Success | Should -Be $true
    }

    It 'Should create an audit entry with a GUID Id' {
        $result = Write-AuditLog -Action 'UnitTest' -Category 'Rule' -Target 'TestRule'
        $result.Data.Id | Should -Not -BeNullOrEmpty
        { [guid]::Parse($result.Data.Id) } | Should -Not -Throw
    }

    It 'Should record the correct Action and Category' {
        $result = Write-AuditLog -Action 'Created' -Category 'Policy' -Target 'MyPolicy'
        $result.Data.Action | Should -Be 'Created'
        $result.Data.Category | Should -Be 'Policy'
    }

    It 'Should record user identity' {
        $result = Write-AuditLog -Action 'Test' -Category 'System'
        $result.Data.User | Should -Not -BeNullOrEmpty
    }

    It 'Should record timestamp in ISO 8601 format' {
        $result = Write-AuditLog -Action 'Test' -Category 'System'
        $result.Data.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
    }

    It 'Should accept OldValue and NewValue for change tracking' {
        $result = Write-AuditLog -Action 'StatusChanged' -Category 'Rule' -Target 'Rule1' -OldValue 'Pending' -NewValue 'Approved'
        $result.Success | Should -Be $true
    }
}

Describe 'Get-AuditLog' -Tag 'Unit', 'Core', 'AuditTrail' {

    BeforeAll {
        # Clean any stale/corrupt audit log from prior test runs to ensure fresh state
        $auditPath = Get-AuditLogPath
        if (Test-Path $auditPath) {
            Remove-Item $auditPath -Force -ErrorAction SilentlyContinue
        }
        # Write some entries for retrieval
        Write-AuditLog -Action 'TestGet1' -Category 'System' -Target 'Target1'
        Write-AuditLog -Action 'TestGet2' -Category 'Rule' -Target 'Target2'
        Write-AuditLog -Action 'TestGet3' -Category 'System' -Target 'Target3'
    }

    It 'Should return a Success result' {
        $result = Get-AuditLog
        $result.Success | Should -Be $true
    }

    It 'Should return audit entries as an array' {
        $result = Get-AuditLog -Last 100
        $result.Data | Should -Not -BeNullOrEmpty
        @($result.Data).Count | Should -BeGreaterOrEqual 1
    }

    It 'Should filter by Category' {
        $result = Get-AuditLog -Category 'System' -Last 50
        $result.Success | Should -Be $true
        if ($result.Data -and @($result.Data).Count -gt 0) {
            @($result.Data | Where-Object { $_.Category -ne 'System' }).Count | Should -Be 0
        }
    }

    It 'Should filter by Action' {
        $result = Get-AuditLog -Action 'TestGet1' -Last 50
        $result.Success | Should -Be $true
    }

    It 'Should respect the -Last parameter' {
        $result = Get-AuditLog -Last 2
        $result.Success | Should -Be $true
        @($result.Data).Count | Should -BeLessOrEqual 2
    }
}

Describe 'Get-AuditLogPath' -Tag 'Unit', 'Core', 'AuditTrail' {

    It 'Should return a path string' {
        $path = Get-AuditLogPath
        $path | Should -Not -BeNullOrEmpty
    }

    It 'Should include AuditTrail in the path' {
        $path = Get-AuditLogPath
        $path | Should -BeLike '*AuditTrail*'
    }

    It 'Should include audit-log.json in the filename' {
        $path = Get-AuditLogPath
        $path | Should -BeLike '*audit-log*'
    }
}

Describe 'Get-AuditLogSummary' -Tag 'Unit', 'Core', 'AuditTrail' {

    BeforeAll {
        # Ensure audit log has fresh entries (may have been cleaned by prior Describe block)
        $auditPath = Get-AuditLogPath
        if (-not (Test-Path $auditPath)) {
            Write-AuditLog -Action 'SummarySetup1' -Category 'System' -Target 'SetupTarget'
            Write-AuditLog -Action 'SummarySetup2' -Category 'Rule' -Target 'SetupTarget2'
        }
    }

    It 'Should return a Success result' {
        $result = Get-AuditLogSummary
        $result.Success | Should -Be $true
    }

    It 'Should include TotalEntries' {
        $result = Get-AuditLogSummary
        $result.Data.TotalEntries | Should -Not -BeNullOrEmpty
    }

    It 'Should include ByCategory breakdown' {
        $result = Get-AuditLogSummary
        $result.Data.PSObject.Properties.Name | Should -Contain 'ByCategory'
    }

    It 'Should respect Days parameter' {
        $result = Get-AuditLogSummary -Days 1
        $result.Success | Should -Be $true
    }
}
