<#
.SYNOPSIS
    Retrieves the Active Directory OU tree structure.

.DESCRIPTION
    Builds a hierarchical tree of Organizational Units starting from
    the domain root or a specified OU. Includes computer counts per OU.

.PARAMETER SearchBase
    The distinguished name of the OU to start from. Defaults to domain root.

.PARAMETER IncludeComputerCount
    Include the count of computers in each OU. Default: $true

.EXAMPLE
    $tree = Get-OUTree
    $tree.Data | Format-Table Name, Path, ComputerCount

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (array of OUs), and Error.

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
#>
function Get-OUTree {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [bool]$IncludeComputerCount = $true
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        #region --- Determine Search Base ---
        if (-not $SearchBase) {
            $domain = Get-ADDomain -ErrorAction Stop
            $SearchBase = $domain.DistinguishedName
        }
        #endregion

        #region --- Get All OUs ---
        $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $SearchBase -Properties CanonicalName |
            Sort-Object CanonicalName
        #endregion

        #region --- Build OU Objects ---
        $ouList = [System.Collections.ArrayList]::new()

        foreach ($ou in $ous) {
            $ouObject = [PSCustomObject]@{
                Name              = $ou.Name
                DistinguishedName = $ou.DistinguishedName
                CanonicalName     = $ou.CanonicalName
                Path              = $ou.CanonicalName
                Depth             = ($ou.DistinguishedName -split ',OU=' ).Count - 1
                ComputerCount     = 0
                MachineType       = Get-MachineTypeFromOU -OUPath $ou.DistinguishedName
            }

            # Get computer count if requested
            if ($IncludeComputerCount) {
                $computers = Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue
                $ouObject.ComputerCount = ($computers | Measure-Object).Count
            }

            [void]$ouList.Add($ouObject)
        }

        # Add the domain root
        $rootObject = [PSCustomObject]@{
            Name              = (Get-ADDomain).Name
            DistinguishedName = $SearchBase
            CanonicalName     = (Get-ADDomain).DNSRoot
            Path              = (Get-ADDomain).DNSRoot
            Depth             = 0
            ComputerCount     = 0
            MachineType       = 'Mixed'
        }

        if ($IncludeComputerCount) {
            $rootComputers = Get-ADComputer -Filter * -SearchBase $SearchBase -SearchScope OneLevel -ErrorAction SilentlyContinue
            $rootObject.ComputerCount = ($rootComputers | Measure-Object).Count
        }

        $result.Data = @($rootObject) + $ouList.ToArray()
        #endregion

        $result.Success = $true
        Write-AppLockerLog -Message "Retrieved $($ouList.Count) OUs from AD" -NoConsole
    }
    catch {
        $result.Error = "Failed to get OU tree: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }

    return $result
}

#region ===== HELPER FUNCTIONS =====
function Get-MachineTypeFromOU {
    param([string]$OUPath)

    $pathLower = $OUPath.ToLower()

    if ($pathLower -match 'domain controllers') {
        return 'DomainController'
    }
    elseif ($pathLower -match 'server|srv') {
        return 'Server'
    }
    elseif ($pathLower -match 'workstation|desktop|laptop|ws') {
        return 'Workstation'
    }

    return 'Unknown'
}
#endregion
