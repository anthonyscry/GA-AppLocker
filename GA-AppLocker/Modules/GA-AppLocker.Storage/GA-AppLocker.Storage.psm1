#Requires -Version 5.1
<#
.SYNOPSIS
    SQLite storage layer for GA-AppLocker rules.

.DESCRIPTION
    Provides high-performance indexed storage for AppLocker rules using SQLite.
    Replaces individual JSON files with a single database for faster queries.

.NOTES
    Uses Microsoft.Data.Sqlite or System.Data.SQLite depending on availability.
#>

#region ===== MODULE VARIABLES =====
$script:DatabaseConnection = $null
$script:SqliteAssemblyLoaded = $false
$script:UseMicrosoftSqlite = $false
#endregion

#region ===== SAFE LOGGING =====
function script:Write-StorageLog {
    param([string]$Message, [string]$Level = 'INFO')
    if (Get-Command -Name 'Write-AppLockerLog' -ErrorAction SilentlyContinue) {
        Write-AppLockerLog -Message "[Storage] $Message" -Level $Level
    } else {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Verbose "[$timestamp] [$Level] [Storage] $Message"
    }
}
#endregion

#region ===== SQLITE ASSEMBLY LOADING =====
function script:Initialize-SqliteAssembly {
    if ($script:SqliteAssemblyLoaded) { return $true }
    
    # Try Microsoft.Data.Sqlite first (comes with .NET Core / newer Windows)
    try {
        Add-Type -AssemblyName 'Microsoft.Data.Sqlite' -ErrorAction Stop
        $script:UseMicrosoftSqlite = $true
        $script:SqliteAssemblyLoaded = $true
        Write-StorageLog -Message "Loaded Microsoft.Data.Sqlite assembly"
        return $true
    }
    catch {
        Write-StorageLog -Message "Microsoft.Data.Sqlite not available, trying System.Data.SQLite" -Level 'DEBUG'
    }
    
    # Try System.Data.SQLite from bundled location
    $modulePath = Split-Path -Parent $PSScriptRoot
    $sqliteDllPath = Join-Path $modulePath "Lib\System.Data.SQLite.dll"
    
    if (Test-Path $sqliteDllPath) {
        try {
            Add-Type -Path $sqliteDllPath -ErrorAction Stop
            $script:SqliteAssemblyLoaded = $true
            Write-StorageLog -Message "Loaded bundled System.Data.SQLite assembly"
            return $true
        }
        catch {
            Write-StorageLog -Message "Failed to load bundled SQLite: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
    
    # Try loading from GAC or system
    try {
        Add-Type -AssemblyName 'System.Data.SQLite' -ErrorAction Stop
        $script:SqliteAssemblyLoaded = $true
        Write-StorageLog -Message "Loaded System.Data.SQLite from system"
        return $true
    }
    catch {
        Write-StorageLog -Message "System.Data.SQLite not available" -Level 'DEBUG'
    }
    
    # Fallback: Use pure ADO.NET with bundled sqlite3.dll
    Write-StorageLog -Message "No SQLite assembly available - will use JSON fallback" -Level 'WARNING'
    return $false
}
#endregion

#region ===== DOT-SOURCE FUNCTIONS =====
$functionPath = Join-Path $PSScriptRoot 'Functions'
if (Test-Path $functionPath) {
    Get-ChildItem -Path $functionPath -Filter '*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-StorageLog -Message "Failed to load function file $($_.Name): $($_.Exception.Message)" -Level 'ERROR'
        }
    }
}
#endregion

# Initialize assembly on module load
$null = Initialize-SqliteAssembly

# Load JSON fallback if SQLite not available
$jsonFallbackPath = Join-Path $PSScriptRoot 'Functions\JsonIndexFallback.ps1'
if (Test-Path $jsonFallbackPath) {
    . $jsonFallbackPath
}

Export-ModuleMember -Function @(
    'Initialize-RuleDatabase',
    'Get-RuleDatabasePath', 
    'Test-RuleDatabaseExists',
    'Add-RuleToDatabase',
    'Get-RuleFromDatabase',
    'Get-RulesFromDatabase',
    'Update-RuleInDatabase',
    'Remove-RuleFromDatabase',
    'Import-RulesToDatabase',
    'Get-RuleCounts',
    'Find-RuleByHash',
    'Find-RuleByPublisher',
    'Get-DuplicateRules',
    # Index watcher functions
    'Start-RuleIndexWatcher',
    'Stop-RuleIndexWatcher',
    'Get-RuleIndexWatcherStatus',
    'Set-RuleIndexWatcherDebounce',
    'Invoke-RuleIndexRebuild'
)
