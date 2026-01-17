<#
.SYNOPSIS
    Retrieves Active Directory domain information.

.DESCRIPTION
    Auto-detects the current domain and returns domain details
    including name, DNS root, domain controllers, and forest info.

.EXAMPLE
    $domain = Get-DomainInfo
    Write-Host "Connected to: $($domain.Data.DnsRoot)"

.OUTPUTS
    [PSCustomObject] Result object with Success, Data, and Error properties.
    Data contains: Name, DnsRoot, NetBIOSName, DomainControllers, Forest, FunctionalLevel

.NOTES
    Author: GA-AppLocker Team
    Version: 1.0.0
    Requires: ActiveDirectory module (RSAT)
#>
function Get-DomainInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    #region --- Validate AD Module ---
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $result.Error = 'ActiveDirectory module not installed. Install RSAT features.'
        Write-AppLockerLog -Level Error -Message $result.Error
        return $result
    }
    #endregion

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        #region --- Get Domain Info ---
        $domain = Get-ADDomain -ErrorAction Stop
        $forest = Get-ADForest -ErrorAction Stop

        # Get domain controllers
        $dcs = Get-ADDomainController -Filter * -ErrorAction SilentlyContinue |
            Select-Object -Property Name, HostName, IPv4Address, Site, IsGlobalCatalog
        #endregion

        #region --- Build Result ---
        $result.Data = [PSCustomObject]@{
            Name              = $domain.Name
            DnsRoot           = $domain.DNSRoot
            NetBIOSName       = $domain.NetBIOSName
            DistinguishedName = $domain.DistinguishedName
            DomainControllers = $dcs
            Forest            = $forest.Name
            ForestMode        = $forest.ForestMode
            DomainMode        = $domain.DomainMode
            PDCEmulator       = $domain.PDCEmulator
            InfrastructureMaster = $domain.InfrastructureMaster
        }

        $result.Success = $true
        Write-AppLockerLog -Message "Domain detected: $($domain.DNSRoot)" -NoConsole
        #endregion
    }
    catch {
        $result.Error = "Failed to get domain info: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }

    return $result
}
