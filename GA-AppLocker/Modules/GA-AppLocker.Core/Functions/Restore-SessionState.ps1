<#
.SYNOPSIS
    Restores the application session state from a saved file.

.DESCRIPTION
    Loads previously saved session state including discovered machines,
    scan artifacts, selected items, and UI state. Automatically ignores
    sessions older than 7 days unless Force is specified.

.PARAMETER Force
    Restore session even if it's older than the expiry threshold.

.PARAMETER ExpiryDays
    Number of days after which a session is considered expired. Default is 7.

.EXAMPLE
    $session = Restore-SessionState
    if ($session.Success) {
        $machines = $session.Data.discoveredMachines
    }

.EXAMPLE
    $session = Restore-SessionState -Force -ExpiryDays 30

.OUTPUTS
    [PSCustomObject] Result with Success and Data (session state) properties.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Restore-SessionState {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [int]$ExpiryDays = 7
    )

    try {
        $dataPath = Get-AppLockerDataPath
        $sessionPath = Join-Path $dataPath 'session.json'

        if (-not (Test-Path $sessionPath)) {
            Write-AppLockerLog -Message 'No saved session found.' -NoConsole
            return [PSCustomObject]@{
                Success = $false
                Error   = 'No saved session file exists.'
                Data    = $null
            }
        }

        # Load session file
        $json = Get-Content -Path $sessionPath -Raw -Encoding UTF8
        $session = $json | ConvertFrom-Json

        # Check expiry
        if (-not $Force -and $session.lastSaved) {
            $savedDate = [datetime]::Parse($session.lastSaved)
            $age = (Get-Date) - $savedDate

            if ($age.TotalDays -gt $ExpiryDays) {
                Write-AppLockerLog -Message "Session expired ($([int]$age.TotalDays) days old). Use -Force to restore." -NoConsole
                
                # Delete expired session
                Remove-Item -Path $sessionPath -Force -ErrorAction SilentlyContinue
                
                return [PSCustomObject]@{
                    Success = $false
                    Error   = "Session expired after $ExpiryDays days."
                    Data    = $null
                }
            }
        }

        Write-AppLockerLog -Message "Session state restored from: $sessionPath" -NoConsole

        # Convert PSCustomObject to hashtable for easier use
        $stateHash = @{}
        $session.PSObject.Properties | ForEach-Object {
            $stateHash[$_.Name] = $_.Value
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = $stateHash
        }
    }
    catch {
        Write-AppLockerLog -Level Error -Message "Failed to restore session state: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
            Data    = $null
        }
    }
}

<#
.SYNOPSIS
    Clears the saved session state file.

.DESCRIPTION
    Removes the session.json file to start with a clean slate.

.EXAMPLE
    Clear-SessionState

.OUTPUTS
    [PSCustomObject] Result with Success property.
#>
function Clear-SessionState {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $dataPath = Get-AppLockerDataPath
        $sessionPath = Join-Path $dataPath 'session.json'

        if (Test-Path $sessionPath) {
            Remove-Item -Path $sessionPath -Force
            Write-AppLockerLog -Message 'Session state cleared.' -NoConsole
        }

        return [PSCustomObject]@{
            Success = $true
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
