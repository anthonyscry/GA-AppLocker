#region ===== MODULE HEADER =====
<#
.MODULE
    GA-AppLocker.Core

.DESCRIPTION
    Core module providing shared utilities, logging, and configuration
    management for the GA-AppLocker Dashboard application.

    This module has no dependencies on other GA-AppLocker modules
    and serves as the foundation for all other modules.

.DEPENDENCIES
    - None (base module)

.CHANGELOG
    2026-01-17  v1.0.0  Initial release

.NOTES
    Air-gapped environment compatible.
    No external network dependencies.
#>
#endregion

#region ===== MODULE CONFIGURATION =====
# Application-wide constants
$script:APP_NAME = 'GA-AppLocker'
$script:APP_VERSION = '1.0.0'

# Default data path - can be overridden via config
$script:DEFAULT_DATA_PATH = Join-Path $env:LOCALAPPDATA $script:APP_NAME
#endregion

#region ===== FUNCTION LOADING =====
# Load all function files from the Functions directory
$functionPath = Join-Path $PSScriptRoot 'Functions'

if (Test-Path $functionPath) {
    $functionFiles = Get-ChildItem -Path $functionPath -Filter '*.ps1' -ErrorAction SilentlyContinue

    foreach ($file in $functionFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "Failed to load function file: $($file.Name). Error: $($_.Exception.Message)"
        }
    }
}
#endregion

#region ===== MODULE INITIALIZATION =====
# Ensure data directory exists on module load
$dataPath = Get-AppLockerDataPath
if (-not (Test-Path $dataPath)) {
    New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
}

# Ensure logs directory exists
$logsPath = Join-Path $dataPath 'Logs'
if (-not (Test-Path $logsPath)) {
    New-Item -Path $logsPath -ItemType Directory -Force | Out-Null
}
#endregion

#region ===== EXPORTS =====
# Export public functions
Export-ModuleMember -Function @(
    # Logging & Config
    'Write-AppLockerLog',
    'Get-AppLockerConfig',
    'Set-AppLockerConfig',
    'Test-Prerequisites',
    'Get-AppLockerDataPath',
    'Invoke-WithRetry',
    # Session State
    'Save-SessionState',
    'Restore-SessionState',
    'Clear-SessionState',
    # Cache Manager
    'Get-CachedValue',
    'Set-CachedValue',
    'Clear-AppLockerCache',
    'Get-CacheStatistics',
    'Test-CacheKey',
    'Invoke-CacheCleanup',
    # Event System
    'Register-AppLockerEvent',
    'Publish-AppLockerEvent',
    'Unregister-AppLockerEvent',
    'Get-AppLockerEventHandlers',
    'Get-AppLockerEventHistory',
    'Clear-AppLockerEventHistory',
    'Get-AppLockerStandardEvents',
    # Validation Helpers
    'Test-ValidHash',
    'Test-ValidSid',
    'Test-ValidGuid',
    'Test-ValidPath',
    'Test-ValidDistinguishedName',
    'Test-ValidHostname',
    'Test-ValidCollectionType',
    'Test-ValidRuleAction',
    'Test-ValidRuleStatus',
    'Test-ValidPolicyStatus',
    'Test-ValidEnforcementMode',
    'Test-ValidTier',
    'Assert-NotNullOrEmpty',
    'Assert-InRange',
    'Assert-MatchesPattern',
    'Assert-InSet',
    'ConvertTo-SafeFileName',
    'ConvertTo-SafeXmlString',
    'Get-ValidValues',
    # Audit Trail
    'Write-AuditLog',
    'Get-AuditLog',
    'Export-AuditLog',
    'Clear-AuditLog',
    'Get-AuditLogPath',
    'Get-AuditLogSummary',
    # Email Notifications
    'Get-EmailSettings',
    'Set-EmailSettings',
    'Set-EmailNotifyOn',
    'Send-AppLockerNotification',
    'Test-EmailSettings',
    # Reporting Export
    'Export-AppLockerReport',
    'Export-ForPowerBI',
    # Backup & Restore
    'Backup-AppLockerData',
    'Restore-AppLockerData',
    'Get-BackupHistory',
    # Group SID Resolution
    'Resolve-GroupSid'
)
#endregion
