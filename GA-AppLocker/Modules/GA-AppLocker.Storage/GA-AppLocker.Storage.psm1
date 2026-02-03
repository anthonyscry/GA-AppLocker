#Requires -Version 5.1
<#
.SYNOPSIS
    JSON-based storage layer for GA-AppLocker rules.

.DESCRIPTION
    Provides high-performance indexed storage for AppLocker rules using JSON files.
    Uses a central index file with in-memory hashtables for O(1) lookups.

.NOTES
    Version 2.0.0 - Simplified to JSON-only storage (removed SQLite dependency)
#>

#region ===== SAFE LOGGING =====
# Changed from script: to regular function so dot-sourced files can call it
function Write-StorageLog {
    param([string]$Message, [string]$Level = 'INFO')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message "[Storage] $Message" -Level $Level
    } else {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Verbose "[$timestamp] [$Level] [Storage] $Message"
    }
}
#endregion

#region ===== DOT-SOURCE FUNCTIONS =====
$functionPath = Join-Path $PSScriptRoot 'Functions'
if (Test-Path $functionPath) {
    # Load files in specific order for dependencies
    $loadOrder = @(
        'RuleStorage.ps1',      # Core JSON storage (renamed from JsonIndexFallback.ps1)
        'BulkOperations.ps1',   # Bulk operations
        'IndexWatcher.ps1',     # File watcher
        'RuleRepository.ps1'    # Repository pattern
    )
    
    foreach ($fileName in $loadOrder) {
        $filePath = Join-Path $functionPath $fileName
        if (Test-Path $filePath) {
            try {
                . $filePath
                Write-StorageLog -Message "Loaded $fileName"
            }
            catch {
                Write-StorageLog -Message "Failed to load $fileName : $($_.Exception.Message)" -Level 'ERROR'
            }
        }
    }
    
    # Load any remaining function files
    Get-ChildItem -Path $functionPath -Filter '*.ps1' -File | 
        Where-Object { $_.Name -notin $loadOrder } |
        ForEach-Object {
            try {
                . $_.FullName
            }
            catch {
                Write-StorageLog -Message "Failed to load $($_.Name): $($_.Exception.Message)" -Level 'ERROR'
            }
        }
}
#endregion

Write-StorageLog -Message "Storage module loaded (JSON-only mode)"

Export-ModuleMember -Function @(
    # Rule Storage Operations (JSON-based)
    'Get-RuleStoragePath',
    'Get-RuleById',
    'Get-AllRules',
    'Add-Rule',
    'Update-Rule',
    'Remove-Rule',
    'Find-RuleByHash',
    'Find-RuleByPublisher',
    
    # Bulk Operations (Batch Rule Generation)
    'Get-RuleCounts',
    'Save-RulesBulk',
    'Add-RulesToIndex',
    'Get-ExistingRuleIndex',
    'Remove-RulesBulk',
    'Remove-RulesFromIndex',
    'Get-BatchPreview',
    'Update-RuleStatusInIndex',
    
    # Index Management
    'Reset-RulesIndexCache',
    'Rebuild-RulesIndex',
    'Remove-OrphanedRuleFiles',
    
    # Index Watcher Functions
    'Start-RuleIndexWatcher',
    'Stop-RuleIndexWatcher',
    'Get-RuleIndexWatcherStatus',
    'Set-RuleIndexWatcherDebounce',
    'Invoke-RuleIndexRebuild',
    
    # Repository Pattern Functions
    'Get-RuleFromRepository',
    'Save-RuleToRepository',
    'Remove-RuleFromRepository',
    'Find-RulesInRepository',
    'Get-RuleCountsFromRepository',
    'Invoke-RuleBatchOperation',
    'Test-RuleExistsInRepository',
    
    # Backwards Compatibility Aliases (needed by Rules module)
    'Get-RulesFromDatabase',
    'Get-RuleFromDatabase',
    'Add-RuleToDatabase',
    'Update-RuleInDatabase',
    'Remove-RuleFromDatabase',
    'Initialize-RuleDatabase',
    'Get-RuleDatabasePath',
    'Test-RuleDatabaseExists'
)
