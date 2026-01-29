<#
.SYNOPSIS
    Retrieves computers from specified Organizational Units.

.DESCRIPTION
    Gets all computer objects from one or more OUs.
    Falls back to LDAP when ActiveDirectory module is not available.

.PARAMETER OUDistinguishedNames
    Array of OU distinguished names to search.

.PARAMETER IncludeNestedOUs
    Search nested OUs recursively. Default: $true

.PARAMETER UseLdap
    Force using LDAP instead of AD module.

.EXAMPLE
    $computers = Get-ComputersByOU -OUDistinguishedNames @('OU=Workstations,DC=corp,DC=local')
    $computers.Data | Format-Table Hostname, OperatingSystem, MachineType

.OUTPUTS
    [PSCustomObject] Result object with Success, Data (array of computers), and Error.
#>
function Get-ComputersByOU {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$OUDistinguishedNames,

        [Parameter()]
        [bool]$IncludeNestedOUs = $true,
        
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

    # Handle empty input gracefully
    if (-not $OUDistinguishedNames -or $OUDistinguishedNames.Count -eq 0) {
        $result.Success = $true
        $result.Data = @()
        return $result
    }

    $useAdModule = -not $UseLdap -and (Get-Module -ListAvailable -Name ActiveDirectory)
    
    if ($useAdModule) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop

            $allComputers = [System.Collections.ArrayList]::new()
            $searchScope = if ($IncludeNestedOUs) { 'Subtree' } else { 'OneLevel' }

            # Cache domain info once outside the loop (B6 fix — was N+1 AD queries)
            $adDomain = Get-ADDomain -ErrorAction Stop
            $dnsRoot = $adDomain.DNSRoot

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
                        FQDN              = "$($computer.Name).$dnsRoot"
                        DNSHostName       = $computer.DNSHostName
                        DistinguishedName = $computer.DistinguishedName
                        OU                = $ouDN
                        OperatingSystem   = $computer.OperatingSystem
                        OSVersion         = $computer.OperatingSystemVersion
                        LastLogon         = $computer.LastLogonDate
                        Description       = $computer.Description
                        IPv4Address       = $computer.IPv4Address
                        SourceOU          = $ouDN
                        MachineType       = Get-MachineTypeFromComputer -Computer $computer
                        Enabled           = $computer.Enabled
                        IsOnline          = $null
                        WinRMStatus       = $null
                    }

                    [void]$allComputers.Add($machineObject)
                }
            }

            $result.Data = $allComputers | Sort-Object Hostname -Unique
            $result.Success = $true
            Write-AppLockerLog -Message "Discovered $($result.Data.Count) computers from $($OUDistinguishedNames.Count) OUs" -NoConsole
            return $result
        }
        catch {
            Write-AppLockerLog -Level Warning -Message "AD module failed, falling back to LDAP: $($_.Exception.Message)"
        }
    }
    
    # LDAP fallback
    Write-AppLockerLog -Message "Using LDAP fallback for computer query" -NoConsole
    return Get-ComputersByOUViaLdap -OUDistinguishedNames $OUDistinguishedNames -Server $Server -Port $Port -Credential $Credential -IncludeNestedOUs $IncludeNestedOUs
}

#region ===== HELPER FUNCTIONS =====
function Get-MachineTypeFromComputer {
    param($Computer)

    $dnLower = $Computer.DistinguishedName.ToLower()
    $osLower = if ($Computer.OperatingSystem) { $Computer.OperatingSystem.ToLower() } else { '' }

    $tierMapping = $null
    try {
        $config = Get-AppLockerConfig
        $tierMapping = $config.TierMapping
    }
    catch { }

    $tier0Patterns = if ($tierMapping.Tier0Patterns) { $tierMapping.Tier0Patterns } else { @('domain controllers') }
    $tier0OSPatterns = if ($tierMapping.Tier0OSPatterns) { $tierMapping.Tier0OSPatterns } else { @() }
    $tier1Patterns = if ($tierMapping.Tier1Patterns) { $tierMapping.Tier1Patterns } else { @('ou=server', 'ou=srv') }
    $tier1OSPatterns = if ($tierMapping.Tier1OSPatterns) { $tierMapping.Tier1OSPatterns } else { @('server') }
    $tier2Patterns = if ($tierMapping.Tier2Patterns) { $tierMapping.Tier2Patterns } else { @('ou=workstation', 'ou=desktop', 'ou=laptop') }
    $tier2OSPatterns = if ($tierMapping.Tier2OSPatterns) { $tierMapping.Tier2OSPatterns } else { @('windows 10', 'windows 11') }

    foreach ($pattern in $tier0Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'DomainController' }
    }
    foreach ($pattern in $tier0OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'DomainController' }
    }

    foreach ($pattern in $tier1OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'Server' }
    }
    foreach ($pattern in $tier1Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'Server' }
    }

    foreach ($pattern in $tier2Patterns) {
        if ($dnLower -match [regex]::Escape($pattern)) { return 'Workstation' }
    }
    foreach ($pattern in $tier2OSPatterns) {
        if ($osLower -match [regex]::Escape($pattern)) { return 'Workstation' }
    }

    return 'Unknown'
}
#endregion
