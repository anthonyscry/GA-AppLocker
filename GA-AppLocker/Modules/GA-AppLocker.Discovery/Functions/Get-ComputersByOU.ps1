<#
.SYNOPSIS
    Retrieves computers from specified Organizational Units.

.DESCRIPTION
    Gets all computer objects from one or more OUs, including
    hostname, OS, last logon, and machine type classification.

.PARAMETER OUDistinguishedNames
    Array of OU distinguished names to search.

.PARAMETER IncludeNestedOUs
    Search nested OUs recursively. Default: $true

.EXAMPLE
    $computers = Get-ComputersByOU -OUDistinguishedNames @('OU=Workstations,DC=corp,DC=local')
    $computers.Data | Format-Table Hostname, OperatingSystem, MachineType

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (array of computers), and Error.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-ComputersByOU {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$OUDistinguishedNames,

        [Parameter()]
        [bool]$IncludeNestedOUs = $true
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
    }

    # Handle empty input gracefully
    if (-not $OUDistinguishedNames -or $OUDistinguishedNames.Count -eq 0) {
        $result.Success = $true
        $result.Data = @()
        return $result
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        $allComputers = [System.Collections.ArrayList]::new()
        $searchScope = if ($IncludeNestedOUs) { 'Subtree' } else { 'OneLevel' }

        #region --- Query Each OU ---
        foreach ($ouDN in $OUDistinguishedNames) {
            $computers = Get-ADComputer -Filter * `
                -SearchBase $ouDN `
                -SearchScope $searchScope `
                -Properties OperatingSystem, OperatingSystemVersion, LastLogonDate, Description, IPv4Address `
                -ErrorAction SilentlyContinue

            foreach ($computer in $computers) {
                $machineObject = [PSCustomObject]@{
                    Id                = [guid]::NewGuid().ToString()
                    Hostname          = $computer.Name
                    FQDN              = "$($computer.Name).$((Get-ADDomain).DNSRoot)"
                    DNSHostName       = $computer.DNSHostName
                    DistinguishedName = $computer.DistinguishedName
                    OperatingSystem   = $computer.OperatingSystem
                    OSVersion         = $computer.OperatingSystemVersion
                    LastLogon         = $computer.LastLogonDate
                    Description       = $computer.Description
                    IPv4Address       = $computer.IPv4Address
                    SourceOU          = $ouDN
                    MachineType       = Get-MachineTypeFromComputer -Computer $computer
                    Enabled           = $computer.Enabled
                    IsOnline          = $null  # Populated by Test-MachineConnectivity
                    WinRMStatus       = $null  # Populated by Test-MachineConnectivity
                }

                [void]$allComputers.Add($machineObject)
            }
        }
        #endregion

        #region --- Deduplicate ---
        $result.Data = $allComputers | Sort-Object Hostname -Unique
        #endregion

        $result.Success = $true
        Write-AppLockerLog -Message "Discovered $($result.Data.Count) computers from $($OUDistinguishedNames.Count) OUs" -NoConsole
    }
    catch {
        $result.Error = "Failed to get computers: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }

    return $result
}

#region ===== HELPER FUNCTIONS =====
function Get-MachineTypeFromComputer {
    param($Computer)

    $dnLower = $Computer.DistinguishedName.ToLower()
    $osLower = if ($Computer.OperatingSystem) { $Computer.OperatingSystem.ToLower() } else { '' }

    # Load tier mapping from config
    $tierMapping = $null
    try {
        $config = Get-AppLockerConfig
        $tierMapping = $config.TierMapping
    }
    catch { }

    # Use configurable patterns or fallback to defaults
    $tier0Patterns = if ($tierMapping.Tier0Patterns) { $tierMapping.Tier0Patterns } else { @('domain controllers') }
    $tier0OSPatterns = if ($tierMapping.Tier0OSPatterns) { $tierMapping.Tier0OSPatterns } else { @() }
    $tier1Patterns = if ($tierMapping.Tier1Patterns) { $tierMapping.Tier1Patterns } else { @('ou=server', 'ou=srv') }
    $tier1OSPatterns = if ($tierMapping.Tier1OSPatterns) { $tierMapping.Tier1OSPatterns } else { @('server') }
    $tier2Patterns = if ($tierMapping.Tier2Patterns) { $tierMapping.Tier2Patterns } else { @('ou=workstation', 'ou=desktop', 'ou=laptop') }
    $tier2OSPatterns = if ($tierMapping.Tier2OSPatterns) { $tierMapping.Tier2OSPatterns } else { @('windows 10', 'windows 11') }

    # Check Tier 0 (Domain Controllers)
    foreach ($pattern in $tier0Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'DomainController' }
    }
    foreach ($pattern in $tier0OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'DomainController' }
    }

    # Check Tier 1 (Servers) - OS first, then OU
    foreach ($pattern in $tier1OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'Server' }
    }
    foreach ($pattern in $tier1Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'Server' }
    }

    # Check Tier 2 (Workstations)
    foreach ($pattern in $tier2Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'Workstation' }
    }
    foreach ($pattern in $tier2OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'Workstation' }
    }

    return 'Unknown'
}
#endregion
