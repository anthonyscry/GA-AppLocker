<#
.SYNOPSIS
    Writes a log entry to the GA-AppLocker log file and optionally to console.

.DESCRIPTION
    Centralized logging function for all GA-AppLocker operations.
    Writes timestamped entries to a daily log file with configurable
    log levels (Info, Warning, Error, Debug).

.PARAMETER Message
    The log message to write.

.PARAMETER Level
    The severity level of the log entry. Valid values: Info, Warning, Error, Debug.
    Default: Info

.PARAMETER NoConsole
    Suppress console output. Log file is always written.

.EXAMPLE
    Write-AppLockerLog -Message "Scan started for DC01"

    Writes an Info-level log entry.

.EXAMPLE
    Write-AppLockerLog -Level Error -Message "WinRM connection failed"

    Writes an Error-level log entry.

.OUTPUTS
    None. Writes to log file and optionally console.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>
function Write-AppLockerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info',

        [Parameter()]
        [switch]$NoConsole
    )

    #region --- Build Log Entry ---
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    #endregion

    #region --- Write to File ---
    $dataPath = Get-AppLockerDataPath
    $logsPath = Join-Path $dataPath 'Logs'
    $logFile = Join-Path $logsPath "GA-AppLocker_$(Get-Date -Format 'yyyy-MM-dd').log"

    # Ensure logs directory exists
    if (-not (Test-Path $logsPath)) {
        New-Item -Path $logsPath -ItemType Directory -Force | Out-Null
    }

    # Append to log file
    # Note: Add-Content uses file locking but is not fully thread-safe for high-concurrency scenarios
    try {
        Add-Content -Path $logFile -Value $logEntry -ErrorAction Stop
    }
    catch {
        # Fallback: write to console if file write fails
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
    #endregion

    #region --- Console Output ---
    if (-not $NoConsole) {
        switch ($Level) {
            'Error'   { Write-Host $logEntry -ForegroundColor Red }
            'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
            'Debug'   { Write-Host $logEntry -ForegroundColor Gray }
            default   { Write-Host $logEntry -ForegroundColor White }
        }
    }
    #endregion
}
