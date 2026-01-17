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
        [string[]]$OUDistinguishedNames,

        [Parameter()]
        [bool]$IncludeNestedOUs = $true
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
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
    $osLower = ($Computer.OperatingSystem ?? '').ToLower()

    # Check OU path first
    if ($dnLower -match 'domain controllers') {
        return 'DomainController'
    }

    # Check OS for server
    if ($osLower -match 'server') {
        return 'Server'
    }

    # Check OU naming
    if ($dnLower -match 'ou=server|ou=srv') {
        return 'Server'
    }

    if ($dnLower -match 'ou=workstation|ou=desktop|ou=laptop') {
        return 'Workstation'
    }

    # Default based on OS
    if ($osLower -match 'windows 10|windows 11') {
        return 'Workstation'
    }

    return 'Unknown'
}
#endregion
