<#
.SYNOPSIS
    Retrieves the Active Directory OU tree structure.

.DESCRIPTION
    Builds a hierarchical tree of Organizational Units.
    Falls back to LDAP when ActiveDirectory module is not available.

.PARAMETER SearchBase
    The distinguished name of the OU to start from.

.PARAMETER IncludeComputerCount
    Include the count of computers in each OU. Default: $true

.PARAMETER UseLdap
    Force using LDAP instead of AD module.

.EXAMPLE
    $tree = Get-OUTree
    $tree.Data | Format-Table Name, Path, ComputerCount

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (array of OUs), and Error.
#>
function Get-OUTree {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [bool]$IncludeComputerCount = $true,
        
        [Parameter()]
        [switch]$UseLdap,
        
        [Parameter()]
        [string]$Server,
        
        [Parameter()]
        [int]$Port = 389,
        
        [Parameter()]
        [pscredential]$Credential
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = @()
        Error   = $null
    }

    $useAdModule = -not $UseLdap -and (Get-Module -ListAvailable -Name ActiveDirectory)
    
    if ($useAdModule) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop

            # Cache domain info once (B7 fix — was 3 separate Get-ADDomain calls)
            $adDomain = Get-ADDomain -ErrorAction Stop
            if (-not $SearchBase) {
                $SearchBase = $adDomain.DistinguishedName
            }

            $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $SearchBase -Properties CanonicalName |
                Sort-Object CanonicalName

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

                if ($IncludeComputerCount) {
                    $computers = Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue
                    $ouObject.ComputerCount = ($computers | Measure-Object).Count
                }

                [void]$ouList.Add($ouObject)
            }

            $rootObject = [PSCustomObject]@{
                Name              = $adDomain.Name
                DistinguishedName = $SearchBase
                CanonicalName     = $adDomain.DNSRoot
                Path              = $adDomain.DNSRoot
                Depth             = 0
                ComputerCount     = 0
                MachineType       = 'Mixed'
            }

            if ($IncludeComputerCount) {
                $rootComputers = Get-ADComputer -Filter * -SearchBase $SearchBase -SearchScope OneLevel -ErrorAction SilentlyContinue
                $rootObject.ComputerCount = ($rootComputers | Measure-Object).Count
            }

            $result.Data = @($rootObject) + $ouList.ToArray()
            $result.Success = $true
            Write-AppLockerLog -Message "Retrieved $($ouList.Count) OUs from AD" -NoConsole
            return $result
        }
        catch {
            Write-AppLockerLog -Level Warning -Message "AD module failed, falling back to LDAP: $($_.Exception.Message)"
        }
    }
    
    # LDAP fallback
    Write-AppLockerLog -Message "Using LDAP fallback for OU tree" -NoConsole
    return Get-OUTreeViaLdap -Server $Server -Port $Port -Credential $Credential -SearchBase $SearchBase -IncludeComputerCount $IncludeComputerCount
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
