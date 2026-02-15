<#
.SYNOPSIS
    Retrieves the GA-AppLocker configuration settings.

.DESCRIPTION
    Loads configuration from the settings.json file in the application
    data directory. Returns default values if config file doesn't exist.

.PARAMETER Key
    Optional. Retrieve a specific configuration key instead of all settings.

.EXAMPLE
    $config = Get-AppLockerConfig

    Returns all configuration settings as a hashtable.

.EXAMPLE
    $timeout = Get-AppLockerConfig -Key 'ScanTimeoutSeconds'

    Returns the value of a specific configuration key.

.OUTPUTS
    [hashtable] or [object] Configuration settings or specific value.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-AppLockerConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Key
    )

    #region --- Default Configuration ---
    # These defaults match specification requirements
    $defaultConfig = @{
        # Scan settings
        ScanTimeoutSeconds    = 300
        MaxConcurrentScans    = 10
        DefaultScanDepth      = 'Standard'
        AutoGenerateRules     = $true
        AutoSaveArtifacts     = $true

        # Artifact types to scan
        ArtifactTypes         = @('EXE', 'DLL', 'MSI', 'Script')

        # Default scan paths
        DefaultScanPaths      = @(
            'C:\Program Files',
            'C:\Program Files (x86)',
            'C:\ProgramData',
            'C:\Windows\System32',
            'C:\Windows\SysWOW64',
            'C:\Users\*\AppData\Local\Programs',
            'C:\Users\*\AppData\Local\Microsoft\WindowsApps'
        )

        # High-risk paths for attention
        HighRiskPaths         = @(
            '%USERPROFILE%\Downloads',
            '%USERPROFILE%\Desktop',
            '%TEMP%',
            '%LOCALAPPDATA%\Temp'
        )

        # Default group assignments by rule collection
        DefaultGroups         = @{
            EXE    = 'S-1-5-11'  # Authenticated Users
            DLL    = 'S-1-1-0'   # Everyone
            MSI    = 'S-1-5-32-544'  # Administrators
            Script = 'S-1-5-32-544'  # Administrators
        }

        # Storage settings
        ScanRetentionDays     = 30
        AutoCleanupEnabled    = $true

        # UI settings
        LastActivePanel       = 'Dashboard'
        SidebarCollapsed      = $false

        # Remember dialog choices
        RememberDialogs       = @{
            FullScanConfirmation = $false
            DeployConfirmation   = $false
            DeleteConfirmation   = $true
        }

        # AD Tier Classification Mapping
        # Maps machine types to administrative tiers (0 = highest privilege)
        TierMapping           = @{
            # Tier 0: Domain Controllers, critical infrastructure
            Tier0Patterns     = @('domain controllers', 'ou=tier0', 'ou=t0')
            Tier0OSPatterns   = @()
            # Tier 1: Servers
            Tier1Patterns     = @('ou=server', 'ou=srv', 'ou=tier1', 'ou=t1')
            Tier1OSPatterns   = @('server')
            # Tier 2: Workstations (default for unmatched)
            Tier2Patterns     = @('ou=workstation', 'ou=desktop', 'ou=laptop', 'ou=tier2', 'ou=t2')
            Tier2OSPatterns   = @('windows 10', 'windows 11')
        }

        # Machine type to tier number mapping
        MachineTypeTiers      = @{
            DomainController = 0
            Server           = 1
            Workstation      = 2
            Unknown          = 2
        }
    }
    #endregion

    #region --- Load Config File ---
    $dataPath = Get-AppLockerDataPath
    $settingsPath = Join-Path $dataPath 'Settings'
    $configFile = Join-Path $settingsPath 'settings.json'

    $config = $defaultConfig.Clone()

    if (Test-Path $configFile) {
        try {
            $jsonContent = Get-Content -Path $configFile -Raw
            $savedConfig = $jsonContent | ConvertFrom-Json
            # Convert PSCustomObject to hashtable for PS 5.1 compatibility
            $savedConfig.PSObject.Properties | ForEach-Object {
                $config[$_.Name] = $_.Value
            }
        }
        catch {
            Write-AppLockerLog -Level Warning -Message "Failed to load config: $($_.Exception.Message)"
        }
    }
    #endregion

    #region --- Return Result ---
    if ($Key) {
        return $config[$Key]
    }
    # Return as PSCustomObject for easier property access
    return [PSCustomObject]$config
    #endregion
}
