<#
.SYNOPSIS
    Updates GA-AppLocker configuration settings.

.DESCRIPTION
    Saves configuration settings to the settings.json file.
    Can update a single key or merge an entire settings hashtable.

.PARAMETER Key
    The configuration key to update.

.PARAMETER Value
    The value to set for the specified key.

.PARAMETER Settings
    A hashtable of settings to merge with existing configuration.

.EXAMPLE
    Set-AppLockerConfig -Key 'ScanTimeoutSeconds' -Value 600

    Updates a single configuration value.

.EXAMPLE
    Set-AppLockerConfig -Settings @{ MaxConcurrentScans = 20; AutoSaveArtifacts = $false }

    Updates multiple configuration values at once.

.OUTPUTS
    [PSCustomObject] Result object with Success, Data, and Error properties.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Set-AppLockerConfig {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'SingleKey', Mandatory)]
        [string]$Key,

        [Parameter(ParameterSetName = 'SingleKey', Mandatory)]
        [object]$Value,

        [Parameter(ParameterSetName = 'Bulk', Mandatory)]
        [hashtable]$Settings
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        #region --- Load Current Config ---
        $config = Get-AppLockerConfig
        #endregion

        #region --- Convert to hashtable for modification ---
        $configHash = @{}
        $config.PSObject.Properties | ForEach-Object {
            $configHash[$_.Name] = $_.Value
        }
        #endregion

        #region --- Apply Changes ---
        if ($PSCmdlet.ParameterSetName -eq 'SingleKey') {
            $configHash[$Key] = $Value
        }
        else {
            foreach ($settingKey in $Settings.Keys) {
                $configHash[$settingKey] = $Settings[$settingKey]
            }
        }
        #endregion

        # Convert back to config object
        $config = [PSCustomObject]$configHash

        #region --- Save to File ---
        $dataPath = Get-AppLockerDataPath
        $settingsPath = Join-Path $dataPath 'Settings'
        $configFile = Join-Path $settingsPath 'settings.json'

        # Ensure settings directory exists
        if (-not (Test-Path $settingsPath)) {
            New-Item -Path $settingsPath -ItemType Directory -Force | Out-Null
        }

        $config | ConvertTo-Json -Depth 3 | Set-Content -Path $configFile -Encoding UTF8
        #endregion

        $result.Success = $true
        $result.Data = $config
        Write-AppLockerLog -Message "Configuration updated successfully" -NoConsole
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-AppLockerLog -Level Error -Message "Failed to save config: $($_.Exception.Message)"
    }

    return $result
}
