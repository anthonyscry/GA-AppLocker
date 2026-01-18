<#
.SYNOPSIS
    Saves the current application session state to a file.

.DESCRIPTION
    Persists the current application state including discovered machines,
    scan artifacts, selected items, and UI state to enable session restoration
    on next app launch. Automatically expires old sessions after 7 days.

.PARAMETER State
    Hashtable containing the session state to save.

.PARAMETER Force
    Overwrite existing session file without checking expiry.

.EXAMPLE
    Save-SessionState -State @{ discoveredMachines = @('PC001', 'PC002') }

.OUTPUTS
    [PSCustomObject] Result with Success and Data properties.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Save-SessionState {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Ensure required assembly is loaded
        if (-not ('System.Security.Cryptography.ProtectedData' -as [type])) {
            Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        }

        $dataPath = Get-AppLockerDataPath
        $sessionPath = Join-Path $dataPath 'session.json'

        # Add metadata
        $State['lastSaved'] = Get-Date -Format 'o'
        $State['version'] = '1.0'

        # Convert to JSON
        $json = $State | ConvertTo-Json -Depth 10 -Compress:$false

        # Encrypt session data using DPAPI (user-only scope)
        $encryptedBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $encryptedBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )

        # Save encrypted data (Base64 encoded for text storage)
        $encryptedJson = [Convert]::ToBase64String($protectedBytes)
        Set-Content -Path $sessionPath -Value $encryptedJson -Encoding UTF8 -Force

        Write-AppLockerLog -Message "Session state saved (encrypted) to: $sessionPath" -NoConsole

        return [PSCustomObject]@{
            Success = $true
            Data    = @{
                Path      = $sessionPath
                Timestamp = $State['lastSaved']
            }
        }
    }
    catch {
        Write-AppLockerLog -Level Error -Message "Failed to save session state: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
