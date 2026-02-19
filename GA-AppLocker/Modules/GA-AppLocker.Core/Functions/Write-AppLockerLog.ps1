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
        [switch]$NoConsole,

        [Parameter()]
        [TimeSpan]$Duration,

        [Parameter()]
        [string]$Panel
    )

    #region --- Build Log Entry ---
    # Use .NET DateTime directly — Get-Date cmdlet can fail in WPF dispatcher/delegate contexts
    # where Microsoft.PowerShell.Utility module resolution breaks after extended runtime.
    $now = [DateTime]::Now
    $timestamp = $now.ToString('yyyy-MM-dd HH:mm:ss')

    # Build log entry with optional panel and duration
    $durationInfo = if ($Duration -and $Duration.TotalMilliseconds -gt 0) {
        " ($($Duration.TotalMilliseconds)ms)"
    } else { "" }

    $panelInfo = if ($Panel) { "[$Panel] " } else { "" }
    $logEntry = "[$timestamp] [$Level] ${panelInfo}$Message${durationInfo}"
    #endregion

    #region --- Write to File ---
    try {
        $dataPath = Get-AppLockerDataPath
    }
    catch {
        # Fallback if Get-AppLockerDataPath not available in current scope
        $dataPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GA-AppLocker')
    }
    $logsPath = [System.IO.Path]::Combine($dataPath, 'Logs')
    $logFile = [System.IO.Path]::Combine($logsPath, "GA-AppLocker_$($now.ToString('yyyy-MM-dd')).log")

    # Ensure logs directory exists (use .NET — Test-Path/New-Item can fail in delegate contexts)
    if (-not [System.IO.Directory]::Exists($logsPath)) {
        [void][System.IO.Directory]::CreateDirectory($logsPath)
    }

    # Append to log file (use .NET — Add-Content can fail in delegate contexts)
    try {
        [System.IO.File]::AppendAllText($logFile, "$logEntry`r`n")
    }
    catch {
        # Fallback: write to console if file write fails
        try { Write-Warning "Failed to write to log file: $($_.Exception.Message)" } catch {
            # Intentional: prevent recursive logging failure — Write-Warning itself may fail in WPF dispatcher context
        }
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
