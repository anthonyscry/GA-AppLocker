<#
.SYNOPSIS
    LDAP helper functions for AD Discovery without RSAT.
.DESCRIPTION
    PowerShell 5.1 compatible LDAP functions.
.NOTES
    Author: GA-AppLocker Team
#>

function Get-LdapConnection {
    [CmdletBinding()]
    param(
        [string]$Server = $env:USERDNSDOMAIN,
        [int]$Port = 389,
        [pscredential]$Credential,
        [bool]$UseSSL = $false
    )
    
    try {
        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
        $ldapServer = if ($Port -ne 389) { "${Server}:${Port}" } else { $Server }
        $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($ldapServer)
        $connection.SessionOptions.ProtocolVersion = 3
        $connection.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::None
        if ($UseSSL) { $connection.SessionOptions.SecureSocketLayer = $true }
        if ($Credential) {
            $connection.Credential = $Credential.GetNetworkCredential()
            $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Basic
        } else {
            $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
        }
        $connection.Bind()
        return $connection
    }
    catch {
        Write-AppLockerLog -Level Error -Message "LDAP connection failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-LdapSearchResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.DirectoryServices.Protocols.LdapConnection]$Connection,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SearchBase,
        [string]$Filter = "(objectClass=*)",
        [string[]]$Properties = @("*"),
        [System.DirectoryServices.Protocols.SearchScope]$Scope = "Subtree"
    )
    try {
        $request = New-Object System.DirectoryServices.Protocols.SearchRequest($SearchBase, $Filter, $Scope, $Properties)
        $request.SizeLimit = 1000
        $response = $Connection.SendRequest($request)
        return $response.Entries
    }
    catch {
        Write-AppLockerLog -Level Error -Message "LDAP search failed: $($_.Exception.Message)"
        return @()
    }
}

function Get-DomainInfoViaLdap {
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential)
    
    $result = [PSCustomObject]@{ Success = $false; Data = $null; Error = $null }
    
    try {
        if (-not $Server) {
            $config = Get-AppLockerConfig
            if ($config.LdapServer) { $Server = $config.LdapServer }
            elseif ($env:USERDNSDOMAIN) { $Server = $env:USERDNSDOMAIN }
            else { $Server = "localhost" }
            if ($config.LdapPort) { $Port = $config.LdapPort }
        }
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server: ${Server}:${Port}"
            return $result
        }
        
        $rootDse = Get-LdapSearchResult -Connection $connection -SearchBase "" -Filter "(objectClass=*)" -Scope Base
        if ($rootDse.Count -eq 0) {
            $result.Error = "Failed to get RootDSE"
            $connection.Dispose()
            return $result
        }
        
        $defaultNC = $rootDse[0].Attributes["defaultNamingContext"][0]
        $dnsRoot = ($defaultNC -replace "DC=", "" -replace ",", ".").Trim(".")
        $domainName = ($defaultNC -split ",")[0] -replace "DC=", ""
        
        $result.Data = [PSCustomObject]@{
            Name = $domainName; DnsRoot = $dnsRoot; NetBIOSName = $domainName.ToUpper()
            DistinguishedName = $defaultNC; DomainControllers = @(); Forest = $dnsRoot
            ForestMode = "Unknown"; DomainMode = "Unknown"; PDCEmulator = $Server
            InfrastructureMaster = $Server; LdapServer = $Server; LdapPort = $Port
        }
        
        $connection.Dispose()
        $result.Success = $true
        Write-AppLockerLog -Message "Domain detected via LDAP: $dnsRoot" -NoConsole
    }
    catch {
        $result.Error = "LDAP domain query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Get-OUTreeViaLdap {
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential, [string]$SearchBase, [bool]$IncludeComputerCount = $true)
    
    $result = [PSCustomObject]@{ Success = $false; Data = @(); Error = $null }
    
    try {
        if (-not $Server) {
            $config = Get-AppLockerConfig
            if ($config.LdapServer) { $Server = $config.LdapServer }
            elseif ($env:USERDNSDOMAIN) { $Server = $env:USERDNSDOMAIN }
            else { $Server = "localhost" }
            if ($config.LdapPort) { $Port = $config.LdapPort }
        }
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server"
            return $result
        }
        
        if (-not $SearchBase) {
            $rootDse = Get-LdapSearchResult -Connection $connection -SearchBase "" -Filter "(objectClass=*)" -Scope Base
            $SearchBase = $rootDse[0].Attributes["defaultNamingContext"][0]
        }
        
        $ouEntries = Get-LdapSearchResult -Connection $connection -SearchBase $SearchBase -Filter "(objectClass=organizationalUnit)" -Properties @("name", "distinguishedName")
        $ouList = [System.Collections.ArrayList]::new()
        
        foreach ($entry in $ouEntries) {
            $dn = $entry.DistinguishedName
            $name = $entry.Attributes["name"][0]
            $ouObject = [PSCustomObject]@{
                Name = $name; DistinguishedName = $dn; CanonicalName = $dn; Path = $dn
                Depth = ($dn -split ",OU=").Count - 1; ComputerCount = 0
                MachineType = Get-MachineTypeFromOU -OUPath $dn
            }
            if ($IncludeComputerCount) {
                $computers = Get-LdapSearchResult -Connection $connection -SearchBase $dn -Filter "(objectClass=computer)" -Properties @("name") -Scope OneLevel
                $ouObject.ComputerCount = $computers.Count
            }
            [void]$ouList.Add($ouObject)
        }
        
        $dnsRoot = ($SearchBase -replace "DC=", "" -replace ",", ".").Trim(".")
        $rootObject = [PSCustomObject]@{
            Name = ($SearchBase -split ",")[0] -replace "DC=", ""; DistinguishedName = $SearchBase
            CanonicalName = $dnsRoot; Path = $dnsRoot; Depth = 0; ComputerCount = 0; MachineType = "Mixed"
        }
        if ($IncludeComputerCount) {
            $rootComputers = Get-LdapSearchResult -Connection $connection -SearchBase $SearchBase -Filter "(objectClass=computer)" -Properties @("name") -Scope OneLevel
            $rootObject.ComputerCount = $rootComputers.Count
        }
        
        $connection.Dispose()
        $result.Data = @($rootObject) + ($ouList | Sort-Object DistinguishedName)
        $result.Success = $true
        Write-AppLockerLog -Message "Retrieved $($ouList.Count) OUs via LDAP" -NoConsole
    }
    catch {
        $result.Error = "LDAP OU query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Get-ComputersByOUViaLdap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$OUDistinguishedNames,
        [string]$Server, [int]$Port = 389, [pscredential]$Credential, [bool]$IncludeNestedOUs = $true
    )
    
    $result = [PSCustomObject]@{ Success = $false; Data = @(); Error = $null }
    
    try {
        if (-not $Server) {
            $config = Get-AppLockerConfig
            if ($config.LdapServer) { $Server = $config.LdapServer }
            elseif ($env:USERDNSDOMAIN) { $Server = $env:USERDNSDOMAIN }
            else { $Server = "localhost" }
            if ($config.LdapPort) { $Port = $config.LdapPort }
        }
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if (-not $connection) {
            $result.Error = "Failed to connect to LDAP server"
            return $result
        }
        
        $allComputers = [System.Collections.ArrayList]::new()
        $scope = if ($IncludeNestedOUs) { "Subtree" } else { "OneLevel" }
        
        foreach ($ouDN in $OUDistinguishedNames) {
            $computerEntries = Get-LdapSearchResult -Connection $connection -SearchBase $ouDN -Filter "(objectClass=computer)" -Properties @("name", "dNSHostName", "operatingSystem", "operatingSystemVersion", "distinguishedName") -Scope $scope
            
            foreach ($entry in $computerEntries) {
                $hostName = $entry.Attributes["name"][0]
                $dnsHost = if ($entry.Attributes["dNSHostName"]) { $entry.Attributes["dNSHostName"][0] } else { $hostName }
                $os = if ($entry.Attributes["operatingSystem"]) { $entry.Attributes["operatingSystem"][0] } else { "Unknown" }
                $osVer = if ($entry.Attributes["operatingSystemVersion"]) { $entry.Attributes["operatingSystemVersion"][0] } else { "" }
                
                $computer = [PSCustomObject]@{
                    Name = $hostName; Hostname = $hostName; DNSHostName = $dnsHost
                    DistinguishedName = $entry.DistinguishedName
                    OU = ($entry.DistinguishedName -split ",", 2)[1]
                    OperatingSystem = $os; OperatingSystemVersion = $osVer
                    MachineType = Get-MachineTypeFromOU -OUPath $entry.DistinguishedName
                    IsOnline = $false; WinRMStatus = "Unknown"
                }
                [void]$allComputers.Add($computer)
            }
        }
        
        $connection.Dispose()
        $result.Data = $allComputers | Sort-Object Hostname -Unique
        $result.Success = $true
        Write-AppLockerLog -Message "Found $($allComputers.Count) computers via LDAP" -NoConsole
    }
    catch {
        $result.Error = "LDAP computer query failed: $($_.Exception.Message)"
        Write-AppLockerLog -Level Error -Message $result.Error
    }
    return $result
}

function Set-LdapConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server, [int]$Port = 389, [switch]$UseSSL)
    
    $config = Get-AppLockerConfig
    $config | Add-Member -NotePropertyName "LdapServer" -NotePropertyValue $Server -Force
    $config | Add-Member -NotePropertyName "LdapPort" -NotePropertyValue $Port -Force
    $config | Add-Member -NotePropertyName "LdapUseSSL" -NotePropertyValue $UseSSL.IsPresent -Force
    Set-AppLockerConfig -Config $config
    Write-AppLockerLog -Message "LDAP configured: ${Server}:${Port} (SSL: $($UseSSL.IsPresent))"
}

function Test-LdapConnection {
    [CmdletBinding()]
    param([string]$Server, [int]$Port = 389, [pscredential]$Credential)
    
    $result = [PSCustomObject]@{ Success = $false; Server = $Server; Port = $Port; Error = $null }
    
    try {
        if (-not $Server) {
            $config = Get-AppLockerConfig
            if ($config.LdapServer) { $Server = $config.LdapServer } else { $Server = "localhost" }
            if ($config.LdapPort) { $Port = $config.LdapPort }
        }
        $result.Server = $Server
        $result.Port = $Port
        
        $connection = Get-LdapConnection -Server $Server -Port $Port -Credential $Credential
        if ($connection) {
            $connection.Dispose()
            $result.Success = $true
            Write-AppLockerLog -Message "LDAP connection test successful: ${Server}:${Port}"
        } else {
            $result.Error = "Connection returned null"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-AppLockerLog -Level Error -Message "LDAP connection test failed: $($result.Error)"
    }
    return $result
}
