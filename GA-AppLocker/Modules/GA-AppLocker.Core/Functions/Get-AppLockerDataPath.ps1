<#
.SYNOPSIS
    Returns the application data directory path for GA-AppLocker.

.DESCRIPTION
    Returns the standardized path where GA-AppLocker stores all data
    including scans, credentials, policies, rules, settings, and logs.
    Creates the directory if it doesn't exist.

.EXAMPLE
    $path = Get-AppLockerDataPath

    Returns: C:\Users\{user}\AppData\Local\GA-AppLocker

.OUTPUTS
    [string] The full path to the GA-AppLocker data directory.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-AppLockerDataPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = Join-Path $env:LOCALAPPDATA 'GA-AppLocker'

    # Ensure directory exists
    if (-not (Test-Path $dataPath)) {
        New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
    }

    return $dataPath
}
